//===- OrdinaryWrites.cpp - Caller-aware procedural power writes ---------===//
#include "OrdinaryWrites.h"
#include "ReferenceWindow.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "talos/Dialect/DPI/DPIDialect.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "llvm/ADT/DenseMap.h"
#include <map>
#include <optional>
#include <set>
#include <tuple>
using namespace mlir;
namespace talos::upf_detail {
namespace {
struct Origins {
  llvm::DenseSet<uint64_t> roots;
  bool unknown = false;
};
struct Role {
  int domain = -1;
  bool initial = false, edge = false;
};
struct Write {
  Operation *op;
  sim::SimFuncOp function;
  Value reference;
  Descriptor root;
  int target = -1;
};
struct Frame {
  // Dynamic execution provenance, not the helper's lexical declaration scope.
  // Scalar SSA formals are safe to forward through the original call graph;
  // each emitted NBA still binds a static capture-free observer.
  Value role, sourceValid, sourceEpoch;
  std::map<unsigned, std::pair<Value, Value>> targets;
};
struct Lowering {
  OrdinaryWriteOptions o;
  OpBuilder b;
  SymbolTableCollection symbols;
  ReferenceWindows windows;
  llvm::DenseMap<Operation *, SmallVector<Operation *>> callers;
  llvm::DenseMap<Operation *, SmallVector<sim::SimFuncOp>> callees;
  llvm::DenseMap<Operation *, unsigned> actorRoles;
  llvm::DenseMap<Operation *, bool> edgeActors;
  llvm::DenseMap<Operation *, std::set<unsigned>> roles, needed;
  llvm::DenseMap<Operation *, Frame> frames;
  llvm::DenseSet<Operation *> opaque, relevant, unsupported;
  llvm::DenseMap<uint64_t, sim::SimStorageDeclOp> storage;
  llvm::DenseMap<uint64_t, unsigned> owners;
  llvm::DenseMap<Operation *, unsigned> actorDomains;
  llvm::DenseMap<uint64_t, unsigned> epochDomains;
  llvm::DenseMap<Value, Origins> originCache;
  std::map<std::pair<Operation *, unsigned>, FrozenClock> tickets;
  std::map<std::pair<int, int>, sim::SimFuncOp> predicates;
  // Initial, AON edge, each domain's edge, then each domain's level actor.
  // The stable source-order table chooses static policy/epoch pairs in CFG.
  SmallVector<Role> roleTable{{-1, true, false}, {-1, false, true}};
  SmallVector<Write> writes;
  std::optional<Descriptor> permanentEpoch;
  uint64_t provenanceWork = 0;
  uint64_t contextWork = 0;
  uint64_t expansionWork = 0;
  Lowering(const OrdinaryWriteOptions &options)
      : o(options), b(o.design.getContext()), windows(o.design) {
    for (auto decl : o.design.getOps<sim::SimStorageDeclOp>())
      storage[decl.getId()] = decl;
    for (auto [index, domain] : llvm::enumerate(o.domains)) {
      epochDomains[domain.epoch.id] = index;
      for (auto *actor : domain.actors)
        actorDomains[actor] = index;
      for (auto id : domain.ordinary)
        owners[id] = index;
      roleTable.push_back({int(index), false, true});
    }
    for (unsigned index = 0; index < o.domains.size(); ++index)
      roleTable.push_back({int(index), false, false});
  }
  Value bit(Location loc, bool value) {
    return arith::ConstantIntOp::create(b, loc, value, 1);
  }
  Value integer(Location loc, uint64_t value, unsigned width = 64) {
    return arith::ConstantIntOp::create(b, loc, value, width);
  }
  Value and_(Location loc, Value a, Value c) {
    return arith::AndIOp::create(b, loc, a, c);
  }
  Value or_(Location loc, Value a, Value c) {
    return arith::OrIOp::create(b, loc, a, c);
  }
  Value read(Location loc, Value ctx, Descriptor d) {
    return load(b, loc, handle(b, loc, ctx, d));
  }
  int owner(sim::SimFuncOp fn) {
    auto known = actorDomains.find(fn);
    return known == actorDomains.end() ? -1 : int(known->second);
  }
  bool edgeActor(sim::SimFuncOp fn) {
    auto known = edgeActors.find(fn);
    if (known != edgeActors.end())
      return known->second;
    bool result = classifyEdgeActor(fn);
    edgeActors.try_emplace(fn, result);
    return result;
  }
  bool classifyEdgeActor(sim::SimFuncOp fn) {
    SmallVector<Operation *> waits;
    fn.walk([&](Operation *op) {
      if (sim::isSuspensionOp(op))
        waits.push_back(op);
    });
    if (waits.size() != 1 ||
        !waits.front()->hasAttr("schedule.repeating_always_wait"))
      return false;
    Operation *wait = waits.front();
    if (auto edge = dyn_cast<sim::SimSuspendEdgeOp>(wait))
      return edge.getEdge() != sim::EdgeKind::Change;
    if (auto edge = dyn_cast<sim::SimSuspendEdgeIffOp>(wait))
      return edge.getEdge() != sim::EdgeKind::Change;
    if (auto any = dyn_cast<sim::SimSuspendAnyOp>(wait))
      return llvm::all_of(any.getEdges(),
                          [](int32_t edge) { return edge != 0; });
    return false;
  }
  LogicalResult graph() {
    llvm::DenseSet<Operation *> original;
    for (auto fn : o.functions)
      original.insert(fn);
    for (auto fn : o.functions) {
      fn.walk([&](Operation *op) {
        if (!isa<sim::SimCallOp, sim::SimSpawnOp>(op))
          return;
        auto callee = op->getAttrOfType<FlatSymbolRefAttr>("callee");
        auto target =
            symbols.lookupNearestSymbolFrom<sim::SimFuncOp>(op, callee);
        if (target && original.contains(target)) {
          callers[target].push_back(op);
          if (isa<sim::SimCallOp>(op))
            callees[fn].push_back(target);
        }
      });
      if (fn.getEntryKind() == sim::EntryKind::Function ||
          fn.getEntryKind() == sim::EntryKind::Observer)
        continue;
      unsigned role;
      if (fn.getEntryKind() == sim::EntryKind::Initial ||
          fn.getEntryKind() == sim::EntryKind::RootInitializer)
        role = 0;
      else {
        int source = owner(fn);
        if (!edgeActor(fn) && source < 0) {
          unsupported.insert(fn);
          continue;
        }
        role =
            source < 0
                ? 1
                : unsigned(2 + source + (edgeActor(fn) ? 0 : o.domains.size()));
      }
      actorRoles[fn] = role;
      roles[fn].insert(role);
    }
    if (auto uses = SymbolTable::getSymbolUses(o.design)) {
      for (const auto &use : *uses) {
        auto target = symbols.lookupNearestSymbolFrom<sim::SimFuncOp>(
            use.getUser(), use.getSymbolRef());
        if (!target || !original.contains(target) ||
            target.getEntryKind() != sim::EntryKind::Function)
          continue;
        auto call = dyn_cast<sim::SimCallOp>(use.getUser());
        if (!call || call.getCalleeAttr() != use.getSymbolRef())
          opaque.insert(target);
      }
    } else
      for (auto fn : o.functions)
        opaque.insert(fn);
    for (auto fn : o.functions)
      if (opaque.contains(fn) || dpi::has<dpi::Export>(fn))
        unsupported.insert(fn);
    bool changed;
    do {
      changed = false;
      for (auto fn : o.functions)
        for (auto target : callees[fn]) {
          if (++contextWork > (1u << 20))
            return fn.emitError(
                "UPF caller-context analysis exceeds supported work");
          if (unsupported.contains(fn))
            changed |= unsupported.insert(target).second;
          for (auto role : roles[fn]) {
            if (++contextWork > (1u << 20))
              return fn.emitError(
                  "UPF caller-context analysis exceeds supported work");
            changed |= roles[target].insert(role).second;
          }
        }
    } while (changed);
    return success();
  }
  FailureOr<Origins> origins(Value reference) {
    if (auto known = originCache.find(reference); known != originCache.end())
      return known->second;
    Origins result;
    SmallVector<Value> pending{reference};
    llvm::DenseSet<Value> seen;
    while (!pending.empty()) {
      Value value = pending.pop_back_val();
      if (!seen.insert(value).second)
        continue;
      if (++provenanceWork > (1u << 20)) {
        emitError(reference.getLoc())
            << "UPF write provenance exceeds supported work";
        return failure();
      }
      if (auto known = originCache.find(value); known != originCache.end()) {
        result.roots.insert(known->second.roots.begin(),
                            known->second.roots.end());
        result.unknown |= known->second.unknown;
        continue;
      }
      if (auto ref = value.getDefiningOp<sim::SimContextStorageOp>()) {
        auto decl = storage.lookup(ref.getId());
        if (decl && decl.getLifetime() != sim::Lifetime::Automatic)
          result.roots.insert(ref.getId());
        continue;
      }
      if (isa_and_nonnull<sim::SimRefAllocOp, sim::SimClassFieldRefOp>(
              value.getDefiningOp()))
        continue;
      if (auto view = value.getDefiningOp<ViewLikeOpInterface>()) {
        pending.push_back(view.getViewSource());
        continue;
      }
      if (auto argument = dyn_cast<BlockArgument>(value)) {
        auto fn = dyn_cast<sim::SimFuncOp>(argument.getOwner()->getParentOp());
        if (fn && argument.getOwner() == &fn.getBody().front()) {
          if (opaque.contains(fn) || callers[fn].empty())
            result.unknown = true;
          for (auto call : callers[fn]) {
            if (argument.getArgNumber() >= call->getNumOperands())
              result.unknown = true;
            else
              pending.push_back(call->getOperand(argument.getArgNumber()));
          }
        } else {
          bool incoming = false;
          for (auto *predecessor : argument.getOwner()->getPredecessors()) {
            auto branch =
                dyn_cast<BranchOpInterface>(predecessor->getTerminator());
            if (!branch) {
              result.unknown = true;
              continue;
            }
            for (unsigned i = 0; i != branch->getNumSuccessors(); ++i) {
              if (branch->getSuccessor(i) != argument.getOwner())
                continue;
              auto values = branch.getSuccessorOperands(i);
              if (argument.getArgNumber() >= values.size() ||
                  values.isOperandProduced(argument.getArgNumber()))
                result.unknown = true;
              else {
                pending.push_back(values[argument.getArgNumber()]);
                incoming = true;
              }
            }
          }
          if (!incoming)
            result.unknown = true;
        }
        continue;
      }
      if (auto from = value.getDefiningOp<sim::SimArgumentRefFromRefOp>()) {
        pending.push_back(from->getOperand(0));
        continue;
      }
      result.unknown = true;
    }
    originCache[reference] = result;
    return result;
  }
  bool poweredSource(sim::SimFuncOp fn) {
    return llvm::any_of(roles[fn],
                        [&](unsigned r) { return roleTable[r].domain >= 0; });
  }
  LogicalResult inventory() {
    for (auto fn : o.functions) {
      if (fn.getEntryKind() == sim::EntryKind::Observer ||
          ((fn.getEntryKind() == sim::EntryKind::PortInput ||
            fn.getEntryKind() == sim::EntryKind::PortOutput ||
            fn.getEntryKind() == sim::EntryKind::PortInitialize) &&
           owner(fn) < 0))
        continue;
      WalkResult walk = fn.walk([&](Operation *op) {
        Value reference;
        if (auto write = dyn_cast<sim::SimRefStoreOp>(op))
          reference = write.getReference();
        if (auto write = dyn_cast<sim::SimNBAEnqueueOp>(op))
          reference = write.getDestination();
        bool indirect =
            isa<sim::SimArgumentRefFromRefOp, sim::SimRefCopyOp>(op);
        if (auto copy = dyn_cast<sim::SimRefCopyOp>(op))
          reference = copy.getDestination();
        if (isa<sim::SimArgumentRefFromRefOp>(op))
          reference = op->getOperand(0);
        if (!reference)
          return WalkResult::advance();
        if (!isa<sim::RefType>(reference.getType())) {
          if (isa<sim::SimNBAEnqueueOp>(op) && poweredSource(fn)) {
            op->emitError("guarded UPF NBA requires a storage reference; "
                          "driver NBA cancellation is not implemented");
            return WalkResult::interrupt();
          }
          return WalkResult::advance();
        }
        auto roots = origins(reference);
        if (failed(roots))
          return WalkResult::interrupt();
        bool originalRoot = llvm::any_of(roots->roots, [&](uint64_t id) {
          return o.originalStorage.contains(id);
        });
        if (!originalRoot && !roots->unknown)
          return WalkResult::advance();
        bool target = llvm::any_of(
            roots->roots, [&](uint64_t id) { return owners.contains(id); });
        bool source = poweredSource(fn);
        if (!target && !source && !roots->unknown)
          return WalkResult::advance();
        // Known heap/automatic references are not powered design roots.
        if (roots->roots.empty() && !roots->unknown)
          return WalkResult::advance();
        if (indirect) {
          if (target || source || roots->unknown) {
            op->emitError("UPF ordinary state through copied or indirect "
                          "argument references is not implemented");
            return WalkResult::interrupt();
          }
          return WalkResult::advance();
        }
        if (unsupported.contains(fn)) {
          op->emitError("UPF external writes require Initial or a repeating "
                        "edge actor; external level restoration, timed and "
                        "opaque caller contexts are not implemented");
          return WalkResult::interrupt();
        }
        if (roles[fn].size() == 1 && *roles[fn].begin() == 0 &&
            !opaque.contains(fn) && !dpi::has<dpi::Export>(fn))
          return WalkResult::advance(); // Preserve direct initialization
                                        // unchanged.
        if (roles[fn].empty()) {
          if (fn.getEntryKind() == sim::EntryKind::Function &&
              !opaque.contains(fn) && callers[fn].empty() &&
              SymbolTable::getSymbolVisibility(fn) ==
                  SymbolTable::Visibility::Private &&
              !dpi::has<dpi::Export>(fn))
            return WalkResult::advance(); // Provably uncalled private closure.
          op->emitError("UPF external writes require Initial or a repeating "
                        "edge actor; external level restoration, timed and "
                        "opaque caller contexts are not implemented");
          return WalkResult::interrupt();
        }
        auto root = windows.getRoot(reference);
        if (failed(root))
          return WalkResult::interrupt();
        uint64_t id = root->id;
        if (!owners.contains(id) && !source)
          return WalkResult::advance();
        if (llvm::any_of(o.domains, [&](const WriteDomain &d) {
              return d.retained.contains(id);
            }))
          return WalkResult::advance();
        int destination =
            owners.contains(root->id) ? int(owners.lookup(root->id)) : -1;
        // Bound the product of shared writers and source policies before any
        // signature or CFG mutation, rather than bounding each axis alone.
        expansionWork += roles[fn].size();
        if (expansionWork > (1u << 20)) {
          op->emitError("UPF write-context expansion exceeds supported work");
          return WalkResult::interrupt();
        }
        for (unsigned role : roles[fn]) {
          auto &r = roleTable[role];
          if (r.initial)
            continue;
          if (destination >= 0 && r.domain != destination && !r.edge) {
            op->emitError("UPF external combinational or level writes require "
                          "per-target restoration and are not implemented");
            return WalkResult::interrupt();
          }
          if (destination >= 0 && r.domain != destination &&
              (!o.domains[destination].exact ||
               (r.domain >= 0 && !o.domains[r.domain].exact &&
                !o.domains[r.domain].immutable))) {
            op->emitError(
                "UPF external writes require exact source and target domain "
                "epochs; resolved-driver loss is not implemented");
            return WalkResult::interrupt();
          }
        }
        if (auto nba = dyn_cast<sim::SimNBAEnqueueOp>(op))
          if (nba.getClockingOutputAttr()) {
            nba.emitError("clocking-output NBAs into a switchable domain are "
                          "not implemented");
            return WalkResult::interrupt();
          }
        writes.push_back({op, fn, reference, *root, destination});
        relevant.insert(fn);
        if (destination >= 0)
          needed[fn].insert(destination);
        return WalkResult::advance();
      });
      if (walk.wasInterrupted())
        return failure();
    }
    bool changed;
    do {
      changed = false;
      for (auto fn : o.functions)
        for (auto callee : callees[fn]) {
          if (++contextWork > (1u << 20))
            return fn.emitError(
                "UPF caller-context analysis exceeds supported work");
          if (relevant.contains(callee))
            changed |= relevant.insert(fn).second;
          for (unsigned domain : needed[callee]) {
            if (++contextWork > (1u << 20))
              return fn.emitError(
                  "UPF caller-context analysis exceeds supported work");
            changed |= needed[fn].insert(domain).second;
          }
        }
    } while (changed);
    for (auto fn : o.functions)
      if (relevant.contains(fn) &&
          fn.getEntryKind() == sim::EntryKind::Function) {
        uint64_t lanes = 3 + 2 * needed[fn].size();
        uint64_t sites = 1 + callers[fn].size();
        if (lanes > (1u << 20) || sites > (1u << 20) ||
            lanes * sites > (1u << 20) - expansionWork)
          return fn.emitError(
              "UPF write-context expansion exceeds supported work");
        expansionWork += lanes * sites;
      }
    return success();
  }
  FailureOr<std::pair<Value, Value>> ticket(sim::SimFuncOp fn, unsigned domain,
                                            Location loc) {
    auto &d = o.domains[domain];
    Value ctx = fn.getArgument(0);
    if (d.immutable || !d.exact || !edgeActor(fn))
      return std::pair{d.normal(b, loc, ctx), read(loc, ctx, d.epoch)};
    auto key = std::make_pair(fn.getOperation(), domain);
    auto found = tickets.find(key);
    if (found == tickets.end()) {
      std::string name = owner(fn) == int(domain)
                             ? "__upf_clock."
                             : "__upf_target." + d.name + ".clock.";
      if (auto id = fn.getCodeUnitId())
        name += std::to_string(*id);
      else
        name += "actor." + fn.getSymName().str();
      auto value = o.clocks.freeze(fn, name, d.epoch, d.normal);
      if (failed(value))
        return failure();
      found = tickets.emplace(key, *value).first;
    }
    return std::pair{read(loc, ctx, found->second.valid),
                     read(loc, ctx, found->second.epoch)};
  }
  FailureOr<Frame> frame(sim::SimFuncOp fn, Location loc,
                         ArrayRef<unsigned> destinations) {
    if (auto found = frames.find(fn); found != frames.end())
      return found->second;
    auto known = actorRoles.find(fn);
    if (known == actorRoles.end())
      return fn.emitError("UPF write helper has no forwarded caller context");
    Frame result;
    unsigned role = known->second;
    auto &r = roleTable[role];
    result.role = integer(loc, role, 32);
    result.sourceValid = bit(loc, true);
    result.sourceEpoch = integer(loc, 0);
    if (r.domain >= 0) {
      auto source = ticket(fn, r.domain, loc);
      if (failed(source))
        return failure();
      std::tie(result.sourceValid, result.sourceEpoch) = *source;
    }
    // Load only this statement/callee's destinations. Loading an actor's full
    // target union at every write would multiply work for unrelated domains.
    for (unsigned domain : destinations) {
      if (r.initial)
        result.targets[domain] = {bit(loc, true), integer(loc, 0)};
      else {
        auto target = ticket(fn, domain, loc);
        if (failed(target))
          return failure();
        result.targets[domain] = *target;
      }
    }
    return result;
  }
  LogicalResult contexts() {
    auto attrs = b.getDictionaryAttr({sim::named<sim::metadata::CaptureKind>(
        sim::CaptureKindAttr::get(b.getContext(), sim::CaptureKind::Formal))});
    for (auto fn : o.functions) {
      if (!relevant.contains(fn) ||
          fn.getEntryKind() != sim::EntryKind::Function)
        continue;
      if (opaque.contains(fn) || dpi::has<dpi::Export>(fn) || fn.isExternal())
        return fn.emitError("UPF write helpers require defined direct callers "
                            "without DPI exports or opaque dispatch");
      WalkResult supported = fn.walk([&](Operation *op) {
        if (sim::isSuspensionOp(op) ||
            isa<sim::SimSpawnOp, sim::SimTaskCallOp, sim::SimClassDirectCallOp,
                sim::SimClassVirtualCallOp, sim::SimClassVirtualTaskCallOp>(
                op)) {
          op->emitError("UPF write helper timing, fork and indirect dispatch "
                        "are not implemented");
          return WalkResult::interrupt();
        }
        return WalkResult::advance();
      });
      if (supported.wasInterrupted())
        return failure();
      Frame f;
      auto append = [&](Type type) -> Value {
        unsigned index = fn.getNumArguments();
        if (failed(fn.insertArgument(index, type, attrs, fn.getLoc())))
          return {};
        return fn.getArgument(index);
      };
      f.role = append(b.getI32Type());
      f.sourceValid = append(b.getI1Type());
      f.sourceEpoch = append(b.getI64Type());
      if (!f.role || !f.sourceValid || !f.sourceEpoch)
        return failure();
      for (unsigned domain : needed[fn])
        f.targets[domain] = {append(b.getI1Type()), append(b.getI64Type())};
      frames[fn] = std::move(f);
    }
    for (auto fn : o.functions) {
      if (!frames.contains(fn))
        continue;
      SmallVector<unsigned> destinations(needed[fn].begin(), needed[fn].end());
      for (auto *site : callers[fn]) {
        auto call = dyn_cast<sim::SimCallOp>(site);
        if (!call)
          return site->emitError(
              "UPF write helpers require synchronous direct calls");
        b.setInsertionPoint(call);
        auto caller = frame(call->getParentOfType<sim::SimFuncOp>(),
                            call.getLoc(), destinations);
        if (failed(caller))
          return failure();
        SmallVector<Value> args{caller->role, caller->sourceValid,
                                caller->sourceEpoch};
        for (unsigned domain : needed[fn]) {
          auto target = caller->targets.find(domain);
          if (target == caller->targets.end())
            return call.emitError("missing UPF target-domain caller context");
          args.push_back(target->second.first);
          args.push_back(target->second.second);
        }
        MutableOperandRange(call).append(args);
        if (auto old = call->getAttrOfType<ArrayAttr>("arg_attrs")) {
          SmallVector<Attribute> expanded(old.getValue());
          expanded.append(args.size(), attrs);
          call->setAttr("arg_attrs", b.getArrayAttr(expanded));
        }
      }
    }
    return success();
  }
  Value sameEpoch(Location loc, Value ctx, unsigned domain, Value captured) {
    return arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, captured,
                                 read(loc, ctx, o.domains[domain].epoch));
  }
  Value permitted(Write w, const Frame &f, unsigned role) {
    Location loc = w.op->getLoc();
    Value ctx = w.function.getArgument(0);
    const auto &r = roleTable[role];
    if (r.initial)
      return bit(loc, true);
    Value allow = bit(loc, true);
    if (r.domain >= 0) {
      auto &d = o.domains[r.domain];
      allow = and_(loc, d.normal(b, loc, ctx),
                   and_(loc, f.sourceValid,
                        sameEpoch(loc, ctx, r.domain, f.sourceEpoch)));
    }
    if (w.target >= 0) {
      auto &d = o.domains[w.target];
      allow = and_(loc, allow, d.normal(b, loc, ctx));
      if (r.edge) {
        auto target = f.targets.at(w.target);
        allow = and_(loc, allow,
                     and_(loc, target.first,
                          sameEpoch(loc, ctx, w.target, target.second)));
      }
    }
    return allow;
  }
  sim::SimFuncOp predicate(int source, int target, Location loc) {
    auto key = std::make_pair(source, target);
    auto found = predicates.find(key);
    if (found != predicates.end())
      return found->second;
    auto fn = o.function(loc,
                         "__upf_write.allowed." + std::to_string(source + 1) +
                             "." + std::to_string(target + 1),
                         {sim::ContextType::get(b.getContext())},
                         sim::EntryKind::Observer);
    fn.setFunctionType(
        b.getFunctionType(fn.getArgumentTypes(), {b.getI1Type()}));
    schedule::set<schedule::Field::ObserverWidth>(fn, b.getI32IntegerAttr(1));
    schedule::set<schedule::Field::ObserverFourState>(fn, b.getBoolAttr(false));
    sim::mark<sim::metadata::PowerMonitor>(fn);
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToEnd(&fn.getBody().front());
    Value allow = bit(loc, true);
    if (source >= 0)
      allow =
          and_(loc, allow, o.domains[source].normal(b, loc, fn.getArgument(0)));
    if (target >= 0 && target != source)
      allow =
          and_(loc, allow, o.domains[target].normal(b, loc, fn.getArgument(0)));
    sim::SimReturnOp::create(b, loc, allow);
    predicates.emplace(key, fn);
    return fn;
  }
  void guardStore(Write w, Value allow) {
    auto *before = w.op->getBlock();
    auto *execute = before->splitBlock(Block::iterator(w.op));
    auto *next = execute->splitBlock(std::next(execute->begin()));
    b.setInsertionPointToEnd(before);
    cf::CondBranchOp::create(b, w.op->getLoc(), allow, execute, next);
    b.setInsertionPointToEnd(execute);
    cf::BranchOp::create(b, w.op->getLoc(), next);
  }
  Descriptor unchangingEpoch(Location loc) {
    if (permanentEpoch)
      return *permanentEpoch;
    permanentEpoch =
        o.storage(loc, "__upf_write.initial_epoch", b.getI64Type());
    OpBuilder::InsertionGuard guard(b);
    b.setInsertionPointToStart(&o.root.getBody().front());
    store(b, loc, handle(b, loc, o.root.getArgument(0), *permanentEpoch),
          integer(loc, 0));
    return *permanentEpoch;
  }
  LogicalResult lowerNBA(Write w, const Frame &f) {
    auto op = cast<sim::SimNBAEnqueueOp>(w.op);
    Location loc = op.getLoc();
    auto window = windows.get(w.reference);
    if (failed(window))
      return failure();
    Value ctx = w.function.getArgument(0);
    auto *head = op->getBlock();
    auto *initial = head->splitBlock(Block::iterator(op));
    auto *next = initial->splitBlock(std::next(initial->begin()));
    Block *test = head;
    bool keepRaw = false;
    for (unsigned role : roles[w.function]) {
      auto &r = roleTable[role];
      // Initial and AON writes remain ordinary NBAs when the destination is
      // whole. A projected formal needs the explicit ancestor bounds even in
      // an exempt caller; the always-true predicate preserves that exemption.
      bool exempt = r.initial || (r.domain < 0 && w.target < 0);
      bool raw = exempt && windows.isWhole(w.reference);
      auto *execute = raw ? initial : new Block;
      if (!raw)
        w.function.getBody().push_back(execute);
      auto *skip = new Block;
      w.function.getBody().push_back(skip);
      b.setInsertionPointToEnd(test);
      Value match = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq,
                                          f.role, integer(loc, role, 32));
      Value allow = and_(loc, match, permitted(w, f, role));
      cf::CondBranchOp::create(b, loc, allow, execute, skip);
      b.setInsertionPointToEnd(execute);
      if (!raw) {
        int source = r.initial ? -1 : r.domain;
        int target = r.initial ? -1 : w.target;
        auto evaluator = predicate(source, target, loc);
        SmallVector<Value> watched;
        for (int domain : {source, target})
          if (domain >= 0)
            for (auto d : o.domains[domain].dependencies)
              watched.push_back(handle(b, loc, ctx, d));
        Value binding = sim::SimObserverBindOp::create(
            b, loc, sim::ObserverType::get(b.getContext(), b.getI1Type()),
            evaluator.getSymNameAttr(), watched, uint32_t{0});
        int first = source >= 0 ? source : w.target;
        int second = w.target >= 0 ? w.target : source;
        auto sourceEpoch =
            first >= 0 ? o.domains[first].epoch : unchangingEpoch(loc);
        auto targetEpoch = second >= 0 ? o.domains[second].epoch : sourceEpoch;
        Value value = flatten(b, loc, op.getValue());
        Type scalar = sim::getPackedScalarType(w.root.type);
        if (!scalar)
          return op.emitError(
              "UPF ordinary NBA requires a packed integral root");
        if (isa<sim::LogicType>(scalar) && isa<IntegerType>(value.getType()))
          value = sim::SimLogicFromBitsOp::create(
              b, loc,
              sim::LogicType::get(b.getContext(),
                                  *sim::getPackedWidth(value.getType())),
              value);
        else if (isa<IntegerType>(scalar) &&
                 isa<sim::LogicType>(value.getType()))
          value = sim::SimLogicToBitsOp::create(
              b, loc, b.getIntegerType(*sim::getPackedWidth(value.getType())),
              value);
        sim::SimPowerNBAViewOp::create(
            b, loc, ctx, value, handle(b, loc, ctx, w.root), window->start,
            window->lower, window->upper, window->valid, binding,
            handle(b, loc, ctx, sourceEpoch), read(loc, ctx, sourceEpoch),
            handle(b, loc, ctx, targetEpoch), read(loc, ctx, targetEpoch),
            op.getDelay());
      }
      if (!raw || !keepRaw)
        cf::BranchOp::create(b, loc, next);
      keepRaw |= raw;
      test = skip;
    }
    b.setInsertionPointToEnd(test);
    cf::BranchOp::create(b, loc, next);
    if (!keepRaw)
      initial->erase();
    return success();
  }
  LogicalResult retainedSources() {
    for (const auto &write : o.retainedWrites) {
      auto gate = cast<cf::CondBranchOp>(write.guard);
      auto fn = gate->getParentOfType<sim::SimFuncOp>();
      int source = owner(fn);
      auto target = epochDomains.find(write.domainEpoch.id);
      if (target == epochDomains.end())
        return gate.emitError("retention update has no physical domain policy");
      // Constant source policy cannot invalidate an issued activation. Treat
      // it like an AON producer, avoiding even a redundant statement guard.
      if (source < 0 || unsigned(source) == target->second ||
          o.domains[source].immutable)
        continue;
      if (!o.domains[source].exact)
        return gate.emitError("retention updates from another domain require "
                              "exact source power epochs; resolved-driver "
                              "source loss is not implemented");
      expansionWork += 1 + write.enqueues.size();
      if (expansionWork > (1u << 20))
        return gate.emitError(
            "UPF write-context expansion exceeds supported work");
      b.setInsertionPoint(gate);
      auto sourceTicket = ticket(fn, source, gate.getLoc());
      if (failed(sourceTicket))
        return failure();
      Value ctx = fn.getArgument(0);
      Descriptor epoch = o.domains[source].epoch;
      Value current = read(gate.getLoc(), ctx, epoch);
      Value same =
          arith::CmpIOp::create(b, gate.getLoc(), arith::CmpIPredicate::eq,
                                sourceTicket->second, current);
      // An exact source ticket was captured in NORMAL. Its unchanged epoch
      // proves NORMAL through this statement, so no additional source policy
      // evaluator or dependent snapshot state is needed.
      Value valid = and_(gate.getLoc(), sourceTicket->first, same);
      gate.getConditionMutable().assign(
          and_(gate.getLoc(), gate.getCondition(), valid));
      for (auto *action : write.enqueues) {
        // These functional writes issue only while retention is writable.
        // Master W-fall and Balloon destructive/priority epochs necessarily
        // advance on any later destination primary loss. The strategy slot
        // therefore subsumes destination loss; reuse the first slot for the
        // independent source lifetime, preserving the existing pair decision
        // and each dynamic-zero Balloon branch and output-view predicate.
        b.setInsertionPoint(action);
        Value reference = handle(b, action->getLoc(), ctx, epoch);
        if (auto nba = dyn_cast<sim::SimPowerNBAOp>(action)) {
          nba.getDomainEpochRefMutable().assign(reference);
          nba.getDomainEpochMutable().assign(current);
        } else if (auto nba = dyn_cast<sim::SimPowerNBAViewOp>(action)) {
          nba.getDomainEpochRefMutable().assign(reference);
          nba.getDomainEpochMutable().assign(current);
        } else
          return action->emitError(
              "retention update has an unknown NBA publication");
      }
    }
    return success();
  }
  LogicalResult run() {
    if (failed(graph()) || failed(inventory()) || failed(contexts()))
      return failure();
    if (failed(retainedSources()))
      return failure();
    SmallVector<Value> refs;
    for (const auto &w : writes)
      if (isa<sim::SimNBAEnqueueOp>(w.op))
        refs.push_back(w.reference);
    if (failed(windows.prepare(refs)))
      return failure();
    for (auto w : writes) {
      b.setInsertionPoint(w.op);
      SmallVector<unsigned, 1> destinations;
      if (w.target >= 0)
        destinations.push_back(w.target);
      auto f = frame(w.function, w.op->getLoc(), destinations);
      if (failed(f))
        return failure();
      if (isa<sim::SimNBAEnqueueOp>(w.op)) {
        if (failed(lowerNBA(w, *f)))
          return failure();
      } else {
        Value allow = bit(w.op->getLoc(), false);
        for (unsigned role : roles[w.function]) {
          Value match =
              arith::CmpIOp::create(b, w.op->getLoc(), arith::CmpIPredicate::eq,
                                    f->role, integer(w.op->getLoc(), role, 32));
          allow = or_(w.op->getLoc(), allow,
                      and_(w.op->getLoc(), match, permitted(w, *f, role)));
        }
        guardStore(w, allow);
      }
    }
    return success();
  }
};
} // namespace
LogicalResult lowerOrdinaryUPFWrites(const OrdinaryWriteOptions &options) {
  if (options.domains.empty())
    return success();
  return Lowering(options).run();
}
} // namespace talos::upf_detail
