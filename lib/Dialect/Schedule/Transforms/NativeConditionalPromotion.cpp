//===- NativeConditionalPromotion.cpp - Conditional input certificates ----===//

#include "NativeConditionalPromotion.h"
#include "../../../Conversion/SimulationToLLVMCoroutine/SimulationToLLVMCoroutinePrivate.h"
#include "mlir/Analysis/DataFlow/ConstantPropagationAnalysis.h"
#include "mlir/Analysis/DataFlow/DeadCodeAnalysis.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "talos/Analysis/NativeAOTAnalysis.h"
#include "talos/Analysis/OrderedDenseAnalysis.h"
#include "talos/Analysis/SimulationAnalysis.h"
#include "talos/Analysis/StorageWriteAnalysis.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "talos/Runtime/StableHandle.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace talos::detail {
namespace {
using Range = std::pair<uint64_t, uint64_t>;
bool overlaps(Range a, Range b) {
  return a.first <= b.first ? a.second > b.first - a.first
                            : b.second > a.first - b.first;
}
struct Access {
  Operation *operation;
  Value reference;
  Range range;
  bool write;
};
struct Candidate {
  Range range;
  Value reference;
  SmallVector<SmallVector<std::pair<Value, bool>>> paths;
};

/// The may-written product lattice. Joining paths unions possible writes;
/// loops converge before a snapshot is certified unchanged from entry.
class MayWrites final : public dataflow::AbstractDenseLattice {
public:
  using AbstractDenseLattice::AbstractDenseLattice;
  bool reachable = false;
  llvm::BitVector bits;
  ChangeResult merge(const llvm::BitVector &incoming) {
    if (!reachable) {
      reachable = true;
      bits = incoming;
      return ChangeResult::Change;
    }
    llvm::BitVector next = bits;
    next |= incoming;
    if (next == bits)
      return ChangeResult::NoChange;
    bits = std::move(next);
    return ChangeResult::Change;
  }
  ChangeResult join(const AbstractDenseLattice &other) override {
    const auto &rhs = static_cast<const MayWrites &>(other);
    return rhs.reachable ? merge(rhs.bits) : ChangeResult::NoChange;
  }
  void print(raw_ostream &os) const override {
    os << bits.count() << " writes";
  }
};
class MayWriteAnalysis final
    : public analysis::OrderedDenseForwardDataFlowAnalysis<MayWrites> {
public:
  MayWriteAnalysis(DataFlowSolver &solver,
                   const DenseMap<Operation *, llvm::BitVector> &writes,
                   unsigned count)
      : OrderedDenseForwardDataFlowAnalysis(solver), writes(writes),
        count(count) {}
  LogicalResult visitOperation(Operation *op, const MayWrites &before,
                               MayWrites *after) override {
    if (!before.reachable)
      return success();
    llvm::BitVector next = before.bits;
    if (auto found = writes.find(op); found != writes.end())
      next |= found->second;
    propagateIfChanged(after, after->merge(next));
    return success();
  }

private:
  void setToEntryState(MayWrites *state) override {
    propagateIfChanged(state, state->merge(llvm::BitVector(count)));
  }
  const DenseMap<Operation *, llvm::BitVector> &writes;
  unsigned count;
};

using Literal = std::pair<unsigned, bool>;
using Term = SmallVector<Literal, 4>;
bool subsumes(const Term &a, const Term &b) {
  return llvm::all_of(
      a, [&](Literal literal) { return llvm::is_contained(b, literal); });
}
/// Disjunction of path conjunctions. Empty is unreachable; one empty term is
/// unconstrained. Subsumption and widening are overapproximations. Excess
/// disjuncts/literals lose predicates, never possible paths. No iteration cap
/// can certify an unfinished loop solve.
class EntryPaths final : public dataflow::AbstractDenseLattice {
public:
  using AbstractDenseLattice::AbstractDenseLattice;
  SmallVector<Term, 1> paths;
  ChangeResult merge(Term path) {
    if (path.size() > 12)
      path.clear();
    // (P && C) || (P && !C) == P. This also recognizes an access reached
    // through every arm of a join as unconditional.
    bool simplified;
    do {
      simplified = false;
      for (const Term &old : paths) {
        if (old.size() != path.size())
          continue;
        unsigned differences = 0, position = 0;
        bool sameConditions = true;
        for (unsigned i = 0; i != path.size(); ++i) {
          sameConditions &= old[i].first == path[i].first;
          if (old[i].second != path[i].second) {
            ++differences;
            position = i;
          }
        }
        if (sameConditions && differences == 1) {
          path.erase(path.begin() + position);
          simplified = true;
          break;
        }
      }
    } while (simplified);
    if (llvm::any_of(paths,
                     [&](const Term &old) { return subsumes(old, path); }))
      return ChangeResult::NoChange;
    llvm::erase_if(paths, [&](const Term &old) { return subsumes(path, old); });
    paths.push_back(std::move(path));
    if (paths.size() > 8) {
      paths.clear();
      paths.emplace_back();
    }
    return ChangeResult::Change;
  }
  ChangeResult join(const AbstractDenseLattice &other) override {
    ChangeResult changed = ChangeResult::NoChange;
    for (const Term &path : static_cast<const EntryPaths &>(other).paths)
      changed |= merge(path);
    return changed;
  }
  void print(raw_ostream &os) const override { os << paths.size() << " paths"; }
};
class EntryPathAnalysis final
    : public analysis::OrderedDenseForwardDataFlowAnalysis<EntryPaths> {
public:
  EntryPathAnalysis(DataFlowSolver &solver,
                    const DenseMap<Value, unsigned> &conditions)
      : OrderedDenseForwardDataFlowAnalysis(solver), conditions(conditions) {}
  LogicalResult visitOperation(Operation *, const EntryPaths &before,
                               EntryPaths *after) override {
    propagateIfChanged(after, after->join(before));
    return success();
  }
  void visitBlockTransfer(Block *block, ProgramPoint *, Block *predecessor,
                          const EntryPaths &before,
                          EntryPaths *after) override {
    auto branch = dyn_cast<cf::CondBranchOp>(predecessor->getTerminator());
    auto found =
        branch ? conditions.find(branch.getCondition()) : conditions.end();
    if (!branch || found == conditions.end() ||
        branch.getTrueDest() == branch.getFalseDest()) {
      propagateIfChanged(after, after->join(before));
      return;
    }
    Literal literal{found->second, branch.getTrueDest() == block};
    for (Term path : before.paths) {
      auto old = llvm::find_if(
          path, [&](Literal value) { return value.first == literal.first; });
      if (old != path.end() && old->second != literal.second)
        continue;
      if (old == path.end()) {
        path.push_back(literal);
        llvm::sort(path);
      }
      propagateIfChanged(after, after->merge(std::move(path)));
    }
  }

private:
  void setToEntryState(EntryPaths *state) override {
    propagateIfChanged(state, state->merge(Term{}));
  }
  const DenseMap<Value, unsigned> &conditions;
};
} // namespace

sim::SimFuncOp materializeConditionalPromotionProbe(
    sim::SimFuncOp source, const NativeStateLayout &layout,
    const analysis::HandleDataflowAnalysis &handleAnalysis,
    SymbolTable &symbols, StringRef name, uint64_t codeUnit) {
  auto encoded =
      schedule::get<schedule::Field::EvalLocalPromotionRanges>(source);
  if (!encoded || encoded.empty() || encoded.size() > 1024 ||
      layout.hasPassSwitch || source.getFunctionType().getNumInputs() != 1 ||
      !isa<sim::ContextType>(source.getFunctionType().getInput(0)) ||
      // A cleaned writable-VPI layout is boundary authority, not original
      // direct-access authority (LRM 38.34/10.6). Keep that established entry
      // guard; this optional null-context predicate does not run outside it.
      schedule::has<cleanEvalBodyAttr>(source) ||
      schedule::has<schedule::Field::EvalInheritedTwoStateCheckpoint>(source))
    return {};
  uint64_t operations = 0;
  source.walk([&](Operation *) { ++operations; });
  if (operations <=
      schedule::getMaxInlineOperations(source->getParentOfType<ModuleOp>()))
    return {};

  auto handles = handleAnalysis.analyze(source);
  auto resolve = [&](Value reference, bool exact) -> std::optional<Range> {
    auto found = handles.facts.find(reference);
    if (found == handles.facts.end() || !found->second.descriptor ||
        (exact && found->second.dynamic))
      return std::nullopt;
    const auto &fact = found->second;
    const auto *roots = fact.resource == schedule::ComputeResourceKind::Storage
                            ? &layout.storage
                        : fact.resource == schedule::ComputeResourceKind::Net
                            ? &layout.nets
                            : nullptr;
    if (!roots)
      return std::nullopt;
    auto root = roots->find(*fact.descriptor);
    talos_rt_stable_handle_v1 decoded{};
    if (root == roots->end() ||
        !talos_rt_stable_handle_decode(root->second, &decoded) ||
        decoded.kind != TALOS_RT_STABLE_HANDLE_STATIC || decoded.offset ||
        !layout.directHandles.contains(decoded.id) ||
        layout.guardedHandles.contains(decoded.id))
      return std::nullopt;
    auto *bound = layout.findBound(decoded.id);
    uint64_t width = fact.width ? fact.width : fact.rootWidth;
    if (!bound || !width || fact.low > bound->width ||
        width > bound->width - fact.low)
      return std::nullopt;
    return Range{bound->offset + fact.low, width};
  };

  // Handle dataflow supplies conservative alias hulls. An unmodelled effect
  // or call prevents speculative control reads; there is no default no-alias
  // assumption. NBAs capture now and publish later (LRM 10.4.2).
  SmallVector<Access> accesses;
  bool supported = true;
  source.walk([&](Operation *op) {
    if (!supported || op == source.getOperation())
      return;
    if (analysis::isDirectOutput(op) || isa<sim::SimTimeNowOp>(op))
      return;
    Value reference;
    bool write = false, deferred = false;
    if (auto load = dyn_cast<sim::SimRefLoadOp>(op))
      reference = load.getReference();
    else if (auto read = dyn_cast<sim::SimNetReadOp>(op))
      reference = read.getNet();
    else if (auto store = dyn_cast<sim::SimRefStoreOp>(op)) {
      reference = store.getReference();
      write = true;
    } else if (auto drive = dyn_cast<sim::SimDriverDriveOp>(op)) {
      reference = drive.getDriver();
      write = true;
    } else if (auto nba = dyn_cast<sim::SimNBAEnqueueOp>(op)) {
      reference = nba.getDestination();
      deferred = true;
    } else if (isa<sim::SimReturnOp, cf::BranchOp, cf::CondBranchOp>(op) ||
               isMemoryEffectFree(op)) {
      return;
    } else {
      supported = false;
      return;
    }
    auto range = resolve(reference, false);
    if (!range) {
      supported = false;
      return;
    }
    accesses.push_back({op, reference, *range, write && !deferred});
  });
  if (!supported)
    return {};

  SmallVector<Range> queryRanges;
  DenseMap<Range, unsigned> rangeIndices;
  DenseMap<Operation *, unsigned> readIndices;
  for (const Access &access : accesses) {
    if (!isa<sim::SimRefLoadOp>(access.operation))
      continue;
    auto [found, inserted] =
        rangeIndices.try_emplace(access.range, queryRanges.size());
    if (inserted)
      queryRanges.push_back(access.range);
    readIndices[access.operation] = found->second;
  }
  DenseMap<Operation *, llvm::BitVector> writes;
  for (const Access &access : accesses) {
    if (!access.write)
      continue;
    auto &mask = writes.try_emplace(access.operation, queryRanges.size(), false)
                     .first->second;
    for (auto [index, range] : llvm::enumerate(queryRanges))
      if (overlaps(access.range, range))
        mask.set(index);
  }
  DataFlowSolver writeSolver(DataFlowConfig().setInterprocedural(false));
  writeSolver.load<dataflow::DeadCodeAnalysis>();
  writeSolver.load<dataflow::SparseConstantPropagation>();
  writeSolver.load<MayWriteAnalysis>(writes, queryRanges.size());
  if (failed(writeSolver.initializeAndRun(source)))
    return {};

  // A rematerialized predicate observes exactly the source's control: every
  // read is a directly addressable static range unchanged from entry at its
  // original program point, proved by the dense may-write fixed point.
  // Pure, total operations only; CFG joins, calls, dynamic aliases and
  // potentially trapping arithmetic retain the ordinary certificate.
  DenseMap<Value, bool> stable;
  DenseSet<Value> active;
  auto canClone = [&](auto &&self, Value value, unsigned depth) -> bool {
    if (depth > 16)
      return false;
    if (auto known = stable.find(value); known != stable.end())
      return known->second;
    if (auto argument = dyn_cast<BlockArgument>(value))
      return argument.getOwner() == &source.getBody().front();
    if (!active.insert(value).second)
      return false;
    Operation *op = value.getDefiningOp();
    bool allowed = op && !op->getNumRegions() && !op->getNumSuccessors();
    if (allowed && isa<sim::SimRefLoadOp>(op)) {
      auto range = resolve(op->getOperand(0), true);
      auto query = readIndices.find(op);
      auto *before = writeSolver.lookupState<MayWrites>(
          writeSolver.getProgramPointBefore(op));
      allowed = range && query != readIndices.end() && before &&
                before->reachable && !before->bits.test(query->second);
    } else if (allowed && isa<sim::SimNetReadOp>(op)) {
      // Connected-net writes may update other physical roots. Until those
      // aliases enter the write lattice, do not hoist a net control read.
      allowed = false;
    } else if (allowed) {
      // Speculatable operations may still produce poison. A reconstructed
      // untaken path must not introduce poison into the Boolean path test.
      // These operations are total on their complete four-state inputs.
      allowed =
          isMemoryEffectFree(op) &&
          isa<arith::ConstantOp, arith::CmpIOp, arith::AndIOp, arith::OrIOp,
              arith::XOrIOp, arith::SelectOp, arith::ExtUIOp, arith::ExtSIOp,
              arith::TruncIOp, sim::SimContextStorageOp, sim::SimContextNetOp,
              sim::SimRefExtractOp, sim::SimRefSubelementOp,
              sim::SimLogicIsTrueOp, sim::SimLogicCompareOp,
              sim::SimLogicUnaryOp, sim::SimLogicBinaryOp,
              sim::SimLogicLogicalOp, sim::SimLogicResizeOp,
              sim::SimLogicFromBitsOp, sim::SimLogicToBitsOp,
              sim::SimLogicConstantOp, sim::SimLogicExtractOp,
              sim::SimLogicConcatOp, sim::SimLogicReductionOp,
              sim::SimPackedFlattenOp, sim::SimPackedUnflattenOp>(op);
      // A flagged integer truncation can produce poison despite being pure.
      // Preserve skipped source control (LRM 12.4/4.6): an eager Boolean AND
      // cannot mask poison from an otherwise untaken nested predicate.
      if (auto flags =
              dyn_cast<arith::ArithIntegerOverflowFlagsInterface>(op))
        allowed &= !flags.hasNoSignedWrap() && !flags.hasNoUnsignedWrap();
    }
    if (allowed)
      for (Value operand : op->getOperands())
        allowed &= self(self, operand, depth + 1);
    active.erase(value);
    stable[value] = allowed;
    return allowed;
  };

  SmallVector<Value> conditionValues;
  DenseMap<Value, unsigned> conditionIndices;
  source.walk([&](cf::CondBranchOp branch) {
    if (canClone(canClone, branch.getCondition(), 0) &&
        conditionIndices
            .try_emplace(branch.getCondition(), conditionValues.size())
            .second)
      conditionValues.push_back(branch.getCondition());
  });
  if (conditionValues.empty())
    return {};
  DataFlowSolver pathSolver(DataFlowConfig().setInterprocedural(false));
  pathSolver.load<dataflow::DeadCodeAnalysis>();
  pathSolver.load<dataflow::SparseConstantPropagation>();
  pathSolver.load<EntryPathAnalysis>(conditionIndices);
  if (failed(pathSolver.initializeAndRun(source)))
    return {};

  SmallVector<Candidate> candidates;
  auto ranges = encoded.asArrayRef();
  for (size_t i = 0; i + 1 < ranges.size(); i += 2) {
    Candidate candidate{{uint64_t(ranges[i]), uint64_t(ranges[i + 1])}, {}, {}};
    if (!candidate.range.second || candidate.range.second > 64)
      continue;
    EntryPaths needed(pathSolver.getProgramPointBefore(source.getOperation()));
    for (const Access &access : accesses) {
      if (!overlaps(access.range, candidate.range))
        continue;
      auto *paths = pathSolver.lookupState<EntryPaths>(
          pathSolver.getProgramPointBefore(access.operation));
      if (!paths) {
        (void)needed.merge(Term{});
        break;
      }
      (void)needed.join(*paths);
      if (access.range == candidate.range &&
          isa<sim::RefType, sim::NetType>(access.reference.getType()) &&
          resolve(access.reference, true))
        candidate.reference = access.reference;
    }
    if (llvm::any_of(needed.paths,
                     [](const Term &path) { return path.empty(); }))
      continue;
    for (const Term &path : needed.paths) {
      SmallVector<std::pair<Value, bool>> literals;
      for (auto [condition, when] : path)
        literals.emplace_back(conditionValues[condition], when);
      candidate.paths.push_back(std::move(literals));
    }
    if (candidate.reference && !candidate.paths.empty() &&
        canClone(canClone, candidate.reference, 0))
      candidates.push_back(std::move(candidate));
  }
  if (candidates.empty())
    return {};

  // Bound generated code independently of loop trip counts and source size.
  // The budget is an admission policy only; exceeding it retains full scans.
  uint64_t cost = 0;
  for (const Candidate &candidate : candidates) {
    DenseSet<Value> seen;
    SmallVector<Value> pending{candidate.reference};
    cost += 6;
    for (const auto &path : candidate.paths) {
      cost += 1 + 2 * path.size();
      for (auto [condition, when] : path)
        pending.push_back(condition);
    }
    while (!pending.empty()) {
      Value value = pending.pop_back_val();
      if (!seen.insert(value).second || isa<BlockArgument>(value))
        continue;
      if (++cost > 4096)
        return {};
      llvm::append_range(pending, value.getDefiningOp()->getOperands());
    }
    if (cost > 4096)
      return {};
  }

  OpBuilder builder(source.getContext());
  builder.setInsertionPointToEnd(source->getBlock());
  SmallVector<DictionaryAttr> argumentAttrs;
  for (BlockArgument argument : source.getBody().front().getArguments())
    argumentAttrs.push_back(source.getArgAttrDict(argument.getArgNumber()));
  auto probe = sim::SimFuncOp::create(
      builder, source.getLoc(), name,
      FunctionType::get(source.getContext(),
                        source.getFunctionType().getInputs(),
                        TypeRange{builder.getI1Type()}),
      sim::EntryKind::Function,
      ArrayRef<NamedAttribute>{builder.getNamedAttr(
          "code_unit_id", builder.getI64IntegerAttr(codeUnit))},
      argumentAttrs);
  symbols.insert(probe);
  SymbolTable::setSymbolVisibility(probe, SymbolTable::Visibility::Private);
  copyNativePartition(source, probe);
  schedule::set<schedule::Field::EvalBorrowedCaptures>(probe,
                                                       builder.getUnitAttr());
  schedule::set<schedule::Field::EvalPathKnownPredicate>(probe,
                                                         builder.getUnitAttr());
  Block *entry = &probe.getBody().front();
  auto mappingFor = [&] {
    IRMapping mapping;
    mapping.map(source.getBody().front().getArguments(), entry->getArguments());
    return mapping;
  };
  auto clone = [&](auto &&self, Value value, IRMapping &mapping) -> Value {
    if (Value mapped = mapping.lookupOrNull(value))
      return mapped;
    Operation *op = value.getDefiningOp();
    for (Value operand : op->getOperands())
      self(self, operand, mapping);
    builder.clone(*op, mapping);
    return mapping.lookup(value);
  };
  Block *failed = new Block;
  probe.getBody().push_back(failed);
  builder.setInsertionPointToStart(entry);
  SmallVector<int64_t> discharged;
  for (const Candidate &candidate : candidates) {
    Block *inspect = new Block, *next = new Block;
    probe.getBody().push_back(inspect);
    probe.getBody().push_back(next);
    auto mapping = mappingFor();
    Value reference = clone(clone, candidate.reference, mapping);
    Value value;
    if (auto ref = dyn_cast<sim::RefType>(reference.getType()))
      value = sim::SimRefLoadOp::create(builder, source.getLoc(),
                                        ref.getElementType(), reference);
    else
      value = sim::SimNetReadOp::create(
          builder, source.getLoc(),
          cast<sim::NetType>(reference.getType()).getElementType(), reference);
    Value known = schedule::NativeKnownValueOp::create(
        builder, source.getLoc(), builder.getI1Type(), value);
    cf::CondBranchOp::create(builder, source.getLoc(), known, next, inspect);
    builder.setInsertionPointToStart(inspect);
    mapping = mappingFor();
    Value needed = arith::ConstantIntOp::create(builder, source.getLoc(), 0, 1);
    for (const auto &path : candidate.paths) {
      Value enabled =
          arith::ConstantIntOp::create(builder, source.getLoc(), 1, 1);
      for (auto [condition, when] : path) {
        Value current = clone(clone, condition, mapping);
        if (!when)
          current = arith::XOrIOp::create(
              builder, source.getLoc(), current,
              arith::ConstantIntOp::create(builder, source.getLoc(), 1, 1));
        enabled =
            arith::AndIOp::create(builder, source.getLoc(), enabled, current);
      }
      needed = arith::OrIOp::create(builder, source.getLoc(), needed, enabled);
    }
    cf::CondBranchOp::create(builder, source.getLoc(), needed, failed, next);
    builder.setInsertionPointToStart(next);
    discharged.append(
        {int64_t(candidate.range.first), int64_t(candidate.range.second)});
  }
  // LRM 6.3.1/12.4: exact four-state controls decide which reads/stores run.
  // LRM 4.5-4.7: this fresh entry proof executes no actors or publications and
  // preserves source-order snapshots. It is never a persistent knownness bit:
  // a value-only enable change must rerun it on the next activation.
  sim::SimReturnOp::create(
      builder, source.getLoc(),
      arith::ConstantIntOp::create(builder, source.getLoc(), 1, 1).getResult());
  builder.setInsertionPointToStart(failed);
  sim::SimReturnOp::create(
      builder, source.getLoc(),
      arith::ConstantIntOp::create(builder, source.getLoc(), 0, 1).getResult());
  schedule::set<schedule::Field::EvalConditionalPromotionProbe>(
      source, FlatSymbolRefAttr::get(source.getContext(), probe.getSymName()));
  schedule::set<schedule::Field::EvalConditionalPromotionRanges>(
      source, builder.getDenseI64ArrayAttr(discharged));
  return probe;
}
} // namespace talos::detail
