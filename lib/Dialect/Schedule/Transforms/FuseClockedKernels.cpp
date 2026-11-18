//===- FuseClockedKernels.cpp - One activation per clock edge ===//
//
// Groups edge-triggered processes by proven clock alias and edge, including
// across instances. IEEE 1800 4.7 permits their Active events to run together.
//
// An NBA can become a direct store only when:
//   - Later reads retain the incoming value through snapshots or deferred stores.
//   - The kernel owns the root's writes in its phase; delayed NBAs conflict.
//   - Combinational consumers are glitch-insensitive and no edge, level, event,
//     VPI, or coverage observer can distinguish the earlier publication.
//   - Other activations in the phase cannot access the root or its consumer cone.
// RHS and destination evaluation and NBA source order remain unchanged.
//
// ActivationPhaseAnalysis separates executions by NBA barriers. A direct-store
// kernel must run at most once per phase, with clock changes from one atomic
// source. Clocks that can repeat through Inactive events retain their NBAs.
//
// With `defer`, the kernel resumes in Inactive after its pass's Active work.
// PostKernelAnalysis checks accesses by later activations and their consumers.
// Unordered Inactive peers must not change kernel inputs, and no later work may
// change its clock. Roots read by final procedures remain protected when a
// later activation can finish the simulation; deferred kernels are skipped
// after a finish request.
//
// Requires one worker and VPI off. Overrides and DPI calls that may access
// design state disable fusion; transparent DPI calls are permitted.
//
//===----------------------------------------------------------------------===//

#include "ComputeFusion.h"
#include "talos/Analysis/ActivationMemoryAnalysis.h"
#include "talos/Analysis/ActivationPhaseAnalysis.h"
#include "talos/Analysis/ClockInferenceAnalysis.h"
#include "talos/Analysis/DPIEffectAnalysis.h"
#include "talos/Analysis/HandleDataflowAnalysis.h"
#include "talos/Analysis/NativeStateLayoutAnalysis.h"
#include "talos/Analysis/OrderedDenseAnalysis.h"
#include "talos/Analysis/ParallelWalk.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ClockedKernelName.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleMetadata.h"
#include "talos/Dialect/Schedule/Transforms/Passes.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/Simulation/SimulationTypes.h"

#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Analysis/DataFlow/DenseAnalysis.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"

#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/ScopeExit.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/Support/raw_ostream.h"

#include <queue>

#include <functional>

using namespace mlir;

namespace talos {

#define GEN_PASS_DEF_TALOSSIMFUSECLOCKEDKERNELSPASS
#include "talos/Dialect/Schedule/Transforms/Passes.h.inc"

namespace {

using analysis::ActivationMemoryAnalysis;

class TalosSimFuseClockedKernelsPass final
    : public impl::TalosSimFuseClockedKernelsPassBase<
          TalosSimFuseClockedKernelsPass> {
public:
  using Base::Base;
  void runOnOperation() override;

private:
  Statistic kernels{this, "kernels", "clocked kernels formed"};
  Statistic fusedMembers{this, "fused-members",
                         "edge-triggered processes fused into kernels"};
  Statistic directRoots{this, "direct-roots",
                        "NBA roots stored at their statements"};
  Statistic snapshotRoots{this, "snapshot-roots",
                          "direct NBA roots read through a snapshot"};
  Statistic delayedRoots{this, "delayed-roots",
                         "direct NBA roots updated at the end of the kernel"};
  Statistic delayedSites{this, "delayed-sites",
                         "NBA statements delayed to the end of the kernel"};
  Statistic retainedRoots{this, "retained-roots",
                          "kernel NBA roots kept on the NBA region"};
  Statistic directSites{this, "direct-sites",
                        "NBA statements replaced by direct stores"};
};

/// Snapshots copy the root once per activation. Wider roots keep their NBA.
constexpr uint64_t maximumSnapshotBits = 2048;

/// A delayed update keeps its value and target operands, sets a flag and
/// tests it at the end of the kernel: about as much work as copying this many
/// bits of a snapshot. Roots read late whose snapshot is cheaper than their
/// delayed updates use the snapshot.
constexpr uint64_t delayedUpdateBits = 256;

struct Member {
  sim::SimFuncOp function;
  sim::SimSpawnOp spawn;
  Block *wait = nullptr;
  Block *body = nullptr;
  SmallVector<Block *> bodyBlocks;
  SmallVector<Operation *> preamble;
  uint64_t clock = 0;
  sim::EdgeKind edge = sim::EdgeKind::Change;
  /// The root a net clock follows through exact pure copies, whether the
  /// copies complement it, and every root on that copy chain.
  uint64_t origin = 0;
  bool inverted = false;
  SmallVector<uint64_t, 2> clockChain;
  /// Multi-edge controls (for example clock or asynchronous reset) retain
  /// their complete wait. Their kernels require the deferred window proof.
  DenseI64ArrayAttr eventSignature;
  SmallVector<uint64_t, 2> eventRoots;
  uint32_t order = UINT32_MAX;
  llvm::DenseSet<uint64_t> reads, nbaWrites, writes;
  /// An update whose root is unresolved.
  bool unresolvedUpdate = false;
  /// A read whose root is unresolved.
  bool unresolvedRead = false;
  SmallVector<unsigned> fusedArguments;
  /// Whole-root reads of `clock` in the body, and whether a call or copy may
  /// read it without such an operation.
  SmallVector<Operation *> clockReads;
  bool opaqueClockRead = false;
  /// The kernel redirects `clockReads` to the clock's source root.
  bool redirectClockReads = false;
};

bool isSuspension(Operation *operation) {
  return sim::isSuspensionOp(operation);
}

std::optional<uint64_t> effectRoot(schedule::ComputeEffectAttr effect) {
  if (effect.getTarget() != schedule::ComputeTargetKind::Descriptor)
    return std::nullopt;
  return ActivationMemoryAnalysis::getRoot(effect.getResource(),
                                           effect.getDescriptor());
}

bool isAccess(schedule::ComputeEffectKind kind) {
  return kind == schedule::ComputeEffectKind::Read ||
         kind == schedule::ComputeEffectKind::Write ||
         kind == schedule::ComputeEffectKind::Drive ||
         kind == schedule::ComputeEffectKind::NBA ||
         kind == schedule::ComputeEffectKind::Trigger;
}

bool isWrite(schedule::ComputeEffectKind kind) {
  return kind == schedule::ComputeEffectKind::Write ||
         kind == schedule::ComputeEffectKind::Drive ||
         kind == schedule::ComputeEffectKind::NBA;
}

/// The storage or net root of a whole-object, constant-address handle.
std::optional<uint64_t> wholeRoot(Value value,
                                  const analysis::HandleFacts &facts) {
  auto found = facts.find(value);
  if (found == facts.end() || !found->second.descriptor ||
      found->second.dynamic || found->second.low != 0 ||
      found->second.width != found->second.rootWidth)
    return std::nullopt;
  return ActivationMemoryAnalysis::getRoot(found->second.resource,
                                           *found->second.descriptor);
}

std::optional<uint64_t> wholeStorageRoot(Value value,
                                         const analysis::HandleFacts &facts) {
  auto root = wholeRoot(value, facts);
  return root && *root < ActivationMemoryAnalysis::netRootTag ? root
                                                              : std::nullopt;
}

/// The storage root a handle may select, if it is a known storage root.
std::optional<uint64_t> storageRoot(Value value,
                                    const analysis::HandleFacts &facts) {
  auto found = facts.find(value);
  if (found == facts.end() || !found->second.descriptor ||
      found->second.resource != schedule::ComputeResourceKind::Storage)
    return std::nullopt;
  return *found->second.descriptor;
}

/// A one-bit clock: four-state `logic` or two-state `bit`.
bool isClockBit(Type type) {
  return isa<sim::LogicType, IntegerType>(type) &&
         sim::getPackedWidth(type) == 1u;
}

/// Remove the termination polls LowerUnit leaves after direct calls. Fusion
/// eligibility excludes every scheduler-writing operation from the members
/// and their callees, so these polls cannot observe a new request during the
/// kernel activation.
void removeTerminationPolls(sim::SimFuncOp function) {
  SmallVector<cf::CondBranchOp> polls;
  function.walk([&](cf::CondBranchOp branch) {
    auto requested =
        branch.getCondition().getDefiningOp<sim::SimTerminationRequestedOp>();
    if (requested &&
        isa<sim::SimReturnOp>(branch.getTrueDest()->getTerminator()))
      polls.push_back(branch);
  });
  OpBuilder builder(function.getContext());
  for (cf::CondBranchOp branch : polls) {
    auto requested =
        branch.getCondition().getDefiningOp<sim::SimTerminationRequestedOp>();
    Block *source = branch->getBlock();
    Block *continuation = branch.getFalseDest();
    SmallVector<Value> operands(branch.getFalseDestOperands());
    Location location = branch.getLoc();
    branch.erase();
    if (requested->use_empty())
      requested.erase();
    builder.setInsertionPointToEnd(source);
    cf::BranchOp::create(builder, location, continuation, operands);
  }
  for (auto block = function.getBody().begin(), end = function.getBody().end();
       block != end;) {
    Block &current = *block++;
    if (&current != &function.getBody().front() &&
        current.hasNoPredecessors() && current.without_terminator().empty() &&
        isa<sim::SimReturnOp>(current.getTerminator()))
      current.erase();
  }
}

bool collectBodyBlocks(Member &member) {
  SmallVector<Block *> pending{member.body};
  llvm::SmallPtrSet<Block *, 16> visited;
  Block *entry = &member.function.getBody().front();
  while (!pending.empty()) {
    Block *block = pending.pop_back_val();
    if (block == member.wait || !visited.insert(block).second)
      continue;
    if (block == entry)
      return false;
    member.bodyBlocks.push_back(block);
    Operation *terminator = block->getTerminator();
    if (isSuspension(terminator))
      return false;
    if (isa<sim::SimReturnOp>(terminator)) {
      // Only termination-poll exits are accepted; they are removed after
      // fusion.
      for (Block *predecessor : block->getPredecessors()) {
        auto branch = dyn_cast<cf::CondBranchOp>(predecessor->getTerminator());
        if (!branch || branch.getTrueDest() != block ||
            !branch.getCondition()
                 .getDefiningOp<sim::SimTerminationRequestedOp>())
          return false;
      }
      if (block->hasNoPredecessors())
        return false;
      continue;
    }
    if (!isa<BranchOpInterface>(terminator))
      return false;
    for (Block *successor : terminator->getSuccessors())
      if (successor != member.wait)
        pending.push_back(successor);
  }
  if (member.bodyBlocks.size() + 2 !=
      member.function.getBody().getBlocks().size())
    return false;
  DenseMap<Block *, unsigned> position;
  for (auto [index, block] : llvm::enumerate(member.function.getBody()))
    position[&block] = index;
  llvm::sort(member.bodyBlocks, [&](Block *lhs, Block *rhs) {
    return position[lhs] < position[rhs];
  });
  return true;
}

/// Operations defined in the entry block and used by the activation.
void collectPreamble(Member &member) {
  Block &entry = member.function.getBody().front();
  llvm::SmallPtrSet<Operation *, 16> needed;
  SmallVector<Value> pending;
  pending.append(member.wait->getTerminator()->operand_begin(),
                 member.wait->getTerminator()->operand_end());
  for (Operation &operation : member.wait->without_terminator())
    pending.append(operation.operand_begin(), operation.operand_end());
  for (Block *block : member.bodyBlocks)
    block->walk([&](Operation *operation) {
      pending.append(operation->operand_begin(), operation->operand_end());
    });
  while (!pending.empty()) {
    Operation *definition = pending.pop_back_val().getDefiningOp();
    if (!definition || definition->getBlock() != &entry ||
        definition == entry.getTerminator() ||
        !needed.insert(definition).second)
      continue;
    pending.append(definition->operand_begin(), definition->operand_end());
  }
  for (Operation &operation : entry.without_terminator())
    if (needed.contains(&operation))
      member.preamble.push_back(&operation);
}

/// The NBA classes (roots, or individual sites) of the current kernel
/// activation that may already have executed. Such an NBA has not updated its
/// root yet (4.9.4), so a direct store there would be visible early to a
/// later read of the root.
class PendingLattice final : public dataflow::AbstractDenseLattice {
public:
  using AbstractDenseLattice::AbstractDenseLattice;
  ChangeResult join(const llvm::BitVector &more) {
    if (more.size() > roots.size())
      roots.resize(more.size());
    llvm::BitVector next = roots;
    next |= more;
    if (next == roots)
      return ChangeResult::NoChange;
    roots = std::move(next);
    return ChangeResult::Change;
  }
  ChangeResult join(const AbstractDenseLattice &rhs) override {
    return join(static_cast<const PendingLattice &>(rhs).roots);
  }
  void print(raw_ostream &os) const override { os << roots.count(); }
  llvm::BitVector roots;
};

class PendingNBAAnalysis final
    : public analysis::OrderedDenseForwardDataFlowAnalysis<PendingLattice> {
public:
  PendingNBAAnalysis(DataFlowSolver &solver,
                     const DenseMap<Operation *, unsigned> &enqueues,
                     unsigned roots)
      : OrderedDenseForwardDataFlowAnalysis(solver), enqueues(enqueues),
        roots(roots) {}
  LogicalResult visitOperation(Operation *op, const PendingLattice &before,
                               PendingLattice *after) override {
    llvm::BitVector state = before.roots;
    state.resize(roots);
    if (auto found = enqueues.find(op); found != enqueues.end())
      state.set(found->second);
    propagateIfChanged(after, after->join(state));
    return success();
  }
  void visitBlockTransfer(Block *block, ProgramPoint *point, Block *predecessor,
                          const PendingLattice &before,
                          PendingLattice *after) override {
    // The kernel's wait starts a new activation after the NBA region.
    if (sim::isSuspensionOp(predecessor->getTerminator())) {
      propagateIfChanged(after, after->join(llvm::BitVector(roots)));
      return;
    }
    propagateIfChanged(after, after->join(before.roots));
  }
  void setToEntryState(PendingLattice *lattice) override {
    propagateIfChanged(lattice, lattice->join(llvm::BitVector(roots)));
  }

private:
  const DenseMap<Operation *, unsigned> &enqueues;
  unsigned roots;
};

/// Whether a root is in a combinational cone.
class ConeState final : public AnalysisState {
public:
  using AnalysisState::AnalysisState;
  ChangeResult reach() {
    if (reached)
      return ChangeResult::NoChange;
    reached = true;
    return ChangeResult::Change;
  }
  void print(raw_ostream &os) const override { os << reached; }
  bool reached = false;
};

class ConeRoot final
    : public GenericLatticeAnchorBase<ConeRoot,
                                      std::pair<uint64_t, Operation *>> {
public:
  using Base::Base;
  Location getLoc() const override { return getValue().second->getLoc(); }
  void print(raw_ostream &os) const override {
    os << "cone of root " << getValue().first;
  }
};

/// Value influence through side-effect-free combinational processes. Toward
/// sources, an exposed output reaches the inputs of every publication to it;
/// toward readers, a reached input reaches the outputs it can influence.
/// Without a value proof, use the conservative watch/write cross-product.
/// This is not general activation reachability: an unrelated watched input
/// can wake the process without influencing a particular output's value.
class ConeAnalysis final : public DataFlowAnalysis {
public:
  struct Process {
    sim::SimFuncOp function;
    SmallVector<uint64_t> watched, written;
    /// Input/output root pairs, including publication control and target
    /// dependencies. An unavailable value proof retains the watch cross-product.
    SmallVector<std::pair<uint64_t, uint64_t>> dependencies{};
    bool precise = false;
  };
  enum class Direction { Sources, Readers };
  ConeAnalysis(DataFlowSolver &solver, Operation *design,
               ArrayRef<Process> processes, ArrayRef<uint64_t> seeds,
               Direction direction)
      : DataFlowAnalysis(solver), design(design), processes(processes),
        seeds(seeds), direction(direction) {
    registerAnchorKind<ConeRoot>();
  }
  LogicalResult initialize(Operation *) override {
    for (uint64_t root : seeds)
      propagateIfChanged(state(root), state(root)->reach());
    for (const Process &process : processes)
      if (failed(visit(pointOf(process))))
        return failure();
    return success();
  }
  LogicalResult visit(ProgramPoint *point) override {
    auto found = byPoint.find(point);
    if (found == byPoint.end())
      return success();
    const Process &process = *found->second;
    bool toSources = direction == Direction::Sources;
    if (process.precise) {
      for (auto [input, output] : process.dependencies) {
        uint64_t from = toSources ? output : input;
        uint64_t to = toSources ? input : output;
        if (getOrCreateFor<ConeState>(point, anchor(from))->reached)
          propagateIfChanged(state(to), state(to)->reach());
      }
      return success();
    }
    ArrayRef<uint64_t> from = toSources ? process.written : process.watched;
    ArrayRef<uint64_t> to = toSources ? process.watched : process.written;
    if (llvm::none_of(from, [&](uint64_t root) {
          return getOrCreateFor<ConeState>(point, anchor(root))->reached;
        }))
      return success();
    for (uint64_t root : to)
      propagateIfChanged(state(root), state(root)->reach());
    return success();
  }
  /// Whether a solved cone contains a root.
  static bool contains(DataFlowSolver &solver, Operation *design,
                       uint64_t root) {
    const auto *state = solver.lookupState<ConeState>(
        solver.getLatticeAnchor<ConeRoot>(std::make_pair(root, design)));
    return state && state->reached;
  }

private:
  ConeRoot *anchor(uint64_t root) {
    return getLatticeAnchor<ConeRoot>(std::make_pair(root, design));
  }
  ConeState *state(uint64_t root) {
    return getOrCreate<ConeState>(anchor(root));
  }
  ProgramPoint *pointOf(const Process &process) {
    sim::SimFuncOp function = process.function;
    ProgramPoint *point = getProgramPointBefore(&function.getBody().front());
    byPoint[point] = &process;
    return point;
  }
  Operation *design;
  ArrayRef<Process> processes;
  ArrayRef<uint64_t> seeds;
  Direction direction;
  DenseMap<ProgramPoint *, const Process *> byPoint;
};

/// Whether an operation may end the simulation (IEEE 1800-2023 20.2, 24.7):
/// `$finish`, `$stop` (batch), `$fatal` and `$exit`, or a call that may.
/// Task calls and spawns start separate activations, whose own blocks are
/// checked where they run; other calls without a known body are opaque.
bool endsSimulation(Operation *operation, const SymbolTable &symbols,
                    function_ref<bool(sim::SimFuncOp)> calleeEnds) {
  if (isa<sim::SimFinishOp, sim::SimStopOp, sim::SimFatalOp,
          sim::SimProgramExitOp>(operation))
    return true;
  if (auto call = dyn_cast<sim::SimCallOp>(operation)) {
    auto callee = symbols.lookup<sim::SimFuncOp>(call.getCallee());
    return !callee || callee.isExternal() || calleeEnds(callee);
  }
  return isa<CallOpInterface>(operation) &&
         !isa<sim::SimSpawnOp, sim::SimTaskCallOp>(operation);
}

/// Whether a function may end the simulation.
class EndsSimulationState final : public AnalysisState {
public:
  using AnalysisState::AnalysisState;
  ChangeResult set() {
    if (ends)
      return ChangeResult::NoChange;
    ends = true;
    return ChangeResult::Change;
  }
  void print(raw_ostream &os) const override { os << ends; }
  bool ends = false;
};

/// Bottom-up over plain calls: a function may end the simulation when one of
/// its operations may (see endsSimulation). States are anchored at function
/// entries.
class EndsSimulationAnalysis final : public DataFlowAnalysis {
public:
  EndsSimulationAnalysis(DataFlowSolver &solver, const SymbolTable &symbols)
      : DataFlowAnalysis(solver), symbols(symbols) {}
  LogicalResult initialize(Operation *top) override {
    top->walk([&](sim::SimFuncOp function) {
      if (!function.isExternal())
        (void)visit(getProgramPointBefore(&function.getBody().front()));
    });
    return success();
  }
  LogicalResult visit(ProgramPoint *point) override {
    Block *entry = point->getBlock();
    auto function = entry ? dyn_cast<sim::SimFuncOp>(entry->getParentOp())
                          : sim::SimFuncOp{};
    if (!function || entry != &function.getBody().front())
      return success();
    bool ends = function
                    .walk([&](Operation *operation) {
                      return endsSimulation(
                                 operation, symbols,
                                 [&](sim::SimFuncOp callee) {
                                   return getOrCreateFor<EndsSimulationState>(
                                              point, entryOf(callee))
                                       ->ends;
                                 })
                                 ? WalkResult::interrupt()
                                 : WalkResult::advance();
                    })
                    .wasInterrupted();
    if (ends) {
      auto *state = getOrCreate<EndsSimulationState>(point);
      propagateIfChanged(state, state->set());
    }
    return success();
  }
  /// Whether a solved function may end the simulation.
  static bool ends(DataFlowSolver &solver, sim::SimFuncOp function) {
    if (function.isExternal())
      return true;
    const auto *state = solver.lookupState<EndsSimulationState>(
        solver.getProgramPointBefore(&function.getBody().front()));
    return state && state->ends;
  }

private:
  ProgramPoint *entryOf(sim::SimFuncOp function) {
    return getProgramPointBefore(&function.getBody().front());
  }
  const SymbolTable &symbols;
};

/// Whether a block's activations may run, a root may change, or a process or
/// task may start or return after a deferred kernel within its phase, before
/// that phase's NBA region.
class AfterState final : public AnalysisState {
public:
  using AnalysisState::AnalysisState;
  ChangeResult set() {
    if (after)
      return ChangeResult::NoChange;
    after = true;
    return ChangeResult::Change;
  }
  void print(raw_ostream &os) const override { os << after; }
  bool after = false;
};

/// A root changed after the kernel; `anyRoot` stands for an unresolved one.
class AfterRoot final
    : public GenericLatticeAnchorBase<AfterRoot,
                                      std::pair<uint64_t, Operation *>> {
public:
  using Base::Base;
  static constexpr uint64_t anyRoot = ~uint64_t{0};
  Location getLoc() const override { return getValue().second->getLoc(); }
  void print(raw_ostream &os) const override {
    os << "change after kernel of root " << getValue().first;
  }
};

/// The start (0) or the return (1) of a process or task.
class AfterEntry final
    : public GenericLatticeAnchorBase<AfterEntry,
                                      std::pair<Operation *, unsigned>> {
public:
  using Base::Base;
  Location getLoc() const override { return getValue().first->getLoc(); }
  void print(raw_ostream &os) const override {
    os << (getValue().second ? "return" : "start") << " after kernel";
  }
};

/// IEEE 1800-2023 4.4.2.3 and 4.5: a deferred kernel resumes in the Inactive
/// region, after every Active event of its pass. Within its phase, what may run
/// after it is what updates made after it wake: its own blocking writes and
/// direct stores, and transitively the blocking writes and event triggers of
/// every activation they wake. NBAs land in the next phase and positive delays
/// in a later slot. Other kernels of the phase are deferred as well, so they
/// may run after it. Zero and variable delays, waits on unresolved roots and
/// waits this analysis does not model are conservatively after it.
class PostKernelAnalysis final : public DataFlowAnalysis {
public:
  using BlockInfo = analysis::ActivationPhaseAnalysis::BlockInfo;
  struct Config {
    Operation *design;
    const analysis::ActivationPhaseAnalysis &phases;
    analysis::ActivationPhaseAnalysis::Phases kernel;
    sim::SimFuncOp rootInitializer;
    /// The kernel's members, which are the kernel itself.
    DenseSet<Operation *> members;
    /// Waits of other kernels' members.
    DenseSet<Operation *> otherKernelWaits;
    /// Roots the kernel itself may change in its phase.
    SmallVector<uint64_t> changed;
    /// Blocks that never run in a later time slot of the kernel's edge, and
    /// whether they also never run with it in the time-zero slot.
    const DenseSet<Block *> *otherSlotBlocks = nullptr;
    bool otherSlotAtZero = false;
  };
  PostKernelAnalysis(DataFlowSolver &solver, const Config &config)
      : DataFlowAnalysis(solver), config(config) {
    registerAnchorKind<AfterRoot>();
    registerAnchorKind<AfterEntry>();
  }
  LogicalResult initialize(Operation *) override {
    for (uint64_t root : config.changed)
      mark(rootState(root));
    for (auto &[block, info] : config.phases.getBlockInfos())
      visitBlock(block, info);
    return success();
  }
  LogicalResult visit(ProgramPoint *point) override {
    if (!point->isBlockStart())
      return success();
    if (const BlockInfo *info = config.phases.getBlockInfo(point->getBlock()))
      visitBlock(point->getBlock(), *info);
    return success();
  }
  /// Whether `block`'s activations may run after the kernel.
  static bool isAfter(DataFlowSolver &solver, Block *block) {
    const auto *state =
        solver.lookupState<AfterState>(solver.getProgramPointBefore(block));
    return state && state->after;
  }

private:
  /// A block's activations run after the kernel if its entry or some
  /// executable edge into it does; then its starts, returns and the blocking
  /// writes and event triggers of its fragment, including the summaries of
  /// what it calls, wake what they reach in the same phase.
  void visitBlock(Block *block, const BlockInfo &info) {
    auto function = cast<sim::SimFuncOp>(block->getParentOp());
    if (config.members.contains(function))
      return;
    ProgramPoint *point = getProgramPointBefore(block);
    bool after = false;
    if (block->isEntryBlock())
      after = entryAfter(function, block, point);
    else
      for (Block *predecessor : info.predecessors)
        after = after || transfer(predecessor, block, point);
    auto *state = getOrCreate<AfterState>(point);
    if (after)
      mark(state);
    if (!state->after)
      return;
    for (Operation *callee : info.spawns)
      mark(entryState(callee, /*returns=*/false));
    for (Operation *callee : info.taskCalls)
      mark(entryState(callee, /*returns=*/false));
    if (info.isReturn)
      mark(entryState(function, /*returns=*/true));
    if (info.hasEffects)
      for (uint64_t root : info.wakes)
        mark(rootState(root));
  }

  bool entryAfter(sim::SimFuncOp function, Block *block, ProgramPoint *point) {
    // Plain functions run inside their callers, whose fragments carry their
    // effects; static initialization precedes every slot.
    if (function == config.rootInitializer ||
        function.getEntryKind() == sim::EntryKind::Function)
      return false;
    if (!config.phases.isModeledStart(function.getSymNameAttr()))
      return config.phases.getPhases(block).meets(config.kernel);
    return getOrCreateFor<AfterState>(
               point, getLatticeAnchor<AfterEntry>(
                          std::make_pair(function.getOperation(), 0u)))
        ->after;
  }

  /// Whether `predecessor`'s terminator enters `block` after the kernel.
  bool transfer(Block *predecessor, Block *block, ProgramPoint *point) {
    const BlockInfo &from = *config.phases.getBlockInfo(predecessor);
    using Transfer = BlockInfo::Transfer;
    if (from.transfer == Transfer::Plain ||
        (from.transfer == Transfer::TaskCall && !from.calleeSuspends))
      return getOrCreateFor<AfterState>(point,
                                        getProgramPointBefore(predecessor))
          ->after;
    if (from.transfer == Transfer::TaskCall)
      return !from.callee || getOrCreateFor<AfterState>(
                                 point, getLatticeAnchor<AfterEntry>(
                                            std::make_pair(from.callee, 1u)))
                                 ->after;
    analysis::ActivationPhaseAnalysis::Phases at =
        config.phases.getPhases(block);
    if (config.otherSlotBlocks && config.otherSlotBlocks->contains(block)) {
      at.later = 0;
      if (config.otherSlotAtZero)
        at.zero = 0;
    }
    if (!at.meets(config.kernel))
      return false;
    if (config.otherKernelWaits.contains(from.terminator))
      return true;
    switch (from.transfer) {
    case Transfer::Positive:
    case Transfer::Forever:
      return false;
    case Transfer::Zero:
    case Transfer::Variable:
    case Transfer::Unknown:
      return true;
    case Transfer::Watch:
    case Transfer::Event: {
      bool woken = changedFor(point, AfterRoot::anyRoot);
      for (uint64_t root : from.watched)
        woken = woken || changedFor(point, root);
      return woken;
    }
    case Transfer::Plain:
    case Transfer::TaskCall:
      break;
    }
    llvm_unreachable("handled above");
  }

  void mark(AfterState *state) { propagateIfChanged(state, state->set()); }
  AfterState *rootState(uint64_t root) {
    return getOrCreate<AfterState>(
        getLatticeAnchor<AfterRoot>(std::make_pair(root, config.design)));
  }
  AfterState *entryState(Operation *function, bool returns) {
    return getOrCreate<AfterState>(getLatticeAnchor<AfterEntry>(
        std::make_pair(function, unsigned{returns})));
  }
  bool changedFor(ProgramPoint *point, uint64_t root) {
    return getOrCreateFor<AfterState>(
               point,
               getLatticeAnchor<AfterRoot>(std::make_pair(root, config.design)))
        ->after;
  }
  const Config &config;
};

/// Union-find over storage roots connected by clock copies.
struct ClockClasses {
  DenseMap<uint64_t, uint64_t> parent;
  uint64_t find(uint64_t root) {
    auto found = parent.find(root);
    if (found == parent.end() || found->second == root)
      return root;
    uint64_t top = find(found->second);
    parent[root] = top;
    return top;
  }
  void join(uint64_t source, uint64_t destination) {
    parent.try_emplace(source, source);
    parent[find(destination)] = find(source);
  }
};

void TalosSimFuseClockedKernelsPass::runOnOperation() {
  sim::SimDesignOp design = getOperation();
  ModuleOp module = design->getParentOfType<ModuleOp>();
  bool report = module && native::has<native::DebugTiming>(module);
  schedule::ComputeGraphAttr graph = design.getComputeGraphAttr();
  if (!graph || graph.getVpi() != schedule::ComputeVPIMode::Off ||
      graph.getWorkers() != 1) {
    if (report)
      llvm::errs() << "talos clocked kernel: skipped design: graph\n";
    return;
  }
  llvm::StringMap<uint64_t> rejections;
  auto reject = [&](StringRef reason) { ++rejections[reason]; };

  // Force, procedural continuous assignment and foreign code can update or
  // observe any root outside the scheduler regions modeled below. Foreign
  // code reaches the design only through context exports (IEEE 1800-2023
  // 35.5.1.3, 35.5.3).
  bool unsupportedDesign =
      analysis::DPIEffectAnalysis(design).anyCallMayAccessDesign();
  design.walk([&](Operation *operation) {
    unsupportedDesign |= isa<sim::SimOverrideOp, sim::SimDynamicOverrideOp,
                             sim::SimReleaseOverrideOp>(operation);
  });
  auto bail = [&](StringRef reason) {
    if (report)
      llvm::errs() << "talos clocked kernel: skipped design: " << reason
                   << '\n';
  };
  if (unsupportedDesign)
    return bail("override or foreign call");

  SymbolTable symbols(design);
  analysis::HandleDataflowAnalysis provenance(design);
  provenance.prepare(design);
  ArrayAttr nodes = graph.getNodes();

  sim::SimFuncOp rootInitializer;
  for (sim::SimFuncOp function :
       design.getBody().front().getOps<sim::SimFuncOp>())
    if (function.getEntryKind() == sim::EntryKind::RootInitializer)
      rootInitializer = function;
  if (!rootInitializer)
    return bail("no root initializer");

  DenseMap<StringAttr, SmallVector<sim::SimSpawnOp>> spawns;
  design.walk([&](sim::SimSpawnOp spawn) {
    spawns[spawn.getCalleeAttr().getAttr()].push_back(spawn);
  });
  auto rootSpawn = [&](sim::SimFuncOp function) -> sim::SimSpawnOp {
    auto found = spawns.find(function.getSymNameAttr());
    if (found == spawns.end() || found->second.size() != 1)
      return {};
    sim::SimSpawnOp spawn = found->second.front();
    if (spawn->getBlock() != &rootInitializer.getBody().front() ||
        !spawn.getResult().use_empty())
      return {};
    return spawn;
  };
  // Every symbol reference other than the root spawn keeps a function alive.
  DenseMap<StringAttr, unsigned> symbolUseCounts;
  if (auto uses = analysis::getSymbolUsesConcurrently(&design.getBody()))
    for (const SymbolTable::SymbolUse &use : *uses)
      ++symbolUseCounts[use.getSymbolRef().getRootReference()];

  // Fragment inventory by function and block.
  DenseMap<StringAttr, SmallVector<schedule::ComputeFragmentAttr>> fragments;
  for (Attribute attribute : nodes)
    if (auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(attribute))
      fragments[fragment.getFunction().getAttr()].push_back(fragment);
  auto blockAt = [](sim::SimFuncOp function, uint32_t index) -> Block * {
    for (Block &block : function.getBody())
      if (index-- == 0)
        return &block;
    return nullptr;
  };

  // Schedule order of Active fragments, used to keep the existing relative
  // order of cohort members wherever no dependence decides it.
  DenseMap<uint32_t, uint32_t> scheduleOrder;
  {
    uint32_t next = 0;
    for (Attribute regionAttribute : graph.getRegions()) {
      auto region = cast<schedule::ComputeRegionAttr>(regionAttribute);
      if (region.getKind() != schedule::ComputeRegionKind::Active)
        continue;
      for (Attribute groupAttribute : region.getGroups())
        for (int64_t member : cast<schedule::ComputeGroupAttr>(groupAttribute)
                                  .getFragments()
                                  .asArrayRef())
          scheduleOrder.try_emplace(static_cast<uint32_t>(member), next++);
    }
  }

  // Time-slot phases of every activation and root change (4.5).
  analysis::ActivationPhaseAnalysis phases(design, provenance);
  if (!phases.isValid())
    return bail("phase analysis");
  using Phases = analysis::ActivationPhaseAnalysis::Phases;
  using PhaseSet = analysis::ActivationPhaseAnalysis::PhaseSet;

  // Writers and watchers of each root from the verified graph.
  struct Writer {
    StringAttr function;
    uint32_t block;
    schedule::ComputeEffectKind kind;
    /// An intra-assignment delayed NBA, which may land in any NBA region.
    bool deferred = false;
  };
  DenseMap<uint64_t, SmallVector<Writer>> writers;
  DenseMap<uint64_t, SmallVector<StringAttr>> watchers;
  DenseSet<uint64_t> readRoots;
  bool unknownRead = false;
  // Writes of an unresolved target may update any root.
  SmallVector<Writer> unknownWriters;
  auto effectRoots = [&](StringAttr function,
                         schedule::ComputeEffectAttr effect) {
    return phases.getEffectRoots(function, effect);
  };
  for (Attribute attribute : nodes) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(attribute);
    if (!fragment)
      continue;
    StringAttr function = fragment.getFunction().getAttr();
    // Ordinary calls execute inside their caller's activation. Their effects
    // are already expanded on the caller's graph fragments; counting the
    // callee again invents an independent writer (notably for static init).
    if (auto callee = symbols.lookup<sim::SimFuncOp>(function);
        callee && callee.getEntryKind() == sim::EntryKind::Function)
      continue;
    for (auto effect :
         fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
      if (effect.getTarget() == schedule::ComputeTargetKind::Local)
        continue;
      std::optional<SmallVector<uint64_t>> roots =
          effectRoots(function, effect);
      if (isWrite(effect.getEffect()) && !roots) {
        unknownWriters.push_back({function, fragment.getBlock(),
                                  effect.getEffect(), effect.getDeferred()});
        continue;
      }
      bool reads = effect.getEffect() == schedule::ComputeEffectKind::Read ||
                   effect.getEffect() == schedule::ComputeEffectKind::Watch;
      if (!roots) {
        unknownRead |= reads;
        continue;
      }
      for (uint64_t root : *roots) {
        if (reads)
          readRoots.insert(root);
        if (isWrite(effect.getEffect()))
          writers[root].push_back({function, fragment.getBlock(),
                                   effect.getEffect(), effect.getDeferred()});
        if (effect.getEffect() == schedule::ComputeEffectKind::Watch)
          watchers[root].push_back(function);
      }
    }
  }

  CombinationalFusionAnalysis combinational(
      design, provenance,
      ActivationMemoryAnalysis::DependencyMode::ReachingValues);
  const llvm::DenseSet<uint64_t> &glitchInsensitive =
      combinational.getGlitchInsensitiveStorage();
  // Diagnostics: roots refused as observed, by the observer that exposes them.
  DenseMap<StringAttr, unsigned> observedRootsBy;
  DenseMap<StringAttr, bool> transparentCache;
  auto isTransparent = [&](StringAttr name) {
    auto [found, inserted] = transparentCache.try_emplace(name, false);
    if (inserted)
      if (auto function = symbols.lookup<sim::SimFuncOp>(name))
        found->second =
            combinational
                .analyze(function, provenance, /*interleaved=*/true, nullptr,
                         /*finalValuesOnly=*/true)
                .has_value();
    return found->second;
  };

  // 1. Clock alias classes: roots connected by proven copies, which change
  // in exactly the phases of their source.
  ClockClasses classes;
  for (auto &[destination, copy] : phases.getCopies())
    classes.join(copy.source, destination);

  // A clock usually reaches a module as a one-bit net: an input port
  // connection or a net declaration assignment such as `wire c = ~clk;`.
  // Each is a continuous assignment (IEEE 1800-2023 10.3.1, 23.3.3) that
  // updates its net only when the value changes (10.3.2). The clock analysis
  // follows exact, exclusive pure copies of this kind back to the variable
  // they all copy, recording whether an odd number of them complement it.
  std::unique_ptr<analysis::NativeStateLayoutAnalysis> clockLayout;
  std::unique_ptr<analysis::ClockInferenceAnalysis> clockCopies;
  DenseMap<uint64_t, uint64_t> clockRootAt;
  bool clockCopiesComputed = false;
  auto computeClockCopies = [&] {
    clockCopiesComputed = true;
    if (!module)
      return;
    // A design the native layout rejects keeps storage clocks only; that
    // rejection is reported by the backend that needs the layout.
    FailureOr<analysis::NativeStateLayoutAnalysis> layout;
    {
      ScopedDiagnosticHandler quiet(design.getContext(),
                                    [](Diagnostic &) { return success(); });
      layout = analysis::NativeStateLayoutAnalysis::compute(module);
    }
    if (failed(layout))
      return;
    clockLayout =
        std::make_unique<analysis::NativeStateLayoutAnalysis>(*layout);
    clockCopies = std::make_unique<analysis::ClockInferenceAnalysis>(
        module, *clockLayout, ArrayRef<analysis::PeriodicClockSeed>{});
    // One-bit roots by physical bit. Aliased descriptors share a bit; the
    // smallest root identifies it deterministically.
    DenseMap<uint64_t, unsigned> widths;
    for (const auto &bound : clockLayout->bounds)
      if (bound.width)
        widths.try_emplace(bound.offset, bound.width);
    auto index = [&](const DenseMap<uint64_t, uint64_t> &offsets,
                     schedule::ComputeResourceKind resource) {
      for (auto [descriptor, offset] : offsets) {
        std::optional<uint64_t> root =
            ActivationMemoryAnalysis::getRoot(resource, descriptor);
        if (widths.lookup(offset) != 1 || !root)
          continue;
        auto [found, inserted] = clockRootAt.try_emplace(offset, *root);
        if (!inserted)
          found->second = std::min(found->second, *root);
      }
    };
    index(clockLayout->storageOffsets, schedule::ComputeResourceKind::Storage);
    index(clockLayout->netOffsets, schedule::ComputeResourceKind::Net);
  };
  // Follows a whole one-bit net clock to its origin root.
  auto resolveNetClock = [&](Value watched, const analysis::HandleFacts &facts,
                             Member &member) {
    auto found = facts.find(watched);
    if (found == facts.end() ||
        found->second.resource != schedule::ComputeResourceKind::Net ||
        !found->second.descriptor || found->second.dynamic ||
        found->second.low != 0 || found->second.width != 1 ||
        found->second.rootWidth != 1)
      return false;
    if (!clockCopiesComputed)
      computeClockCopies();
    if (!clockCopies)
      return false;
    std::optional<analysis::ClockBit> bit = clockCopies->getBit(found->second);
    std::optional<uint64_t> clock = ActivationMemoryAnalysis::getRoot(
        schedule::ComputeResourceKind::Net, *found->second.descriptor);
    if (!bit || !clock)
      return false;
    member.clock = *clock;
    member.clockChain = {*clock};
    member.inverted = false;
    DenseSet<analysis::ClockBit> visited{*bit};
    while (std::optional<analysis::ClockOrigin> source =
               clockCopies->getCopySource(*bit)) {
      auto root = clockRootAt.find(source->bit.second);
      if (root == clockRootAt.end() || !visited.insert(source->bit).second)
        return false;
      bit = source->bit;
      member.inverted ^= source->inverted;
      member.clockChain.push_back(root->second);
    }
    member.origin = member.clockChain.back();
    return true;
  };
  // The level a clock root holds before its first update: x for 4-state
  // variables, 0 for 2-state variables (Table 6-7), and z for nets (6.6).
  // A declaration initializer gives an initial value only that root has.
  enum InitialLevel : unsigned { Low, High, Unknown, Initialized };
  DenseMap<uint64_t, Type> storageTypes;
  for (auto declaration :
       design.getBody().front().getOps<sim::SimStorageDeclOp>())
    storageTypes[declaration.getId()] = declaration.getType();
  DenseMap<uint64_t, Type> netTypes;
  for (auto declaration : design.getBody().front().getOps<sim::SimNetDeclOp>())
    netTypes[declaration.getId()] = declaration.getType();
  auto rootType = [&](uint64_t root) -> Type {
    if (root >= ActivationMemoryAnalysis::netRootTag)
      return netTypes.lookup(root & ~ActivationMemoryAnalysis::netRootTag);
    return storageTypes.lookup(root);
  };
  auto initialLevel = [&](uint64_t root) -> unsigned {
    if (root >= ActivationMemoryAnalysis::netRootTag)
      return Unknown;
    if (llvm::any_of(writers.lookup(root), [&](const Writer &writer) {
          return writer.function == rootInitializer.getSymNameAttr();
        }))
      return Initialized;
    Type type = storageTypes.lookup(root);
    if (isa_and_nonnull<IntegerType>(type))
      return Low;
    if (isa_and_nonnull<sim::LogicType>(type))
      return Unknown;
    return Initialized;
  };

  // 2. Clocked members, grouped by clock class, edge, and time-zero
  // behavior.
  // (class root, edge relative to the class | time-zero variant << 8).
  using GroupKey = std::pair<uint64_t, unsigned>;
  auto groupEdge = [](const GroupKey &key) {
    return static_cast<sim::EdgeKind>(key.second & 0xff);
  };
  llvm::MapVector<GroupKey, std::vector<Member>> groups;
  // Multi-edge signatures get variants beyond the single-edge startup
  // variants (0..3); their low edge byte remains Change, so opposite-edge
  // exclusion is never applied to a control with independent inputs.
  DenseMap<Attribute, unsigned> multiEventGroups;
  for (sim::SimFuncOp function :
       design.getBody().front().getOps<sim::SimFuncOp>()) {
    if (function.isExternal() ||
        (function.getEntryKind() != sim::EntryKind::AlwaysFF &&
         function.getEntryKind() != sim::EntryKind::Always))
      continue;
    Member member;
    member.function = function;
    member.spawn = rootSpawn(function);
    if (!member.spawn) {
      reject("member spawn");
      continue;
    }
    if (symbolUseCounts.lookup(function.getSymNameAttr()) != 1) {
      reject("member symbol uses");
      continue;
    }
    if (function.getHomeRegion() != sim::EventRegion::Active ||
        function.getDomain() != sim::ExecutionDomain::Design) {
      reject("member region");
      continue;
    }
    Operation *wait = nullptr;
    unsigned suspensions = 0;
    function.walk([&](Operation *operation) {
      if (!isSuspension(operation))
        return;
      ++suspensions;
      wait = operation;
    });
    auto edgeWait = dyn_cast_or_null<sim::SimSuspendEdgeOp>(wait);
    auto anyWait = dyn_cast_or_null<sim::SimSuspendAnyOp>(wait);
    if (suspensions != 1 || (!edgeWait && !anyWait) ||
        wait->hasAttr("resume_region") ||
        !cast<BranchOpInterface>(wait)
             .getSuccessorOperands(0)
             .getForwardedOperands()
             .empty() ||
        wait->getParentRegion() != &function.getBody()) {
      reject("member wait shape");
      continue;
    }
    member.wait = wait->getBlock();
    member.body = wait->getSuccessor(0);
    member.edge = edgeWait ? edgeWait.getEdge() : sim::EdgeKind::Change;
    Block &entry = function.getBody().front();
    auto entryBranch = dyn_cast<cf::BranchOp>(entry.getTerminator());
    if (!entryBranch || entryBranch.getDest() != member.wait ||
        !entryBranch.getDestOperands().empty() ||
        member.wait->getNumArguments() != 0 ||
        member.body->getNumArguments() != 0 || member.body == member.wait ||
        !llvm::all_of(entry.without_terminator(),
                      [](Operation &operation) {
                        return isMemoryEffectFree(&operation);
                      }) ||
        !llvm::all_of(member.wait->without_terminator(),
                      [](Operation &operation) {
                        return isMemoryEffectFree(&operation);
                      })) {
      reject("member entry shape");
      continue;
    }
    if (!collectBodyBlocks(member)) {
      reject("member body shape");
      continue;
    }
    if (!isComputeBodyFusionEligible(function, provenance)) {
      reject("member body eligibility");
      continue;
    }
    analysis::HandleFacts facts = provenance.derive(function);
    if (anyWait) {
      struct Event {
        uint64_t root, origin;
        sim::EdgeKind edge;
        unsigned variant;
      };
      SmallVector<Event> events;
      bool supported = true;
      for (auto [watched, encoded] :
           llvm::zip_equal(anyWait.getWatched(), anyWait.getEdges())) {
        Type type = watched.getType();
        auto ref = dyn_cast<sim::RefType>(type);
        auto net = dyn_cast<sim::NetType>(type);
        Type element = ref   ? ref.getElementType()
                       : net ? net.getElementType()
                             : Type{};
        auto root = wholeRoot(watched, facts);
        auto edge = static_cast<sim::EdgeKind>(encoded);
        if (!element || !root || !isClockBit(element) ||
            (edge != sim::EdgeKind::Posedge &&
             edge != sim::EdgeKind::Negedge)) {
          supported = false;
          break;
        }
        unsigned level = initialLevel(*root);
        unsigned variant = level == Initialized             ? level
                           : edge == sim::EdgeKind::Posedge ? level == High
                                                            : level == Low;
        events.push_back({*root, classes.find(*root), edge, variant});
        member.eventRoots.push_back(*root);
      }
      if (!supported || events.empty()) {
        reject("member multi-edge clock");
        continue;
      }
      llvm::sort(events, [](const Event &a, const Event &b) {
        return std::tie(a.origin, a.edge, a.variant) <
               std::tie(b.origin, b.edge, b.variant);
      });
      SmallVector<int64_t> signature;
      for (const Event &event : events) {
        signature.push_back(event.origin);
        signature.push_back(static_cast<unsigned>(event.edge));
        signature.push_back(event.variant);
      }
      member.eventSignature =
          DenseI64ArrayAttr::get(design.getContext(), signature);
      member.clock = member.origin = events.front().root;
    } else {
      Type watchedType = edgeWait.getWatched().getType();
      if (auto ref = dyn_cast<sim::RefType>(watchedType)) {
        std::optional<uint64_t> clock =
            wholeStorageRoot(edgeWait.getWatched(), facts);
        if (!clock || !isClockBit(ref.getElementType())) {
          reject("member clock");
          continue;
        }
        member.clock = member.origin = *clock;
      } else {
        // An edge event of a copy is an edge event of its source (Table 9-2
        // is symmetric under complement, since `~` maps x and z to x per
        // Table 11-15); a value change is not (`~z` equals `~x`).
        auto net = dyn_cast<sim::NetType>(watchedType);
        if (!net || !isClockBit(net.getElementType()) ||
            member.edge == sim::EdgeKind::Change ||
            !resolveNetClock(edgeWait.getWatched(), facts, member)) {
          reject("member clock");
          continue;
        }
      }
    }
    bool native = true;
    uint32_t bodyIndex = 0;
    for (auto [index, block] : llvm::enumerate(function.getBody()))
      if (&block == member.body)
        bodyIndex = index;
    llvm::DenseSet<Block *> body(member.bodyBlocks.begin(),
                                 member.bodyBlocks.end());
    for (schedule::ComputeFragmentAttr fragment :
         fragments.lookup(function.getSymNameAttr())) {
      native &= fragment.getTier() == schedule::ComputeTierKind::Native;
      if (fragment.getBlock() == bodyIndex) {
        auto order = scheduleOrder.find(fragment.getId());
        if (order != scheduleOrder.end())
          member.order = order->second;
      }
      Block *block = blockAt(function, fragment.getBlock());
      if (!block || !body.contains(block))
        continue;
      for (auto effect :
           fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
        std::optional<uint64_t> root = effectRoot(effect);
        if (!root) {
          bool shared =
              effect.getTarget() != schedule::ComputeTargetKind::Local;
          member.unresolvedUpdate |=
              shared &&
              (isWrite(effect.getEffect()) ||
               effect.getEffect() == schedule::ComputeEffectKind::Trigger);
          member.unresolvedRead |=
              shared && effect.getEffect() == schedule::ComputeEffectKind::Read;
          continue;
        }
        switch (effect.getEffect()) {
        case schedule::ComputeEffectKind::Read:
          member.reads.insert(*root);
          break;
        case schedule::ComputeEffectKind::NBA:
          member.nbaWrites.insert(*root);
          break;
        case schedule::ComputeEffectKind::Write:
        case schedule::ComputeEffectKind::Drive:
        case schedule::ComputeEffectKind::Trigger:
          member.writes.insert(*root);
          break;
        default:
          break;
        }
      }
    }
    if (!native) {
      reject("member tier");
      continue;
    }
    // The explicit reads of the member's own clock. A message that prints the
    // clock is the common case. Calls and copies may read it without such an
    // operation, which the kernel cannot redirect.
    for (Block *block : member.bodyBlocks)
      block->walk([&](Operation *operation) {
        if (isa<sim::SimCallOp, sim::SimRefCopyOp>(operation)) {
          member.opaqueClockRead = true;
          return;
        }
        std::optional<uint64_t> root;
        if (auto load = dyn_cast<sim::SimRefLoadOp>(operation)) {
          root = wholeStorageRoot(load.getReference(), facts);
        } else if (auto read = dyn_cast<sim::SimNetReadOp>(operation)) {
          auto found = facts.find(read.getNet());
          if (found != facts.end() && found->second.descriptor &&
              found->second.resource == schedule::ComputeResourceKind::Net &&
              !found->second.dynamic && found->second.low == 0 &&
              found->second.width == found->second.rootWidth)
            root = ActivationMemoryAnalysis::getRoot(
                schedule::ComputeResourceKind::Net, *found->second.descriptor);
        }
        if (root && *root == member.clock)
          member.clockReads.push_back(operation);
      });
    collectPreamble(member);
    if (member.eventSignature) {
      auto group =
          multiEventGroups
              .try_emplace(member.eventSignature, multiEventGroups.size() + 16)
              .first;
      groups[{classes.find(member.origin), group->second << 8}].push_back(
          std::move(member));
      continue;
    }
    // Members are equivalent when their edge events coincide in every time
    // slot, including the time-zero updates of copies (4.9.1, 23.3.3.3).
    // Relative to the class, a complemented chain swaps posedge and negedge.
    // With the class source quiet at time zero (checked per kernel), a
    // variable keeps its initial level then, while a net copy moves once from
    // z to its source's value. A posedge there needs a final 1 from a level
    // other than 1 and a negedge a final 0 from a level other than 0
    // (Table 9-2), so members agree at time zero when their roots agree on
    // whether the initial level rules the edge out; any edge needs the level.
    sim::EdgeKind edge = member.edge;
    unsigned level = initialLevel(member.clock);
    if (member.inverted) {
      if (edge == sim::EdgeKind::Posedge)
        edge = sim::EdgeKind::Negedge;
      else if (edge == sim::EdgeKind::Negedge)
        edge = sim::EdgeKind::Posedge;
      if (level == Low || level == High)
        level = level == Low ? High : Low;
    }
    unsigned variant = level;
    if (level != Initialized && edge == sim::EdgeKind::Posedge)
      variant = level == High;
    else if (level != Initialized && edge == sim::EdgeKind::Negedge)
      variant = level == Low;
    groups[{classes.find(member.origin),
            static_cast<unsigned>(edge) | variant << 8}]
        .push_back(std::move(member));
  }

  // Transparent combinational processes: the roots each one waits on and
  // the roots it writes.
  std::vector<ConeAnalysis::Process> combinationalProcesses;
  {
    DenseMap<StringAttr, unsigned> index;
    for (auto &[root, list] : watchers)
      for (StringAttr watcher : list)
        if (isTransparent(watcher)) {
          auto [found, inserted] =
              index.try_emplace(watcher, combinationalProcesses.size());
          if (inserted)
            combinationalProcesses.push_back(
                {symbols.lookup<sim::SimFuncOp>(watcher), {}, {}});
          combinationalProcesses[found->second].watched.push_back(root);
        }
    for (auto &[root, list] : writers)
      for (const Writer &write : list)
        if (auto found = index.find(write.function); found != index.end())
          combinationalProcesses[found->second].written.push_back(root);
    // A process can publish several independent outputs. Access to one must
    // expose only the inputs that can affect that publication (LRM 4.3), not
    // every root on its union wait. Include every intermediate publication;
    // the separate glitch-insensitivity certificate decides what can be hidden.
    for (ConeAnalysis::Process &process : combinationalProcesses) {
      auto body = combinational.analyze(process.function, provenance,
                                        /*interleaved=*/true, nullptr,
                                        /*finalValuesOnly=*/true);
      if (!body || !body->structured)
        continue;
      const auto &memory = body->structured->getMemory();
      if (!memory.hasValueDependencies())
        continue;
      process.precise = true;
      DenseSet<std::pair<uint64_t, uint64_t>> seen;
      for (const auto &[operation, publications] : memory.getPublications())
        for (const auto &publication : publications)
          for (const auto &input : publication.inputs) {
            auto edge = std::pair{input.root, publication.output.root};
            if (seen.insert(edge).second)
              process.dependencies.push_back(edge);
          }
    }
  }

  // Held-state observers: change-triggered combinational activations that
  // keep some output between activations, such as a `case` whose selector
  // matches no item (12.5) or a latch (9.2.2.3). Seeing a direct
  // store before the NBA region can change what such an observer holds, so
  // a root they watch is not glitch-insensitive. The exception is a root
  // whose observers are all quiescent for the kernel (see planRoots). An
  // observer's cone is the set of written roots that reach its inputs through
  // transparent processes and other held-state observers.
  struct HeldCone {
    SmallVector<uint64_t> roots;
    /// Held-state observers writing a root of the cone, itself included.
    SmallVector<StringAttr> observers;
  };
  DenseMap<StringAttr, HeldCone> heldCones;
  DenseMap<uint64_t, SmallVector<StringAttr>> heldObserversOf;
  DenseMap<StringAttr, SmallVector<uint32_t>> heldBlocks;
  DenseMap<StringAttr, SmallVector<schedule::ComputeFragmentAttr>> fragmentsOf;
  // The processes exposure follows: with held-state observers in play, an
  // activation reading a held observer's output also sees its inputs early.
  std::vector<ConeAnalysis::Process> exposureProcesses = combinationalProcesses;
  const DenseSet<uint64_t> &heldInsensitive =
      combinational.getHeldStateInsensitiveStorage();
  if (llvm::any_of(heldInsensitive, [&](uint64_t root) {
        return !glitchInsensitive.contains(root);
      })) {
    for (Attribute attribute : nodes)
      if (auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(attribute))
        fragmentsOf[fragment.getFunction().getAttr()].push_back(fragment);
    // Observers of at least one root that only held-state observers see.
    DenseMap<StringAttr, bool> heldCache;
    auto isHeld = [&](StringAttr name) {
      auto [found, inserted] = heldCache.try_emplace(name, false);
      if (inserted && !isTransparent(name))
        if (auto function = symbols.lookup<sim::SimFuncOp>(name))
          found->second = combinational.isHeldStateObserver(function);
      return found->second;
    };
    llvm::SetVector<StringAttr> held;
    for (auto &[root, list] : watchers)
      if (heldInsensitive.contains(root) && !glitchInsensitive.contains(root))
        for (StringAttr watcher : list)
          if (isHeld(watcher))
            held.insert(watcher);
    SmallVector<StringAttr> ordered(held.begin(), held.end());
    llvm::sort(ordered, [](StringAttr a, StringAttr b) {
      return a.getValue() < b.getValue();
    });
    // Every read and watch is an input: a read the observer does not wait on
    // still decides what it holds. An unresolved one leaves its cone open.
    DenseMap<StringAttr, SetVector<uint64_t>> inputs;
    DenseSet<StringAttr> open;
    for (Attribute attribute : nodes) {
      auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(attribute);
      if (!fragment)
        continue;
      StringAttr name = fragment.getFunction().getAttr();
      if (!held.contains(name))
        continue;
      heldBlocks[name].push_back(fragment.getBlock());
      for (auto effect :
           fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
        if (effect.getTarget() == schedule::ComputeTargetKind::Local ||
            (effect.getEffect() != schedule::ComputeEffectKind::Read &&
             effect.getEffect() != schedule::ComputeEffectKind::Watch))
          continue;
        if (std::optional<SmallVector<uint64_t>> roots =
                effectRoots(name, effect))
          inputs[name].insert(roots->begin(), roots->end());
        else
          open.insert(name);
      }
    }
    DenseMap<StringAttr, SmallVector<uint64_t>> heldWrites;
    for (auto &[root, list] : writers)
      for (const Writer &write : list)
        if (held.contains(write.function))
          heldWrites[write.function].push_back(root);
    // A change can make a transparent process run and publish again, even
    // where no published value depends on it, and the held-state observer
    // then evaluates again. Its cone therefore follows every watch to every
    // write, as the glitch-insensitivity fixpoint does, not value
    // dependencies alone.
    std::vector<ConeAnalysis::Process> coneProcesses = combinationalProcesses;
    for (ConeAnalysis::Process &process : coneProcesses) {
      process.precise = false;
      process.dependencies.clear();
    }
    for (StringAttr name : ordered)
      coneProcesses.push_back({symbols.lookup<sim::SimFuncOp>(name),
                               inputs[name].takeVector(),
                               heldWrites.lookup(name)});
    SmallVector<uint64_t> writtenRoots;
    for (auto &[root, list] : writers)
      writtenRoots.push_back(root);
    llvm::sort(writtenRoots);
    // An unresolved read may observe any root, so no root is then known to
    // reach only bounded cones.
    ArrayRef<ConeAnalysis::Process> heldProcesses =
        open.empty()
            ? ArrayRef(coneProcesses).drop_front(combinationalProcesses.size())
            : ArrayRef<ConeAnalysis::Process>();
    for (const ConeAnalysis::Process &process : heldProcesses) {
      StringAttr name = sim::SimFuncOp(process.function).getSymNameAttr();
      DataFlowSolver solver;
      solver.load<ConeAnalysis>(design.getOperation(), coneProcesses,
                                process.watched,
                                ConeAnalysis::Direction::Sources);
      if (process.watched.empty() || failed(solver.initializeAndRun(design))) {
        heldCones.clear();
        heldObserversOf.clear();
        break;
      }
      HeldCone &cone = heldCones[name];
      DenseSet<StringAttr> observers{name};
      cone.observers.push_back(name);
      for (uint64_t root : writtenRoots) {
        if (!ConeAnalysis::contains(solver, design.getOperation(), root))
          continue;
        cone.roots.push_back(root);
        heldObserversOf[root].push_back(name);
        for (const Writer &write : writers.lookup(root))
          if (held.contains(write.function) &&
              observers.insert(write.function).second)
            cone.observers.push_back(write.function);
      }
    }
    if (!heldCones.empty())
      llvm::append_range(exposureProcesses, heldProcesses);
  }

  // IEEE 1800-2023 20.2 and 9.2.3: `$finish` ends the simulation at once,
  // and final procedures then read the state with no remaining scheduled
  // event executed, including NBAs still pending. Find the activations that
  // may end the simulation and the roots final procedures read.
  DataFlowSolver ending;
  ending.load<EndsSimulationAnalysis>(symbols);
  if (failed(ending.initializeAndRun(design)))
    return bail("end-of-simulation analysis");
  DenseSet<std::pair<StringAttr, uint32_t>> endingFragments;
  SmallVector<uint64_t> finalReads;
  bool unknownFinalRead = false;
  for (Attribute attribute : nodes) {
    auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(attribute);
    if (!fragment)
      continue;
    StringAttr name = fragment.getFunction().getAttr();
    auto function = symbols.lookup<sim::SimFuncOp>(name);
    if (!function || function.isExternal())
      continue;
    if (function.getEntryKind() == sim::EntryKind::Final) {
      for (auto effect :
           fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
        if (effect.getEffect() != schedule::ComputeEffectKind::Read ||
            effect.getTarget() == schedule::ComputeTargetKind::Local)
          continue;
        if (std::optional<SmallVector<uint64_t>> roots =
                phases.getEffectRoots(name, effect))
          llvm::append_range(finalReads, *roots);
        else
          unknownFinalRead = true;
      }
      continue;
    }
    Block *block = blockAt(function, fragment.getBlock());
    if (block && llvm::any_of(*block, [&](Operation &operation) {
          return operation
              .walk([&](Operation *nested) {
                return endsSimulation(nested, symbols,
                                      [&](sim::SimFuncOp callee) {
                                        return EndsSimulationAnalysis::ends(
                                            ending, callee);
                                      })
                           ? WalkResult::interrupt()
                           : WalkResult::advance();
              })
              .wasInterrupted();
        }))
      endingFragments.insert({name, fragment.getBlock()});
  }

  // Every root of each clock alias class.
  DenseMap<uint64_t, SmallVector<uint64_t>> classMembers;
  for (auto &[destination, copy] : phases.getCopies()) {
    classMembers[classes.find(destination)].push_back(destination);
    classMembers[classes.find(copy.source)].push_back(copy.source);
  }

  // A process that suspends only on positive constant delays runs at most
  // once per time slot (9.4.1): a delay always resumes in a later slot.
  auto isPeriodic = [&](StringAttr name) {
    auto function = symbols.lookup<sim::SimFuncOp>(name);
    if (!function || function.isExternal() || !rootSpawn(function) ||
        symbolUseCounts.lookup(name) != 1)
      return false;
    bool periodic = true;
    function.walk([&](Operation *operation) {
      if (!isSuspension(operation))
        return;
      auto delay = dyn_cast<sim::SimSuspendDelayOp>(operation);
      auto constant =
          delay ? delay.getDelay().getDefiningOp<sim::SimTimeConstantOp>()
                : sim::SimTimeConstantOp{};
      periodic &= constant && constant.getValue() > 0;
    });
    return periodic;
  };

  // Waits of every planned member, which a deferred kernel resumes after.
  DenseSet<Operation *> memberWaits;
  for (auto &[key, members] : groups)
    for (Member &member : members)
      memberWaits.insert(member.wait->getTerminator());

  // The body blocks of the members on each edge of each clock class, with the
  // edge relative to the class (a complemented chain swaps posedge and
  // negedge). A member suspends only at its edge wait, so its body runs only
  // in time slots in which its clock has that edge (9.4.2). Also every clock
  // root of each class, and the roots its net copy chains update. Both are
  // collected before planning drops members that access their clock: such a
  // process still runs only on its edge.
  struct EdgeBodies {
    DenseSet<Block *> blocks;
    DenseSet<std::pair<StringAttr, uint32_t>> indices;
  };
  DenseMap<std::pair<uint64_t, unsigned>, EdgeBodies> edgeBodies;
  DenseMap<uint64_t, SmallVector<uint64_t>> classClockRoots;
  DenseMap<uint64_t, DenseSet<uint64_t>> classNetCopies;
  // The events of each multi-edge member, for the held-state proof's NBA
  // order. Copied, since planning later removes members from their groups.
  struct MultiEdgeEvents {
    SmallVector<uint64_t, 2> roots;
    SmallVector<sim::EdgeKind, 2> edges;
  };
  DenseMap<StringAttr, MultiEdgeEvents> multiEdgeMembers;
  // Across kernels, for held-state observers (planRoots): the functions a
  // kernel stores a root of some held cone for, and the writers a kernel's
  // proof relied on to execute after its members, keeping their NBAs. One
  // function in both would apply some NBA early that a proof assumed late.
  DenseSet<StringAttr> heldStorers, trailingWriters;
  for (auto &[key, members] : groups)
    for (const Member &member : members) {
      if (!member.eventSignature)
        continue;
      auto wait = cast<sim::SimSuspendAnyOp>(member.wait->getTerminator());
      MultiEdgeEvents &events =
          multiEdgeMembers[sim::SimFuncOp(member.function).getSymNameAttr()];
      events.roots.assign(member.eventRoots.begin(), member.eventRoots.end());
      events.edges.clear();
      for (int32_t edge : wait.getEdges())
        events.edges.push_back(static_cast<sim::EdgeKind>(edge));
    }
  for (auto &[key, members] : groups) {
    sim::EdgeKind edge = groupEdge(key);
    bool directed =
        edge == sim::EdgeKind::Posedge || edge == sim::EdgeKind::Negedge;
    for (Member &member : members) {
      if (directed) {
        EdgeBodies &bodies =
            edgeBodies[{key.first, static_cast<unsigned>(edge)}];
        DenseMap<Block *, uint32_t> position;
        for (auto [index, block] : llvm::enumerate(member.function.getBody()))
          position[&block] = index;
        for (Block *block : member.bodyBlocks) {
          bodies.blocks.insert(block);
          bodies.indices.insert(
              {member.function.getSymNameAttr(), position.lookup(block)});
        }
      }
      SmallVector<uint64_t> &roots = classClockRoots[key.first];
      roots.push_back(member.clock);
      llvm::append_range(roots, member.clockChain);
      for (uint64_t root : member.clockChain)
        if (root != member.origin)
          classNetCopies[key.first].insert(root);
    }
  }

  // Whether every root of a clock class changes at most once in each time
  // slot after time zero. Copies change exactly when their source does
  // (10.3.2, 23.3.3), so it suffices that the class sources have one writer in
  // later slots, a periodic process, which resumes only from positive delays
  // and so runs at most once per slot (4.4.2.3, 4.5), and that no activation
  // of it stores a source twice. A single change is a posedge, a negedge or
  // neither, never both (9.4.2, Table 9-2), so no later slot then has both
  // edges of the class.
  //
  // At time zero, when nothing but static initialization (which precedes
  // every process, 6.8) writes a class source, the sources and their variable
  // copies keep their values. A copy chain root (a net, or a variable a
  // continuous assignment drives) that starts at x or z, a 4-state net or an
  // uninitialized 4-state variable (6.6, 6.8, Table 6-7), then only moves
  // through x to its source's value or that value's complement (4.9.1,
  // 10.3.2; the complement of x or z is x, 11.4.8). Every edge of that slot
  // then has the direction of the source's value relative to the class, so
  // the time-zero slot also never has both edges. A root that starts at a
  // known value, such as a 2-state variable at 0, passes that stale value on:
  // a net it drives may move from z to it and then on to the final value.
  enum class SlotChanges { Any, OnceLater, Once };
  DenseMap<uint64_t, SlotChanges> slotChanges;
  unsigned slotProofDepth = 0;
  std::function<SlotChanges(uint64_t)> classSlotChanges =
      [&](uint64_t classRoot) -> SlotChanges {
    if (auto found = slotChanges.find(classRoot); found != slotChanges.end())
      return found->second;
    // Memoize a conservative answer while following copy sources. Cycles and
    // excessive capture depth cannot certify a new clock schedule.
    slotChanges[classRoot] = SlotChanges::Any;
    if (slotProofDepth == 128)
      return SlotChanges::Any;
    ++slotProofDepth;
    llvm::scope_exit restoreDepth([&] { --slotProofDepth; });
    bool quietAtZero = true;
    // Returns why the class may change twice in a later slot, or an empty
    // string.
    auto decide = [&]() -> StringRef {
      SmallVector<uint64_t> roots{classRoot};
      if (auto found = classMembers.find(classRoot);
          found != classMembers.end())
        llvm::append_range(roots, found->second);
      llvm::append_range(roots, classClockRoots.lookup(classRoot));
      static const DenseSet<uint64_t> noNetCopies;
      auto netCopiesFound = classNetCopies.find(classRoot);
      const DenseSet<uint64_t> &netCopies =
          netCopiesFound != classNetCopies.end() ? netCopiesFound->second
                                                 : noNetCopies;
      // A delayed NBA lands in a later slot whatever its writer's phases
      // (4.9.4).
      auto inLaterSlots = [&](const Writer &write) {
        return write.deferred ||
               phases.getPhases(write.function, write.block).later != 0;
      };
      auto atTimeZero = [&](const Writer &write) {
        return write.deferred ||
               phases.getPhases(write.function, write.block).zero != 0;
      };
      if (llvm::any_of(unknownWriters, inLaterSlots))
        return "unknown writer";
      quietAtZero = llvm::none_of(unknownWriters, atTimeZero);
      DenseSet<uint64_t> sources;
      StringAttr source;
      for (uint64_t root : roots) {
        if (phases.getCopies().count(root) || netCopies.contains(root))
          continue;
        sources.insert(root);
        for (const Writer &write : writers.lookup(root)) {
          if (write.function == rootInitializer.getSymNameAttr())
            continue;
          quietAtZero &= !atTimeZero(write);
          if (!inLaterSlots(write))
            continue;
          if (write.kind == schedule::ComputeEffectKind::NBA)
            return "nba writer";
          if (!isPeriodic(write.function)) {
            // A clock copied from a statically initialized source has an
            // extra startup evaluation, so it is not a value-sequence alias.
            // It still changes at most once per later slot when its source
            // has that certificate, and the source is quiet during startup.
            // Retain this copy and its original watched root.
            auto copy = phases.getClockCopies().find(root);
            if (copy == phases.getClockCopies().end() ||
                copy->second.process != write.function ||
                classSlotChanges(classes.find(copy->second.source)) !=
                    SlotChanges::Once)
              return "aperiodic writer";
          }
          if (source && source != write.function)
            return "second writer";
          source = write.function;
        }
      }
      for (uint64_t root : netCopies)
        quietAtZero &= root >= ActivationMemoryAnalysis::netRootTag
                           ? isa_and_nonnull<sim::LogicType>(rootType(root))
                           : initialLevel(root) == Unknown;
      if (!source)
        return {};
      // Blocks of the writer that store a source: each holds one blocking
      // store of a resolved source root and no other write.
      auto function = symbols.lookup<sim::SimFuncOp>(source);
      DenseSet<Block *> storing;
      for (Block &block : function.getBody()) {
        unsigned stores = 0;
        for (Operation &operation : block) {
          if (auto store = dyn_cast<sim::SimRefStoreOp>(&operation)) {
            std::optional<uint64_t> root =
                phases.getRoot(function, store.getReference());
            if (!root)
              return "unresolved store";
            stores += sources.contains(*root);
            continue;
          }
          if (isSuspension(&operation) || isMemoryEffectFree(&operation))
            continue;
          auto effects = dyn_cast<MemoryEffectOpInterface>(&operation);
          if (!effects || effects.hasEffect<MemoryEffects::Write>() ||
              effects.hasEffect<MemoryEffects::Allocate>() ||
              effects.hasEffect<MemoryEffects::Free>())
            return "writer effect";
        }
        if (stores > 1)
          return "two stores";
        if (stores)
          storing.insert(&block);
      }
      // No activation reaches a second store: an activation continues only
      // over plain terminators (a periodic writer makes no task calls).
      using Transfer = analysis::ActivationPhaseAnalysis::BlockInfo::Transfer;
      for (Block *start : storing) {
        SmallVector<Block *> pending;
        DenseSet<Block *> visited;
        auto follow = [&](Block *block) {
          const auto *info = phases.getBlockInfo(block);
          if (!info)
            return false;
          if (info->transfer != Transfer::Plain)
            return true;
          llvm::append_range(pending, info->successors);
          return true;
        };
        if (!follow(start))
          return "unsummarized block";
        while (!pending.empty()) {
          Block *block = pending.pop_back_val();
          if (storing.contains(block))
            return "two stores";
          if (visited.insert(block).second && !follow(block))
            return "unsummarized block";
        }
      }
      return {};
    };
    StringRef blocker = decide();
    SlotChanges result = !blocker.empty() ? SlotChanges::Any
                         : quietAtZero    ? SlotChanges::Once
                                          : SlotChanges::OnceLater;
    if (report)
      llvm::errs() << "talos clocked kernel class " << classRoot << ": "
                   << (result == SlotChanges::Once ? "once per slot"
                       : result == SlotChanges::OnceLater
                           ? "once per later slot"
                           : blocker)
                   << '\n';
    slotChanges[classRoot] = result;
    return result;
  };

  // 3. Plan every kernel on the unmodified design: the analyses above
  // describe the original processes and graph, which materialization erases.
  struct Plan {
    GroupKey key;
    std::vector<Member> *members;
    DenseSet<uint64_t> eligibleRoots;
    bool deferred = false;
    SmallVector<unsigned> sequence;
    unsigned waitMember = 0;
    SmallVector<Value> operands;
    SmallVector<Type> inputTypes;
    SmallVector<DictionaryAttr> argumentAttrs;
    sim::SimSpawnOp insertionSpawn;
  };
  std::vector<Plan> plans;
  // Deferral takes a whole-design analysis per kernel, and only a large kernel
  // repays it with more direct stores. A design with a clock class per instance
  // would otherwise make this pass quadratic.
  constexpr size_t maximumDeferralAnalyses = 16;
  SmallVector<const std::vector<Member> *> largestGroups;
  for (auto &[key, members] : groups)
    largestGroups.push_back(&members);
  llvm::stable_sort(largestGroups, [](const auto *lhs, const auto *rhs) {
    return lhs->size() > rhs->size();
  });
  if (largestGroups.size() > maximumDeferralAnalyses)
    largestGroups.truncate(maximumDeferralAnalyses);
  DenseSet<const std::vector<Member> *> deferrable(largestGroups.begin(),
                                                   largestGroups.end());
  for (auto &[key, members] : groups) {
    uint64_t classRoot = key.first;
    bool multiEvent = bool(members.front().eventSignature);
    // A member that accesses any root of its clock class could observe a
    // copy that has not run yet when the kernel starts. It stays a process of
    // its own, which the root planning below treats like any non-member.
    {
      DenseSet<uint64_t> aliasRoots{classRoot};
      if (auto found = classMembers.find(classRoot);
          found != classMembers.end())
        aliasRoots.insert(found->second.begin(), found->second.end());
      for (const Member &member : members) {
        aliasRoots.insert(member.clock);
        aliasRoots.insert(member.clockChain.begin(), member.clockChain.end());
      }
      DenseSet<uint64_t> triggerRoots(aliasRoots);
      for (const Member &member : members)
        for (uint64_t root : member.eventRoots) {
          uint64_t origin = classes.find(root);
          triggerRoots.insert(root);
          triggerRoots.insert(origin);
          if (auto found = classMembers.find(origin);
              found != classMembers.end())
            triggerRoots.insert(found->second.begin(), found->second.end());
        }
      auto isAlias = [&](uint64_t root) { return aliasRoots.contains(root); };
      // A member that only reads its own watched clock can join: in the
      // reference algorithm it runs after that copy's update event, when the
      // copy equals the class source (23.3.3, 4.9.1), and the source is
      // current whenever the kernel runs because every copy wakes on it. The
      // kernel therefore redirects those reads to the source root (below).
      // Writes, reads of other aliases, complemented chains, opaque reads and
      // a source of another type keep the member a process of its own.
      auto source = [&](uint64_t root) {
        const auto &copies = phases.getCopies();
        for (auto copy = copies.find(root); copy != copies.end();
             copy = copies.find(root))
          root = copy->second.source;
        return root;
      };
      auto clockAccess = [&](StringRef detail) {
        ++rejections["member accesses its clock"];
        if (report)
          ++rejections[("member accesses its clock: " + detail).str()];
        return true;
      };
      llvm::erase_if(members, [&](Member &member) {
        auto isTrigger = [&](uint64_t root) {
          return triggerRoots.contains(root);
        };
        if (llvm::any_of(member.writes, isTrigger) ||
            llvm::any_of(member.nbaWrites, isTrigger))
          return clockAccess("write");
        if (llvm::none_of(member.reads, isAlias))
          return false;
        if (llvm::any_of(member.reads, [&](uint64_t root) {
              return root != member.clock && isAlias(root);
            }))
          return clockAccess("read of another alias");
        if (member.opaqueClockRead)
          return clockAccess("opaque read");
        if (member.clockReads.empty())
          return clockAccess("no whole-root read");
        if (member.inverted)
          return clockAccess("complemented chain");
        // A copy is its source or, for a 2-state source feeding a 4-state
        // port, its exact widening (23.3.3; `logic.from_bits` maps 0/1 only).
        Type type = rootType(source(member.origin));
        if (!type || llvm::any_of(member.clockReads, [&](Operation *read) {
              Type produced = read->getResult(0).getType();
              return produced != type &&
                     !(type.isInteger(1) && isClockBit(produced) &&
                       !isa<IntegerType>(produced));
            }))
          return clockAccess("source type");
        member.redirectClockReads = true;
        return false;
      });
      if (members.empty())
        continue;
    }
    DenseSet<StringAttr> memberNames;
    DenseSet<Operation *> memberFunctions;
    for (Member &member : members) {
      memberNames.insert(member.function.getSymNameAttr());
      memberFunctions.insert(member.function);
    }

    SmallVector<uint64_t> clockRoots{classRoot};
    if (auto found = classMembers.find(classRoot); found != classMembers.end())
      llvm::append_range(clockRoots, found->second);
    // Roots a net clock copy chain updates after its origin. They follow
    // their source; their own writers are the exclusive copies.
    DenseSet<uint64_t> netCopies;
    for (Member &member : members) {
      clockRoots.push_back(member.clock);
      llvm::append_range(clockRoots, member.clockChain);
      for (uint64_t root : member.eventRoots) {
        uint64_t origin = classes.find(root);
        clockRoots.push_back(root);
        clockRoots.push_back(origin);
        if (auto found = classMembers.find(origin); found != classMembers.end())
          llvm::append_range(clockRoots, found->second);
      }
      for (uint64_t root : member.clockChain)
        if (root != member.origin)
          netCopies.insert(root);
    }
    llvm::sort(clockRoots);
    clockRoots.erase(std::unique(clockRoots.begin(), clockRoots.end()),
                     clockRoots.end());
    // The phases in which this kernel's clock edges occur. Every alias in the
    // class changes in exactly the phases of the class root. A net copy can
    // additionally update at its own time-zero evaluation (4.9.1).
    Phases kernelPhases = phases.getChangePhases(classRoot);
    if (multiEvent)
      for (uint64_t root : clockRoots)
        kernelPhases = kernelPhases | phases.getChangePhases(root);
    if (!netCopies.empty()) {
      // Net copies are edge-equivalent only while each root changes at most
      // once per phase. A source that also changes at time zero can change a
      // copy twice in the phase of that evaluation (z, then its initial value,
      // then the new one), and a later copy, evaluated after both updates
      // (10.3.2, 4.7), may never see the middle value.
      PhaseSet sourceAtZero = 0;
      for (uint64_t root : clockRoots)
        if (!netCopies.contains(root))
          sourceAtZero |= phases.getChangePhases(root).zero;
      if (sourceAtZero) {
        reject("net clock source changes at time zero");
        continue;
      }
      for (uint64_t root : clockRoots)
        kernelPhases = kernelPhases | phases.getChangePhases(root);
    }
    // The opposite-edge members of a class that changes at most once per
    // later slot never run in a later slot of this kernel, nor at time zero
    // when the class changes once in that slot too.
    const EdgeBodies *otherSlot = nullptr;
    bool otherSlotAtZero = false;
    sim::EdgeKind kernelEdge = groupEdge(key);
    SlotChanges changes = SlotChanges::Any;
    if (kernelEdge == sim::EdgeKind::Posedge ||
        kernelEdge == sim::EdgeKind::Negedge)
      changes = classSlotChanges(classRoot);
    if (changes != SlotChanges::Any) {
      otherSlotAtZero = changes == SlotChanges::Once;
      auto opposite = kernelEdge == sim::EdgeKind::Posedge
                          ? sim::EdgeKind::Negedge
                          : sim::EdgeKind::Posedge;
      if (auto found =
              edgeBodies.find({classRoot, static_cast<unsigned>(opposite)});
          found != edgeBodies.end())
        otherSlot = &found->second;
    }
    auto meetsPhases = [&](StringAttr function, uint32_t blockIndex,
                           Phases kernel) {
      Phases at = phases.getPhases(function, blockIndex);
      if (otherSlot && otherSlot->indices.contains({function, blockIndex})) {
        at.later = 0;
        if (otherSlotAtZero)
          at.zero = 0;
      }
      return at.meets(kernel);
    };
    auto meetsKernel = [&](StringAttr function, uint32_t blockIndex) {
      return meetsPhases(function, blockIndex, kernelPhases);
    };
    // The kernel's phases without time zero when its edge cannot occur then.
    // Change phases do not tell edges apart. If every time-zero write of the
    // class root (outside its declaration initializer) stores the same known
    // level the edge cannot end at, the root moves at most once, to that
    // level, and a posedge needs a final 1, x or z, a negedge a final 0, x or
    // z (Table 9-2). Writes inside calls, delayed NBAs, other writing
    // operations and unresolved targets keep time zero.
    Phases edgeKernelPhases = kernelPhases;
    if (kernelPhases.zero && !multiEvent && netCopies.empty() &&
        classRoot < ActivationMemoryAnalysis::netRootTag &&
        (kernelEdge == sim::EdgeKind::Posedge ||
         kernelEdge == sim::EdgeKind::Negedge) &&
        llvm::none_of(
            unknownWriters,
            [&](const Writer &write) {
              return phases.getPhases(write.function, write.block).zero != 0;
            })) {
      bool rising = kernelEdge == sim::EdgeKind::Posedge;
      DenseSet<StringAttr> scanned;
      bool quiet = true;
      for (const Writer &write : writers.lookup(classRoot)) {
        if (!quiet)
          break;
        if (write.function == rootInitializer.getSymNameAttr() ||
            !phases.getPhases(write.function, write.block).zero ||
            !scanned.insert(write.function).second)
          continue;
        auto function = symbols.lookup<sim::SimFuncOp>(write.function);
        if (!function) {
          quiet = false;
          break;
        }
        for (Block &block : function.getBody()) {
          if (!quiet || !phases.getPhases(&block).zero)
            continue;
          for (Operation &operation : block) {
            Value target, value;
            if (auto store = dyn_cast<sim::SimRefStoreOp>(&operation)) {
              target = store.getReference();
              value = store.getValue();
            } else if (auto enqueue =
                           dyn_cast<sim::SimNBAEnqueueOp>(&operation)) {
              target = enqueue.getDestination();
              value = enqueue.getDelay() ? Value() : enqueue.getValue();
            } else {
              // Any other write may be one of the class root, and so may a
              // task or process-control operation.
              if (isa<sim::SimTaskCallOp, sim::SimClassVirtualTaskCallOp,
                      sim::SimProcessControlOp, sim::SimControlBoundaryOp>(
                      operation)) {
                quiet = false;
                continue;
              }
              if (isSuspension(&operation) || isMemoryEffectFree(&operation))
                continue;
              auto effects = dyn_cast<MemoryEffectOpInterface>(&operation);
              if (!effects || effects.hasEffect<MemoryEffects::Write>() ||
                  isa<CallOpInterface, sim::SimSpawnOp>(operation))
                quiet = false;
              continue;
            }
            std::optional<uint64_t> root = phases.getRoot(function, target);
            if (!root) {
              quiet = false;
              break;
            }
            if (*root != classRoot)
              continue;
            auto level = value ? value.getDefiningOp<sim::SimLogicConstantOp>()
                               : sim::SimLogicConstantOp();
            if (!level || level.getValue().getBitWidth() != 1 ||
                !level.getUnknown().isZero() ||
                level.getValue().isOne() == rising) {
              quiet = false;
              break;
            }
          }
        }
      }
      if (quiet)
        edgeKernelPhases.zero = 0;
    }

    // The kernel must run at most once between NBA regions. A second run in
    // the same phase would read its own direct stores, where its NBAs would
    // still be pending (4.9.4).
    //
    // Immediate kernels run as soon as an edge wakes them (4.7). A process
    // waiting on an event is scheduled once when it occurs (4.5, 9.4.2), so
    // each phase may see clock changes from at most one atomic source:
    //   - the NBA region before it. Its updates, delayed ones included, are
    //     all processed before the evaluations they cause (4.5, 10.4.2);
    //   - one activation of a periodic process, which suspends only on
    //     positive constant delays and so runs at most once per slot
    //     (9.4.1). A resumable named-block exit (9.6.2) or a process-control
    //     operation (9.7) is a suspension too, so `disable` and handles from
    //     other processes cannot restart such a process within a slot.
    // Copies follow their source (23.3.3). A net copy's time-zero evaluation
    // (4.9.1) moves it once from z to its source's value, and later updates
    // track single source changes, so a phase still sees at most one edge of
    // each direction on every root of the class.
    // A multi-edge control can be triggered by independent Active events.
    // Keep its complete wait and defer the kernel until those events have
    // drained; the window proof below protects every watched input.
    bool singleClockSource = !multiEvent && [&] {
      DenseMap<std::pair<unsigned, unsigned>, StringAttr> sources;
      for (uint64_t root : clockRoots) {
        if (phases.getCopies().count(root) || netCopies.contains(root))
          continue;
        for (const Writer &write : writers.lookup(root)) {
          if (write.function == rootInitializer.getSymNameAttr())
            continue;
          if (write.kind == schedule::ComputeEffectKind::NBA)
            continue;
          if (!isPeriodic(write.function)) {
            auto copy = phases.getClockCopies().find(root);
            if (copy == phases.getClockCopies().end() ||
                copy->second.process != write.function ||
                classSlotChanges(classes.find(copy->second.source)) !=
                    SlotChanges::Once)
              return false;
          }
          Phases at = phases.getPhases(write.function, write.block);
          for (auto [slot, set] : {std::pair{0u, at.zero}, {1u, at.later}})
            for (unsigned bit = 0; bit != 32; ++bit)
              if (set & (PhaseSet{1} << bit)) {
                auto [found, inserted] =
                    sources.try_emplace({slot, bit}, write.function);
                if (!inserted && found->second != write.function)
                  return false;
              }
        }
      }
      return llvm::none_of(unknownWriters, [&](const Writer &write) {
        return write.kind != schedule::ComputeEffectKind::NBA &&
               meetsKernel(write.function, write.block);
      });
    }();

    // A deferred kernel resumes in the Inactive region, after every Active
    // event of its pass (4.4.2.3, 4.5). The original could run its members
    // last in that pass (4.7). Then only what its own updates wake, other
    // kernels, and other Inactive events of its phase with what they wake can
    // run after it. The window analysis covers the whole design, so it runs
    // only when deferral could store more roots (see below).
    PostKernelAnalysis::Config windowConfig{design.getOperation(),
                                            phases,
                                            kernelPhases,
                                            rootInitializer,
                                            memberFunctions,
                                            {},
                                            {}};
    if (otherSlot) {
      windowConfig.otherSlotBlocks = &otherSlot->blocks;
      windowConfig.otherSlotAtZero = otherSlotAtZero;
    }
    DataFlowSolver window(DataFlowConfig().setInterprocedural(false));
    auto isAfter = [&](StringAttr name, uint32_t index) {
      auto function = symbols.lookup<sim::SimFuncOp>(name);
      Block *block = function ? blockAt(function, index) : nullptr;
      if (!block)
        return true;
      return PostKernelAnalysis::isAfter(window, block);
    };
    auto changedIn = [&](DataFlowSolver &solver, uint64_t root) {
      for (uint64_t key : {root, AfterRoot::anyRoot}) {
        const auto *state =
            solver.lookupState<AfterState>(solver.getLatticeAnchor<AfterRoot>(
                std::make_pair(key, design.getOperation())));
        if (state && state->after)
          return true;
      }
      return false;
    };
    auto changedAfter = [&](uint64_t root) { return changedIn(window, root); };
    // Returns why this kernel cannot be deferred, or an empty string.
    auto analyzeDeferral = [&, &members = members]() -> StringRef {
      // An Inactive event of the phase (a zero or variable delay) and what it
      // wakes run in a later iteration than the original members, so they
      // may run before the deferred kernel only if it reads nothing they
      // write. The window below places them after it as well, which covers
      // their accesses, writers and finishes.
      bool inactiveShared = false;
      for (auto &[block, info] : phases.getBlockInfos()) {
        using Transfer = analysis::ActivationPhaseAnalysis::BlockInfo::Transfer;
        if ((info.transfer != Transfer::Zero &&
             info.transfer != Transfer::Variable) ||
            memberFunctions.contains(block->getParentOp()))
          continue;
        auto delay = cast<sim::SimSuspendDelayOp>(info.terminator);
        inactiveShared |=
            phases.getPhases(delay.getContinuation()).meets(kernelPhases);
      }
      if (inactiveShared) {
        if (llvm::any_of(members, [](const Member &member) {
              return member.unresolvedRead;
            }))
          return "inactive event writes kernel input";
        // Without kernel updates, the window holds exactly what Inactive
        // events start or wake in the phase, plus what it cannot model.
        PostKernelAnalysis::Config inactiveConfig{design.getOperation(),
                                                  phases,
                                                  kernelPhases,
                                                  rootInitializer,
                                                  memberFunctions,
                                                  {},
                                                  {}};
        if (otherSlot) {
          inactiveConfig.otherSlotBlocks = &otherSlot->blocks;
          inactiveConfig.otherSlotAtZero = otherSlotAtZero;
        }
        DataFlowSolver inactive(DataFlowConfig().setInterprocedural(false));
        inactive.load<PostKernelAnalysis>(inactiveConfig);
        if (failed(inactive.initializeAndRun(design)))
          return "post-kernel analysis";
        for (const Member &member : members)
          if (llvm::any_of(member.reads, [&](uint64_t root) {
                return changedIn(inactive, root);
              }))
            return "inactive event writes kernel input";
      }
      for (Operation *wait : memberWaits)
        if (!memberFunctions.contains(wait->getParentOfType<sim::SimFuncOp>()))
          windowConfig.otherKernelWaits.insert(wait);
      for (Member &member : members) {
        llvm::append_range(windowConfig.changed, member.writes);
        for (uint64_t root : member.nbaWrites)
          if (glitchInsensitive.contains(root))
            windowConfig.changed.push_back(root);
        if (member.unresolvedUpdate)
          windowConfig.changed.push_back(AfterRoot::anyRoot);
      }
      window.load<PostKernelAnalysis>(windowConfig);
      if (failed(window.initializeAndRun(design)))
        return "post-kernel analysis";
      // A clock change after a deferred kernel would run it again.
      if (llvm::any_of(clockRoots, changedAfter))
        return "clock changes after kernel";
      return {};
    };

    // The roots one kernel mode may store directly. `mayFollow` holds for
    // every activation that may run between the kernel and its NBA region.
    enum class Mode { Immediate, Deferred };
    auto planRoots = [&, &members = members](Mode mode,
                                             llvm::StringMap<uint64_t> &reasons,
                                             DenseSet<StringAttr> &trailing)
        -> std::optional<DenseSet<uint64_t>> {
      auto refuse = [&](StringRef reason) { ++reasons[reason]; };
      bool deferred = mode == Mode::Deferred;
      auto mayFollow = [&](StringAttr function, uint32_t block) {
        return deferred ? isAfter(function, block)
                        : meetsKernel(function, block);
      };
      // (d) Accesses by activations that may follow the kernel.
      SmallVector<uint64_t> seeds(clockRoots);
      for (Attribute attribute : nodes) {
        auto fragment = dyn_cast<schedule::ComputeFragmentAttr>(attribute);
        if (!fragment)
          continue;
        StringAttr name = fragment.getFunction().getAttr();
        if (memberNames.contains(name) ||
            name == rootInitializer.getSymNameAttr())
          continue;
        if (auto function = symbols.lookup<sim::SimFuncOp>(name))
          if (function.getEntryKind() == sim::EntryKind::Final)
            continue;
        if (!mayFollow(name, fragment.getBlock()) || isTransparent(name))
          continue;
        for (auto effect :
             fragment.getEffects().getAsRange<schedule::ComputeEffectAttr>()) {
          if (!isAccess(effect.getEffect()) ||
              effect.getTarget() == schedule::ComputeTargetKind::Local)
            continue;
          std::optional<SmallVector<uint64_t>> roots =
              effectRoots(name, effect);
          if (!roots) {
            refuse("unknown event access");
            return std::nullopt;
          }
          llvm::append_range(seeds, *roots);
        }
      }
      // An activation that may follow the kernel and end the simulation lets
      // final procedures read a direct store before its NBA would apply.
      // Members cannot end it: body fusion admits no finish, fatal or stop.
      if (llvm::any_of(endingFragments, [&](const auto &fragment) {
            return !memberNames.contains(fragment.first) &&
                   fragment.first != rootInitializer.getSymNameAttr() &&
                   mayFollow(fragment.first, fragment.second);
          })) {
        if (unknownFinalRead) {
          refuse("unknown final procedure access");
          return std::nullopt;
        }
        llvm::append_range(seeds, finalReads);
      }
      // A root is exposed when anything in its combinational cone is accessed
      // by such an activation, or feeds this kernel's clock.
      DataFlowSolver exposure;
      exposure.load<ConeAnalysis>(design.getOperation(), exposureProcesses,
                                  seeds, ConeAnalysis::Direction::Sources);
      if (failed(exposure.initializeAndRun(design))) {
        refuse("exposure analysis");
        return std::nullopt;
      }
      auto isExposed = [&](uint64_t root) {
        return ConeAnalysis::contains(exposure, design.getOperation(), root);
      };
      // (b) Another NBA of the root that lands in the same NBA region would
      // now be applied after the store instead of before it (4.6(b)); a
      // delayed one may land in any region. A blocking write that may follow
      // the kernel would be overwritten by the NBA but not by the store.
      auto conflicts = [&](const Writer &write) {
        if (write.kind == schedule::ComputeEffectKind::NBA)
          return write.deferred || meetsKernel(write.function, write.block);
        return mayFollow(write.function, write.block);
      };
      DenseSet<uint64_t> eligible;
      // Roots only held-state observers see, decided after the others.
      SmallVector<uint64_t> heldPending;
      for (Member &member : members)
        for (uint64_t root : member.nbaWrites) {
          if (eligible.contains(root))
            continue;
          if (root >= ActivationMemoryAnalysis::netRootTag) {
            refuse("root net");
            continue;
          }
          // Nothing reads the root: unread-NBA elimination removes the update
          // entirely (4.3), which is better than a store.
          if (!unknownRead && !readRoots.contains(root)) {
            refuse("root unread");
            continue;
          }
          if (!glitchInsensitive.contains(root)) {
            if (!heldInsensitive.contains(root) ||
                !heldObserversOf.count(root)) {
              refuse("root observed");
              if (report)
                ++observedRootsBy[combinational.getGlitchObserver(root)];
              continue;
            }
            heldPending.push_back(root);
          } else if (heldObserversOf.count(root)) {
            // Insensitive for its watchers, but a held-state observer reads
            // it: storing it early is visible to that observer whenever
            // another input wakes it before this NBA would apply.
            heldPending.push_back(root);
          }
          // An earlier kernel's proof keeps this member's NBAs late.
          if (heldObserversOf.count(root) &&
              llvm::any_of(writers.lookup(root), [&](const Writer &write) {
                return write.kind == schedule::ComputeEffectKind::NBA &&
                       memberNames.contains(write.function) &&
                       trailingWriters.contains(write.function);
              })) {
            refuse("root held-state observer");
            continue;
          }
          if (isExposed(root)) {
            refuse("root accessed by event activation");
            continue;
          }
          bool writersOk = true;
          for (const Writer &write : writers.lookup(root)) {
            if (write.function == rootInitializer.getSymNameAttr())
              continue;
            if (memberNames.contains(write.function))
              writersOk &= write.kind == schedule::ComputeEffectKind::NBA;
            else
              writersOk &= !conflicts(write);
          }
          writersOk &= llvm::none_of(unknownWriters, conflicts);
          if (!writersOk) {
            refuse("root writers");
            continue;
          }
          eligible.insert(root);
        }

      // A held-state observer sees the direct stores as one legal NBA region
      // when nothing else changes its cone in the kernel's slot (4.4, 4.7,
      // 10.4.2). In the reference, the members' NBAs are all pending until
      // the NBA region, which may apply every one of them before any
      // evaluation they cause (4.5, 4.6(b)). Moving them into the kernel's
      // Active phase instead lets the observer evaluate once on those same
      // values, unless something else changes its cone in that phase, or lands
      // in the same NBA region in an order the members cannot precede. Then a
      // reference evaluation the observer must make on old values could be
      // lost, and with it what it holds, e.g. under an X/Z case selector
      // (12.5). So no clock of the kernel may feed the cone, and every write
      // to a cone root that can land with the kernel must be one of:
      //   - the root initializer, before any slot;
      //   - a transparent or held-state process, which changes only when
      //     its inputs do (the cone includes the inputs of those it reaches);
      //   - an immediate NBA of a member, stored directly together with that
      //     member's other NBAs into the cone;
      //   - an NBA a body of this clock edge executes in the kernel's phase.
      // Activations that read the observer's outputs see its inputs early, so
      // exposure follows held-state observers too.
      // No held-state observer of the cone may evaluate in the kernel's
      // phases, including its time-zero startup (9.2.2.2.2). A refused root
      // can refuse its member's other roots in turn, to a fixpoint.
      if (!heldPending.empty()) {
        DenseSet<uint64_t> clocks(clockRoots.begin(), clockRoots.end());
        // Whether `function`, an edge-triggered member or a writer that runs
        // in these phases only after this edge, may execute after every
        // member with the same effects (4.7): there it writes only by NBA and
        // reads no root anything writes otherwise there. Its own trigger has
        // already occurred, so its waits do not matter. Without this, a
        // blocking write it reads, or one it makes that a member reads, can
        // force it before a member, as the kernel's own order and values do.
        bool unknownBlocking =
            llvm::any_of(unknownWriters, [&](const Writer &w) {
              return w.kind != schedule::ComputeEffectKind::NBA &&
                     meetsPhases(w.function, w.block, edgeKernelPhases);
            });
        DenseMap<uint64_t, bool> blockingWritten;
        auto writtenInPhase = [&](uint64_t root) {
          auto [found, inserted] = blockingWritten.try_emplace(root, false);
          if (inserted)
            found->second =
                llvm::any_of(writers.lookup(root), [&](const Writer &w) {
                  return w.kind != schedule::ComputeEffectKind::NBA &&
                         w.function != rootInitializer.getSymNameAttr() &&
                         meetsPhases(w.function, w.block, edgeKernelPhases);
                });
          return found->second;
        };
        DenseMap<StringAttr, bool> commuting;
        auto commutes = [&](StringAttr function) {
          if (auto found = commuting.find(function); found != commuting.end())
            return found->second;
          bool result = !unknownBlocking;
          for (schedule::ComputeFragmentAttr fragment :
               fragmentsOf.lookup(function)) {
            if (!result)
              break;
            if (!meetsPhases(function, fragment.getBlock(), edgeKernelPhases))
              continue;
            for (auto effect : fragment.getEffects()
                                   .getAsRange<schedule::ComputeEffectAttr>()) {
              auto kind = effect.getEffect();
              if (effect.getTarget() == schedule::ComputeTargetKind::Local ||
                  kind == schedule::ComputeEffectKind::NBA ||
                  kind == schedule::ComputeEffectKind::Watch)
                continue;
              if (kind != schedule::ComputeEffectKind::Read) {
                result = false;
                break;
              }
              std::optional<SmallVector<uint64_t>> roots =
                  effectRoots(function, effect);
              if (!roots || llvm::any_of(*roots, writtenInPhase)) {
                result = false;
                break;
              }
            }
          }
          commuting[function] = result;
          return result;
        };
        // Whether no other process enqueues an NBA to a root `function` does
        // in the kernel's phases. Moving `function` after the members then
        // reorders no NBAs of one variable (4.6(b)).
        DenseMap<StringAttr, bool> owning;
        auto ownsItsNBAs = [&](StringAttr function) {
          if (auto found = owning.find(function); found != owning.end())
            return found->second;
          auto otherNBA = [&](const Writer &w) {
            return w.function != function &&
                   w.kind == schedule::ComputeEffectKind::NBA &&
                   (w.deferred ||
                    meetsPhases(w.function, w.block, edgeKernelPhases));
          };
          bool result = llvm::none_of(unknownWriters, otherNBA);
          for (schedule::ComputeFragmentAttr fragment :
               fragmentsOf.lookup(function)) {
            for (auto effect : fragment.getEffects()
                                   .getAsRange<schedule::ComputeEffectAttr>()) {
              if (!result)
                break;
              if (effect.getTarget() == schedule::ComputeTargetKind::Local ||
                  effect.getEffect() != schedule::ComputeEffectKind::NBA)
                continue;
              std::optional<SmallVector<uint64_t>> roots =
                  effectRoots(function, effect);
              result = roots && llvm::none_of(*roots, [&](uint64_t root) {
                         return llvm::any_of(writers.lookup(root), otherNBA);
                       });
            }
          }
          owning[function] = result;
          return result;
        };
        // A blocking write in the kernel's phase, or an NBA landing in it,
        // changes the cone where the observer must still see the members' old
        // values. An NBA executed in the kernel's phase lands in the members'
        // NBA region, performed in execution order (4.6(b)): one executed
        // before the members' edge, by the process causing it or before a
        // later edge in the phase, applies first, and the observer could
        // never see the members' new values with its old one. Only a process
        // that runs in these phases solely after this clock edge (9.4.2), as
        // the members do and in any order with them (4.7), may also follow
        // them: a body of this edge, or a multi-edge member whose other
        // events never occur in the kernel's phases. A storage root in the
        // class is an exact copy of it, so its edges are the class's. The same
        // root's NBA order is check (b)'s.
        const EdgeBodies *sameEdge = nullptr;
        bool directed = kernelEdge == sim::EdgeKind::Posedge ||
                        kernelEdge == sim::EdgeKind::Negedge;
        if (directed)
          if (auto found = edgeBodies.find(
                  {classRoot, static_cast<unsigned>(kernelEdge)});
              found != edgeBodies.end())
            sameEdge = &found->second;
        auto afterEdgeOnly = [&](const Writer &write) {
          if (sameEdge &&
              sameEdge->indices.contains({write.function, write.block}))
            return true;
          auto found = multiEdgeMembers.find(write.function);
          if (!directed || found == multiEdgeMembers.end() ||
              found->second.roots.size() != found->second.edges.size())
            return false;
          bool thisEdge = false;
          for (auto [root, edge] :
               llvm::zip_equal(found->second.roots, found->second.edges)) {
            if (root < ActivationMemoryAnalysis::netRootTag &&
                classes.find(root) == classRoot && edge == kernelEdge) {
              thisEdge = true;
              continue;
            }
            if (phases.getChangePhases(root).meets(edgeKernelPhases))
              return false;
          }
          return thisEdge;
        };
        // A writer another kernel stores a held-cone root for applies some
        // NBA early, so it cannot trail; one that trails is recorded, so that
        // its own kernel keeps those NBAs.
        auto landsWithKernel = [&](const Writer &write,
                                   DenseSet<StringAttr> *trailed = nullptr) {
          if (write.kind != schedule::ComputeEffectKind::NBA)
            return meetsPhases(write.function, write.block, edgeKernelPhases);
          if (write.deferred ||
              analysis::ActivationPhaseAnalysis::afterNBA(
                  phases.getPhases(write.function, write.block))
                  .meets(edgeKernelPhases))
            return true;
          if (!meetsPhases(write.function, write.block, edgeKernelPhases))
            return false;
          if (heldStorers.contains(write.function) || !afterEdgeOnly(write) ||
              !commutes(write.function) || !ownsItsNBAs(write.function))
            return true;
          if (trailed)
            trailed->insert(write.function);
          return false;
        };
        auto memberNBA = [&](const Writer &write) {
          return write.kind == schedule::ComputeEffectKind::NBA &&
                 !write.deferred && memberNames.contains(write.function);
        };
        bool unknownLands =
            llvm::any_of(unknownWriters, [&](const Writer &write) {
              return landsWithKernel(write);
            });
        DenseMap<StringAttr, bool> quiet;
        DenseMap<StringAttr, DenseSet<StringAttr>> trailedBy;
        auto isQuiet = [&](StringAttr held) {
          if (auto found = quiet.find(held); found != quiet.end())
            return found->second;
          auto cone = heldCones.find(held);
          bool result =
              cone != heldCones.end() && !unknownLands &&
              llvm::none_of(
                  cone->second.observers,
                  [&](StringAttr observer) {
                    return llvm::any_of(
                        heldBlocks.lookup(observer), [&](uint32_t block) {
                          return meetsPhases(observer, block, edgeKernelPhases);
                        });
                  }) &&
              llvm::none_of(cone->second.roots, [&](uint64_t root) {
                return clocks.contains(root) ||
                       llvm::any_of(
                           writers.lookup(root), [&](const Writer &write) {
                             return write.function !=
                                        rootInitializer.getSymNameAttr() &&
                                    !isTransparent(write.function) &&
                                    !heldBlocks.count(write.function) &&
                                    !memberNBA(write) &&
                                    landsWithKernel(write, &trailedBy[held]);
                           });
              });
          quiet[held] = result;
          return result;
        };
        // One reference order serves every observer: the kernel's order,
        // with every member keeping an NBA into a held-state observer's cone
        // moved after the members storing a root of such a cone. One process
        // executes its NBAs in statement order (4.6(a)) and they apply in that
        // order (4.6(b)), so no member may do both. A keeper must commute with
        // the phase and own its NBA roots, so that moving it after the others
        // changes neither its effects nor the order of any variable's NBAs.
        // Refusing a root can make its member a keeper, so iterate to a
        // fixpoint.
        for (bool changed = true; changed;) {
          changed = false;
          DenseSet<StringAttr> storers;
          for (auto &[root, list] : heldObserversOf)
            if (eligible.contains(root))
              for (const Writer &write : writers.lookup(root))
                if (memberNBA(write))
                  storers.insert(write.function);
          auto trails = [&](const Writer &kept) {
            return !memberNBA(kept) ||
                   (!storers.contains(kept.function) &&
                    commutes(kept.function) && ownsItsNBAs(kept.function));
          };
          for (uint64_t root : heldPending) {
            if (!eligible.contains(root))
              continue;
            for (StringAttr held : heldObserversOf.lookup(root)) {
              if (isQuiet(held) &&
                  llvm::all_of(
                      heldCones.find(held)->second.roots, [&](uint64_t other) {
                        return eligible.contains(other) ||
                               llvm::all_of(writers.lookup(other), trails);
                      }))
                continue;
              eligible.erase(root);
              refuse("root held-state observer");
              if (report)
                ++observedRootsBy[held];
              changed = true;
              break;
            }
          }
        }
        for (uint64_t root : heldPending)
          if (eligible.contains(root))
            for (StringAttr held : heldObserversOf.lookup(root))
              for (StringAttr writer : trailedBy.lookup(held))
                trailing.insert(writer);
      }

      return eligible;
    };

    // Prefer the immediate kernel, which needs no extra Inactive pass, unless
    // deferral stores more roots directly. Deferral only changes which
    // activations may follow the kernel, so it can add only roots the
    // immediate kernel refuses for them ((b), (d)), or rescue a clock that
    // could run an immediate kernel twice per phase.
    llvm::StringMap<uint64_t> immediateReasons, deferredReasons;
    DenseSet<StringAttr> immediateTrailing, deferredTrailing;
    std::optional<DenseSet<uint64_t>> immediate, deferred;
    if (singleClockSource)
      immediate =
          planRoots(Mode::Immediate, immediateReasons, immediateTrailing);
    if (defer && deferrable.contains(&members) &&
        (!immediate ||
         immediateReasons.count("root accessed by event activation") ||
         immediateReasons.count("root writers"))) {
      if (StringRef blocker = analyzeDeferral(); !blocker.empty())
        reject(("deferral: " + blocker).str());
      else
        deferred = planRoots(Mode::Deferred, deferredReasons, deferredTrailing);
    }
    bool useDeferred =
        deferred && (!immediate || deferred->size() > immediate->size());
    if (!immediate && !deferred) {
      if (!singleClockSource)
        reject("clock source");
      for (llvm::StringMap<uint64_t> *reasons :
           {&immediateReasons, &deferredReasons})
        for (auto &[reason, total] : *reasons)
          rejections[reason] += total;
      continue;
    }
    for (auto &[reason, total] :
         useDeferred ? deferredReasons : immediateReasons)
      rejections[reason] += total;
    DenseSet<uint64_t> eligibleRoots =
        std::move(useDeferred ? *deferred : *immediate);
    for (StringAttr writer : useDeferred ? deferredTrailing : immediateTrailing)
      trailingWriters.insert(writer);
    for (uint64_t root : eligibleRoots)
      if (heldObserversOf.count(root))
        for (const Writer &write : writers.lookup(root))
          if (write.kind == schedule::ComputeEffectKind::NBA &&
              memberNames.contains(write.function))
            heldStorers.insert(write.function);

    // Kernel order: readers of an eligible root before its NBA writers;
    // otherwise keep the existing schedule order, including between writers
    // and readers of immediate stores.
    size_t count = members.size();
    llvm::sort(members, [](const Member &lhs, const Member &rhs) {
      return lhs.order < rhs.order;
    });
    SmallVector<SmallVector<unsigned>> successors(count);
    SmallVector<unsigned> indegree(count, 0);
    {
      DenseMap<uint64_t, SmallVector<unsigned>> readersOf, nbaWritersOf,
          writersOf;
      for (auto [index, member] : llvm::enumerate(members)) {
        for (uint64_t root : member.reads)
          readersOf[root].push_back(index);
        for (uint64_t root : member.nbaWrites)
          if (eligibleRoots.contains(root))
            nbaWritersOf[root].push_back(index);
        for (uint64_t root : member.writes)
          writersOf[root].push_back(index);
      }
      llvm::DenseSet<std::pair<unsigned, unsigned>> edges;
      auto addEdge = [&](unsigned from, unsigned to) {
        if (from != to && edges.insert({from, to}).second) {
          successors[from].push_back(to);
          ++indegree[to];
        }
      };
      for (auto &[root, nbaWriters] : nbaWritersOf)
        for (unsigned reader : readersOf.lookup(root))
          for (unsigned writer : nbaWriters)
            addEdge(reader, writer);
      for (auto &[root, immediate] : writersOf) {
        SmallVector<unsigned> touching(immediate.begin(), immediate.end());
        llvm::append_range(touching, readersOf.lookup(root));
        llvm::sort(touching);
        touching.erase(std::unique(touching.begin(), touching.end()),
                       touching.end());
        for (unsigned writer : immediate)
          for (unsigned other : touching)
            if (writer < other)
              addEdge(writer, other);
            else if (other < writer)
              addEdge(other, writer);
      }
    }
    SmallVector<unsigned> sequence;
    {
      std::priority_queue<unsigned, std::vector<unsigned>,
                          std::greater<unsigned>>
          ready;
      SmallVector<bool> done(count, false);
      for (unsigned index = 0; index != count; ++index)
        if (indegree[index] == 0)
          ready.push(index);
      while (sequence.size() != count) {
        if (ready.empty()) {
          // A cycle: take the earliest remaining member. Its late reads are
          // resolved by snapshots or retained NBAs below.
          for (unsigned index = 0; index != count; ++index)
            if (!done[index]) {
              ready.push(index);
              indegree[index] = 0;
              break;
            }
        }
        unsigned next = ready.top();
        ready.pop();
        if (done[next])
          continue;
        done[next] = true;
        sequence.push_back(next);
        for (unsigned successor : successors[next])
          if (!done[successor] && --indegree[successor] == 0)
            ready.push(successor);
      }
    }

    // Choose the clock root most members already wait on.
    DenseMap<uint64_t, unsigned> clockVotes;
    for (Member &member : members)
      ++clockVotes[member.clock];
    unsigned waitMember = 0;
    for (auto [index, member] : llvm::enumerate(members))
      if (clockVotes[member.clock] > clockVotes[members[waitMember].clock] ||
          (clockVotes[member.clock] == clockVotes[members[waitMember].clock] &&
           member.clock < members[waitMember].clock))
        waitMember = index;
    // The kernel exists to store NBAs directly; without an eligible root the
    // existing per-instance process fusion is left in place.
    if (eligibleRoots.empty())
      continue;

    // The kernel's captures: the union of the members' spawn operands.
    SmallVector<Value> operands;
    SmallVector<Type> inputTypes;
    SmallVector<DictionaryAttr> argumentAttrs;
    DenseMap<Value, unsigned> operandIndices;
    sim::SimSpawnOp insertionSpawn = members.front().spawn;
    bool compatible = true;
    for (Member &member : members) {
      if (insertionSpawn->isBeforeInBlock(member.spawn))
        insertionSpawn = member.spawn;
      Block &entry = member.function.getBody().front();
      member.fusedArguments.clear();
      for (auto [argument, operand] :
           llvm::zip_equal(entry.getArguments(), member.spawn.getOperands())) {
        DictionaryAttr attrs =
            member.function.getArgAttrDict(argument.getArgNumber());
        auto [found, inserted] =
            operandIndices.try_emplace(operand, operands.size());
        if (inserted) {
          operands.push_back(operand);
          inputTypes.push_back(argument.getType());
          argumentAttrs.push_back(attrs);
        } else if (inputTypes[found->second] != argument.getType() ||
                   argumentAttrs[found->second] != attrs) {
          compatible = false;
        }
        member.fusedArguments.push_back(found->second);
      }
    }
    if (!compatible) {
      reject("incompatible captures");
      continue;
    }
    plans.push_back({key, &members, std::move(eligibleRoots), useDeferred,
                     std::move(sequence), waitMember, std::move(operands),
                     std::move(inputTypes), std::move(argumentAttrs),
                     insertionSpawn});
  }

  // 4. Build each planned kernel.
  bool changed = false;
  for (Plan &plan : plans) {
    std::vector<Member> &members = *plan.members;
    size_t count = members.size();
    ArrayRef<unsigned> sequence = plan.sequence;
    unsigned waitMember = plan.waitMember;
    uint64_t classRoot = plan.key.first;
    Member &first = members[sequence.front()];
    Location location = first.function.getLoc();
    OpBuilder builder = OpBuilder::atBlockEnd(&design.getBody().front());
    SmallVector<NamedAttribute> attributes;
    if (IntegerAttr codeUnit = first.function.getCodeUnitIdAttr())
      attributes.emplace_back(first.function.getCodeUnitIdAttrName(), codeUnit);
    unsigned symbolCounter = 0;
    SmallString<48> base;
    (schedule::clockedKernelPrefix + Twine(classRoot) + "_" +
     Twine(plan.key.second))
        .toVector(base);
    SmallString<48> name = SymbolTable::generateSymbolName<48>(
        base,
        [&](StringRef candidate) {
          return symbols.lookup(candidate) != nullptr;
        },
        symbolCounter);
    sim::SimFuncOp kernel = sim::SimFuncOp::create(
        builder, location, name,
        FunctionType::get(design.getContext(), plan.inputTypes, TypeRange{}),
        first.function.getEntryKind(), attributes, plan.argumentAttrs);
    symbols.insert(kernel);
    SymbolTable::setSymbolVisibility(kernel, SymbolTable::Visibility::Private);

    Block &entry = kernel.getBody().front();
    Block *wait = new Block;
    kernel.getBody().push_back(wait);
    std::vector<IRMapping> mappings(count);
    for (auto [index, member] : llvm::enumerate(members))
      for (auto [argument, fused] :
           llvm::zip_equal(member.function.getBody().front().getArguments(),
                           member.fusedArguments))
        mappings[index].map(argument, entry.getArgument(fused));
    for (unsigned index : sequence) {
      Member &member = members[index];
      for (Block *source : member.bodyBlocks) {
        Block *cloned = new Block;
        kernel.getBody().push_back(cloned);
        mappings[index].map(source, cloned);
        for (BlockArgument argument : source->getArguments())
          mappings[index].map(argument, cloned->addArgument(argument.getType(),
                                                            argument.getLoc()));
      }
    }
    for (auto [position, index] : llvm::enumerate(sequence)) {
      Block *next = position + 1 == count
                        ? wait
                        : mappings[sequence[position + 1]].lookup(
                              members[sequence[position + 1]].body);
      mappings[index].map(members[index].wait, next);
    }
    // The wait resumes into a block of its own, so state captured at the
    // start of an activation is captured exactly once per activation even if
    // the first member begins with a loop.
    Block *activation = new Block;
    kernel.getBody().getBlocks().insert(std::next(Region::iterator(wait)),
                                        activation);
    {
      OpBuilder start = OpBuilder::atBlockEnd(activation);
      cf::BranchOp::create(start, location,
                           mappings[sequence.front()].lookup(first.body));
    }

    builder.setInsertionPointToStart(&entry);
    for (unsigned index : sequence)
      for (Operation *operation : members[index].preamble)
        builder.clone(*operation, mappings[index]);
    cf::BranchOp::create(builder, location, wait);
    builder.setInsertionPointToStart(wait);
    for (unsigned index : sequence)
      for (Operation &operation : members[index].wait->without_terminator())
        builder.clone(operation, mappings[index]);
    Operation *suspend = builder.clone(
        *members[waitMember].wait->getTerminator(), mappings[waitMember]);
    suspend->setSuccessor(activation, 0);
    // A deferred kernel resumes in the Inactive region of its iteration, as
    // `@(edge) #0` would (4.4.2.3): after every Active event of its pass.
    if (plan.deferred)
      suspend->setAttr("resume_region",
                       sim::EventRegionAttr::get(design.getContext(),
                                                 sim::EventRegion::Inactive));
    for (unsigned index : sequence) {
      Member &member = members[index];
      for (Block *source : member.bodyBlocks) {
        builder.setInsertionPointToEnd(mappings[index].lookup(source));
        for (Operation &operation : *source)
          builder.clone(operation, mappings[index]);
      }
    }
    // Reads of a member's own clock see the class source, which is current
    // when the kernel runs; the member's copy may not have been updated yet
    // (admission above, 23.3.3, 4.9.1).
    unsigned redirectedClockReads = 0;
    for (unsigned index : sequence) {
      Member &member = members[index];
      if (!member.redirectClockReads)
        continue;
      uint64_t root = member.origin;
      for (auto copy = phases.getCopies().find(root);
           copy != phases.getCopies().end();
           copy = phases.getCopies().find(root))
        root = copy->second.source;
      Value context;
      for (BlockArgument argument :
           member.function.getBody().front().getArguments())
        if (isa<sim::ContextType>(argument.getType()))
          context = mappings[index].lookup(argument);
      if (!context)
        return design.emitError("clocked kernel member without a context"),
               signalPassFailure();
      for (Operation *read : member.clockReads) {
        Operation *cloned =
            mappings[index].lookup(read->getResult(0)).getDefiningOp();
        OpBuilder redirect(cloned);
        Type produced = read->getResult(0).getType();
        Type type = rootType(root);
        Value value;
        if (root >= ActivationMemoryAnalysis::netRootTag) {
          Value net = sim::SimContextNetOp::create(
              redirect, cloned->getLoc(),
              sim::NetType::get(design.getContext(), type), context,
              redirect.getI64IntegerAttr(
                  root & ~ActivationMemoryAnalysis::netRootTag));
          value =
              sim::SimNetReadOp::create(redirect, cloned->getLoc(), type, net);
        } else {
          Value reference = sim::SimContextStorageOp::create(
              redirect, cloned->getLoc(),
              sim::RefType::get(design.getContext(), type), context, root);
          value = sim::SimRefLoadOp::create(redirect, cloned->getLoc(), type,
                                            reference);
        }
        if (type != produced)
          value = sim::SimLogicFromBitsOp::create(redirect, cloned->getLoc(),
                                                  produced, value);
        cloned->getResult(0).replaceAllUsesWith(value);
        cloned->erase();
        ++redirectedClockReads;
      }
    }
    removeTerminationPolls(kernel);

    builder.setInsertionPoint(plan.insertionSpawn);
    sim::SimSpawnOp::create(builder, location, kernel.getSymNameAttr(),
                            plan.operands, ArrayAttr{}, ArrayAttr{});
    for (Member &member : members) {
      member.spawn.erase();
      symbols.erase(member.function);
    }
    changed = true;
    ++kernels;
    fusedMembers += count;

    // 5. Late reads. A read executed after an NBA site of its root must see
    // the incoming value (4.9.4); find them with a forward may-dataflow over
    // the activation CFG.
    SmallVector<uint64_t> rootList(plan.eligibleRoots.begin(),
                                   plan.eligibleRoots.end());
    llvm::sort(rootList);
    DenseMap<uint64_t, unsigned> rootIndex;
    for (auto [index, root] : llvm::enumerate(rootList))
      rootIndex[root] = index;
    analysis::HandleDataflowResult handleProofs = provenance.analyze(kernel);
    const analysis::HandleFacts &facts = handleProofs.facts;
    llvm::BitVector unsupported(rootList.size());
    enum class EventKind { Enqueue, Read, OpaqueRead };
    struct Event {
      EventKind kind;
      unsigned root;
      Operation *operation;
    };
    SmallVector<Block *> blocks;
    {
      SmallVector<Block *> pending{activation};
      DenseSet<Block *> seen;
      while (!pending.empty()) {
        Block *block = pending.pop_back_val();
        if (block == wait || !seen.insert(block).second)
          continue;
        blocks.push_back(block);
        for (Block *successor : block->getSuccessors())
          pending.push_back(successor);
      }
    }
    DenseMap<Block *, SmallVector<Event>> events;
    auto eligibleIndex = [&](Value value) -> std::optional<unsigned> {
      std::optional<uint64_t> root = storageRoot(value, facts);
      if (!root)
        return std::nullopt;
      auto found = rootIndex.find(*root);
      if (found == rootIndex.end())
        return std::nullopt;
      return found->second;
    };
    auto markAllUnsupported = [&] { unsupported.set(); };
    for (Block *block : blocks) {
      SmallVector<Event> &list = events[block];
      block->walk([&](Operation *operation) {
        bool nested = operation->getBlock() != block;
        if (auto enqueue = dyn_cast<sim::SimNBAEnqueueOp>(operation)) {
          std::optional<unsigned> index =
              eligibleIndex(enqueue.getDestination());
          if (!index)
            return;
          auto reference =
              dyn_cast<sim::RefType>(enqueue.getDestination().getType());
          auto view =
              enqueue.getDestination().getDefiningOp<sim::SimRefDynExtractOp>();
          // An NBA view clips to its immediate input, which can be a struct
          // member or an array lane inside a larger physical root. A direct
          // store retains only the root's bounds. Preserve the captured NBA
          // unless that loses no narrower boundary (IEEE 1800-2023 11.5.1).
          bool needsClipping =
              view && *sim::getPackedWidth(
                          view.getResult().getType().getElementType()) >
                          *sim::getPackedWidth(
                              view.getInput().getType().getElementType());
          if (view) {
            auto parent = facts.find(view.getInput());
            auto selected = facts.find(view.getResult());
            auto exactAddress = [&](Value value) {
              auto proof = handleProofs.certificates.find(value);
              return proof != handleProofs.certificates.end() &&
                     proof->second.constantAddress;
            };
            bool wholeRoot = parent != facts.end() &&
                             !parent->second.dynamic &&
                             parent->second.low == 0 &&
                             parent->second.width == parent->second.rootWidth &&
                             sim::getPackedWidth(
                                 view.getInput().getType().getElementType()) ==
                                 parent->second.rootWidth;
            bool contained =
                parent != facts.end() && selected != facts.end() &&
                !parent->second.dynamic && !selected->second.dynamic &&
                exactAddress(view.getInput()) && exactAddress(view.getResult()) &&
                selected->second.low >= parent->second.low &&
                selected->second.low - parent->second.low <=
                    parent->second.width &&
                selected->second.width <=
                    parent->second.width -
                        (selected->second.low - parent->second.low);
            needsClipping |= !wholeRoot && !contained;
          }
          if (nested || enqueue.getDelay() || enqueue.getClockingOutputAttr() ||
              !reference || needsClipping ||
              reference.getElementType() != enqueue.getValue().getType())
            unsupported.set(*index);
          else
            list.push_back({EventKind::Enqueue, *index, operation});
          if (eligibleIndex(enqueue.getValue()))
            unsupported.set(*eligibleIndex(enqueue.getValue()));
          return;
        }
        if (auto load = dyn_cast<sim::SimRefLoadOp>(operation)) {
          if (std::optional<unsigned> index =
                  eligibleIndex(load.getReference()))
            list.push_back({EventKind::Read, *index, operation});
          return;
        }
        if (auto copy = dyn_cast<sim::SimRefCopyOp>(operation)) {
          if (std::optional<unsigned> index = eligibleIndex(copy.getSource()))
            list.push_back({EventKind::Read, *index, operation});
          if (std::optional<unsigned> index =
                  eligibleIndex(copy.getDestination()))
            unsupported.set(*index);
          return;
        }
        if (auto call = dyn_cast<sim::SimCallOp>(operation)) {
          for (Value operand : call->getOperands())
            if (std::optional<unsigned> index = eligibleIndex(operand))
              unsupported.set(*index);
          auto callee =
              symbols.lookup<sim::SimFuncOp>(call.getCalleeAttr().getValue());
          ArrayAttr summary = callee ? callee.getEffectSummaryAttr() : nullptr;
          if (!summary) {
            markAllUnsupported();
            return;
          }
          for (auto effect :
               summary.getAsRange<schedule::ComputeEffectAttr>()) {
            if (effect.getTarget() == schedule::ComputeTargetKind::Formal ||
                effect.getTarget() == schedule::ComputeTargetKind::Local)
              continue;
            std::optional<uint64_t> root = effectRoot(effect);
            if (!root) {
              if (isAccess(effect.getEffect()))
                markAllUnsupported();
              continue;
            }
            auto found = rootIndex.find(*root);
            if (found == rootIndex.end())
              continue;
            if (isWrite(effect.getEffect()))
              unsupported.set(found->second);
            else if (effect.getEffect() == schedule::ComputeEffectKind::Read)
              list.push_back({EventKind::OpaqueRead, found->second, operation});
          }
          return;
        }
        if (isa<ViewLikeOpInterface>(operation))
          return;
        // Any other use of an eligible root's handle, including immediate
        // stores, is outside the contract.
        for (Value operand : operation->getOperands())
          if (std::optional<unsigned> index = eligibleIndex(operand))
            unsupported.set(*index);
      });
    }
    DenseMap<Operation *, unsigned> enqueues;
    for (Block *block : blocks)
      for (const Event &event : events[block])
        if (event.kind == EventKind::Enqueue)
          enqueues[event.operation] = event.root;
    SmallVector<SmallVector<Operation *>> lateReads(rootList.size());
    llvm::BitVector opaqueLate(rootList.size());
    {
      DataFlowSolver pending;
      pending.load<dataflow::DeadCodeAnalysis>();
      pending.load<dataflow::SparseConstantPropagation>();
      pending.load<PendingNBAAnalysis>(enqueues, rootList.size());
      if (failed(pending.initializeAndRun(kernel)))
        unsupported.set();
      for (Block *block : blocks)
        for (const Event &event : events[block]) {
          if (event.kind == EventKind::Enqueue)
            continue;
          const auto *state = pending.lookupState<PendingLattice>(
              pending.getProgramPointBefore(event.operation));
          // Without a state the read is unreachable; keep the NBA anyway.
          if (!state) {
            unsupported.set(event.root);
            continue;
          }
          if (event.root >= state->roots.size() ||
              !state->roots.test(event.root))
            continue;
          if (event.kind == EventKind::OpaqueRead)
            opaqueLate.set(event.root);
          else
            lateReads[event.root].push_back(event.operation);
        }
    }

    // 6. Roots read late. Each NBA site of such a root may keep its value and
    // the operands of its target (4.9.4) in activation-local slots and set a
    // flag instead; the kernel then applies the flagged updates after its
    // last member, in execution order (4.6(b)), as Verilator's V3Delayed
    // does. Every read before that sees the incoming value, at a cost that
    // grows with the updates instead of the root. A site that may run twice
    // in one activation would need a queue. Late reads that are views of the
    // whole root may instead read a snapshot of its incoming value.
    // The commit runs where the activation ends; every path there passes
    // through the entry block and then the block the wait resumes into.
    auto dominatesCommit = [&](Value value) {
      Block *owner = isa<BlockArgument>(value)
                         ? cast<BlockArgument>(value).getOwner()
                         : value.getDefiningOp()->getBlock();
      return owner == &entry || owner == activation;
    };
    // Values the commit can use directly or recreate; the others are
    // captured at the site.
    auto rematerializable = [&](Value value) {
      if (dominatesCommit(value))
        return true;
      Operation *definition = value.getDefiningOp();
      return definition &&
             (definition->hasTrait<OpTrait::ConstantLike>() ||
              isa<sim::SimContextStorageOp>(definition)) &&
             llvm::all_of(definition->getOperands(), dominatesCommit);
    };
    struct DelayedSite {
      sim::SimNBAEnqueueOp enqueue;
      unsigned root;
      /// Views from the target back toward its root handle.
      SmallVector<Operation *> chain{};
      /// How many sites may run before this one; orders the commit.
      unsigned position = 0;
    };
    SmallVector<DelayedSite> delays;
    llvm::BitVector delayed(rootList.size());
    SmallVector<uint64_t> delayedCost(rootList.size());
    {
      for (unsigned index = 0; index != rootList.size(); ++index)
        if (!unsupported.test(index) &&
            (!lateReads[index].empty() || opaqueLate.test(index)))
          delayed.set(index);
      SmallVector<DelayedSite> sites;
      DenseMap<Operation *, unsigned> siteIndices;
      for (Block *block : blocks)
        for (const Event &event : events[block])
          if (event.kind == EventKind::Enqueue && delayed.test(event.root)) {
            siteIndices[event.operation] = sites.size();
            sites.push_back(
                {cast<sim::SimNBAEnqueueOp>(event.operation), event.root});
          }
      DataFlowSolver order;
      order.load<dataflow::DeadCodeAnalysis>();
      order.load<dataflow::SparseConstantPropagation>();
      order.load<PendingNBAAnalysis>(siteIndices, sites.size());
      if (!sites.empty() && failed(order.initializeAndRun(kernel)))
        delayed.reset();
      auto capturable = [&](Value value) {
        return rematerializable(value) || sim::hasKnownZero(value.getType());
      };
      for (auto [index, site] : llvm::enumerate(sites)) {
        if (!delayed.test(site.root))
          continue;
        const auto *state = order.lookupState<PendingLattice>(
            order.getProgramPointBefore(site.enqueue));
        // A site in its own past may run again before the commit.
        bool once =
            state && !(index < state->roots.size() && state->roots.test(index));
        bool supported = once && capturable(site.enqueue.getValue());
        Value target = site.enqueue.getDestination();
        while (Operation *definition = target.getDefiningOp()) {
          if (!isa<sim::SimRefSubelementOp, sim::SimRefArrayElementOp,
                   sim::SimRefExtractOp, sim::SimRefDynExtractOp>(definition))
            break;
          site.chain.push_back(definition);
          target = cast<ViewLikeOpInterface>(definition).getViewSource();
          for (Value operand : definition->getOperands())
            if (operand != target && !capturable(operand))
              supported = false;
        }
        if (!supported || !rematerializable(target)) {
          delayed.reset(site.root);
          continue;
        }
        site.position = state->roots.count();
        delayedCost[site.root] +=
            delayedUpdateBits +
            sim::getProvenanceSpan(site.enqueue.getValue().getType())
                .value_or(maximumSnapshotBits);
      }
      for (DelayedSite &site : sites)
        if (delayed.test(site.root))
          delays.push_back(std::move(site));
      // A site that may precede another has fewer sites that may precede it.
      llvm::stable_sort(delays,
                        [](const DelayedSite &lhs, const DelayedSite &rhs) {
                          return lhs.position < rhs.position;
                        });
    }
    struct Snapshot {
      Value base;
      SmallVector<std::pair<Operation *, SmallVector<Operation *>>> reads;
    };
    DenseMap<unsigned, Snapshot> snapshots;
    for (unsigned index = 0; index != rootList.size(); ++index) {
      if (unsupported.test(index) || lateReads[index].empty() ||
          opaqueLate.test(index))
        continue;
      Snapshot snapshot;
      uint64_t snapshotBits = 0;
      bool ok = true;
      for (Operation *read : lateReads[index]) {
        Value reference = read->getOperand(0);
        SmallVector<Operation *> chain;
        while (Operation *definition = reference.getDefiningOp()) {
          if (!isa<sim::SimRefSubelementOp, sim::SimRefArrayElementOp,
                   sim::SimRefExtractOp, sim::SimRefDynExtractOp>(definition))
            break;
          chain.push_back(definition);
          reference = cast<ViewLikeOpInterface>(definition).getViewSource();
        }
        bool argument = isa<BlockArgument>(reference) &&
                        cast<BlockArgument>(reference).getOwner() == &entry;
        bool context = static_cast<bool>(
            reference.getDefiningOp<sim::SimContextStorageOp>());
        std::optional<uint64_t> whole = wholeStorageRoot(reference, facts);
        auto type = dyn_cast<sim::RefType>(reference.getType());
        std::optional<uint64_t> span =
            type ? sim::getProvenanceSpan(type.getElementType()) : std::nullopt;
        if ((!argument && !context) || !whole || *whole != rootList[index] ||
            !span || *span > maximumSnapshotBits ||
            (snapshot.base && snapshot.base.getType() != reference.getType())) {
          ok = false;
          break;
        }
        snapshotBits = *span;
        if (!snapshot.base || argument)
          snapshot.base = reference;
        snapshot.reads.push_back({read, std::move(chain)});
      }
      if (ok && delayed.test(index) && delayedCost[index] < snapshotBits)
        ok = false;
      if (ok) {
        snapshots[index] = std::move(snapshot);
        delayed.reset(index);
      }
    }
    for (unsigned index = 0; index != rootList.size(); ++index)
      if (!lateReads[index].empty() || opaqueLate.test(index))
        if (!snapshots.count(index) && !delayed.test(index))
          unsupported.set(index);
    // The held-state proof (planRoots) assumed every root of a held cone the
    // plan admits is stored. If one keeps its NBA here, every other one keeps
    // its NBA too: a member could otherwise store one and keep another, which
    // the proof's single reference order forbids (4.6(b)). Kept NBAs are the
    // reference itself.
    if (llvm::any_of(llvm::enumerate(rootList), [&](auto entry) {
          return unsupported.test(entry.index()) &&
                 heldObserversOf.count(entry.value());
        }))
      for (auto [index, root] : llvm::enumerate(rootList))
        if (heldObserversOf.count(root))
          unsupported.set(index);
    builder.setInsertionPoint(activation->getTerminator());
    for (auto &[index, snapshot] : snapshots) {
      Value base = snapshot.base;
      if (auto context = base.getDefiningOp<sim::SimContextStorageOp>())
        base = builder.clone(*context)->getResult(0);
      auto type = cast<sim::RefType>(base.getType());
      Value old = sim::SimRefLoadOp::create(builder, location,
                                            type.getElementType(), base);
      // The copy is never stored to, so a whole read of it is `old` of the same
      // activation. Only reads through views need the copy: a bytecode
      // activation allocates an automatic cell for it each time it runs
      // (two-tier B2 Q5).
      Value copy;
      for (auto &[read, chain] : snapshot.reads) {
        if (auto load = dyn_cast<sim::SimRefLoadOp>(read);
            load && chain.empty()) {
          // Every read's root reference has the type of `base`.
          assert(load.getType() == old.getType() && "snapshot read type");
          load.getResult().replaceAllUsesWith(old);
          load.erase();
          continue;
        }
        if (!copy)
          copy = sim::SimRefAllocOp::create(builder, location, type, old);
        OpBuilder viewBuilder(read);
        Value current = copy;
        for (Operation *view : llvm::reverse(chain)) {
          IRMapping mapping;
          mapping.map(cast<ViewLikeOpInterface>(view).getViewSource(), current);
          current = viewBuilder.clone(*view, mapping)->getResult(0);
        }
        read->setOperand(0, current);
      }
    }

    // 7. Store at the NBA statements of every remaining root, or delay them.
    for (Block *block : blocks)
      for (const Event &event : events[block]) {
        if (event.kind != EventKind::Enqueue || unsupported.test(event.root) ||
            delayed.test(event.root))
          continue;
        auto enqueue = cast<sim::SimNBAEnqueueOp>(event.operation);
        OpBuilder storeBuilder(enqueue);
        auto store = sim::SimRefStoreOp::create(storeBuilder, enqueue.getLoc(),
                                                enqueue.getValue(),
                                                enqueue.getDestination());
        // The store performs the NBA update early (4.5, 10.4.2).
        schedule::set<schedule::Field::EvalNbaEquivalentStore>(
            store, storeBuilder.getUnitAttr());
        enqueue.erase();
        ++directSites;
      }
    delayed.reset(unsupported);
    if (delayed.any()) {
      // The slots live for one activation and start unset.
      builder.setInsertionPoint(activation->getTerminator());
      Type flagType = builder.getI1Type();
      auto flagReference = sim::RefType::get(builder.getContext(), flagType);
      Value unset = arith::ConstantOp::create(builder, location,
                                              builder.getBoolAttr(false));
      // Every path that ends the activation commits first.
      Block *commit = new Block;
      kernel.getBody().push_back(commit);
      for (Block *block : blocks)
        for (BlockOperand &successor :
             block->getTerminator()->getBlockOperands())
          if (successor.get() == wait)
            successor.set(commit);
      OpBuilder commitBuilder = OpBuilder::atBlockEnd(commit);
      for (DelayedSite &site : delays) {
        if (!delayed.test(site.root))
          continue;
        Location siteLocation = site.enqueue.getLoc();
        Value flag =
            sim::SimRefAllocOp::create(builder, location, flagReference, unset);
        llvm::MapVector<Value, Value> slots;
        auto capture = [&](Value value) {
          if (rematerializable(value) || slots.count(value))
            return;
          Value zero =
              *sim::materializeKnownZero(builder, location, value.getType());
          slots[value] = sim::SimRefAllocOp::create(
              builder, location,
              sim::RefType::get(builder.getContext(), value.getType()), zero);
        };
        capture(site.enqueue.getValue());
        for (Operation *view : site.chain)
          for (Value operand : view->getOperands())
            if (operand != cast<ViewLikeOpInterface>(view).getViewSource())
              capture(operand);
        {
          OpBuilder siteBuilder(site.enqueue);
          for (auto &[value, slot] : slots)
            sim::SimRefStoreOp::create(siteBuilder, siteLocation, value, slot);
          Value set = arith::ConstantOp::create(siteBuilder, siteLocation,
                                                siteBuilder.getBoolAttr(true));
          sim::SimRefStoreOp::create(siteBuilder, siteLocation, set, flag);
        }
        Block *apply = new Block, *next = new Block;
        kernel.getBody().push_back(apply);
        kernel.getBody().push_back(next);
        Value isSet = sim::SimRefLoadOp::create(commitBuilder, siteLocation,
                                                flagType, flag);
        cf::CondBranchOp::create(commitBuilder, siteLocation, isSet, apply,
                                 next);
        commitBuilder.setInsertionPointToEnd(apply);
        IRMapping mapping;
        for (auto &[value, slot] : slots)
          mapping.map(value,
                      sim::SimRefLoadOp::create(commitBuilder, siteLocation,
                                                value.getType(), slot));
        auto recreate = [&](Value value) {
          if (mapping.contains(value) || dominatesCommit(value))
            return;
          mapping.map(
              value, commitBuilder.clone(*value.getDefiningOp())->getResult(0));
        };
        for (Operation *view : llvm::reverse(site.chain)) {
          for (Value operand : view->getOperands())
            recreate(operand);
          commitBuilder.clone(*view, mapping);
        }
        recreate(site.enqueue.getDestination());
        recreate(site.enqueue.getValue());
        auto store = sim::SimRefStoreOp::create(
            commitBuilder, siteLocation,
            mapping.lookupOrDefault(site.enqueue.getValue()),
            mapping.lookupOrDefault(site.enqueue.getDestination()));
        schedule::set<schedule::Field::EvalNbaEquivalentStore>(
            store, commitBuilder.getUnitAttr());
        cf::BranchOp::create(commitBuilder, siteLocation, next);
        commitBuilder.setInsertionPointToEnd(next);
        site.enqueue.erase();
        ++delayedSites;
      }
      cf::BranchOp::create(commitBuilder, location, wait);
    }
    for (unsigned index = 0; index != rootList.size(); ++index) {
      if (unsupported.test(index))
        ++retainedRoots;
      else {
        ++directRoots;
        if (snapshots.count(index))
          ++snapshotRoots;
        if (delayed.test(index))
          ++delayedRoots;
      }
    }
    if (report)
      llvm::errs() << "talos clocked kernel: " << kernel.getSymName()
                   << " members=" << count << " eligible=" << rootList.size()
                   << " retained=" << unsupported.count()
                   << " snapshots=" << snapshots.size()
                   << " deferred=" << plan.deferred
                   << " delayed=" << delayed.count()
                   << " clock_reads=" << redirectedClockReads << '\n';
  }
  if (report) {
    for (auto &[reason, total] : rejections)
      llvm::errs() << "talos clocked kernel rejection: " << reason << " = "
                   << total << '\n';
    // The processes whose observation keeps the most roots on their NBAs.
    DenseMap<int64_t, StringRef> hierarchies;
    for (auto unit : design.getBody().front().getOps<sim::SimCodeUnitDeclOp>())
      hierarchies[unit.getId()] = unit.getHierarchicalName();
    SmallVector<std::pair<unsigned, StringAttr>> observers;
    for (auto &[observer, total] : observedRootsBy)
      observers.emplace_back(total, observer);
    llvm::sort(observers, [](const auto &a, const auto &b) {
      return std::make_pair(b.first, a.second.getValue()) <
             std::make_pair(a.first, b.second.getValue());
    });
    for (auto [total, observer] : ArrayRef(observers).take_front(12)) {
      StringRef hierarchy;
      std::string reason;
      if (auto function = observer ? symbols.lookup<sim::SimFuncOp>(observer)
                                   : sim::SimFuncOp{}) {
        if (IntegerAttr unit = function.getCodeUnitIdAttr())
          hierarchy = hierarchies.lookup(unit.getInt());
        CombinationalFusionFailure failure;
        if (!combinational.analyze(function, provenance, /*interleaved=*/true,
                                   &failure, /*finalValuesOnly=*/true))
          reason = failure.getMessage();
      }
      llvm::errs() << "talos clocked kernel observed roots: observer="
                   << (observer ? observer.getValue() : "<unknown>")
                   << " hierarchy=\"" << hierarchy << "\" roots=" << total
                   << " reason=" << reason << '\n';
    }
  }
  if (changed)
    design.removeComputeGraphAttr();
}

} // namespace
} // namespace talos
