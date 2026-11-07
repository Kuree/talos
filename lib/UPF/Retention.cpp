#include "Retention.h"
#include "BalloonRetention.h"
#include "ClockSnapshot.h"
#include "PowerState.h"
#include "PublicationCallback.h"
#include "ReferenceWindow.h"
#include "RetentionReadback.h"
#include "RetentionSelection.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/IR/DerivedTypes.h"
#include <limits>
#include <map>
#include <set>
using namespace mlir;
namespace talos {
namespace {
using namespace upf_detail;
using Alias = RetentionAlias;
using Register = RetentionRegister;
struct Strategy {
  upf::RetentionAttr attribute;
  SmallVector<Register *> registers;
  SmallVector<upf::UPFSupplySetOp> primary, retention;
  SmallVector<Descriptor> dependencies;
  Descriptor epoch, previousWritable, previousBad;
  sim::SimFuncOp predicate, outputPredicate;
  llvm::DenseMap<Operation *, FrozenClock> clocks;
};
struct Lowering {
  RetentionLoweringOptions o;
  RetentionLoweringResult &result;
  OpBuilder b;
  ReferenceWindows references;
  SmallVector<Register> registers;
  SmallVector<Strategy, 0> strategies;
  llvm::DenseMap<uint64_t, sim::SimScopeDeclOp> scopes;
  llvm::DenseMap<uint64_t, uint64_t> unitScopes;
  llvm::DenseMap<uint64_t, uint64_t> instanceOwners;
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
    for (auto unit : this->o.design.getOps<sim::SimCodeUnitDeclOp>())
      unitScopes[unit.getId()] = unit.getScopeId();
    for (auto port : this->o.design.getOps<sim::SimPortDeclOp>())
      if (!port.getSourceIsNet())
        aliases[port.getSourceId()].push_back(port);
    if (!this->o.root)
      return;
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
                                     : o.design.getLoc();
  }
  uint64_t owner(uint64_t scope) {
    llvm::DenseSet<uint64_t> seen;
    while (seen.insert(scope).second) {
      if (auto known = instanceOwners.find(scope);
          known != instanceOwners.end()) {
        scope = known->second;
        break;
      }
      auto declaration = scopes.lookup(scope);
      if (!declaration || declaration.getDefinitionName() ||
          declaration.getVpiDefinitionAttr() || declaration.getInterfaceType())
        break;
      if (!declaration.getParent())
        break;
      scope = *declaration.getParent();
    }
    for (auto visited : seen)
      instanceOwners[visited] = scope;
    return scope;
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
    if (fn.getEntryKind() == sim::EntryKind::RootInitializer ||
        fn.getEntryKind() == sim::EntryKind::Initial)
      // IEEE 1801-2018 9.2.1 exempts Initial execution at every scheduled
      // time. Only functional clocked writers use policy/epoch issue guards.
      return true;
    // Declaration initializers are zero-time functions called by the root
    // before spawning any HDL process (1801-2018 9.2.1).
    if (!initializers.contains(fn))
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
  LogicalResult plan(RetentionSelection &selection) {
    llvm::DenseMap<uint64_t, StringRef> processBindings;
    llvm::StringSet<> processNames;
    llvm::StringSet<> requestedProcesses;
    for (auto unit : o.design.getOps<sim::SimCodeUnitDeclOp>())
      if (auto name = unit.getSourceProcess()) {
        processBindings[unit.getId()] = *name;
        processNames.insert(*name);
      }
    for (auto &entry : selection.processes()) {
      StringRef name = entry.getKey();
      if (!processNames.contains(name))
        return o.design.emitError()
               << "retention process selector has no source-code-unit binding: "
               << name;
      requestedProcesses.insert(name);
    }
    // Preserve the producing procedure across direct calls. Unsupported helper
    // writers must reach the ordinary writer diagnostic after selection, rather
    // than disappear because their stores live in another executable unit.
    llvm::DenseMap<Operation *, SmallVector<StringRef>> origins;
    llvm::DenseMap<Operation *, SmallVector<sim::SimFuncOp>> callees;
    SymbolTableCollection processSymbols;
    SmallVector<std::pair<sim::SimFuncOp, StringRef>> pending;
    for (auto fn : o.design.getOps<sim::SimFuncOp>())
      if (auto id = fn.getCodeUnitId()) {
        auto found = processBindings.find(*id);
        if (found != processBindings.end() &&
            requestedProcesses.contains(found->second) &&
            fn.getEntryKind() != sim::EntryKind::Initial &&
            fn.getEntryKind() != sim::EntryKind::Final)
          pending.emplace_back(fn, found->second);
      }
    llvm::DenseSet<std::pair<Operation *, StringRef>> visited;
    while (!pending.empty()) {
      auto item = pending.pop_back_val();
      auto fn = item.first;
      StringRef name = item.second;
      if (!visited.insert({fn.getOperation(), name}).second)
        continue;
      origins[fn].push_back(name);
      auto entry = callees.try_emplace(fn);
      if (entry.second) {
        auto &targets = entry.first->second;
        WalkResult calls = fn.walk([&](Operation *op) {
          if (isa<sim::SimSpawnOp, sim::SimClassVirtualCallOp,
                  sim::SimClassVirtualTaskCallOp>(op)) {
            op->emitError("retention process selection through forked or "
                          "indirect work is not implemented");
            return WalkResult::interrupt();
          }
          if (auto call = dyn_cast<sim::SimDPICallOp>(op))
            if (call.getIsContext()) {
              call.emitError("retention process selection through context DPI "
                             "calls is not implemented");
              return WalkResult::interrupt();
            }
          if (!isa<sim::SimCallOp, sim::SimTaskCallOp,
                   sim::SimClassDirectCallOp>(op))
            return WalkResult::advance();
          auto callee = op->getAttrOfType<FlatSymbolRefAttr>("callee");
          auto target = processSymbols.lookupNearestSymbolFrom<sim::SimFuncOp>(
              op, callee);
          if (!target || target.isExternal()) {
            op->emitError("retention process selection requires defined "
                          "compiled call targets");
            return WalkResult::interrupt();
          }
          targets.push_back(target);
          return WalkResult::advance();
        });
        if (calls.wasInterrupted())
          return failure();
      }
      for (auto target : entry.first->second)
        pending.emplace_back(target, name);
    }
    llvm::DenseMap<uint64_t, SmallVector<Operation *>> writers;
    llvm::DenseSet<uint64_t> domainUnits;
    for (auto unit : o.design.getOps<sim::SimCodeUnitDeclOp>())
      if (selection.domain(unit.getHierarchicalName()))
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
    llvm::DenseMap<uint64_t, SmallVector<StringRef>> opaqueOrigins;
    o.design.walk([&](Operation *op) {
      if (!isa<sim::SimCallOp, sim::SimTaskCallOp, sim::SimRefCopyOp,
               sim::SimArgumentRefFromRefOp, sim::SimOverrideOp,
               sim::SimDynamicOverrideOp>(op))
        return;
      auto fn = op->getParentOfType<sim::SimFuncOp>();
      if (!fn)
        return;
      for (Value operand : op->getOperands())
        if (isa<sim::RefType>(operand.getType()))
          if (auto id = storageID(operand, fn)) {
            opaqueWriters.insert(*id);
            for (auto name : origins[fn])
              if (!llvm::is_contained(opaqueOrigins[*id], name))
                opaqueOrigins[*id].push_back(name);
          }
    });
    for (auto decl : o.design.getOps<sim::SimStorageDeclOp>()) {
      if (!decl.getHierarchicalName() ||
          decl.getLifetime() == sim::Lifetime::Automatic)
        continue;
      Register reg;
      reg.domain = selection.domain(*decl.getHierarchicalName());
      reg.declaration = decl;
      reg.visible = {decl.getId(), decl.getType()};
      reg.aliases.push_back({*decl.getHierarchicalName(), decl.getScopeId()});
      for (auto port : aliases.lookup(decl.getId()))
        reg.aliases.push_back({port.getHierarchicalName(), port.getScopeId(),
                               port.getSourceLow() != 0 ||
                                   sim::getPackedWidth(port.getType()) !=
                                       sim::getPackedWidth(decl.getType())});
      reg.writers = writers.lookup(decl.getId());
      reg.processes = opaqueOrigins.lookup(decl.getId());
      for (auto *write : reg.writers)
        for (auto name : origins[write->getParentOfType<sim::SimFuncOp>()])
          if (!llvm::is_contained(reg.processes, name))
            reg.processes.push_back(name);
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
      auto candidates =
          reg.domain ? reg.domain.getRetentionsAttr() : ArrayAttr{};
      for (auto attribute : candidates
                                ? candidates
                                : ArrayAttr::get(o.design.getContext(), {})) {
        auto strategy = cast<upf::RetentionAttr>(attribute);
        bool partialMatch = false;
        unsigned precedence = selection.rank(strategy, reg, partialMatch);
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
      selection.record(reg);
      if (!reg.strategy || reg.strategy.getNoRetention()) {
        // Ordinary roots, including external producers, are instrumented by
        // the global owner-aware write lowering after retention resolution.
        continue;
      }
      if (opaqueWriters.contains(decl.getId()))
        return decl.emitError("retained storage may be written through an "
                              "unsupported helper, copy or override");
      if (partial)
        return decl.emitError(
            "retention through a partial port alias is not implemented");
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
          reg.domain.getIsolationControl() &&
          reg.domain.getIsolationDiffSupplyOnly())
        // IEEE 1801-2018 6.50 Note 2 changes the driver supply used by
        // 6.45's default diff_supply_only filter. The current whole-boundary
        // mux cannot prove that selection for mixed RET/primary outputs.
        // Explicit diff_supply_only FALSE satisfies this filter for any port.
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
    return getRetentionSupplyPolicies(o.domain, root);
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
    Value supply = s.attribute.getRetentionSupplyCorrupt()
                       ? normal(loc, ctx, s.retention)
                       : bit(loc, true);
    Value on = arith::AndIOp::create(b, loc, primary(s, loc, ctx), supply);
    return arith::AndIOp::create(b, loc, on, negate(loc, rtc(s, loc, ctx)));
  }
  Value bad(Strategy &s, Location loc, Value ctx) {
    // IEEE 1801-2018 9.7.3 Table 11: master/slave storage is destroyed
    // by retention loss when RET_SUP_COR is set, by both supplies OFF, or
    // by primary OFF without retention. NO_RET_SUP_COR protects normal
    // storage while primary is ON; it cannot power either store when both
    // supplies are OFF (the unqualified both-OFF row of Table 11).
    Value retentionOff = negate(loc, normal(loc, ctx, s.retention));
    return arith::OrIOp::create(
        b, loc,
        s.attribute.getRetentionSupplyCorrupt() ? retentionOff
                                                : bit(loc, false),
        arith::AndIOp::create(
            b, loc, negate(loc, primary(s, loc, ctx)),
            arith::OrIOp::create(b, loc, retentionOff,
                                 negate(loc, rtc(s, loc, ctx)))));
  }
  Value outputEnabled(Strategy &s, Location loc, Value ctx) {
    Value enabled = normal(loc, ctx, s.retention);
    if (!s.attribute.getUseRetentionAsPrimary()) {
      if (!s.attribute.getRetentionSupplyCorrupt())
        enabled = bit(loc, true);
      enabled = arith::AndIOp::create(b, loc, primary(s, loc, ctx), enabled);
    }
    return enabled;
  }
  std::string strategyName(Strategy &s) {
    return "__upf_retention." + o.domain.getSymName().str() + "." +
           s.attribute.getName().getValue().str();
  }
  Value policy(Strategy &s, Location loc, Value ctx) {
    auto type = b.getIntegerType(3);
    Value value = arith::ExtUIOp::create(b, loc, type, canWrite(s, loc, ctx));
    SmallVector<Value> fields{bad(s, loc, ctx), outputEnabled(s, loc, ctx)};
    for (auto [index, field] : llvm::enumerate(fields)) {
      Value lane = arith::ExtUIOp::create(b, loc, type, field);
      lane = arith::ShLIOp::create(
          b, loc, lane, arith::ConstantIntOp::create(b, loc, index + 1, 3));
      value = arith::OrIOp::create(b, loc, value, lane);
    }
    return value;
  }
  Value policyBit(Location loc, Value value, unsigned index) {
    if (index)
      value = arith::ShRUIOp::create(
          b, loc, value, arith::ConstantIntOp::create(b, loc, index, 3));
    return arith::TruncIOp::create(b, loc, b.getI1Type(), value);
  }
  Value pack(Location loc, ValueRange values) {
    SmallVector<Value> parts;
    bool twoState = true;
    uint64_t width = 0;
    for (Value value : llvm::reverse(values)) {
      value = flatten(b, loc, value);
      uint64_t bits = *sim::getPackedWidth(value.getType());
      width += bits;
      if (isa<IntegerType>(value.getType()))
        value = sim::SimLogicFromBitsOp::create(
            b, loc, sim::LogicType::get(b.getContext(), bits), value);
      else
        twoState = false;
      parts.push_back(value);
    }
    Value result =
        parts.size() == 1
            ? parts.front()
            : sim::SimLogicConcatOp::create(
                  b, loc, sim::LogicType::get(b.getContext(), width), parts);
    if (twoState)
      result = sim::SimLogicToBitsOp::create(b, loc, b.getIntegerType(width),
                                             result);
    return result;
  }
  FailureOr<PublicationCallback>
  callback(Strategy &s, StringRef suffix,
           llvm::function_ref<Value(Value)> body) {
    Location loc = location(s.attribute);
    auto fn = o.function(loc, strategyName(s) + suffix.str(),
                         {sim::ContextType::get(b.getContext())},
                         sim::EntryKind::Observer);
    sim::mark<sim::metadata::PowerMonitor>(fn);
    b.setInsertionPointToEnd(&fn.getBody().front());
    Value result = body(fn.getArgument(0));
    fn.setFunctionType(
        b.getFunctionType(fn.getArgumentTypes(), {result.getType()}));
    schedule::set<schedule::Field::ObserverWidth>(
        fn, b.getI32IntegerAttr(*sim::getPackedWidth(result.getType())));
    schedule::set<schedule::Field::ObserverFourState>(
        fn, b.getBoolAttr(isa<sim::LogicType>(result.getType())));
    sim::SimReturnOp::create(b, loc, result);
    return closePublicationCallback(fn, b);
  }
  LogicalResult makePolicy(Strategy &s) {
    Location loc = location(s.attribute);
    constexpr uint64_t maxWidth = llvm::IntegerType::MAX_INT_BITS;
    struct Target {
      Descriptor descriptor;
      Register *reg = nullptr;
      bool output = false;
    };
    SmallVector<SmallVector<Target>> groups{
        {{s.epoch}, {s.previousWritable}, {s.previousBad}}};
    uint64_t width = 66;
    for (auto *reg : s.registers)
      for (bool output : {false, true}) {
        Descriptor d = output ? reg->visible : reg->backing;
        uint64_t bits = *sim::getPackedWidth(d.type);
        if (bits > maxWidth)
          return emitError(loc)
                 << "master retention target exceeds supported packed width";
        if (bits > maxWidth - width) {
          groups.emplace_back();
          width = 0;
        }
        groups.back().push_back({d, reg, output});
        width += bits;
      }
    auto primaryCallback =
        callback(s, ".policy", [&](Value ctx) { return policy(s, loc, ctx); });
    if (failed(primaryCallback))
      return failure();
    for (auto group : llvm::enumerate(groups)) {
      auto &targets = group.value();
      unsigned index = group.index();
      std::string name = ".policy." + std::to_string(index);
      auto payloadFor = [&](Value ctx, bool initialize) {
        Value fields = policy(s, loc, ctx);
        Value writable = policyBit(loc, fields, 0),
              destructive = policyBit(loc, fields, 1),
              visible = policyBit(loc, fields, 2);
        // A retained Initial write may replace an already-corrupt N. Only
        // a new destructive transition may destroy it again; changing Q's
        // output supply alone must never decide the lifetime of N.
        Value corruptNow =
            initialize
                ? destructive
                : arith::AndIOp::create(
                      b, loc, destructive,
                      negate(loc,
                             load(b, loc, handle(b, loc, ctx, s.previousBad))));
        SmallVector<Value> outputs;
        for (auto target : targets) {
          Value next;
          if (target.reg) {
            next = arith::SelectOp::create(
                b, loc, corruptNow, corrupt(b, loc, target.descriptor.type),
                load(b, loc, handle(b, loc, ctx, target.reg->backing)));
            if (target.output)
              next = arith::SelectOp::create(
                  b, loc, visible, next,
                  corrupt(b, loc, target.descriptor.type));
          } else if (target.descriptor.id == s.epoch.id && initialize) {
            next = load(b, loc, handle(b, loc, ctx, s.epoch));
          } else if (target.descriptor.id == s.epoch.id) {
            Value lostWrite = arith::AndIOp::create(
                b, loc, load(b, loc, handle(b, loc, ctx, s.previousWritable)),
                negate(loc, writable));
            Value becameBad = arith::AndIOp::create(
                b, loc, destructive,
                negate(loc, load(b, loc, handle(b, loc, ctx, s.previousBad))));
            Value invalidate =
                arith::OrIOp::create(b, loc, lostWrite, becameBad);
            next = arith::AddIOp::create(
                b, loc, load(b, loc, handle(b, loc, ctx, s.epoch)),
                arith::ExtUIOp::create(b, loc, b.getI64Type(), invalidate));
          } else {
            next = target.descriptor.id == s.previousWritable.id ? writable
                                                                 : destructive;
          }
          outputs.push_back(next);
        }
        return pack(loc, outputs);
      };
      auto sampler = callback(s, name + ".capture", [&](Value ctx) {
        return payloadFor(ctx, false);
      });
      auto initialize = callback(s, name + ".initialize", [&](Value ctx) {
        return payloadFor(ctx, true);
      });
      if (failed(sampler) || failed(initialize))
        return failure();
      // Apply startup policy exactly once before HDL Initial actors. The
      // callback is pure; initialize from its same bounded packed payload.
      auto owner = o.function(loc, strategyName(s) + name + ".owner",
                              {sim::ContextType::get(b.getContext())},
                              sim::EntryKind::Fork);
      sim::mark<sim::metadata::PowerMonitor>(owner);
      schedule::set<schedule::Field::DetachedControls>(owner, b.getUnitAttr());
      schedule::set<schedule::Field::PrimeOnSpawn>(owner, b.getUnitAttr());
      b.setInsertionPointToEnd(&owner.getBody().front());
      Value ctx = owner.getArgument(0);
      auto call = [&](const PublicationCallback &cb) -> Value {
        auto fn = cb.function;
        return sim::SimCallOp::create(b, loc, fn.getResultTypes(),
                                      fn.getSymNameAttr(),
                                      publicationArguments(b, loc, ctx, cb),
                                      ArrayAttr{}, ArrayAttr{})
            .getResult(0);
      };
      Value payload = call(*initialize);
      if (auto type = dyn_cast<IntegerType>(payload.getType()))
        payload = sim::SimLogicFromBitsOp::create(
            b, loc, sim::LogicType::get(b.getContext(), type.getWidth()),
            payload);
      uint64_t offset = 0;
      for (auto target : targets) {
        uint64_t bits = *sim::getPackedWidth(target.descriptor.type);
        Value value = sim::SimLogicExtractOp::create(
            b, loc, sim::LogicType::get(b.getContext(), bits), payload, offset);
        Type scalar = sim::getPackedScalarType(target.descriptor.type);
        if (isa<IntegerType>(scalar))
          value = sim::SimLogicToBitsOp::create(b, loc, scalar, value);
        if (scalar != target.descriptor.type)
          value = sim::SimPackedUnflattenOp::create(
              b, loc, target.descriptor.type, value);
        store(b, loc, handle(b, loc, ctx, target.descriptor), value);
        offset += bits;
      }
      SmallVector<Value> values{
          bindPublication(b, loc, ctx, *primaryCallback, true),
          call(*primaryCallback),
          bindPublication(b, loc, ctx, *sampler, false)};
      for (auto target : targets)
        values.push_back(handle(b, loc, ctx, target.descriptor));
      // Every admitted functional NBA already carries this exact epoch;
      // Initial retained NBAs are rejected. Do not cancel on benign recovery.
      sim::SimEventSnapshotRegisterOp::create(
          b, loc, ctx, values, targets.size(), 0, b.getDenseI32ArrayAttr({0}),
          b.getDenseI32ArrayAttr({-1}), DenseI32ArrayAttr{});
      auto *parked = new Block;
      owner.getBody().push_back(parked);
      sim::SimSuspendForeverOp::create(b, loc, ValueRange{},
                                       schedule::ContinuationSiteAttr{},
                                       sim::EventRegionAttr{}, parked);
      b.setInsertionPointToEnd(parked);
      sim::SimReturnOp::create(b, loc, ValueRange{});
      rootInsertion();
      sim::SimSpawnOp::create(b, loc, owner.getSymNameAttr(),
                              ValueRange{o.root.getArgument(0)}, ArrayAttr{},
                              ArrayAttr{});
    }
    return success();
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
    s.predicate = observer(loc, strategyName(s) + ".update.allowed");
    b.setInsertionPointToEnd(&s.predicate.getBody().front());
    sim::SimReturnOp::create(b, loc,
                             canWrite(s, loc, s.predicate.getArgument(0)));
    if (s.attribute.getUseRetentionAsPrimary() &&
        !s.attribute.getRetentionSupplyCorrupt()) {
      s.outputPredicate =
          observer(loc, strategyName(s) + ".update.output_allowed");
      b.setInsertionPointToEnd(&s.outputPredicate.getBody().front());
      Value ctx = s.outputPredicate.getArgument(0);
      Value output = arith::AndIOp::create(b, loc, canWrite(s, loc, ctx),
                                           normal(loc, ctx, s.retention));
      sim::SimReturnOp::create(b, loc, output);
    }
  }
  void rootInsertion() { b.setInsertionPoint(rootBoundary); }
  FailureOr<Value> cloneView(Value value, sim::SimFuncOp fn,
                             Descriptor backing) {
    SmallVector<Operation *> projections;
    Value source = value;
    while (auto view = source.getDefiningOp<ViewLikeOpInterface>()) {
      projections.push_back(view.getOperation());
      source = view.getViewSource();
    }
    IRMapping mapping;
    Value replacement = handle(b, fn.getLoc(), fn.getArgument(0), backing);
    if (source.getType() != replacement.getType())
      return failure();
    mapping.map(source, replacement);
    for (Operation *projection : llvm::reverse(projections)) {
      Operation *copy = b.clone(*projection, mapping);
      mapping.map(projection->getResults(), copy->getResults());
    }
    return mapping.lookup(value);
  }
  LogicalResult normalReads(Register &reg, bool initialOnly = false) {
    llvm::DenseSet<Operation *> seen;
    for (auto *writer : reg.writers) {
      auto fn = writer->getParentOfType<sim::SimFuncOp>();
      if ((initialOnly && fn.getEntryKind() != sim::EntryKind::Initial) ||
          (startup(fn) && fn.getEntryKind() != sim::EntryKind::Initial) ||
          !seen.insert(fn).second)
        continue;
      if (!startup(fn)) {
        auto id = fn.getCodeUnitId();
        auto unit = id ? unitScopes.find(*id) : unitScopes.end();
        auto scope = unit == unitScopes.end() ? sim::SimScopeDeclOp{}
                                              : scopes.lookup(unit->second);
        if (!scope)
          return fn.emitError("retention writer has no resolved owning scope");
        // An external producer receives the powered Q output (4.4.3/6.50),
        // even when its data input feeds this register. It must not observe
        // hidden N in either feedback or neighboring expressions. Keep the
        // local inferred-model and Initial own-read interpretations separate.
        if (owner(scope.getId()) != owner(reg.declaration.getScopeId()))
          continue;
      }
      if (failed(validateRetentionReadbackHelpers(
              fn, reg.visible.id, "retention-powered normal-state readback")))
        return failure();
      SmallVector<sim::SimRefLoadOp> loads;
      fn.walk([&](sim::SimRefLoadOp load) {
        if (storageID(load.getReference(), fn) == reg.visible.id)
          loads.push_back(load);
      });
      for (auto load : loads) {
        b.setInsertionPoint(load);
        auto reference = cloneView(load.getReference(), fn, reg.backing);
        if (failed(reference))
          return load.emitError("retention-powered normal-state readback "
                                "through partial captured aliases is not "
                                "implemented");
        load.getReferenceMutable().assign(*reference);
      }
    }
    return success();
  }
  Operation *guard(Operation *op, Value valid,
                   llvm::function_ref<void()> emit) {
    Location loc = op->getLoc();
    auto *before = op->getBlock();
    auto *execute = before->splitBlock(Block::iterator(op));
    auto *next = execute->splitBlock(std::next(execute->begin()));
    b.setInsertionPointToEnd(before);
    auto branch = cf::CondBranchOp::create(b, loc, valid, execute, next);
    b.setInsertionPoint(op);
    emit();
    b.setInsertionPointToEnd(execute);
    cf::BranchOp::create(b, loc, next);
    return branch;
  }
  void enqueue(Strategy &s, Register &reg, Location loc, Value ctx, Value value,
               Value domainEpoch, Value strategyEpoch, Value delay,
               SmallVectorImpl<Operation *> &enqueues) {
    SmallVector<Value> dependencies;
    for (auto descriptor : s.dependencies)
      dependencies.push_back(handle(b, loc, ctx, descriptor));
    Value predicate = sim::SimObserverBindOp::create(
        b, loc, sim::ObserverType::get(b.getContext(), b.getI1Type()),
        s.predicate.getSymNameAttr(), dependencies, uint32_t{0});
    if (s.outputPredicate) {
      // Retention-powered Q can be OFF while primary-powered N still
      // updates under NO_RET_SUP_COR. Keep each Q NBA occurrence, rather
      // than coalescing several backing writes in the output monitor.
      Value zero = arith::ConstantIntOp::create(b, loc, 0, 64);
      Value width = arith::ConstantIntOp::create(
          b, loc, *sim::getPackedWidth(reg.backing.type), 64);
      auto issue = [&](Descriptor target, Value guard) {
        enqueues.push_back(sim::SimPowerNBAViewOp::create(
            b, loc, ctx, value, handle(b, loc, ctx, target), zero, zero, width,
            bit(loc, true), guard, handle(b, loc, ctx, o.domainEpoch),
            domainEpoch, handle(b, loc, ctx, s.epoch), strategyEpoch, delay));
      };
      issue(reg.backing, predicate);
      Value output = sim::SimObserverBindOp::create(
          b, loc, sim::ObserverType::get(b.getContext(), b.getI1Type()),
          s.outputPredicate.getSymNameAttr(), dependencies, uint32_t{0});
      issue(reg.visible, output);
    } else {
      enqueues.push_back(sim::SimPowerNBAOp::create(
          b, loc, ctx, value, handle(b, loc, ctx, reg.backing),
          handle(b, loc, ctx, reg.visible), predicate,
          handle(b, loc, ctx, o.domainEpoch), domainEpoch,
          handle(b, loc, ctx, s.epoch), strategyEpoch, delay));
    }
  }
  void nba(Strategy &s, Register &reg, sim::SimNBAEnqueueOp op,
           Value domainEpoch, Value strategyEpoch,
           SmallVectorImpl<Operation *> &enqueues) {
    Location loc = op.getLoc();
    auto fn = op->getParentOfType<sim::SimFuncOp>();
    // IEEE 1800-2023 4.6(b)/10.4.2: queue at the original statement. A
    // detached helper would reorder delayed writes by helper identity and
    // defer a dynamic zero delay to Inactive instead of enqueueing now.
    enqueue(s, reg, loc, fn.getArgument(0), op.getValue(), domainEpoch,
            strategyEpoch, op.getDelay(), enqueues);
    op.erase();
  }
  LogicalResult lower() {
    registers.assign(o.plan.begin(), o.plan.end());
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
      if (s.attribute.getSave() || s.attribute.getRestore()) {
        SmallVector<BalloonRegister> selected;
        for (auto *reg : s.registers) {
          selected.push_back({reg->declaration, reg->writers});
          for (Operation *op : reg->writers)
            result.publishedProcesses.insert(
                op->getParentOfType<sim::SimFuncOp>().getOperation());
        }
        if (failed(lowerBalloonRetention(o, s.attribute, s.primary, s.retention,
                                         selected, rootBoundary,
                                         result.writes)))
          return failure();
        continue;
      }
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
      s.previousWritable =
          o.storage(loc, name + ".previous_writable", b.getI1Type());
      s.previousBad = o.storage(loc, name + ".previous_bad", b.getI1Type());
      for (auto *reg : s.registers)
        reg->backing =
            o.storage(reg->declaration.getLoc(),
                      name + ".backing." + std::to_string(reg->visible.id),
                      reg->visible.type);
      makePredicate(s);
      for (auto *reg : s.registers)
        if (failed(normalReads(*reg, !s.outputPredicate)))
          return failure();
      rootInsertion();
      Value ctx = o.root.getArgument(0);
      store(b, loc, handle(b, loc, ctx, s.epoch),
            arith::ConstantIntOp::create(b, loc, 0, 64));
      for (auto *reg : s.registers)
        store(b, loc, handle(b, loc, ctx, reg->backing),
              load(b, loc, handle(b, loc, ctx, reg->visible)));
      if (failed(makePolicy(s)))
        return failure();
      for (auto *reg : s.registers)
        for (auto *op : reg->writers) {
          auto fn = op->getParentOfType<sim::SimFuncOp>();
          if (startup(fn) || s.clocks.contains(fn))
            continue;
          auto clock = o.clocks->freeze(
              fn, name + ".clock." + std::to_string(s.clocks.size()), s.epoch,
              [&](OpBuilder &sampleBuilder, Location loc, Value ctx) {
                OpBuilder::InsertionGuard guard(b);
                b.restoreInsertionPoint(sampleBuilder.saveInsertionPoint());
                return canWrite(s, loc, ctx);
              });
          if (failed(clock))
            return failure();
          s.clocks.try_emplace(fn, *clock);
          result.publishedProcesses.insert(fn);
        }
      for (auto *reg : s.registers)
        for (auto *op : reg->writers) {
          auto fn = op->getParentOfType<sim::SimFuncOp>();
          b.setInsertionPoint(op);
          Value context = fn.getArgument(0);
          if (startup(fn)) {
            bool lateRoot = fn == o.root &&
                (op->getBlock() != rootBoundary->getBlock() ||
                 !op->isBeforeInBlock(rootBoundary));
            auto write = cast<sim::SimRefStoreOp>(op);
            auto destination =
                cloneView(write.getReference(), fn, reg->backing);
            if (failed(destination))
              return write.emitError(
                  "retention initialization through a "
                  "partial captured alias is not implemented");
            store(b, op->getLoc(), *destination, write.getValue());
            if (fn.getEntryKind() == sim::EntryKind::Initial || lateRoot)
              write.getValueMutable().assign(arith::SelectOp::create(
                  b, op->getLoc(), outputEnabled(s, op->getLoc(), context),
                  write.getValue(),
                  corrupt(b, op->getLoc(), write.getValue().getType())));
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
          auto clock = s.clocks.lookup(fn);
          Value sameEpoch = arith::CmpIOp::create(
              b, op->getLoc(), arith::CmpIPredicate::eq,
              load(b, op->getLoc(),
                   handle(b, op->getLoc(), context, clock.epoch)),
              load(b, op->getLoc(), handle(b, op->getLoc(), context, s.epoch)));
          Value valid = arith::AndIOp::create(
              b, op->getLoc(), canWrite(s, op->getLoc(), context),
              arith::AndIOp::create(
                  b, op->getLoc(), sameEpoch,
                  load(b, op->getLoc(),
                       handle(b, op->getLoc(), context, clock.valid))));
          SmallVector<Operation *> enqueues;
          auto *branch = guard(op, valid, [&] {
            if (auto write = dyn_cast<sim::SimRefStoreOp>(op)) {
              // Preserve visible RHS/program order; mirror only this value.
              store(b, op->getLoc(),
                    handle(b, op->getLoc(), context, reg->backing),
                    write.getValue());
              if (s.outputPredicate)
                write.getValueMutable().assign(arith::SelectOp::create(
                    b, op->getLoc(), normal(op->getLoc(), context, s.retention),
                    write.getValue(),
                    corrupt(b, op->getLoc(), write.getValue().getType())));
            } else {
              auto enqueue = cast<sim::SimNBAEnqueueOp>(op);
              nba(s, *reg, enqueue, domainSnapshot, strategySnapshot, enqueues);
            }
          });
          result.writes.push_back({o.domainEpoch, branch, std::move(enqueues)});
        }
    }
    return success();
  }
};
} // namespace
LogicalResult planRetentions(sim::SimDesignOp design, sim::SimFuncOp root,
                             const llvm::StringMap<Descriptor> &descriptors,
                             const llvm::StringMap<Descriptor> &supplies,
                             RetentionPlans &plans) {
  auto module = design->getParentOfType<ModuleOp>();
  bool needed = !module.getOps<upf::UPFHierarchyOp>().empty() ||
                !module.getOps<upf::UPFRetentionElementsOp>().empty() ||
                !module.getOps<upf::UPFDesignAttributesOp>().empty();
  for (auto domain : module.getOps<upf::UPFDomainOp>())
    needed |= domain.getRetentionsAttr() && !domain.getRetentionsAttr().empty();
  if (!needed)
    return success();
  RetentionSelection selection(design);
  if (failed(selection.initialize()))
    return failure();
  bool strategies = false;
  for (auto domain : module.getOps<upf::UPFDomainOp>())
    strategies |=
        domain.getRetentionsAttr() && !domain.getRetentionsAttr().empty();
  // Neither 5.6 nor 6.51 has an active obligation without a strategy. Avoid
  // demanding closed writer/call provenance for dormant annotations/lists.
  if (!strategies)
    return success();
  RetentionLoweringResult unused;
  RetentionLoweringOptions options{design, {},      root, descriptors, supplies,
                                   {},     nullptr, {},   {},          {},
                                   {},     {},      {},   {}};
  Lowering planning(options, unused);
  if (failed(planning.plan(selection)) || failed(selection.validate()))
    return failure();
  for (auto &reg : planning.registers)
    plans[reg.domain].push_back(std::move(reg));
  return success();
}
LogicalResult lowerRetentions(const RetentionLoweringOptions &options,
                              RetentionLoweringResult &result) {
  return Lowering(options, result).lower();
}
} // namespace talos
