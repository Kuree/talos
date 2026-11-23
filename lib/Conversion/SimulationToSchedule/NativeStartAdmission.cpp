//===- NativeStartAdmission.cpp - Eval owners created at their wait -------===//
//
// IEEE 1800-2023 9.2 leaves the order in which procedures start open ("There
// shall be no implied order of execution between initial and always
// procedures"; also 4.7), so an eval owner that waits at one signal event
// control for its whole life, and
// whose entry before that wait only computes values, can be created already
// waiting there: its process body takes no first activation at time zero and
// every activation is the generated owner's. An always_comb or always_latch
// owner, whose entry is its continuation's activation, takes that first
// activation as a generated ready bit raised after every procedure has started
// (9.2.2.2, 9.2.2.3: "automatically triggered once at time zero, after all
// initial and always procedures have been started"; 4.9.1 for continuous
// assignments and the implicit ones of port connections).
//
// A read-capable owner keeps its source frame. A certified initial activation
// uses the same guarded ready bit as a subsequent wake. A publishing owner
// executes the original continuation, including any observable first write.
//
// Owners that are observed as threads keep their first activation: process
// identity and control (9.7), per-process random state (18.14.1), named
// blocks a disable can target (9.6.2), fork,
// suspending task calls, checkpoints that resume through the instance,
// bytecode continuations, and non-Active home regions (programs and checkers
// run in the Reactive set). Writable VPI and procedural overrides keep the
// ordinary activation path.
//
//===----------------------------------------------------------------------===//

#include "NativePipeline.h"
#include "NativeStaticWait.h"

#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "talos/Analysis/ThreadObservationAnalysis.h"
#include "talos/Dialect/Runtime/RuntimeDialect.h"
#include "talos/Dialect/Runtime/RuntimeOps.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "llvm/ADT/MapVector.h"
#include "llvm/Support/raw_ostream.h"

using namespace mlir;

namespace talos::detail {
namespace {

/// The single wait of an actor, its continuation and its static record.
struct SingleWait {
  Operation *operation = nullptr;
  Block *continuation = nullptr;
  StaticRuntimeWait record;
};

// The source can exit on vpiFinish and still wait permanently during a live
// simulation. Prove that every edge to the return tests this actor's own
// context. Ordinary conditional returns still exclude startup admission.
static bool isTerminationOnlyExit(sim::SimFuncOp actor, Block *block) {
  if (!actor.getNumArguments() || block->hasNoPredecessors())
    return false;
  return llvm::all_of(block->getPredecessors(), [&](Block *pred) {
    auto branch = dyn_cast<cf::CondBranchOp>(pred->getTerminator());
    if (!branch || branch.getTrueDest() != block ||
        branch.getFalseDest() == block)
      return false;
    auto poll = branch.getCondition()
                    .getDefiningOp<runtime::RTTerminationRequestedOp>();
    auto projection =
        poll ? poll.getOperand().getDefiningOp<sim::SimContextRuntimeOp>()
             : sim::SimContextRuntimeOp{};
    return projection && projection.getOperand() == actor.getArgument(0);
  });
}

/// Why an actor keeps its first activation, or nullopt for a single signal
/// wait with no other suspension or live simulation return.
std::optional<StringRef> findSingleSignalWait(sim::SimFuncOp actor,
                                              SingleWait &wait,
                                              bool publishingRead) {
  unsigned waits = 0;
  bool returns = false;
  actor.walk([&](Operation *operation) {
    if (isa<sim::SimReturnOp>(operation))
      returns |= !publishingRead ||
                 !isTerminationOnlyExit(actor, operation->getBlock());
    if (sim::isSuspensionOp(operation)) {
      ++waits;
      wait.operation = operation;
    }
  });
  // A procedure that can return is not permanently waiting; a second
  // suspension, including a task call, gives it more than one continuation.
  auto branch = dyn_cast_if_present<BranchOpInterface>(wait.operation);
  if (waits != 1 || returns || !branch ||
      !isa<schedule::NativeSuspendChangeOp, schedule::NativeSuspendEdgeOp,
           schedule::NativeSuspendAnyOp>(wait.operation) ||
      wait.operation->getNumSuccessors() != 1)
    return StringRef("wait");
  wait.continuation = wait.operation->getSuccessor(0);
  if (!branch.getSuccessorOperands(0).empty() ||
      wait.continuation->getNumArguments() != 0)
    return StringRef("continuation-state");
  FailureOr<StaticRuntimeWait> record = getStaticRuntimeWait(wait.operation);
  if (failed(record))
    return StringRef("wait-record");
  wait.record = std::move(*record);
  return std::nullopt;
}

/// Whether a block computes only values before its terminator. Frame lowering
/// may place a wait's stack storage there; an allocation is not observable.
bool pureBeforeTerminator(Block *block) {
  return llvm::all_of(block->without_terminator(), [](Operation &operation) {
    return operation.getNumRegions() == 0 &&
           (isMemoryEffectFree(&operation) || isa<LLVM::AllocaOp>(operation) ||
            hasSingleEffect<MemoryEffects::Allocate>(&operation));
  });
}

/// Whether the first activation only arms the wait (false) or is exactly the
/// continuation's activation (true); nullopt when it is neither.
std::optional<bool> firstActivationRunsContinuation(sim::SimFuncOp actor,
                                                    const SingleWait &wait) {
  Block *entry = &actor.getBody().front();
  if (!pureBeforeTerminator(entry))
    return std::nullopt;
  if (entry->getTerminator() == wait.operation)
    return false;
  auto branch = dyn_cast<cf::BranchOp>(entry->getTerminator());
  if (!branch || branch.getNumOperands() != 0)
    return std::nullopt;
  Block *next = branch.getDest();
  if (next == wait.continuation)
    return true;
  if (next->getTerminator() == wait.operation && next->getNumArguments() == 0 &&
      pureBeforeTerminator(next))
    return false;
  return std::nullopt;
}

bool admittedEntryKind(sim::EntryKind kind) {
  switch (kind) {
  case sim::EntryKind::Always:
  case sim::EntryKind::AlwaysComb:
  case sim::EntryKind::AlwaysFF:
  case sim::EntryKind::AlwaysLatch:
  case sim::EntryKind::Continuous:
  case sim::EntryKind::PortInput:
  case sim::EntryKind::PortOutput:
    return true;
  default:
    return false;
  }
}

uint64_t nodeKey(uint32_t slot, uint32_t continuation) {
  return uint64_t{slot} << 32 | continuation;
}

} // namespace

LogicalResult NativePipelineAnalysis::admitStartedOwners() {
  if (bytecodeOnly || !useAOT || !evalScheduler || failed(resolvedEval) ||
      failed(directFragments) || !metadataDesign)
    return success();
  llvm::MapVector<StringRef, unsigned> rejected;
  unsigned admitted = 0, timeZero = 0;
  auto report = [&] {
    if (!detailedTiming)
      return;
    llvm::errs() << "talos started owners: admitted=" << admitted
                 << " time_zero=" << timeZero;
    if (!bytecodeFallbackOwners.empty())
      llvm::errs() << " bytecode-fallback=" << bytecodeFallbackOwners.size();
    auto reasons = rejected.takeVector();
    llvm::sort(reasons, llvm::less_first());
    for (const auto &[reason, count] : reasons)
      llvm::errs() << ' ' << reason << '=' << count;
    llvm::errs() << '\n';
  };
  // External writers and procedural force/assign can change the wait route
  // during startup. Keep the ordinary first activation in those designs.
  if (vpi.allowsWrite()) {
    rejected["vpi"] = analyses.size();
    report();
    return success();
  }
  if (hasLanguageOverride || hasDynamicLanguageOverride) {
    rejected["override"] = analyses.size();
    report();
    return success();
  }
  const ResolvedNativeEvalPlan &plan = *resolvedEval;
  if (evalOwnership.fanoutOwners.size() != plan.fanoutEntries.size() ||
      evalOwnership.periodicFanoutOwners.size() != plan.fanoutEntries.size()) {
    rejected["ownership"] = analyses.size();
    report();
    return success();
  }

  // Index the plan once per (slot, continuation) instead of scanning it for
  // every actor.
  DenseMap<uint32_t, SmallVector<size_t, 2>> fanoutEntriesBySlot;
  for (auto [index, fanout] : llvm::enumerate(plan.fanoutEntries))
    fanoutEntriesBySlot[fanout.actor_slot].push_back(index);
  // Per node: whether every merged fragment has a clean generated executor,
  // and how many there are.
  struct NodeOwners {
    bool clean = true;
    bool independent = true;
    unsigned records = 0;
  };
  APInt subsumed;
  if (vpi.requiresPublicationGuards()) {
    subsumed = APInt(std::max<size_t>(64, plan.mergedFragments.size()), 0);
    for (const APInt &mask : plan.ownerSubsumptionMasks)
      subsumed |= mask;
  }
  DenseMap<uint64_t, NodeOwners> cleanOwners;
  for (auto [index, fragment] : llvm::enumerate(plan.mergedFragments)) {
    NodeOwners &owners =
        cleanOwners[nodeKey(fragment.actor_slot, fragment.continuation)];
    owners.clean &= (fragment.flags & TALOS_RT_MERGED_FRAGMENT_FALLBACK) == 0 &&
                    index < plan.mergedExecutors.size() &&
                    !plan.mergedExecutors[index].empty();
    if (vpi.requiresPublicationGuards())
      owners.independent &= index < plan.ownerSubsumptionMasks.size() &&
                            plan.ownerSubsumptionMasks[index].isZero() &&
                            !subsumed[fragment.bit];
    ++owners.records;
  }
  DenseSet<uint64_t> handoffExecutors;
  for (const NativeDirectFragment &direct : *directFragments)
    if (direct.runtimeCheckpoint || direct.tier2Convergence)
      handoffExecutors.insert(nodeKey(direct.actorSlot, direct.continuation));

  // Every admitted owner is spawned exactly once by the root initializer,
  // which runs before any procedure (IEEE 1800-2023 6.8, 4.5).
  DenseMap<StringAttr, SmallVector<Operation *, 1>> spawns;
  metadataDesign.walk([&](Operation *operation) {
    if (auto spawn = dyn_cast<sim::SimSpawnOp>(operation))
      spawns[spawn.getCalleeAttr().getAttr()].push_back(operation);
    else if (auto spawn = dyn_cast<schedule::NativeSpawnOp>(operation))
      spawns[spawn.getCalleeAttr().getAttr()].push_back(operation);
  });
  analysis::ThreadObservationAnalysis threads(module);

  auto reject = [&](StringRef reason) {
    ++rejected[reason];
    return false;
  };
  auto admit = [&](sim::SimFuncOp actor, uint32_t slot,
                   const SimulationProcessFrameAnalysis &frame,
                   SingleWait &wait, bool &initial) {
    if (!admittedEntryKind(actor.getEntryKind()))
      return reject("entry-kind");
    if (actor.getHomeRegion() != sim::EventRegion::Active ||
        (rootSlotZero && slot == 0))
      return reject("region");
    if (schedule::has<schedule::Field::PrimeOnSpawn>(actor) ||
        schedule::has<schedule::Field::DetachedControls>(actor) ||
        schedule::get<schedule::Field::ProgramOwnerId>(actor) ||
        schedule::has<schedule::Field::PrioritySignalResume>(actor) ||
        schedule::has<schedule::Field::ConcurrentCancel>(actor) ||
        schedule::has<schedule::Field::ConcurrentAbort>(actor))
      return reject("process-control");
    IntegerAttr codeUnit = actor.getCodeUnitIdAttr();
    if (!codeUnit || checkpointOnlyActors.contains(codeUnit.getUInt()))
      return reject("checkpoint");
    if (!aotBytecodeContinuations.lookup(actor).empty())
      return reject("bytecode");
    if (!vpi.allowsRead() && copyActivations.contains(actor))
      return reject("copy-activation");
    if (std::optional<StringRef> reason = findSingleSignalWait(actor, wait, vpi.requiresPublicationGuards() && !vpi.allowsWrite()))
      return reject(*reason);
    uint32_t continuation = wait.record.continuation;
    // The frame holds nothing the skipped entry would have stored for the
    // continuation.
    if (!frame.getContinuationLayout(continuation).empty())
      return reject("continuation-state");
    std::optional<bool> runsContinuation =
        firstActivationRunsContinuation(actor, wait);
    if (!runsContinuation)
      return reject("entry-prefix");
    initial = *runsContinuation;
    if (runtimeCheckpointContinuations.contains(
            {codeUnit.getUInt(), continuation}))
      return reject("checkpoint");
    if (threads.observes(actor))
      return reject("thread");
    // The continuation must be a generated eval owner: merged ready bits with
    // clean executors and a direct fragment that never hands the activation
    // back to the runtime. A time-zero activation raises every merged bit of
    // the node, so it must have exactly one.
    auto owner = cleanOwners.find(nodeKey(slot, continuation));
    if (owner == cleanOwners.end())
      return reject("no-owner");
    if (!owner->second.clean)
      return reject("fallback-owner");
    if (initial && owner->second.records != 1)
      return reject("time-zero-owners");
    if (initial && vpi.requiresPublicationGuards()) {
      // A fractured owner reactivates its children rather than executing an
      // individual source body. Its entry must still run on its own frame.
      // Only a single, independent, publishable actor can share its first
      // activation's bit with the original wait (4.9.1, 9.2.2.2, 38.36).
      auto kind = actor.getEntryKind();
      if (!owner->second.independent || (kind != sim::EntryKind::AlwaysComb &&
                                         kind != sim::EntryKind::AlwaysLatch &&
                                         kind != sim::EntryKind::Continuous &&
                                         kind != sim::EntryKind::PortInput &&
                                         kind != sim::EntryKind::PortOutput))
        return reject("observable-start");
    }
    if (handoffExecutors.contains(nodeKey(slot, continuation)))
      return reject("executor");
    // Every wake must reach that generated owner, so that an input change
    // before the time-zero activation and the activation itself set one
    // ready bit (9.2.2.2): a runtime-routed wake would run the process body
    // a second time.
    auto entries = fanoutEntriesBySlot.find(slot);
    if (entries != fanoutEntriesBySlot.end())
      for (size_t index : entries->second) {
        const talos_rt_static_fanout_entry &fanout = plan.fanoutEntries[index];
        if (fanout.continuation != continuation ||
            (fanout.reserved & TALOS_RT_FANOUT_ROUTE_MASK) !=
                TALOS_RT_FANOUT_DIRECT ||
            evalOwnership.fanoutOwners[index].kind !=
                NativeEvalFanoutOwnerKind::Direct ||
            evalOwnership.periodicFanoutOwners[index].kind !=
                NativeEvalFanoutOwnerKind::Direct)
          return reject("route");
      }
    auto spawned = spawns.find(actor.getSymNameAttr());
    if (spawned == spawns.end() || spawned->second.size() != 1)
      return reject("spawn");
    auto parent = spawned->second.front()->getParentOfType<sim::SimFuncOp>();
    if (!parent || parent.getEntryKind() != sim::EntryKind::RootInitializer)
      return reject("spawn");
    return true;
  };

  Builder builder(context);
  for (auto &entry : analyses) {
    auto actor = dyn_cast<sim::SimFuncOp>(entry.first);
    if (!actor)
      continue;
    std::optional<uint32_t> slot = aotActorSlotFor(actor);
    if (!slot)
      continue;
    SingleWait wait;
    bool initial = false;
    if (!admit(actor, *slot, *entry.second, wait, initial))
      continue;
    if (vpi.allowsRead() && !vpi.requiresPublicationGuards()) {
      // A reader may register before the root spawns, or arrive through DPI.
      // Keep the ordinary process, entry and wait for those observation
      // points (IEEE 1800-2023 9.2, 38.15, 38.36). Only its implementation
      // outside the generated coordinator changes.
      if (runtime::has<runtime::BytecodeFunction>(actor))
        bytecodeFallbackOwners.insert(actor);
      continue;
    }
    schedule::set<schedule::Field::NativeStartedAt>(
        actor, builder.getI32IntegerAttr(wait.record.continuation));
    if (initial)
      schedule::set<schedule::Field::NativeTimeZeroActivation>(
          actor, builder.getUnitAttr());
    ++admitted;
    timeZero += initial;
  }
  report();
  return success();
}

} // namespace talos::detail
