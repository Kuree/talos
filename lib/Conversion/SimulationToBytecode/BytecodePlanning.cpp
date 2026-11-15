//===- BytecodePlanning.cpp - Design-wide bytecode planning --------------===//

#include "BytecodeEncoder.h"
#include "BytecodeRegisterPlanning.h"
#include "BytecodeSerialization.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Transforms/RegionUtils.h"
#include "talos/Analysis/ActivationRegionAnalysis.h"
#include "talos/Analysis/NativeAOTAnalysis.h"
#include "talos/Analysis/SimulationEffectAnalysis.h"
#include "talos/Analysis/SimulationScheduleAnalysis.h"
#include "talos/Analysis/StaticSpecializationAnalysis.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/SAIF/SAIFDialect.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Runtime/Runtime.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

#include <limits>
#include <tuple>

using namespace mlir;

namespace talos::bytecode {

LogicalResult Encoder::prepareStaticSpecializationSites() {
  FailureOr<analysis::StaticSpecializationAnalysis> specialization =
      analysis::StaticSpecializationAnalysis::compute(design);
  if (failed(specialization))
    return failure();
  staticNBASites = specialization->getNBASites();
  return success();
}

LogicalResult Encoder::planTwoStateRegisters() {
  FailureOr<llvm::DenseSet<Value>> planned =
      bytecode::planTwoStateRegisters(design);
  if (failed(planned))
    return failure();
  twoStateLogicRegisters = std::move(*planned);
  return success();
}

FailureOr<Layout> Encoder::getValueLayout(Value value) const {
  FailureOr<Layout> layout = getLayout(value.getType());
  if (failed(layout) || !isa<sim::LogicType>(value.getType()) ||
      !twoStateLogicRegisters.contains(value))
    return layout;
  layout->kind = Bits;
  layout->size = ((uint64_t{layout->width} + 63) / 64) * 8;
  return layout;
}

namespace {

bool isReferenceType(Type type) {
  if (isa<sim::ContextType, sim::TimeType>(type))
    return true;
  if (auto ref = dyn_cast<sim::RefType>(type))
    type = ref.getElementType();
  else if (auto net = dyn_cast<sim::NetType>(type))
    type = net.getElementType();
  else if (auto driver = dyn_cast<sim::DriverType>(type))
    type = driver.getElementType();
  return analysis::isPlainValueType(type);
}

bool hasReferenceEffects(sim::SimFuncOp function,
                         const analysis::SimulationEffectAnalysis &effects,
                         llvm::DenseSet<Operation *> &visiting,
                         llvm::DenseMap<Operation *, bool> &cache) {
  if (auto found = cache.find(function); found != cache.end())
    return found->second;
  if (!visiting.insert(function).second)
    return false;
  bool pure = llvm::all_of(function.getArgumentTypes(), isReferenceType);
  function.getBody().walk([&](Operation *op) {
    pure &= llvm::all_of(op->getResultTypes(), isReferenceType);
    if (auto call = dyn_cast<sim::SimCallOp>(op)) {
      auto callee = SymbolTable::lookupNearestSymbolFrom<sim::SimFuncOp>(
          call, call.getCalleeAttr());
      pure &= callee && !callee.isExternal() && effects.isReadOnly(callee) &&
              hasReferenceEffects(callee, effects, visiting, cache);
      return;
    }
    if (isMemoryEffectFree(op) ||
        isa<cf::BranchOp, cf::CondBranchOp, cf::SwitchOp, sim::SimReturnOp,
            sim::SimSuspendChangeOp, sim::SimSuspendAnyOp,
            sim::SimSuspendDelayOp, sim::SimRefLoadOp, sim::SimNetReadOp,
            sim::SimDriverReadOp, sim::SimRefAllocOp, sim::SimRefStoreOp,
            sim::SimDriverDriveOp, sim::SimDriverDriveChangedOp,
            sim::SimDriverDriveDelayedNetOp, sim::SimDriverDriveInertialOp,
            sim::SimDriverDriveInertialPathOp,
            sim::SimDriverDriveInertialStrengthPairOp,
            sim::SimDriverDriveInertialPathStrengthPairOp,
            sim::SimRefStoreInertialPathOp, sim::SimGCSafepointOp,
            sim::SimTerminationRequestedOp>(op))
      return;
    pure = false;
  });
  visiting.erase(function);
  cache[function] = pure;
  return pure;
}

bool isSAIFReference(sim::SimFuncOp function,
                     const analysis::HandleDataflowAnalysis &handles,
                     const analysis::SimulationEffectAnalysis &effects,
                     llvm::DenseMap<Operation *, bool> &cache) {
  auto kind = function.getEntryKind();
  bool continuous = kind == sim::EntryKind::Continuous ||
                    kind == sim::EntryKind::PortInput ||
                    kind == sim::EntryKind::PortOutput;
  if (!continuous && kind != sim::EntryKind::AlwaysComb &&
      kind != sim::EntryKind::Always)
    return false;
  llvm::DenseSet<Operation *> visiting;
  if (!hasReferenceEffects(function, effects, visiting, cache))
    return false;
  OwningOpRef<sim::SimFuncOp> delayErased;
  sim::SimFuncOp reference = function;
  bool hasDelay = false;
  bool hasTerminationPoll = false;
  function.walk([&](sim::SimSuspendDelayOp) { hasDelay = true; });
  function.walk(
      [&](sim::SimTerminationRequestedOp) { hasTerminationPoll = true; });
  if (hasDelay || hasTerminationPoll || kind == sim::EntryKind::Always) {
    delayErased = cast<sim::SimFuncOp>(function->clone());
    delayErased->walk([&](sim::SimSuspendDelayOp delay) {
      OpBuilder builder(delay);
      cf::BranchOp::create(builder, delay.getLoc(), delay.getContinuation(),
                           delay.getContinuationOperands());
      delay.erase();
    });
    // Certified callees cannot request termination; this compiler-inserted
    // guard is false in the isolated reference context. Remove its dead exit
    // before proving a complete combinational activation.
    delayErased->walk([&](sim::SimTerminationRequestedOp poll) {
      OpBuilder builder(poll);
      Value clear = arith::ConstantIntOp::create(builder, poll.getLoc(), 0, 1);
      poll.getResult().replaceAllUsesWith(clear);
      poll.erase();
    });
    delayErased->walk([&](cf::CondBranchOp branch) {
      auto constant =
          branch.getCondition().getDefiningOp<arith::ConstantIntOp>();
      if (!constant)
        return;
      OpBuilder builder(branch);
      bool taken = constant.value() != 0;
      cf::BranchOp::create(builder, branch.getLoc(),
                           taken ? branch.getTrueDest() : branch.getFalseDest(),
                           taken ? branch.getTrueDestOperands()
                                 : branch.getFalseDestOperands());
      branch.erase();
    });
    IRRewriter rewriter(function.getContext());
    (void)eraseUnreachableBlocks(
        rewriter, MutableArrayRef<Region>(&delayErased->getBody(), 1));
    if (kind == sim::EntryKind::Always) {
      SmallVector<Operation *> waits;
      delayErased->walk([&](Operation *op) {
        if (sim::isSuspensionOp(op))
          waits.push_back(op);
      });
      if (waits.size() != 1 ||
          !isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp>(waits[0]) ||
          waits[0]->getNumSuccessors() != 1 ||
          !cast<BranchOpInterface>(waits[0]).getSuccessorOperands(0).empty())
        return false;
      // A plain always procedure first arms its sensitivity and executes its
      // body only on a wake. Certify that resumed body; the replay still uses
      // the original entry, preserving time-zero initialization and arming.
      auto *entryBranch = delayErased->getBody().front().getTerminator();
      OpBuilder builder(entryBranch);
      cf::BranchOp::create(builder, entryBranch->getLoc(),
                           waits[0]->getSuccessor(0));
      entryBranch->erase();
    }
    reference = *delayErased;
  }
  analysis::ActivationPreparationOptions preparation;
  preparation.symbols = function->getParentOp();
  analysis::ActivationRegionAnalysis activation(
      analysis::prepareActivation(reference, preparation), handles);
  if (activation.isValid()) {
    const auto &memory = activation.getMemory();
    return memory.hasCompleteWrites() &&
           analysis::intersect(memory.getLiveIns(), memory.getMayWrites())
               .empty();
  }
  // The activation proof established equivalent finite initial/resumed CFGs,
  // but its memory model intentionally does not admit delayed publications.
  // Prove the separate reference semantics on a detached zero-delay view;
  // leave the primary IR and the ordinary activation legality unchanged.
  if (activation.getFailureReason() !=
          analysis::ActivationRegionAnalysis::FailureReason::MemoryEffects ||
      !activation.getActivationFunction())
    return false;
  OwningOpRef<sim::SimFuncOp> model(
      cast<sim::SimFuncOp>(activation.getActivationFunction()->clone()));
  model->walk([&](Operation *op) {
    OpBuilder builder(op);
    auto drive = [&](Value driver, Value value) {
      sim::SimDriverDriveOp::create(builder, op->getLoc(), driver, value);
    };
    if (auto delayed = dyn_cast<sim::SimDriverDriveInertialOp>(op))
      drive(delayed.getDriver(), delayed.getValue());
    else if (auto delayed = dyn_cast<sim::SimDriverDriveInertialPathOp>(op))
      drive(delayed.getDriver(), delayed.getValue());
    else if (auto delayed = dyn_cast<sim::SimDriverDriveDelayedNetOp>(op))
      drive(delayed.getDriver(), delayed.getValue());
    else if (auto pair =
                 dyn_cast<sim::SimDriverDriveInertialStrengthPairOp>(op)) {
      drive(pair.getLowDriver(), pair.getLowValue());
      drive(pair.getHighDriver(), pair.getHighValue());
    } else if (auto pair =
                   dyn_cast<sim::SimDriverDriveInertialPathStrengthPairOp>(
                       op)) {
      drive(pair.getLowDriver(), pair.getLowValue());
      drive(pair.getHighDriver(), pair.getHighValue());
    } else if (auto delayed = dyn_cast<sim::SimRefStoreInertialPathOp>(op))
      sim::SimRefStoreOp::create(builder, op->getLoc(), delayed.getValue(),
                                 delayed.getReference());
    else
      return;
    op->erase();
  });
  analysis::ActivationMemoryAnalysis memory(
      *model, handles, 65536,
      analysis::ActivationMemoryAnalysis::DependencyMode::Accesses,
      function->getParentOp());
  return memory.isValid() && memory.hasCompleteWrites() &&
         analysis::intersect(memory.getLiveIns(), memory.getMayWrites())
             .empty();
}

// IEEE 1800-2023, Clauses 4.5 and 4.6: changing an execution tier must
// preserve the process continuation and its scheduled effects.
void pruneNativeFunctions(sim::SimDesignOp design,
                          SmallVectorImpl<sim::SimFuncOp> &functions) {
  auto module = design->getParentOfType<ModuleOp>();
  if (!module)
    return;
  auto native = analysis::NativeAOTAnalysis::compute(module);
  if (!native.isEligible())
    return;

  llvm::StringMap<sim::SimFuncOp> symbols;
  llvm::DenseMap<Operation *, SmallVector<Operation *>> dependencies,
      bodyDependencies, callers;
  llvm::DenseSet<Operation *> fallback, retained, processOnly;
  SmallVector<Operation *> pendingFallback, worklist;
  // `retain` follows every symbol the function references, its metadata
  // included; `retainProcess` follows only what its body's operations
  // reference (calls, spawns, other operands the encoder resolves), so a
  // process kept as a fallback does not pull in the generated eval bodies and
  // variants its schedule metadata names.
  auto retain = [&](Operation *function) {
    bool added = retained.insert(function).second;
    if (added || processOnly.erase(function))
      worklist.push_back(function);
  };
  auto retainProcess = [&](Operation *function) {
    if (retained.insert(function).second) {
      processOnly.insert(function);
      worklist.push_back(function);
    }
  };
  llvm::DenseSet<Operation *> nativeBootstraps;
  for (auto function : functions) {
    auto slot = native.getActorSlots().find(function);
    if (function.getEntryKind() != sim::EntryKind::RootInitializer ||
        (slot != native.getActorSlots().end() &&
         native.getBytecodeFragments().contains(function)))
      continue;
    bool suspends = false;
    function.walk([&](Operation *op) { suspends |= sim::isSuspensionOp(op); });
    if (!suspends)
      nativeBootstraps.insert(function);
  }
  auto requireFallback = [&](Operation *function) {
    // IEEE 1800-2023 6.8: declaration initialization precedes process startup.
    // An unsuspended root uses the ordinary native executor, including when
    // managed captures exclude it from AOT scheduling. Only admitted bytecode
    // continuations can select the interpreter during native startup.
    if (nativeBootstraps.contains(function))
      return;
    if (fallback.insert(function).second)
      pendingFallback.push_back(function);
  };
  for (auto function : functions)
    symbols[function.getSymName()] = function;
  // Every spawned process keeps its bytecode body: it is the exact fallback
  // executor when the runtime must run the process outside tier 1 (whole-plan
  // deopt, islands, uncertified static eval islands), IEEE 1800-2023 4.5 and
  // 4.6 (the continuation and its scheduled effects are preserved across
  // tiers). A fused kernel is itself the spawned process, so it keeps its own
  // body. Generated eval bodies are not processes, and a root initializer
  // that never suspends runs once natively at time 0 (6.8).
  llvm::DenseSet<StringRef> spawned;
  design.walk(
      [&](sim::SimSpawnOp spawn) { spawned.insert(spawn.getCallee()); });
  auto isRetainedProcess = [&](sim::SimFuncOp function) {
    return (spawned.contains(function.getSymName()) ||
            native.getActorSlots().contains(function)) &&
           !nativeBootstraps.contains(function) &&
           !::talos::schedule::has<::talos::schedule::Field::EvalContinuation>(
               function);
  };
  for (auto function : functions) {
    auto uses = SymbolTable::getSymbolUses(function);
    if (!uses)
      return;
    for (const auto &use : *uses)
      if (auto target = symbols.lookup(use.getSymbolRef().getRootReference())) {
        dependencies[function].push_back(target);
        if (use.getUser() != function.getOperation())
          bodyDependencies[function].push_back(target);
        if (isa<sim::SimCallOp, sim::SimTaskCallOp>(use.getUser()))
          callers[target].push_back(function);
      }

    // Keep callback and helper entry points conservatively. Their native
    // callers need bytecode only when a call can reach an interpreter boundary.
    // A generated eval body is not one: only the native dispatch calls it, and
    // a checkpoint resumes its owning actor's continuation, not the body. It
    // stays only when a retained function depends on it.
    if (!native.getActorSlots().contains(function) &&
        !nativeBootstraps.contains(function) &&
        !::talos::schedule::has<::talos::schedule::Field::EvalContinuation>(
            function))
      retain(function);
    else if (isRetainedProcess(function))
      retainProcess(function);
    bool needsFallback = native.getBytecodeFragments().contains(function) ||
                         native.getRuntimeCheckpointActors().contains(function);
    function.walk([&](Operation *op) {
      needsFallback |=
          isa<sim::SimTaskCallOp>(op) || sim::isColdRuntimeCheckpoint(op);
      if (auto call = dyn_cast<sim::SimCallOp>(op))
        needsFallback |= !symbols.contains(call.getCallee());
    });
    // A generated eval body clones its owner's operations, checkpoints
    // included, but never needs a fallback of its own: only the native
    // dispatch calls it, and a checkpoint there resumes the owning actor's
    // continuation (two-tier B4: BP encoded 112 such eval bodies, 7.2 MB).
    if (needsFallback &&
        !::talos::schedule::has<::talos::schedule::Field::EvalContinuation>(
            function))
      requireFallback(function);
  }
  while (!pendingFallback.empty()) {
    Operation *function = pendingFallback.pop_back_val();
    // A spawned process that needs a fallback (a runtime checkpoint, a task
    // call) stays as the first loop kept it: through what its body
    // references. Its checkpoints resume its own continuation, never the
    // generated eval body its schedule metadata names.
    if (!isRetainedProcess(cast<sim::SimFuncOp>(function)))
      retain(function);
    for (Operation *caller : callers[function])
      requireFallback(caller);
  }
  while (!worklist.empty()) {
    Operation *function = worklist.pop_back_val();
    bool fromProcess = processOnly.contains(function);
    for (Operation *callee :
         fromProcess ? bodyDependencies[function] : dependencies[function]) {
      // A process that a fallback-only process spawns is kept as a fallback
      // too, not upgraded to follow its metadata.
      if (fromProcess && isRetainedProcess(cast<sim::SimFuncOp>(callee)))
        retainProcess(callee);
      else
        retain(callee);
    }
  }
  if (native::has<native::DebugTiming>(module))
    llvm::errs() << "talos bytecode retention: " << retained.size() << "/"
                 << functions.size() << " functions\n";
  llvm::erase_if(functions, [&](sim::SimFuncOp function) {
    return !retained.contains(function);
  });
}

} // namespace

LogicalResult Encoder::planFunctions() {
  analysis::SimulationEffectAnalysis effects(design);
  design.walk([&](sim::SimFuncOp function) {
    sim::remove<sim::metadata::BytecodeReadOnly>(function);
    if (effects.isReadOnly(function))
      sim::mark<sim::metadata::BytecodeReadOnly>(function);
  });
  SmallVector<sim::SimFuncOp> functions;
  for (sim::SimFuncOp function : design.getBody().getOps<sim::SimFuncOp>()) {
    if (function.isExternal())
      externalFunctions[function.getSymName()] = function;
    else
      functions.push_back(function);
  }
  if (options.pruneNative && !options.requireBytecode)
    pruneNativeFunctions(design, functions);
  auto getStableID = [](sim::SimFuncOp function) {
    return function.getCodeUnitId().value_or(
        stableHash(function.getSymName()) &
        static_cast<uint64_t>(std::numeric_limits<int64_t>::max()));
  };
  llvm::sort(functions, [&](sim::SimFuncOp left, sim::SimFuncOp right) {
    return std::make_tuple(getStableID(left), left.getSymName()) <
           std::make_tuple(getStableID(right), right.getSymName());
  });
  if (functions.empty() && (!options.pruneNative || options.requireBytecode))
    return design.emitOpError("contains no executable functions");
  plans.reserve(functions.size());
  llvm::DenseMap<uint64_t, sim::SimFuncOp> stableIDs;
  bool collectSAIF =
      saif::has<saif::Output>(design->getParentOfType<ModuleOp>());
  // Reference certification is SAIF-only; other designs skip its analyses.
  std::optional<analysis::HandleDataflowAnalysis> referenceHandles;
  if (collectSAIF)
    referenceHandles.emplace(design);
  llvm::DenseMap<Operation *, bool> referenceEffects;
  for (auto [index, function] : llvm::enumerate(functions)) {
    FunctionPlan &plan = plans.emplace_back();
    plan.function = function;
    plan.index = static_cast<uint32_t>(index);
    plan.stableID = getStableID(function);
    plan.saifReference =
        collectSAIF &&
        isSAIFReference(function, *referenceHandles, effects, referenceEffects);
    if (plan.stableID == 0)
      return function.emitOpError("executable code-unit ID must be nonzero");
    auto [collision, inserted] = stableIDs.try_emplace(plan.stableID, function);
    if (!inserted) {
      function.emitOpError()
          << "duplicate executable code-unit ID " << plan.stableID;
      collision->second.emitRemark("first function with this ID is here");
      return failure();
    }
    indices[function.getSymName()] = plan.index;
  }
  for (FunctionPlan &plan : plans) {
    FunctionType type = plan.function.getFunctionType();
    auto allocateLayout = [&](Layout layout) -> uint32_t {
      uint64_t aligned = llvm::alignTo(plan.scratchSize, uint64_t{8});
      layout.offset = aligned;
      plan.scratchSize = aligned + layout.size;
      plan.layouts.push_back(layout);
      return plan.layouts.size() - 1;
    };
    auto allocateType = [&](Type type) -> FailureOr<uint32_t> {
      FailureOr<Layout> layout = getLayout(type);
      if (failed(layout))
        return failure();
      return allocateLayout(*layout);
    };
    auto allocateValue = [&](Value value) -> FailureOr<uint32_t> {
      FailureOr<Layout> layout = getValueLayout(value);
      if (failed(layout))
        return failure();
      if (layout->kind == Bits && isa<sim::LogicType>(value.getType()))
        ++plan.twoStateLogicRegisters;
      return allocateLayout(*layout);
    };
    Block &entry = plan.function.getBody().front();
    if (entry.getNumArguments() != type.getNumInputs())
      return plan.function.emitOpError("entry signature is inconsistent");
    for (BlockArgument argument : entry.getArguments()) {
      FailureOr<uint32_t> reg = allocateValue(argument);
      if (failed(reg))
        return argument.getOwner()->getParentOp()->emitError()
               << "cannot encode argument type " << argument.getType();
      plan.registers.insert({argument, *reg});
    }
    for (Type result : type.getResults()) {
      FailureOr<uint32_t> reg = allocateType(result);
      if (failed(reg))
        return plan.function.emitOpError()
               << "cannot encode result type " << result;
      plan.resultRegisters.push_back(*reg);
    }
    for (Block &block : plan.function.getBody()) {
      if (&block != &entry)
        for (BlockArgument argument : block.getArguments()) {
          FailureOr<uint32_t> reg = allocateValue(argument);
          if (failed(reg))
            return plan.function.emitOpError()
                   << "cannot encode block argument type "
                   << argument.getType();
          plan.registers.insert({argument, *reg});
        }
      for (Operation &operation : block)
        for (Value result : operation.getResults()) {
          // A representation change between equal register layouts is the
          // identity on the register, so its result shares the operand's
          // register and encodes no instruction (two-tier B3). SSA keeps the
          // sharing exact: every use of the result is dominated by its
          // definition, so no use can observe the operand's register after a
          // later redefinition of the operand without that redefinition
          // having re-executed the conversion first.
          if (isa<sim::SimLogicFromBitsOp, sim::SimLogicToBitsOp,
                  sim::SimPackedFlattenOp, sim::SimPackedUnflattenOp,
                  sim::SimLogicResizeOp>(operation)) {
            auto source = plan.registers.find(operation.getOperand(0));
            FailureOr<Layout> layout = getValueLayout(result);
            if (source != plan.registers.end() && succeeded(layout)) {
              const Layout &existing = plan.layouts[source->second];
              if ((layout->kind == Bits || layout->kind == Logic) &&
                  existing.kind == layout->kind &&
                  existing.flags == layout->flags &&
                  existing.width == layout->width &&
                  existing.size == layout->size &&
                  existing.auxiliary == layout->auxiliary) {
                // The count reports narrowed logic values, shared or not.
                if (layout->kind == Bits &&
                    isa<sim::LogicType>(result.getType()))
                  ++plan.twoStateLogicRegisters;
                plan.registers.insert({result, source->second});
                continue;
              }
            }
          }
          FailureOr<uint32_t> reg = allocateValue(result);
          if (failed(reg))
            return operation.emitOpError()
                   << "cannot encode result type " << result.getType();
          plan.registers.insert({result, *reg});
        }
    }
    plan.scratchSize = llvm::alignTo(plan.scratchSize, uint64_t{8});
    if (plan.function.getEntryKind() != sim::EntryKind::Function &&
        plan.function.getEntryKind() != sim::EntryKind::Observer) {
      FailureOr<std::unique_ptr<SimulationProcessFrameAnalysis>> frame =
          SimulationProcessFrameAnalysis::create(plan.function, dataLayout);
      if (failed(frame))
        return failure();
      plan.frame = std::move(*frame);
      if (plan.frame->getFrameSize() >=
          TALOS_RT_DESIGN_FUNCTION_FRAME_SIZE_LIMIT)
        return plan.function.emitOpError(
            "process frame is too large for bytecode function flags");
      ArrayRef<ProcessFrameValue> captures =
          plan.frame->getEntryCaptureLayout();
      if (captures.size() != entry.getNumArguments())
        return plan.function.emitOpError("entry capture layout is incomplete");
      for (auto [argument, capture] : llvm::enumerate(captures))
        captureRecords.push_back(
            {plan.index, static_cast<uint32_t>(argument), capture.valueOffset,
             capture.hasSecondaryStorage() ? capture.getSecondaryOffset()
                                           : UINT64_MAX,
             capture.storageSize});
    }
  }
  return success();
}

LogicalResult Encoder::planScheduleRanks() {
  FailureOr<analysis::SimulationScheduleAnalysis> schedule =
      analysis::SimulationScheduleAnalysis::compute(design);
  if (failed(schedule))
    return failure();
  for (FunctionPlan &plan : plans) {
    if (std::optional<uint32_t> rank =
            schedule->getEntryRank(plan.function.getOperation()))
      plan.initialScheduleRank = *rank;
    for (Block &block : plan.function.getBody())
      if (std::optional<uint32_t> rank = schedule->getBlockRank(&block))
        plan.blockScheduleRanks[&block] = *rank;
  }
  return success();
}

} // namespace talos::bytecode
