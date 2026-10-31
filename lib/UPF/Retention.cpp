#include "Retention.h"
#include "PowerState.h"
#include "ReferenceWindow.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include <limits>
#include <map>
#include <set>
using namespace mlir;
namespace talos {
namespace {
using namespace upf_detail;
struct Alias {
  StringRef path;
  uint64_t scope;
  bool partial = false;
};
struct Register {
  sim::SimStorageDeclOp declaration;
  SmallVector<Alias> aliases;
  SmallVector<Operation *> writers;
  upf::RetentionAttr strategy;
  Descriptor visible, backing;
};
struct Strategy {
  upf::RetentionAttr attribute;
  SmallVector<Register *> registers;
  SmallVector<upf::UPFSupplySetOp> primary, retention;
  SmallVector<Descriptor> dependencies;
  Descriptor epoch, visible, badProcess, freezeProcess;
  sim::SimFuncOp update, predicate;
};
struct Lowering {
  RetentionLoweringOptions o;
  RetentionLoweringResult &result;
  OpBuilder b;
  ReferenceWindows references;
  SmallVector<Register> registers;
  SmallVector<Strategy, 0> strategies;
  llvm::DenseMap<uint64_t, sim::SimScopeDeclOp> scopes;
  llvm::DenseMap<Operation *, bool> startupCache, edgeCache;
  llvm::DenseSet<Operation *> initializers;
  std::map<std::pair<Operation *, uint64_t>, bool> completeCache;
  llvm::DenseMap<uint64_t, SmallVector<sim::SimPortDeclOp>> aliases;
  Operation *rootBoundary = nullptr;
  Lowering(const RetentionLoweringOptions &o, RetentionLoweringResult &result)
      : o(o), result(result), b(this->o.design.getContext()),
        references(this->o.design) {
    for (auto scope : this->o.design.getOps<sim::SimScopeDeclOp>())
      scopes[scope.getId()] = scope;
    for (auto port : this->o.design.getOps<sim::SimPortDeclOp>())
      if (!port.getSourceIsNet())
        aliases[port.getSourceId()].push_back(port);
    rootBoundary = this->o.root.getBody().front().getTerminator();
    for (Operation &op : this->o.root.getBody().front()) {
      if (isa<sim::SimSpawnOp>(op)) {
        rootBoundary = &op;
        break;
      }
      if (auto call = dyn_cast<sim::SimCallOp>(op))
        if (auto fn = SymbolTable::lookupNearestSymbolFrom<sim::SimFuncOp>(
                call, call.getCalleeAttr()))
          if (auto path = sim::get<sim::metadata::HierarchicalName>(fn))
            if (this->o.descriptors.count(path.getValue()))
              initializers.insert(fn);
    }
  }
  Location location(upf::RetentionAttr strategy) {
    return strategy.getDeclaration() ? Location(strategy.getDeclaration())
                                     : o.domain.getLoc();
  }
  uint64_t owner(uint64_t scope) {
    llvm::DenseSet<uint64_t> seen;
    while (seen.insert(scope).second) {
      auto declaration = scopes.lookup(scope);
      if (!declaration || declaration.getDefinitionName() ||
          declaration.getVpiDefinitionAttr() || declaration.getInterfaceType())
        return scope;
      if (!declaration.getParent())
        return scope;
      scope = *declaration.getParent();
    }
    return scope;
  }
  unsigned rank(upf::RetentionAttr strategy, Register &reg, bool &partial) {
    // IEEE 1801-2018 5.9.3: explicit descendant inclusions survive an
    // excluded ancestor, and an exact exclusion wins. Resolve membership
    // across every alias of the physical register, so an excluded variable
    // cannot reenter the strategy through its output-port name. Signal names
    // have the same specificity regardless of their spelling or hierarchy.
    size_t included = 0, excluded = 0;
    unsigned precedence = 0;
    partial = false;
    auto scope = scopes.lookup(owner(reg.declaration.getScopeId()));
    StringRef instance = scope && scope.getHierarchicalName()
                             ? *scope.getHierarchicalName()
                             : StringRef{};
    for (const auto &alias : reg.aliases) {
      if (!contains(o.domain, alias.path))
        continue;
      if (strategy.getDomainDefault()) {
        included = std::max(included, size_t{1});
        precedence = std::max(precedence, 1u);
      }
      auto match = [&](upf::RetentionElementAttr element) {
        StringRef path = element.getPath().getValue();
        return element.getKind() == upf::RetentionElementKind::Signal
                   ? path == alias.path
                   : within(alias.path, path);
      };
      auto specificity = [&](upf::RetentionElementAttr element) {
        return element.getKind() == upf::RetentionElementKind::Signal
                   ? std::numeric_limits<size_t>::max()
                   : size_t{2} + element.getPath().getValue().count('.');
      };
      for (auto attribute : strategy.getElements()) {
        auto element = cast<upf::RetentionElementAttr>(attribute);
        if (!match(element))
          continue;
        bool signal = element.getKind() == upf::RetentionElementKind::Signal;
        included = std::max(included, specificity(element));
        // 5.7.3: explicit signal > owning instance > transitive instance >
        // domain default. Exclusions affect membership, never precedence.
        precedence = std::max(precedence,
                              signal                                     ? 4u
                              : element.getPath().getValue() == instance ? 3u
                                                                         : 2u);
        partial |= signal && alias.partial;
      }
      for (auto attribute : strategy.getExcluded()) {
        auto element = cast<upf::RetentionElementAttr>(attribute);
        if (match(element))
          excluded = std::max(excluded, specificity(element));
      }
    }
    return included > excluded ? precedence : 0;
  }
  bool startup(sim::SimFuncOp fn) {
    auto found = startupCache.find(fn);
    if (found != startupCache.end())
      return found->second;
    bool result = classifyStartup(fn);
    startupCache[fn] = result;
    return result;
  }
  bool classifyStartup(sim::SimFuncOp fn) {
    if (fn.getEntryKind() == sim::EntryKind::RootInitializer)
      return true;
    // Declaration initializers are zero-time functions called by the root
    // before spawning any HDL process (1801-2018 9.2.1).
    if (fn.getEntryKind() != sim::EntryKind::Initial &&
        !initializers.contains(fn))
      return false;
    llvm::DenseSet<Block *> active, finished;
    SmallVector<std::pair<Block *, bool>> pending{
        {&fn.getBody().front(), false}};
    while (!pending.empty()) {
      auto [block, finish] = pending.pop_back_val();
      if (finish) {
        active.erase(block);
        finished.insert(block);
        continue;
      }
      if (finished.contains(block))
        continue;
      if (!active.insert(block).second)
        return false;
      pending.emplace_back(block, true);
      for (auto *next : block->getSuccessors())
        pending.emplace_back(next, false);
    }
    bool untimed = true;
    fn.walk([&](Operation *op) {
      StringRef name = op->getName().getStringRef();
      if (name.starts_with("simulation.suspend.") ||
          isa<sim::SimSpawnOp, sim::SimTaskCallOp, sim::SimNBAEnqueueOp>(op))
        untimed = false;
    });
    return untimed;
  }
  bool edgeWriter(sim::SimFuncOp fn) {
    auto found = edgeCache.find(fn);
    if (found != edgeCache.end())
      return found->second;
    bool result = classifyEdge(fn);
    edgeCache[fn] = result;
    return result;
  }
  bool classifyEdge(sim::SimFuncOp fn) {
    if (fn.getEntryKind() != sim::EntryKind::AlwaysFF &&
        fn.getEntryKind() != sim::EntryKind::Always)
      return false;
    SmallVector<Operation *> waits;
    fn.walk([&](Operation *op) {
      if (op->getName().getStringRef().starts_with("simulation.suspend."))
        waits.push_back(op);
    });
    if (waits.size() != 1 ||
        !waits.front()->hasAttr("schedule.repeating_always_wait"))
      return false;
    // IEEE 1801-2018 9.7.3 gives RTC priority over asynchronous set/reset
    // as well as clocks. A direct edge list remains one sequential writer;
    // change-sensitive terms would instead admit unsupported level behavior.
    if (auto edge = dyn_cast<sim::SimSuspendEdgeOp>(waits.front()))
      return edge.getEdge() != sim::EdgeKind::Change;
    if (auto edge = dyn_cast<sim::SimSuspendEdgeIffOp>(waits.front()))
      return edge.getEdge() != sim::EdgeKind::Change;
    if (auto any = dyn_cast<sim::SimSuspendAnyOp>(waits.front()))
      return !any.getEdges().empty() &&
             llvm::all_of(any.getEdges(), [](int32_t edge) {
               return edge >= static_cast<int32_t>(sim::EdgeKind::Posedge) &&
                      edge <= static_cast<int32_t>(sim::EdgeKind::Both);
             });
    return false;
  }
  bool completeLevelWriter(sim::SimFuncOp fn, uint64_t id) {
    auto key = std::pair{fn.getOperation(), id};
    auto found = completeCache.find(key);
    if (found != completeCache.end())
      return found->second;
    bool result = classifyLevel(fn, id);
    completeCache[key] = result;
    return result;
  }
  bool classifyLevel(sim::SimFuncOp fn, uint64_t id) {
    if (fn.getEntryKind() == sim::EntryKind::Continuous)
      return true;
    if (fn.getEntryKind() == sim::EntryKind::PortInput ||
        fn.getEntryKind() == sim::EntryKind::PortOutput ||
        fn.getEntryKind() == sim::EntryKind::PortInitialize)
      return true;
    if (fn.getEntryKind() != sim::EntryKind::Always &&
        fn.getEntryKind() != sim::EntryKind::AlwaysComb)
      return false;
    // Definite assignment on every route to the sensitivity wait distinguishes
    // ordinary combinational variables from unsupported inferred latches.
    Block *start = &fn.getBody().front();
    SmallVector<Operation *> waits;
    fn.walk([&](Operation *op) {
      if (op->getName().getStringRef().starts_with("simulation.suspend."))
        waits.push_back(op);
    });
    if (waits.size() != 1)
      return false;
    if (!isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp>(waits.front()))
      return false;
    if (auto any = dyn_cast<sim::SimSuspendAnyOp>(waits.front()))
      if (llvm::any_of(any.getEdges(), [](int32_t edge) { return edge != 0; }))
        return false;
    if (waits.front()->hasAttr("schedule.repeating_always_wait") ||
        waits.front()->hasAttr("schedule.top_level_wildcard_wait"))
      start = waits.front()->getSuccessor(0);
    std::set<std::pair<Block *, bool>> visited;
    SmallVector<std::pair<Block *, bool>> pending{{start, false}};
    while (!pending.empty()) {
      auto [block, assigned] = pending.pop_back_val();
      if (!visited.emplace(block, assigned).second)
        continue;
      bool suspended = false;
      for (Operation &op : *block) {
        Value target;
        if (auto write = dyn_cast<sim::SimRefStoreOp>(op))
          target = write.getReference();
        if (auto write = dyn_cast<sim::SimNBAEnqueueOp>(op))
          target = write.getDestination();
        if (target && storageID(target, fn) == id &&
            !target.getDefiningOp<ViewLikeOpInterface>())
          assigned = true;
        if (op.getName().getStringRef().starts_with("simulation.suspend.")) {
          if (isa<sim::SimSuspendEdgeOp, sim::SimSuspendEdgeIffOp>(op))
            return false;
          if (!assigned)
            return false;
          suspended = true;
          break;
        }
      }
      if (suspended)
        continue;
      for (Block *next : block->getSuccessors())
        pending.emplace_back(next, assigned);
      if (block->getNumSuccessors() == 0 && !assigned)
        return false;
    }
    return true;
  }
  LogicalResult plan() {
    if (!o.domain.getRetentionsAttr())
      return success();
    llvm::DenseMap<uint64_t, SmallVector<Operation *>> writers;
    llvm::DenseSet<uint64_t> domainUnits;
    for (auto unit : o.design.getOps<sim::SimCodeUnitDeclOp>())
      if (contains(o.domain, unit.getHierarchicalName()))
        domainUnits.insert(unit.getId());
    WalkResult inventory = o.design.walk([&](Operation *op) {
      Value target;
      if (auto write = dyn_cast<sim::SimRefStoreOp>(op))
        target = write.getReference();
      if (auto write = dyn_cast<sim::SimNBAEnqueueOp>(op))
        target = write.getDestination();
      if (target)
        if (auto fn = op->getParentOfType<sim::SimFuncOp>()) {
          // IEEE 1801-2018 6.50/9.7.3: selection concerns physical state.
          // A CFG lane or unannotated formal is still a sequential writer;
          // never silently classify it as ordinary combinational storage.
          if (fn.getCodeUnitId() && domainUnits.contains(*fn.getCodeUnitId())) {
            auto root = references.getRoot(target);
            if (failed(root))
              return WalkResult::interrupt();
            writers[root->id].push_back(op);
          } else if (auto id = storageID(target, fn))
            writers[*id].push_back(op);
        }
      return WalkResult::advance();
    });
    if (inventory.wasInterrupted())
      return failure();
    llvm::DenseSet<uint64_t> opaqueWriters;
    o.design.walk([&](Operation *op) {
      if (!isa<sim::SimCallOp, sim::SimTaskCallOp, sim::SimRefCopyOp,
               sim::SimOverrideOp, sim::SimDynamicOverrideOp>(op))
        return;
      auto fn = op->getParentOfType<sim::SimFuncOp>();
      if (!fn)
        return;
      for (Value operand : op->getOperands())
        if (isa<sim::RefType>(operand.getType()))
          if (auto id = storageID(operand, fn))
            opaqueWriters.insert(*id);
    });
    for (auto decl : o.design.getOps<sim::SimStorageDeclOp>()) {
      if (!decl.getHierarchicalName() ||
          !contains(o.domain, *decl.getHierarchicalName()))
        continue;
      Register reg;
      reg.declaration = decl;
      reg.visible = {decl.getId(), decl.getType()};
      reg.aliases.push_back({*decl.getHierarchicalName(), decl.getScopeId()});
      for (auto port : aliases.lookup(decl.getId()))
        reg.aliases.push_back({port.getHierarchicalName(), port.getScopeId(),
                               port.getSourceLow() != 0 ||
                                   sim::getPackedWidth(port.getType()) !=
                                       sim::getPackedWidth(decl.getType())});
      reg.writers = writers.lookup(decl.getId());
      bool state = opaqueWriters.contains(decl.getId());
      for (auto *op : reg.writers) {
        auto fn = op->getParentOfType<sim::SimFuncOp>();
        // The common clocked process is classified once, before considering
        // register-specific definite assignment in a combinational process.
        // Do not rescan a large flip-flop process for every written register.
        if (state ||
            (!startup(fn) &&
             (edgeWriter(fn) || !completeLevelWriter(fn, decl.getId())))) {
          state = true;
          break;
        }
      }
      if (!state)
        continue;
      unsigned best = 0;
      bool partial = false;
      upf::RetentionAttr ambiguous;
      for (auto attribute : o.domain.getRetentionsAttr()) {
        auto strategy = cast<upf::RetentionAttr>(attribute);
        bool partialMatch = false;
        unsigned precedence = rank(strategy, reg, partialMatch);
        if (precedence == 0 || precedence < best)
          continue;
        if (precedence == best && reg.strategy != strategy) {
          ambiguous = strategy;
          continue;
        }
        ambiguous = {};
        best = precedence;
        reg.strategy = strategy;
        partial = partialMatch;
      }
      if (ambiguous) {
        auto diagnostic = emitError(location(ambiguous))
                          << "ambiguous retention strategies for "
                          << *decl.getHierarchicalName()
                          << " (IEEE 1801-2018 5.7.3/5.7.9)";
        diagnostic.attachNote(location(reg.strategy))
            << "other strategy is declared here";
        return failure();
      }
      if (!reg.strategy || reg.strategy.getNoRetention())
        continue;
      if (opaqueWriters.contains(decl.getId()))
        return decl.emitError("retained storage may be written through an "
                              "unsupported helper, copy or override");
      if (partial)
        return decl.emitError(
            "retention through a partial port alias is not implemented");
      if (reg.strategy.getSave() || reg.strategy.getRestore())
        return emitError(location(reg.strategy))
               << "retention simulation lowering is not implemented for "
                  "balloon-style strategies";
      if (!supportedState(decl.getType()))
        return decl.emitError("retention requires packed integral state");
      llvm::DenseSet<Operation *> functions;
      bool blocking = false, nonblocking = false;
      for (auto *op : reg.writers) {
        auto fn = op->getParentOfType<sim::SimFuncOp>();
        if (startup(fn)) {
          if (!isa<sim::SimRefStoreOp>(op))
            return op->emitError(
                "nonblocking retention initialization is not implemented");
          continue;
        }
        if (!edgeWriter(fn))
          return op->emitError(
              "retention requires one top-level edge-sensitive event control; "
              "latch, mixed level/edge, computed, timed and helper writers are "
              "not "
              "implemented (IEEE 1801-2018 6.50/9.7.3)");
        Value destination =
            isa<sim::SimRefStoreOp>(op)
                ? cast<sim::SimRefStoreOp>(op).getReference()
                : cast<sim::SimNBAEnqueueOp>(op).getDestination();
        if (!references.isWhole(destination))
          return op->emitError("partial retention writes are not implemented");
        functions.insert(fn);
        blocking |= isa<sim::SimRefStoreOp>(op);
        nonblocking |= isa<sim::SimNBAEnqueueOp>(op);
      }
      if (blocking && nonblocking)
        return decl.emitError(
            "mixed blocking/nonblocking retention writers are not implemented");
      if (functions.size() != 1)
        return decl.emitError(
            "retention requires one sequential writer per register");
      if (reg.strategy.getUseRetentionAsPrimary() &&
          o.domain.getIsolationControl())
        // IEEE 1801-2018 6.50 Note 2 changes the driver supply used by
        // 6.45's default diff_supply_only filter. The current whole-boundary
        // mux cannot prove that selection for mixed RET/primary outputs.
        return emitError(location(reg.strategy))
               << "isolation of retention-powered outputs requires per-path "
                  "supply filtering and is not implemented";
      registers.push_back(std::move(reg));
    }
    // A reference passed to a helper can hide a writer outside the local
    // inventory. Index roots once instead of walking the design per register.
    llvm::DenseMap<uint64_t, SmallVector<Value>> roots;
    if (!registers.empty()) {
      o.design.walk([&](sim::SimContextStorageOp ref) {
        roots[ref.getId()].push_back(ref.getResult());
      });
      for (auto fn : o.design.getOps<sim::SimFuncOp>())
        for (auto [index, arg] : llvm::enumerate(fn.getArguments()))
          if (isa<sim::RefType>(arg.getType()))
            if (auto attr = fn.getArgAttrOfType<IntegerAttr>(
                    index, sim::metadata::DescriptorId::getNameStr()))
              roots[attr.getUInt()].push_back(arg);
    }
    for (auto &reg : registers) {
      llvm::DenseSet<Value> seen;
      llvm::DenseSet<Operation *> knownWriters(reg.writers.begin(),
                                               reg.writers.end());
      SmallVector<Value> pending(roots.lookup(reg.visible.id));
      while (!pending.empty()) {
        Value value = pending.pop_back_val();
        if (!seen.insert(value).second)
          continue;
        for (Operation *use : value.getUsers()) {
          if (auto view = dyn_cast<ViewLikeOpInterface>(use)) {
            if (view.getViewSource() == value && isMemoryEffectFree(use)) {
              pending.append(use->getResults().begin(),
                             use->getResults().end());
              continue;
            }
          }
          if (isa<sim::SimRefLoadOp>(use))
            continue;
          if (isa<sim::SimRefStoreOp, sim::SimNBAEnqueueOp>(use)) {
            if (!knownWriters.contains(use))
              return use->emitError(
                  "retained storage has an unsupported captured writer");
            continue;
          }
          if (auto bind = dyn_cast<sim::SimObserverBindOp>(use)) {
            auto evaluator =
                SymbolTable::lookupNearestSymbolFrom<sim::SimFuncOp>(
                    bind, bind.getEvaluatorAttr());
            // Dependencies observe publications; captured references execute
            // inside the evaluator and need the same closed writer audit.
            for (auto [index, capture] : llvm::enumerate(bind.getCaptures()))
              if (capture == value) {
                if (!evaluator)
                  return bind.emitError(
                      "retained observer capture requires a defined evaluator");
                pending.push_back(evaluator.getArgument(index + 1));
              }
            continue;
          }
          if (sim::isSuspensionOp(use)) {
            auto branch = cast<BranchOpInterface>(use);
            for (unsigned index = 0; index != use->getNumSuccessors();
                 ++index) {
              auto operands = branch.getSuccessorOperands(index);
              for (unsigned lane = 0; lane != operands.size(); ++lane)
                if (!operands.isOperandProduced(lane) &&
                    operands[lane] == value)
                  pending.push_back(
                      use->getSuccessor(index)->getArgument(lane));
            }
            continue;
          }
          if (auto spawn = dyn_cast<sim::SimSpawnOp>(use)) {
            auto callee = SymbolTable::lookupNearestSymbolFrom<sim::SimFuncOp>(
                spawn, spawn.getCalleeAttr());
            if (callee) {
              bool captured = true;
              for (auto [index, operand] : llvm::enumerate(spawn.getOperands()))
                if (operand == value) {
                  auto attr = callee.getArgAttrOfType<IntegerAttr>(
                      index, sim::metadata::DescriptorId::getNameStr());
                  captured &= attr && attr.getUInt() == reg.visible.id;
                  if (captured)
                    pending.push_back(callee.getArgument(index));
                }
              if (captured)
                continue;
            }
          }
          return use->emitError("retained storage escapes through an "
                                "unsupported reference consumer");
        }
      }
    }
    return success();
  }
  Value bit(Location loc, bool value) {
    return arith::ConstantIntOp::create(b, loc, value, 1);
  }
  Value negate(Location loc, Value value) {
    return arith::XOrIOp::create(b, loc, value, bit(loc, true));
  }
  SmallVector<upf::UPFSupplySetOp> policies(FlatSymbolRefAttr root) {
    SmallVector<upf::UPFSupplySetOp> result;
    llvm::DenseSet<Operation *> seen;
    llvm::DenseSet<Operation *> included;
    SmallVector<std::pair<upf::UPFSupplySetOp, bool>> pending{
        {SymbolTable::lookupNearestSymbolFrom<upf::UPFSupplySetOp>(o.domain,
                                                                   root),
         true}};
    while (!pending.empty()) {
      auto [set, supplier] = pending.pop_back_val();
      if (!set)
        continue;
      // 6.10: strategy handles have local state catalogs. Traverse
      // electrical equivalence, admitting the selected handle and its
      // supplying catalogs, but never an unrelated consumer strategy's
      // private policy.
      if ((supplier || (!set.getOwnerAttr() && !set.getStrategyAttr())) &&
          included.insert(set).second)
        result.push_back(set);
      if (!seen.insert(set).second)
        continue;
      if (auto associated = set.getAssociatedAttr())
        for (auto attr : llvm::reverse(associated))
          pending.emplace_back(
              SymbolTable::lookupNearestSymbolFrom<upf::UPFSupplySetOp>(
                  set, cast<FlatSymbolRefAttr>(attr)),
              false);
      if (auto source = set.getBindingAttr())
        pending.emplace_back(
            SymbolTable::lookupNearestSymbolFrom<upf::UPFSupplySetOp>(set,
                                                                      source),
            true);
    }
    return result;
  }
  Value normal(Location loc, Value ctx, ArrayRef<upf::UPFSupplySetOp> sets) {
    Value value = bit(loc, true);
    for (auto set : sets) {
      auto evaluation =
          evaluateSupplySet(set, b, loc, [&](FlatSymbolRefAttr ref) {
            return o.readSupply(b, loc, ctx, ref);
          });
      value = arith::AndIOp::create(b, loc, value, evaluation.normal);
    }
    return value;
  }
  Value primary(Strategy &s, Location loc, Value ctx) {
    return arith::AndIOp::create(b, loc, o.domainNormal(b, loc, ctx),
                                 normal(loc, ctx, s.primary));
  }
  Value rtc(Strategy &s, Location loc, Value ctx) {
    return Expression(s.attribute.getCondition())
        .predicate(b, loc, ctx, o.descriptors);
  }
  Value canWrite(Strategy &s, Location loc, Value ctx) {
    Value on = arith::AndIOp::create(b, loc, primary(s, loc, ctx),
                                     normal(loc, ctx, s.retention));
    return arith::AndIOp::create(b, loc, on, negate(loc, rtc(s, loc, ctx)));
  }
  Value bad(Strategy &s, Location loc, Value ctx) {
    // IEEE 1801-2018 9.7.3 Table 11: master/slave storage is destroyed
    // whenever retention power is lost, or RTC is not True while primary is
    // off.
    return arith::OrIOp::create(
        b, loc, negate(loc, normal(loc, ctx, s.retention)),
        arith::AndIOp::create(b, loc, negate(loc, primary(s, loc, ctx)),
                              negate(loc, rtc(s, loc, ctx))));
  }
  Value pending(Location loc, Value ctx, Descriptor actor) {
    return sim::SimProcessEventPendingOp::create(
        b, loc, b.getI1Type(), load(b, loc, handle(b, loc, ctx, actor)));
  }
  Value allowed(Strategy &s, Location loc, Value ctx) {
    // IEEE 1801-2018 9.7.3 gives RTC priority while it is True. A later
    // clock after RTC falls can write in the same Active batch. Captured
    // epochs invalidate older NBAs without suppressing that later clock.
    Value event = arith::OrIOp::create(b, loc, pending(loc, ctx, s.badProcess),
                                       pending(loc, ctx, s.freezeProcess));
    return arith::AndIOp::create(b, loc, canWrite(s, loc, ctx),
                                 negate(loc, event));
  }
  void cancel(Strategy &s, Location loc, Value ctx) {
    Value reference = handle(b, loc, ctx, s.epoch);
    Value next =
        arith::AddIOp::create(b, loc, load(b, loc, reference),
                              arith::ConstantIntOp::create(b, loc, 1, 64));
    store(b, loc, reference, next);
    for (auto *reg : s.registers)
      for (auto descriptor : {reg->visible, reg->backing})
        sim::SimPowerCancelNBAOp::create(b, loc, ctx,
                                         handle(b, loc, ctx, descriptor),
                                         *sim::getPackedWidth(descriptor.type));
  }
  void corruptBacking(Strategy &s, Location loc, Value ctx,
                      bool invalidate = true) {
    if (invalidate)
      cancel(s, loc, ctx);
    for (auto *reg : s.registers)
      store(b, loc, handle(b, loc, ctx, reg->backing),
            corrupt(b, loc, reg->backing.type));
  }
  void callUpdate(Strategy &s, Location loc, Value ctx) {
    sim::SimCallOp::create(
        b, loc, TypeRange{},
        FlatSymbolRefAttr::get(b.getContext(), s.update.getSymName()),
        ValueRange{ctx}, ArrayAttr{}, ArrayAttr{});
  }
  void conditional(Location loc, Value condition,
                   llvm::function_ref<void()> body) {
    auto *source = b.getInsertionBlock();
    auto *function = source->getParent();
    auto *execute = new Block, *next = new Block;
    function->push_back(execute);
    function->push_back(next);
    cf::CondBranchOp::create(b, loc, condition, execute, next);
    b.setInsertionPointToEnd(execute);
    body();
    cf::BranchOp::create(b, loc, next);
    b.setInsertionPointToEnd(next);
  }
  void makeUpdate(Strategy &s) {
    Location loc = location(s.attribute);
    std::string name = "__upf_retention." + o.domain.getSymName().str() + "." +
                       s.attribute.getName().getValue().str();
    s.update = o.function(loc, name + ".update",
                          {sim::ContextType::get(b.getContext())},
                          sim::EntryKind::Function);
    sim::mark<sim::metadata::PowerMonitor>(s.update);
    b.setInsertionPointToEnd(&s.update.getBody().front());
    Value ctx = s.update.getArgument(0);
    // IEEE 1801-2018 9.7.3: a destructive event may still be pending when
    // the freeze handler wins scheduler priority. Never republish stale data.
    Value destructive = arith::OrIOp::create(b, loc, bad(s, loc, ctx),
                                             pending(loc, ctx, s.badProcess));
    conditional(loc, destructive, [&] { corruptBacking(s, loc, ctx, false); });
    // IEEE 1801-2018 6.50/9.7.3 Table 12: RET can power the output during
    // primary shutdown. Functional writes still require primary power in
    // canWrite(); neither the data input nor its supply handle is rebound.
    Value visible = normal(loc, ctx, s.retention);
    if (!s.attribute.getUseRetentionAsPrimary())
      visible = arith::AndIOp::create(b, loc, primary(s, loc, ctx), visible);
    Value previous = handle(b, loc, ctx, s.visible);
    Value changed = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ne,
                                          visible, load(b, loc, previous));
    conditional(loc, changed, [&] {
      // Output masking changes invalidate queued output publications without
      // replacing the retained value with the corrupt visible value.
      for (auto *reg : s.registers)
        sim::SimPowerCancelNBAOp::create(
            b, loc, ctx, handle(b, loc, ctx, reg->visible),
            *sim::getPackedWidth(reg->visible.type));
    });
    store(b, loc, previous, visible);
    for (auto *reg : s.registers) {
      // Select whole packed values with CFG, preserving 2/4-state and declared
      // packed layout, including non-host widths and ascending dimensions.
      auto *on = new Block, *off = new Block, *merge = new Block;
      auto &region = s.update.getBody();
      region.push_back(on);
      region.push_back(off);
      region.push_back(merge);
      merge->addArgument(reg->visible.type, loc);
      cf::CondBranchOp::create(b, loc, visible, on, off);
      b.setInsertionPointToEnd(on);
      cf::BranchOp::create(b, loc, merge,
                           load(b, loc, handle(b, loc, ctx, reg->backing)));
      b.setInsertionPointToEnd(off);
      cf::BranchOp::create(b, loc, merge, corrupt(b, loc, reg->visible.type));
      b.setInsertionPointToEnd(merge);
      store(b, loc, handle(b, loc, ctx, reg->visible), merge->getArgument(0));
    }
    sim::SimReturnOp::create(b, loc, ValueRange{});
    result.updates.push_back(
        FlatSymbolRefAttr::get(b.getContext(), s.update.getSymName()));
  }
  sim::SimFuncOp observer(Location loc, StringRef name) {
    auto fn = o.function(loc, name, {sim::ContextType::get(b.getContext())},
                         sim::EntryKind::Observer);
    fn.setFunctionType(b.getFunctionType(
        {sim::ContextType::get(b.getContext())}, {b.getI1Type()}));
    schedule::set<schedule::Field::ObserverWidth>(fn, b.getI32IntegerAttr(1));
    schedule::set<schedule::Field::ObserverFourState>(fn, b.getBoolAttr(false));
    return fn;
  }
  void makePredicate(Strategy &s) {
    Location loc = location(s.attribute);
    s.predicate = observer(loc, s.update.getSymName().str() + ".allowed");
    b.setInsertionPointToEnd(&s.predicate.getBody().front());
    sim::SimReturnOp::create(b, loc,
                             allowed(s, loc, s.predicate.getArgument(0)));
  }
  void eventActor(Strategy &s, StringRef suffix, bool destructive) {
    Location loc = location(s.attribute);
    std::string name = s.update.getSymName().str() + suffix.str();
    auto evaluator = observer(loc, name + ".evaluate");
    b.setInsertionPointToEnd(&evaluator.getBody().front());
    Value evaluated =
        destructive ? bad(s, loc, evaluator.getArgument(0))
                    : negate(loc, canWrite(s, loc, evaluator.getArgument(0)));
    sim::SimReturnOp::create(b, loc, evaluated);
    auto actor = o.function(loc, name, {sim::ContextType::get(b.getContext())},
                            sim::EntryKind::Fork);
    sim::mark<sim::metadata::PowerMonitor>(actor);
    schedule::set<schedule::Field::DetachedControls>(actor, b.getUnitAttr());
    schedule::set<schedule::Field::PrimeOnSpawn>(actor, b.getUnitAttr());
    schedule::set<schedule::Field::PrioritySignalResume>(actor,
                                                         b.getUnitAttr());
    Value ctx = actor.getArgument(0);
    auto *wait = new Block, *event = new Block;
    actor.getBody().push_back(wait);
    actor.getBody().push_back(event);
    b.setInsertionPointToEnd(&actor.getBody().front());
    cf::BranchOp::create(b, loc, wait);
    b.setInsertionPointToEnd(wait);
    SmallVector<Value> dependencies;
    for (auto descriptor : s.dependencies)
      dependencies.push_back(handle(b, loc, ctx, descriptor));
    Value observer = sim::SimObserverBindOp::create(
        b, loc, sim::ObserverType::get(b.getContext(), b.getI1Type()),
        evaluator.getSymNameAttr(), dependencies, uint32_t{0});
    Value initial =
        destructive ? bad(s, loc, ctx) : negate(loc, canWrite(s, loc, ctx));
    sim::SimSuspendObserveOp::create(
        b, loc, ValueRange{observer, initial}, uint32_t{0},
        b.getDenseI32ArrayAttr({1}), b.getDenseI32ArrayAttr({-1}),
        schedule::ContinuationSiteAttr{}, sim::EventRegionAttr{}, event);
    b.setInsertionPointToEnd(event);
    // Act on the latched occurrence even if the current predicate recovered.
    // Otherwise a zero-time OFF/ON or RTC pulse could revive a delayed write.
    if (destructive)
      corruptBacking(s, loc, ctx);
    else
      cancel(s, loc, ctx);
    callUpdate(s, loc, ctx);
    cf::BranchOp::create(b, loc, wait);
    rootInsertion();
    Value spawned = sim::SimSpawnOp::create(b, loc, actor.getSymNameAttr(),
                                            ValueRange{o.root.getArgument(0)},
                                            ArrayAttr{}, ArrayAttr{});
    store(b, loc,
          handle(b, loc, o.root.getArgument(0),
                 destructive ? s.badProcess : s.freezeProcess),
          spawned);
  }
  void rootInsertion() { b.setInsertionPoint(rootBoundary); }
  Value cloneView(Value value, sim::SimFuncOp fn, Descriptor backing) {
    SmallVector<Operation *> projections;
    Value source = value;
    while (auto view = source.getDefiningOp<ViewLikeOpInterface>()) {
      projections.push_back(view.getOperation());
      source = view.getViewSource();
    }
    IRMapping mapping;
    mapping.map(source, handle(b, fn.getLoc(), fn.getArgument(0), backing));
    for (Operation *projection : llvm::reverse(projections)) {
      Operation *copy = b.clone(*projection, mapping);
      mapping.map(projection->getResults(), copy->getResults());
    }
    return mapping.lookup(value);
  }
  void guard(Operation *op, Value valid, llvm::function_ref<void()> emit) {
    Location loc = op->getLoc();
    auto *before = op->getBlock();
    auto *execute = before->splitBlock(Block::iterator(op));
    auto *next = execute->splitBlock(std::next(execute->begin()));
    b.setInsertionPointToEnd(before);
    cf::CondBranchOp::create(b, loc, valid, execute, next);
    b.setInsertionPoint(op);
    emit();
    b.setInsertionPointToEnd(execute);
    cf::BranchOp::create(b, loc, next);
  }
  void enqueue(Strategy &s, Register &reg, Location loc, Value ctx, Value value,
               Value domainEpoch, Value strategyEpoch, Value delay) {
    SmallVector<Value> dependencies;
    for (auto descriptor : s.dependencies)
      dependencies.push_back(handle(b, loc, ctx, descriptor));
    Value predicate = sim::SimObserverBindOp::create(
        b, loc, sim::ObserverType::get(b.getContext(), b.getI1Type()),
        s.predicate.getSymNameAttr(), dependencies, uint32_t{0});
    sim::SimPowerNBAOp::create(
        b, loc, ctx, value, handle(b, loc, ctx, reg.backing),
        handle(b, loc, ctx, reg.visible), predicate,
        handle(b, loc, ctx, o.domainEpoch), domainEpoch,
        handle(b, loc, ctx, s.epoch), strategyEpoch, delay);
  }
  void nba(Strategy &s, Register &reg, sim::SimNBAEnqueueOp op,
           Value domainEpoch, Value strategyEpoch) {
    Location loc = op.getLoc();
    auto fn = op->getParentOfType<sim::SimFuncOp>();
    // IEEE 1800-2023 4.6(b)/10.4.2: queue at the original statement. A
    // detached helper would reorder delayed writes by helper identity and
    // defer a dynamic zero delay to Inactive instead of enqueueing now.
    enqueue(s, reg, loc, fn.getArgument(0), op.getValue(), domainEpoch,
            strategyEpoch, op.getDelay());
    op.erase();
  }
  LogicalResult lower() {
    if (failed(plan()))
      return failure();
    for (auto &reg : registers) {
      auto found = llvm::find_if(strategies, [&](const Strategy &s) {
        return s.attribute == reg.strategy;
      });
      if (found == strategies.end()) {
        Strategy strategy;
        strategy.attribute = reg.strategy;
        strategies.push_back(std::move(strategy));
        found = std::prev(strategies.end());
      }
      found->registers.push_back(&reg);
      result.storage.insert(reg.visible.id);
    }
    for (auto &s : strategies) {
      Location loc = location(s.attribute);
      std::string name = "__upf_retention." + o.domain.getSymName().str() +
                         "." + s.attribute.getName().getValue().str();
      s.primary = policies(s.attribute.getPrimarySupply());
      s.retention = policies(s.attribute.getRetentionSupply());
      llvm::DenseSet<std::pair<uint64_t, uint32_t>> seen;
      auto add = [&](Descriptor descriptor) {
        if (seen.insert({descriptor.id, descriptor.net}).second)
          s.dependencies.push_back(descriptor);
      };
      for (auto descriptor : o.domainDependencies)
        add(descriptor);
      for (auto set : llvm::concat<upf::UPFSupplySetOp>(s.primary, s.retention))
        for (auto ref : getSupplySetReferences(set))
          for (auto dependency : o.supplyDependencies(ref))
            add(dependency);
      for (auto path : Expression(s.attribute.getCondition()).controls) {
        auto found = o.descriptors.find(path);
        if (found == o.descriptors.end())
          return emitError(loc)
                 << "retention control is absent from simulation storage: "
                 << path;
        add(found->second);
      }
      s.epoch = o.storage(loc, name + ".epoch", b.getI64Type());
      s.visible = o.storage(loc, name + ".visible", b.getI1Type());
      s.badProcess = o.storage(loc, name + ".bad_process",
                               sim::ProcessType::get(b.getContext()));
      s.freezeProcess = o.storage(loc, name + ".freeze_process",
                                  sim::ProcessType::get(b.getContext()));
      for (auto *reg : s.registers)
        reg->backing =
            o.storage(reg->declaration.getLoc(),
                      name + ".backing." + std::to_string(reg->visible.id),
                      reg->visible.type);
      makeUpdate(s);
      makePredicate(s);
      rootInsertion();
      Value ctx = o.root.getArgument(0);
      store(b, loc, handle(b, loc, ctx, s.epoch),
            arith::ConstantIntOp::create(b, loc, 0, 64));
      store(b, loc, handle(b, loc, ctx, s.visible), bit(loc, false));
      for (auto *reg : s.registers)
        store(b, loc, handle(b, loc, ctx, reg->backing),
              load(b, loc, handle(b, loc, ctx, reg->visible)));
      eventActor(s, ".bad", true);
      eventActor(s, ".freeze", false);
      auto monitor = o.function(loc, name + ".monitor",
                                {sim::ContextType::get(b.getContext())},
                                sim::EntryKind::Fork);
      sim::mark<sim::metadata::PowerMonitor>(monitor);
      schedule::set<schedule::Field::DetachedControls>(monitor,
                                                       b.getUnitAttr());
      schedule::set<schedule::Field::PrimeOnSpawn>(monitor, b.getUnitAttr());
      schedule::set<schedule::Field::PrioritySignalResume>(monitor,
                                                           b.getUnitAttr());
      auto *loop = new Block;
      monitor.getBody().push_back(loop);
      b.setInsertionPointToEnd(&monitor.getBody().front());
      cf::BranchOp::create(b, loc, loop);
      b.setInsertionPointToEnd(loop);
      Value monitorCtx = monitor.getArgument(0);
      callUpdate(s, loc, monitorCtx);
      SmallVector<Value> watched;
      for (auto descriptor : s.dependencies)
        watched.push_back(handle(b, loc, monitorCtx, descriptor));
      for (auto *reg : s.registers)
        watched.push_back(handle(b, loc, monitorCtx, reg->backing));
      sim::SimSuspendAnyOp::create(
          b, loc, watched,
          b.getDenseI32ArrayAttr(SmallVector<int32_t>(watched.size(), 0)),
          schedule::ContinuationSiteAttr{}, sim::EventRegionAttr{}, loop);
      rootInsertion();
      sim::SimSpawnOp::create(b, loc, monitor.getSymNameAttr(), ValueRange{ctx},
                              ArrayAttr{}, ArrayAttr{});
      for (auto *reg : s.registers)
        for (auto *op : reg->writers) {
          auto fn = op->getParentOfType<sim::SimFuncOp>();
          b.setInsertionPoint(op);
          Value context = fn.getArgument(0);
          if (startup(fn)) {
            auto write = cast<sim::SimRefStoreOp>(op);
            Value destination =
                cloneView(write.getReference(), fn, reg->backing);
            store(b, op->getLoc(), destination, write.getValue());
            continue;
          }
          Value domainSnapshot, strategySnapshot;
          if (isa<sim::SimNBAEnqueueOp>(op)) {
            domainSnapshot =
                load(b, op->getLoc(),
                     handle(b, op->getLoc(), context, o.domainEpoch));
            strategySnapshot = load(b, op->getLoc(),
                                    handle(b, op->getLoc(), context, s.epoch));
          }
          Value valid = allowed(s, op->getLoc(), context);
          guard(op, valid, [&] {
            if (auto write = dyn_cast<sim::SimRefStoreOp>(op)) {
              // Preserve visible RHS/program order; mirror only this value.
              store(b, op->getLoc(),
                    handle(b, op->getLoc(), context, reg->backing),
                    write.getValue());
            } else {
              auto enqueue = cast<sim::SimNBAEnqueueOp>(op);
              nba(s, *reg, enqueue, domainSnapshot, strategySnapshot);
            }
          });
        }
    }
    return success();
  }
};
} // namespace
LogicalResult lowerRetentions(const RetentionLoweringOptions &options,
                              RetentionLoweringResult &result) {
  return Lowering(options, result).lower();
}
} // namespace talos
