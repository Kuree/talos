//===- CoalesceContinuousDrivers.cpp - Merge per-slice continuous drivers -===//
//
// A generate loop elaborates into one continuous assignment per bit or row
// (IEEE 1800-2023 27.4), and each becomes its own process with its own driver
// of one net. This pass merges the continuous-assignment processes that drive
// adjacent, disjoint static slices of one undelayed wire, each slice with one
// strong contribution (also across port-collapsed nets, 23.3.3.7), into one
// process with one driver, and turns the concatenation of their per-slice
// values into word operations when the slices are isomorphic bit lanes. A
// member that reads a collapsed alias of the run keeps its own process: the
// merged process would read those bits before it drives them. Continuous
// assignments to adjacent slices of one variable merge the same way into one
// store: each bit of a packed variable is an independent element with at
// most one continuous writer and no procedural writer (6.5), so the store
// writes exactly the bits the members would. Not under VPI mutation: a
// vpi_put_value() deposit is a write (38.34) that lasts until the next write
// of that bit (6.5, "the last write determines the value"), and a merged
// store rewrites every bit whenever any member re-evaluates.
//
// A member's body may branch, as `?:` does (11.4.11), when every operation
// that does not run on all paths is safe to evaluate eagerly. The unchosen
// operand of `?:` is not evaluated, and its "side effects or run-time errors
// ... shall not occur"; implementations may evaluate differently "as long as
// the simulation behavior (including side effects) is as if the standard
// rules were followed" (11.3.5). Such operations are pure, cannot trap and
// cannot produce poison; a read of an array element at an invalid index
// returns the default of Table 7-1 (7.4.5) without a diagnostic. The merged
// process if-converts the body: each block runs under the predicate of the
// paths that reach it, and each block argument selects the value of the edge
// taken. Exactly one path runs per activation, so the selected values are
// those the branching member computes.
//
// A four-state `c ? a : b` lane with a one-bit `c` becomes a bit of one
// logic.bitwise_mux (logic.mux when every lane has the same `c`). A lane is
// such a conditional when folding it for each of c's four values leaves `a`
// for 1, `b` for 0 and the Table 11-20 merge of `a` and `b` for X and Z,
// which is the value of `c ? a : b` (11.4.11) in each case.
//
// Semantics. Each continuous assignment re-evaluates when an operand changes
// (10.3.2). The merged process re-evaluates every member when any operand
// changes; a member whose operands did not change recomputes its old value,
// and an update that does not change a value is no update event (4.3, 4.5).
// The order of Active events is arbitrary (4.7), so running the members back
// to back, before any of their observers, is a schedule the separate
// processes can also take; reads of slices another member drives can then
// take that member's value directly. Resolution is per bit (6.6.1, 28.12):
// one strong contribution per bit resolves to itself, merged or not, and a
// value deposited by vpi_put_value() lasts until a driver of the net changes
// value, when the whole net is resolved again (38.34), which a merged driver
// does exactly when one of its members would. In-process forwarding hides a
// deposit or force on an intermediate slice, so it requires that neither can
// happen: no VPI mutation and no override of the net.
//
// Code-unit, statement and VPI declarations are kept: they describe the
// source, and VPI derives driver relations from them rather than from the
// runtime driver table. The first member's driver declaration takes the
// merged range; the others are removed so that resolution sees one
// contribution per bit.
//
//===----------------------------------------------------------------------===//

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "talos/Analysis/HandleDataflowAnalysis.h"
#include "talos/Analysis/NetConnectivityAnalysis.h"
#include "talos/Analysis/ParallelWalk.h"
#include "talos/Dialect/Native/NativeDialect.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/Simulation/SimulationTypes.h"
#include "talos/Dialect/Simulation/Transforms/Passes.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/Support/raw_ostream.h"

#include <functional>
#include <map>

using namespace mlir;

namespace talos {

#define GEN_PASS_DEF_TALOSSIMCOALESCECONTINUOUSDRIVERSPASS
#include "talos/Dialect/Simulation/Transforms/Passes.h.inc"

namespace {
namespace sim = ::talos::sim;

/// Lanes narrower than this are packed into one word per drive.
constexpr unsigned kWordBits = 64;
/// Bound on the operation tree the lane matcher explores per word.
constexpr unsigned kMaximumPlanNodes = 4096;

bool isViewOp(Operation *op) {
  return isa<sim::SimRefExtractOp, sim::SimRefSubelementOp,
             sim::SimNetExtractOp, sim::SimDriverExtractOp,
             sim::SimDriverSubelementOp>(op);
}

bool isPureValueOp(Operation &op) {
  return op.getNumResults() == 1 && op.getNumRegions() == 0 &&
         op.getNumSuccessors() == 0 && isMemoryEffectFree(&op);
}

/// Whether `op` can produce LLVM poison for some operand values: integer
/// arithmetic with overflow flags, and shifts by a non-constant or
/// out-of-range amount. Selects stop poison from the operand they do not
/// choose; the and/or forms this pass builds do not.
bool mayProducePoison(Operation *op) {
  if (auto flags = dyn_cast<arith::ArithIntegerOverflowFlagsInterface>(op))
    if (flags.getOverflowAttr().getValue() !=
        arith::IntegerOverflowFlags::none)
      return true;
  if (isa<arith::ShLIOp, arith::ShRUIOp, arith::ShRSIOp>(op)) {
    APInt amount;
    auto width = dyn_cast<IntegerType>(op->getResult(0).getType());
    return !width || !matchPattern(op->getOperand(1), m_ConstantInt(&amount)) ||
           amount.uge(width.getWidth());
  }
  return false;
}

/// No operation in the pure cone of `v` (to `depth`) can produce poison.
bool poisonFree(Value v, unsigned depth = 16) {
  Operation *def = v.getDefiningOp();
  if (!def || isa<sim::SimNetReadOp, sim::SimRefLoadOp>(def))
    return true;
  if (!depth || mayProducePoison(def) || def->getNumRegions())
    return false;
  return llvm::all_of(def->getOperands(), [&](Value operand) {
    return poisonFree(operand, depth - 1);
  });
}

/// A fixed slice of a declared net or variable.
struct Slice {
  bool net = false;
  uint64_t id = 0, low = 0, width = 0;
  bool overlaps(const Slice &o) const {
    return net == o.net && id == o.id && low < o.low + o.width &&
           o.low < low + width;
  }
  bool within(uint64_t l, uint64_t w) const {
    return low >= l && low + width <= l + w;
  }
};

std::optional<Slice> sliceOf(const analysis::HandleFacts &facts, Value v) {
  auto fact = facts.find(v);
  if (fact == facts.end() || !fact->second.descriptor || fact->second.dynamic ||
      !fact->second.width)
    return std::nullopt;
  if (fact->second.resource != schedule::ComputeResourceKind::Storage &&
      fact->second.resource != schedule::ComputeResourceKind::Net)
    return std::nullopt;
  return Slice{fact->second.resource == schedule::ComputeResourceKind::Net,
               *fact->second.descriptor, fact->second.low, fact->second.width};
}

/// The block argument a chain of static views starts from.
BlockArgument viewRoot(Value v) {
  while (Operation *def = v.getDefiningOp()) {
    if (!isViewOp(def))
      return {};
    v = def->getOperand(0);
  }
  return dyn_cast<BlockArgument>(v);
}

/// Whether a captured root is a packed four-state (true) or two-state
/// (false) value; nullopt for other roots such as unpacked arrays, whose
/// slices count padded provenance bits.
std::optional<bool> packedRootDomain(BlockArgument root) {
  Type element;
  if (auto net = dyn_cast<sim::NetType>(root.getType()))
    element = net.getElementType();
  else if (auto ref = dyn_cast<sim::RefType>(root.getType()))
    element = ref.getElementType();
  else
    return std::nullopt;
  if (isa<sim::UnpackedArrayType>(element) || !sim::getPackedWidth(element))
    return std::nullopt;
  Type scalar = sim::getPackedScalarType(element);
  if (!scalar)
    return std::nullopt;
  return isa<sim::LogicType>(scalar);
}

/// A continuous assignment process: `cf.br ^h`, then an acyclic body from
/// ^h of reads and pure operations whose last block holds the one write (a
/// net drive, or a continuous store to a variable) and suspends on change
/// back to ^h; spawned once at startup from the root initializer.
struct Member {
  sim::SimFuncOp function;
  sim::SimSpawnOp spawn;
  /// The member's only write: a net driver drive, or a continuous store to
  /// a variable (`variable`), whose value and target view these are.
  Operation *write = nullptr;
  Value writeValue, writeTarget;
  bool variable = false;
  sim::SimDriverDeclOp decl;
  sim::SimContextDriverOp contextDriver;
  unsigned driverArgument = ~0u; // none for a variable
  /// The written root (net or storage ID) and slice, and whether the written
  /// value is four-state.
  uint64_t net = 0, low = 0, width = 0;
  bool fourState = false;
  /// Body blocks in topological order: the loop header first, the block
  /// holding the write and the suspension last.
  SmallVector<Block *> blocks;

  Slice slice() const { return Slice{!variable, net, low, width}; }
  /// Reads of the member's own net, by read operation.
  SmallVector<std::pair<Operation *, Slice>> ownReads;
  /// Every read and its slice (the whole root for a dynamic selection).
  DenseMap<Operation *, Slice> readSlices;
  DenseSet<Operation *> dynamicReads;
  /// Watched handles and their slices.
  SmallVector<std::pair<Value, std::optional<Slice>>> waits;
};

/// Strips round trips through packed and domain casts that canonicalization
/// would fold: flatten(unflatten(x)) and to_bits(from_bits(x)).
Value stripCasts(Value v) {
  while (true) {
    if (auto flatten = v.getDefiningOp<sim::SimPackedFlattenOp>())
      if (auto unflatten =
              flatten.getInput().getDefiningOp<sim::SimPackedUnflattenOp>())
        if (unflatten.getInput().getType() == v.getType()) {
          v = unflatten.getInput();
          continue;
        }
    if (auto toBits = v.getDefiningOp<sim::SimLogicToBitsOp>())
      if (auto fromBits =
              toBits.getInput().getDefiningOp<sim::SimLogicFromBitsOp>())
        if (fromBits.getInput().getType() == v.getType()) {
          v = fromBits.getInput();
          continue;
        }
    return v;
  }
}

/// Operation shapes of one bit lane that become one word operation.
struct Plan {
  enum Kind {
    Leaf,      // read of a contiguous slice
    Extract,   // contiguous bits of one value
    Broadcast, // the same one-bit value in every lane
    Constant,  // constant lanes
    Bitwise,   // the same bitwise operation in every lane
    Not,       // bitwise complement in every lane
    Reduce,    // transposed reduction of gathered bits
    Select,    // two-state one-bit selects: (c & a) | (~c & b)
    ViewLeaf,  // reads at contiguous constant offsets of one view
    Mux,       // four-state `c ? a : b` in every lane
  } kind;
  unsigned width = 0; // total width
  // Leaf
  Operation *read = nullptr; // a lane read: the handle source
  uint64_t offset = 0;       // first lane's bit offset (leaf, extract)
  Value value;               // extract base, broadcast bit
  APInt bits, unknown;       // constant
  // Bitwise / Reduce
  sim::BinaryKind binary = sim::BinaryKind::And;
  SmallVector<std::unique_ptr<Plan>> children;
};

class LaneVectorizer {
public:
  LaneVectorizer(OpBuilder &builder, Location loc,
                 const DenseMap<Value, std::pair<BlockArgument, Slice>> &leaves,
                 const DenseMap<BlockArgument, uint64_t> &argumentLows)
      : builder(builder), loc(loc), leaves(leaves),
        argumentLows(argumentLows) {}

  /// The lanes (least significant first) as one value, or null.
  Value vectorize(ArrayRef<Value> lanes, unsigned laneWidth, bool fourState,
                  unsigned scalarCost) {
    nodes = 0;
    std::unique_ptr<Plan> plan = match(lanes, laneWidth, fourState);
    if (!plan || nodes > scalarCost)
      return {};
    return emit(*plan, fourState);
  }

private:
  Type flatType(unsigned width, bool fourState) {
    if (fourState)
      return sim::LogicType::get(builder.getContext(), width);
    return builder.getIntegerType(width);
  }

  static bool laneTypeOK(Value v, unsigned width, bool fourState) {
    if (fourState) {
      auto logic = dyn_cast<sim::LogicType>(v.getType());
      return logic && logic.getWidth() == width;
    }
    auto integer = dyn_cast<IntegerType>(v.getType());
    return integer && integer.getWidth() == width;
  }

  /// Equal values, or reads of the same slice of the same root: members read
  /// their operands separately, and no write separates the reads.
  bool sameValue(Value a, Value b) const {
    if (equivalent(a, b))
      return true;
    auto left = leaves.find(a), right = leaves.find(b);
    return left != leaves.end() && right != leaves.end() &&
           left->second.first == right->second.first &&
           left->second.second.net == right->second.second.net &&
           left->second.second.id == right->second.second.id &&
           left->second.second.low == right->second.second.low &&
           left->second.second.width == right->second.second.width &&
           a.getType() == b.getType();
  }

  /// A shape key used to orient commutative operands of a lane like lane 0:
  /// the root of a read, the name of another defining operation, or the
  /// value itself.
  const void *shapeKey(Value v) const {
    if (auto leaf = leaves.find(v); leaf != leaves.end())
      return leaf->second.first.getAsOpaquePointer();
    if (Operation *def = v.getDefiningOp())
      return def->getName().getAsOpaquePointer();
    return v.getAsOpaquePointer();
  }

  /// Structurally equal values: the same pure operation or read applied to
  /// equivalent operands. Merged members compute their operands separately,
  /// and in the merged body every read precedes every write, so equivalent
  /// reads observe the same state.
  static bool equivalent(Value a, Value b, unsigned depth = 8) {
    if (a == b)
      return true;
    Operation *left = a.getDefiningOp(), *right = b.getDefiningOp();
    if (!depth || !left || !right || left->getName() != right->getName() ||
        left->getAttrDictionary() != right->getAttrDictionary() ||
        left->getNumOperands() != right->getNumOperands() ||
        left->getNumRegions() || right->getNumRegions() ||
        left->getResultTypes() != right->getResultTypes() ||
        cast<OpResult>(a).getResultNumber() !=
            cast<OpResult>(b).getResultNumber() ||
        !(isMemoryEffectFree(left) ||
          isa<sim::SimNetReadOp, sim::SimRefLoadOp>(left)))
      return false;
    for (auto [x, y] : llvm::zip(left->getOperands(), right->getOperands()))
      if (!equivalent(x, y, depth - 1))
        return false;
    return true;
  }

  /// A read through constant views of a base handle: the base, the bit
  /// offset in it, and the read operation.
  static std::optional<std::pair<Value, uint64_t>> viewOffset(Value read) {
    Operation *def = read.getDefiningOp();
    if (!isa_and_nonnull<sim::SimNetReadOp, sim::SimRefLoadOp>(def))
      return std::nullopt;
    Value handle = def->getOperand(0);
    uint64_t offset = 0;
    while (Operation *view = handle.getDefiningOp()) {
      Type element;
      if (auto ref = dyn_cast<sim::RefType>(view->getOperand(0).getType()))
        element = ref.getElementType();
      else if (auto net = dyn_cast<sim::NetType>(view->getOperand(0).getType()))
        element = net.getElementType();
      if (!element || isa<sim::UnpackedArrayType>(element) ||
          !sim::getPackedWidth(element))
        break;
      if (auto sub = dyn_cast<sim::SimRefSubelementOp>(view)) {
        uint64_t local = 0;
        Type type = element;
        bool ok = true;
        for (int64_t index : sub.getIndices()) {
          auto step = sim::getAggregateProvenanceSubelement(type, index);
          if (!step) {
            ok = false;
            break;
          }
          local += step->first;
          type = sim::getAggregateElementType(type, index);
        }
        if (!ok)
          break;
        offset += local;
      } else if (auto extract = dyn_cast<sim::SimRefExtractOp>(view)) {
        offset += extract.getLowBit();
      } else if (auto extract = dyn_cast<sim::SimNetExtractOp>(view)) {
        offset += extract.getLowBit();
      } else {
        break;
      }
      handle = view->getOperand(0);
    }
    if (handle == def->getOperand(0))
      return std::nullopt;
    return std::make_pair(handle, offset);
  }

  /// Bit offset of `v` inside the flat value it was extracted from.
  static std::optional<std::pair<Value, uint64_t>>
  extractOf(Value v, bool fourState) {
    Operation *def = v.getDefiningOp();
    if (!def)
      return std::nullopt;
    if (fourState) {
      if (auto extract = dyn_cast<sim::SimLogicExtractOp>(def))
        return std::make_pair(extract.getInput(),
                              uint64_t(extract.getLowBit()));
    } else if (auto trunc = dyn_cast<arith::TruncIOp>(def)) {
      Value input = trunc.getIn();
      if (auto shift = input.getDefiningOp<arith::ShRUIOp>()) {
        APInt amount;
        if (matchPattern(shift.getRhs(), m_ConstantInt(&amount)) &&
            amount.ult(cast<IntegerType>(input.getType()).getWidth()))
          return std::make_pair(shift.getLhs(), amount.getZExtValue());
        return std::nullopt;
      }
      return std::make_pair(input, uint64_t(0));
    }
    if (auto extract = dyn_cast<sim::SimAggregateExtractOp>(def)) {
      Type type = extract.getInput().getType();
      if (!sim::getPackedWidth(type))
        return std::nullopt;
      auto sub = sim::getAggregateProvenanceSubelement(
          type, unsigned(extract.getIndex()));
      if (!sub)
        return std::nullopt;
      return std::make_pair(extract.getInput(), sub->first);
    }
    return std::nullopt;
  }

  /// The one-bit values that `v` concatenates, least significant first.
  static bool gatheredBits(Value v, bool fourState,
                           SmallVectorImpl<Value> &bits) {
    v = stripCasts(v);
    if (fourState) {
      auto concat = v.getDefiningOp<sim::SimLogicConcatOp>();
      if (!concat)
        return false;
      for (Value input : llvm::reverse(concat.getInputs())) {
        auto logic = dyn_cast<sim::LogicType>(input.getType());
        if (!logic || logic.getWidth() != 1)
          return false;
        bits.push_back(input);
      }
      return true;
    }
    // A disjoint or-tree of shifted zero-extended i1 values.
    auto integer = dyn_cast<IntegerType>(v.getType());
    if (!integer || integer.getWidth() > kWordBits)
      return false;
    SmallVector<Value> slots(integer.getWidth());
    SmallVector<Value> work{v};
    while (!work.empty()) {
      Value x = work.pop_back_val();
      if (auto orOp = x.getDefiningOp<arith::OrIOp>()) {
        work.push_back(orOp.getLhs());
        work.push_back(orOp.getRhs());
        continue;
      }
      uint64_t position = 0;
      if (auto shift = x.getDefiningOp<arith::ShLIOp>()) {
        APInt amount;
        if (!matchPattern(shift.getRhs(), m_ConstantInt(&amount)) ||
            amount.uge(integer.getWidth()))
          return false;
        position = amount.getZExtValue();
        x = shift.getLhs();
      }
      auto extend = x.getDefiningOp<arith::ExtUIOp>();
      if (!extend || !extend.getIn().getType().isInteger(1) ||
          slots[position])
        return false;
      slots[position] = stripCasts(extend.getIn());
    }
    for (Value slot : slots) {
      if (!slot)
        return false;
      bits.push_back(slot);
    }
    return true;
  }

  /// The value of a lane once its condition bit is a constant: a constant,
  /// an unchanged SSA value, or the X merge of two unchanged values.
  struct Residue {
    Attribute constant;
    Value value;
    Value left, right;
  };

  /// Folds `v` with every use of `condition` replaced by `constant`. Values
  /// that do not fold stay as they are, which is their actual value when the
  /// condition has that constant; every folded constant is so too.
  std::optional<Residue> residue(Value v, Value condition, Attribute constant,
                                 DenseMap<Value, Residue> &memo,
                                 unsigned depth) {
    if (auto found = memo.find(v); found != memo.end())
      return found->second;
    auto remember = [&](Residue r) -> std::optional<Residue> {
      memo[v] = r;
      return r;
    };
    if (sameValue(v, condition))
      return remember(Residue{constant, {}, {}, {}});
    Attribute literal;
    if (matchPattern(v, m_Constant(&literal)))
      return remember(Residue{literal, v, {}, {}});
    Operation *op = v.getDefiningOp();
    if (!op || !depth || op->getNumResults() != 1 || op->getNumRegions() ||
        !isMemoryEffectFree(op))
      return remember(Residue{{}, v, {}, {}});
    SmallVector<Residue> operands;
    bool changed = false;
    for (Value operand : op->getOperands()) {
      std::optional<Residue> r =
          residue(operand, condition, constant, memo, depth - 1);
      if (!r)
        return std::nullopt;
      changed |= r->value != operand;
      operands.push_back(*r);
    }
    if (!changed)
      return remember(Residue{{}, v, {}, {}});
    // A select on a folded predicate is the chosen operand's residue.
    if (auto select = dyn_cast<arith::SelectOp>(op))
      if (auto predicate = dyn_cast_or_null<IntegerAttr>(operands[0].constant))
        return remember(operands[predicate.getValue().isZero() ? 2 : 1]);
    // A known logic.mux condition selects an operand; an X/Z one merges
    // them (Table 11-20).
    if (isa<sim::SimLogicMuxOp>(op)) {
      auto planes = dyn_cast_or_null<ArrayAttr>(operands[0].constant);
      auto value = planes && planes.size() == 2
                       ? dyn_cast<IntegerAttr>(planes[0])
                       : IntegerAttr();
      auto unknown = planes && planes.size() == 2
                         ? dyn_cast<IntegerAttr>(planes[1])
                         : IntegerAttr();
      if (value && unknown && unknown.getValue().isZero())
        return remember(operands[value.getValue().isZero() ? 2 : 1]);
      if (unknown && operands[1].value && operands[2].value)
        return remember(Residue{{}, {}, operands[1].value, operands[2].value});
    }
    SmallVector<Attribute> attributes;
    for (Residue &r : operands) {
      if (r.left)
        return std::nullopt;
      attributes.push_back(r.constant);
    }
    // The folders read operand values only where no constant is given, so
    // they see the operation's own operands: those must be unchanged.
    for (auto [r, operand] : llvm::zip(operands, op->getOperands()))
      if (!r.constant && r.value != operand)
        return std::nullopt;
    // Fold a detached copy: Operation::fold also applies trait folds, which
    // may reorder a commutative operation's operands in place.
    Operation *copy = op->clone();
    SmallVector<OpFoldResult> results;
    bool folds = succeeded(copy->fold(attributes, results)) &&
                 results.size() == 1 &&
                 (isa<Attribute>(results.front()) ||
                  cast<Value>(results.front()) != copy->getResult(0));
    copy->destroy();
    if (!folds)
      return std::nullopt;
    if (auto folded = dyn_cast<Attribute>(results.front()))
      return remember(Residue{folded, {}, {}, {}});
    Value folded = cast<Value>(results.front());
    std::optional<Residue> r =
        residue(folded, condition, constant, memo, depth - 1);
    if (r)
      memo[v] = *r;
    return r;
  }

  /// A four-state lane that computes `c ? a : b` (11.4.11) for a one-bit
  /// `c`. The frontend branches on `c`, so that the unchosen operand is not
  /// evaluated (11.3.5), and if-conversion turns the branches into selects
  /// on predicates of `c`. Folding the lane for each of c's values 0, 1, X
  /// and Z must leave `a`, `b` and twice the merge of `a` and `b`: those are
  /// the values of logic.mux(c, a, b), and c has no other value.
  struct Conditional {
    Value condition, onTrue, onFalse;
  };
  std::optional<Conditional> conditional(Value lane) {
    // Candidate conditions: one-bit four-state reads in the lane.
    SmallVector<Value> candidates;
    SmallVector<std::pair<Value, unsigned>> work{{lane, 0}};
    DenseSet<Value> seen;
    while (!work.empty() && seen.size() < 64) {
      auto [v, depth] = work.pop_back_val();
      if (!seen.insert(v).second)
        continue;
      Operation *op = v.getDefiningOp();
      if (isa_and_nonnull<sim::SimNetReadOp, sim::SimRefLoadOp>(op)) {
        auto type = dyn_cast<sim::LogicType>(v.getType());
        Value read = v;
        if (type && type.getWidth() == 1 &&
            llvm::none_of(candidates,
                          [&](Value c) { return sameValue(c, read); }))
          candidates.push_back(read);
        continue;
      }
      if (!op || depth == 12 || !isMemoryEffectFree(op))
        continue;
      for (Value operand : op->getOperands())
        work.push_back({operand, depth + 1});
    }
    MLIRContext *context = builder.getContext();
    Type bit = builder.getIntegerType(1);
    auto planes = [&](bool value, bool unknown) -> Attribute {
      return ArrayAttr::get(context, {IntegerAttr::get(bit, value),
                                      IntegerAttr::get(bit, unknown)});
    };
    for (Value c : ArrayRef(candidates).take_front(4)) {
      std::optional<Residue> results[4];
      bool ok = true;
      for (unsigned k = 0; k < 4 && ok; ++k) {
        // 0, 1, X (unknown, value 0) and Z (unknown, value 1).
        DenseMap<Value, Residue> memo;
        results[k] = residue(lane, c, planes(k & 1, k >= 2), memo, 16);
        ok = results[k].has_value();
      }
      if (!ok)
        continue;
      Value onFalse = results[0]->left ? Value() : results[0]->value;
      Value onTrue = results[1]->left ? Value() : results[1]->value;
      auto merges = [&](const Residue &r) {
        return r.left &&
               ((sameValue(r.left, onTrue) && sameValue(r.right, onFalse)) ||
                (sameValue(r.left, onFalse) && sameValue(r.right, onTrue)));
      };
      if (onTrue && onFalse && merges(*results[2]) && merges(*results[3]))
        return Conditional{c, onTrue, onFalse};
    }
    return std::nullopt;
  }

  std::unique_ptr<Plan> make(Plan::Kind kind, unsigned width) {
    ++nodes;
    auto plan = std::make_unique<Plan>();
    plan->kind = kind;
    plan->width = width;
    return plan;
  }

  std::unique_ptr<Plan> match(ArrayRef<Value> rawLanes, unsigned w,
                              bool fourState) {
    if (nodes > kMaximumPlanNodes)
      return nullptr;
    SmallVector<Value> stripped;
    for (Value lane : rawLanes)
      stripped.push_back(stripCasts(lane));
    ArrayRef<Value> lanes = stripped;
    unsigned n = lanes.size();
    for (Value lane : lanes)
      if (!laneTypeOK(lane, w, fourState))
        return nullptr;
    // Constants.
    {
      SmallVector<APInt> values, unknowns;
      for (Value lane : lanes) {
        APInt value, unknown(w, 0);
        if (fourState) {
          auto constant = lane.getDefiningOp<sim::SimLogicConstantOp>();
          if (!constant)
            break;
          value = constant.getValue();
          unknown = constant.getUnknown();
        } else if (!matchPattern(lane, m_ConstantInt(&value))) {
          break;
        }
        values.push_back(value);
        unknowns.push_back(unknown);
      }
      if (values.size() == n) {
        auto plan = make(Plan::Constant, n * w);
        plan->bits = APInt(n * w, 0);
        plan->unknown = APInt(n * w, 0);
        for (unsigned k = 0; k < n; ++k) {
          plan->bits.insertBits(values[k], k * w);
          plan->unknown.insertBits(unknowns[k], k * w);
        }
        return plan;
      }
    }
    // One bit in every lane.
    if (w == 1 && llvm::all_of(lanes, [&](Value lane) {
          return sameValue(lane, lanes.front());
        })) {
      auto plan = make(Plan::Broadcast, n);
      plan->value = lanes.front();
      return plan;
    }
    // Reads of a contiguous slice.
    {
      auto first = leaves.find(lanes.front());
      if (first != leaves.end()) {
        bool contiguous = true;
        for (unsigned k = 1; k < n && contiguous; ++k) {
          auto leaf = leaves.find(lanes[k]);
          contiguous = leaf != leaves.end() &&
                       leaf->second.first == first->second.first &&
                       leaf->second.second.net == first->second.second.net &&
                       leaf->second.second.id == first->second.second.id &&
                       leaf->second.second.low ==
                           first->second.second.low + k * w;
        }
        if (contiguous) {
          auto plan = make(Plan::Leaf, n * w);
          plan->read = lanes.front().getDefiningOp();
          plan->offset = first->second.second.low;
          return plan;
        }
      }
    }
    // Reads at contiguous constant offsets of one (possibly dynamic) view,
    // such as the bits of an array element at a run-time index: the bits of
    // one element read (7.4.5) are its bit-selects (11.5.1), including the
    // default element of an invalid index.
    if (auto first = viewOffset(lanes.front())) {
      bool contiguous = true;
      for (unsigned k = 1; k < n && contiguous; ++k) {
        auto other = viewOffset(lanes[k]);
        contiguous = other && equivalent(other->first, first->first) &&
                     other->second == first->second + k * w;
      }
      if (contiguous) {
        auto plan = make(Plan::ViewLeaf, n * w);
        plan->value = first->first;
        plan->offset = first->second;
        return plan;
      }
    }
    // Contiguous bits of one value.
    if (auto first = extractOf(lanes.front(), fourState)) {
      bool contiguous = true;
      for (unsigned k = 1; k < n && contiguous; ++k) {
        auto other = extractOf(lanes[k], fourState);
        contiguous = other && sameValue(other->first, first->first) &&
                     other->second == first->second + k * w;
      }
      auto width = sim::getPackedWidth(first->first.getType());
      // No new shifts of integers wider than i128 (native lowering limit).
      if (contiguous && width && *width <= 128 &&
          first->second + n * w <= *width) {
        auto plan = make(Plan::Extract, n * w);
        plan->value = first->first;
        plan->offset = first->second;
        return plan;
      }
    }
    // Four-state `?:` lanes: one logic.mux for a common condition, else a
    // per-bit one.
    if (fourState) {
      SmallVector<Value> conditions, trues, falses;
      for (Value lane : lanes) {
        std::optional<Conditional> parts = conditional(lane);
        if (!parts)
          break;
        conditions.push_back(parts->condition);
        trues.push_back(parts->onTrue);
        falses.push_back(parts->onFalse);
      }
      if (conditions.size() == n) {
        unsigned before = nodes;
        auto condition = match(conditions, 1, fourState);
        bool common = condition && condition->kind == Plan::Broadcast;
        auto onTrue = condition && (common || w == 1)
                          ? match(trues, w, fourState)
                          : nullptr;
        auto onFalse = onTrue ? match(falses, w, fourState) : nullptr;
        // The and/or lowering evaluates both operands.
        if (onFalse && poisonFreePlan(*onTrue) && poisonFreePlan(*onFalse)) {
          auto plan = make(Plan::Mux, n * w);
          plan->children.push_back(std::move(condition));
          plan->children.push_back(std::move(onTrue));
          plan->children.push_back(std::move(onFalse));
          return plan;
        }
        nodes = before;
      }
    }
    Operation *head = lanes.front().getDefiningOp();
    if (!head)
      return nullptr;
    auto sameName = [&](Operation *op) {
      return op && op->getName() == head->getName() &&
             op->getAttrDictionary() == head->getAttrDictionary();
    };
    for (Value lane : lanes)
      if (!sameName(lane.getDefiningOp()))
        return nullptr;
    // Bitwise operations, operand lanes in place or commuted.
    auto bitwise = [&](sim::BinaryKind kind) -> std::unique_ptr<Plan> {
      for (bool swap : {false, true}) {
        // Lane 0 fixes the orientation (swapped on the second attempt);
        // every other lane is oriented to match lane 0's operand shapes.
        Operation *zero = lanes.front().getDefiningOp();
        Value left0 = zero->getOperand(swap ? 1 : 0);
        Value right0 = zero->getOperand(swap ? 0 : 1);
        SmallVector<Value> lhs, rhs;
        for (Value lane : lanes) {
          Operation *op = lane.getDefiningOp();
          Value a = op->getOperand(0), b = op->getOperand(1);
          bool keep = (sameValue(a, left0) || sameValue(b, right0)) ||
                      (shapeKey(a) == shapeKey(left0) &&
                       shapeKey(b) == shapeKey(right0));
          bool flip = (sameValue(b, left0) || sameValue(a, right0)) ||
                      (shapeKey(b) == shapeKey(left0) &&
                       shapeKey(a) == shapeKey(right0));
          if (!keep && flip)
            std::swap(a, b);
          lhs.push_back(a);
          rhs.push_back(b);
        }
        unsigned before = nodes;
        auto left = match(lhs, w, fourState);
        auto right = left ? match(rhs, w, fourState) : nullptr;
        if (left && right) {
          auto plan = make(Plan::Bitwise, n * w);
          plan->binary = kind;
          plan->children.push_back(std::move(left));
          plan->children.push_back(std::move(right));
          return plan;
        }
        nodes = before;
      }
      return nullptr;
    };
    if (fourState) {
      if (auto binary = dyn_cast<sim::SimLogicBinaryOp>(head)) {
        sim::BinaryKind kind = binary.getKind();
        if (kind == sim::BinaryKind::And || kind == sim::BinaryKind::Or ||
            kind == sim::BinaryKind::Xor || kind == sim::BinaryKind::Xnor)
          return bitwise(kind);
        return nullptr;
      }
      if (auto unary = dyn_cast<sim::SimLogicUnaryOp>(head)) {
        if (unary.getKind() != sim::UnaryKind::BitNot)
          return nullptr;
        SmallVector<Value> inputs;
        for (Value lane : lanes)
          inputs.push_back(lane.getDefiningOp()->getOperand(0));
        auto child = match(inputs, w, fourState);
        if (!child)
          return nullptr;
        auto plan = make(Plan::Not, n * w);
        plan->children.push_back(std::move(child));
        return plan;
      }
      if (auto reduction = dyn_cast<sim::SimLogicReductionOp>(head)) {
        sim::ReductionKind kind = reduction.getKind();
        sim::BinaryKind binary;
        if (kind == sim::ReductionKind::Or)
          binary = sim::BinaryKind::Or;
        else if (kind == sim::ReductionKind::And)
          binary = sim::BinaryKind::And;
        else if (kind == sim::ReductionKind::Xor)
          binary = sim::BinaryKind::Xor;
        else
          return nullptr;
        return reduce(lanes, binary, fourState, [](Operation *op) {
          return op->getOperand(0);
        });
      }
      return nullptr;
    }
    if (isa<arith::AndIOp>(head))
      return bitwise(sim::BinaryKind::And);
    if (isa<arith::OrIOp>(head))
      return bitwise(sim::BinaryKind::Or);
    if (isa<arith::XOrIOp>(head))
      return bitwise(sim::BinaryKind::Xor);
    if (isa<arith::SelectOp>(head)) {
      // For bits in {0, 1}, c ? a : b (11.4.11) equals (c & a) | (~c & b)
      // by Tables 11-11, 11-12 and 11-15. A four-state condition instead
      // merges X/Z per bit (Table 11-20), so four-state selects stay.
      if (w != 1)
        return nullptr;
      SmallVector<Value> conditions, trues, falses;
      for (Value lane : lanes) {
        Operation *op = lane.getDefiningOp();
        conditions.push_back(op->getOperand(0));
        trues.push_back(op->getOperand(1));
        falses.push_back(op->getOperand(2));
      }
      auto condition = match(conditions, 1, fourState);
      auto onTrue = condition ? match(trues, 1, fourState) : nullptr;
      auto onFalse = onTrue ? match(falses, 1, fourState) : nullptr;
      // The and/or form evaluates both operands: they must not carry
      // poison the select would have discarded.
      if (!onFalse || !poisonFreePlan(*onTrue) || !poisonFreePlan(*onFalse))
        return nullptr;
      auto plan = make(Plan::Select, n);
      plan->children.push_back(std::move(condition));
      plan->children.push_back(std::move(onTrue));
      plan->children.push_back(std::move(onFalse));
      return plan;
    }
    if (auto compare = dyn_cast<arith::CmpIOp>(head)) {
      // `x != 0` is the OR and `x == ~0` the AND of x's bits (11.4.9).
      auto predicate = compare.getPredicate();
      if (predicate != arith::CmpIPredicate::ne &&
          predicate != arith::CmpIPredicate::eq)
        return nullptr;
      for (Value lane : lanes) {
        auto other = lane.getDefiningOp<arith::CmpIOp>();
        APInt constant;
        if (!matchPattern(other.getRhs(), m_ConstantInt(&constant)) ||
            !(predicate == arith::CmpIPredicate::ne ? constant.isZero()
                                                    : constant.isAllOnes()))
          return nullptr;
      }
      sim::BinaryKind kind = predicate == arith::CmpIPredicate::ne
                                 ? sim::BinaryKind::Or
                                 : sim::BinaryKind::And;
      return reduce(lanes, kind, fourState,
                    [](Operation *op) { return op->getOperand(0); });
    }
    return nullptr;
  }

  /// The values a plan uses directly (broadcast bits, extract bases) are
  /// free of poison; reads, constants and bitwise combinations add none.
  static bool poisonFreePlan(const Plan &plan) {
    if ((plan.kind == Plan::Broadcast || plan.kind == Plan::Extract) &&
        !poisonFree(plan.value))
      return false;
    return llvm::all_of(plan.children, [](const std::unique_ptr<Plan> &child) {
      return poisonFreePlan(*child);
    });
  }

  /// Lane k reduces the bits b(k, 0..J-1) with `kind`; the word is the
  /// `kind` of the J transposed lane vectors.
  std::unique_ptr<Plan> reduce(ArrayRef<Value> lanes, sim::BinaryKind kind,
                               bool fourState,
                               function_ref<Value(Operation *)> gathered) {
    unsigned n = lanes.size();
    SmallVector<SmallVector<Value>> bits(n);
    for (unsigned k = 0; k < n; ++k)
      if (!gatheredBits(gathered(lanes[k].getDefiningOp()), fourState,
                        bits[k]) ||
          bits[k].size() != bits.front().size())
        return nullptr;
    unsigned count = bits.front().size();
    // A reduction of one four-state bit turns z into x (11.4.9); the bit
    // itself would not.
    if (!count || (fourState && count < 2))
      return nullptr;
    auto plan = make(Plan::Reduce, n);
    plan->binary = kind;
    for (unsigned j = 0; j < count; ++j) {
      SmallVector<Value> column;
      for (unsigned k = 0; k < n; ++k)
        column.push_back(bits[k][j]);
      auto child = match(column, 1, fourState);
      if (!child)
        return nullptr;
      plan->children.push_back(std::move(child));
    }
    return plan;
  }

  Value binaryOp(sim::BinaryKind kind, Value lhs, Value rhs, bool fourState) {
    if (fourState)
      return sim::SimLogicBinaryOp::create(builder, loc, lhs.getType(), kind,
                                           lhs, rhs);
    switch (kind) {
    case sim::BinaryKind::And:
      return arith::AndIOp::create(builder, loc, lhs, rhs);
    case sim::BinaryKind::Or:
      return arith::OrIOp::create(builder, loc, lhs, rhs);
    case sim::BinaryKind::Xor:
      return arith::XOrIOp::create(builder, loc, lhs, rhs);
    default:
      llvm_unreachable("two-state lanes use and/or/xor");
    }
  }

  Value flat(Value v) {
    Type scalar = sim::getPackedScalarType(v.getType());
    if (v.getType() == scalar)
      return v;
    return sim::SimPackedFlattenOp::create(builder, loc, scalar, v);
  }

  Value emit(Plan &plan, bool fourState) {
    Type type = flatType(plan.width, fourState);
    switch (plan.kind) {
    case Plan::Leaf: {
      Operation *read = plan.read;
      auto leaf = leaves.lookup(read->getResult(0));
      BlockArgument root = leaf.first;
      uint64_t low = plan.offset - argumentLows.lookup(root);
      Value view;
      if (auto net = dyn_cast<sim::NetType>(root.getType())) {
        view = sim::SimNetExtractOp::create(
            builder, loc, sim::NetType::get(builder.getContext(), type), root,
            low);
        return sim::SimNetReadOp::create(builder, loc, type, view);
      }
      view = sim::SimRefExtractOp::create(
          builder, loc, sim::RefType::get(builder.getContext(), type), root,
          low);
      return sim::SimRefLoadOp::create(builder, loc, type, view);
    }
    case Plan::ViewLeaf: {
      Value base = plan.value;
      if (isa<sim::NetType>(base.getType())) {
        Value view = sim::SimNetExtractOp::create(
            builder, loc, sim::NetType::get(builder.getContext(), type), base,
            plan.offset);
        return sim::SimNetReadOp::create(builder, loc, type, view);
      }
      Value view = sim::SimRefExtractOp::create(
          builder, loc, sim::RefType::get(builder.getContext(), type), base,
          plan.offset);
      return sim::SimRefLoadOp::create(builder, loc, type, view);
    }
    case Plan::Extract: {
      Value base = flat(plan.value);
      if (fourState)
        return sim::SimLogicExtractOp::create(builder, loc, type, base,
                                              plan.offset);
      if (plan.offset) {
        Value shift = arith::ConstantOp::create(
            builder, loc, base.getType(),
            builder.getIntegerAttr(base.getType(), plan.offset));
        base = arith::ShRUIOp::create(builder, loc, base, shift);
      }
      if (base.getType() != type)
        base = arith::TruncIOp::create(builder, loc, type, base);
      return base;
    }
    case Plan::Broadcast:
      if (fourState)
        return sim::SimLogicReplicateOp::create(builder, loc, type, plan.value,
                                                plan.width);
      // Sign extension of one bit repeats it (11.4.12.1).
      return arith::ExtSIOp::create(builder, loc, type, plan.value);
    case Plan::Constant:
      if (fourState)
        return sim::SimLogicConstantOp::create(
            builder, loc, type,
            builder.getIntegerAttr(builder.getIntegerType(plan.width),
                                   plan.bits),
            builder.getIntegerAttr(builder.getIntegerType(plan.width),
                                   plan.unknown));
      return arith::ConstantOp::create(builder, loc, type,
                                       builder.getIntegerAttr(type, plan.bits));
    case Plan::Bitwise:
      return binaryOp(plan.binary, emit(*plan.children[0], fourState),
                      emit(*plan.children[1], fourState), fourState);
    case Plan::Not:
      return sim::SimLogicUnaryOp::create(builder, loc, type,
                                          sim::UnaryKind::BitNot,
                                          emit(*plan.children[0], fourState));
    case Plan::Mux: {
      Value onTrue = emit(*plan.children[1], fourState);
      Value onFalse = emit(*plan.children[2], fourState);
      if (plan.children[0]->kind == Plan::Broadcast)
        return sim::SimLogicMuxOp::create(
            builder, loc, type, plan.children[0]->value, onTrue, onFalse);
      return sim::SimLogicBitwiseMuxOp::create(
          builder, loc, type, emit(*plan.children[0], fourState), onTrue,
          onFalse);
    }
    case Plan::Select: {
      Value condition = emit(*plan.children[0], fourState);
      Value onTrue = emit(*plan.children[1], fourState);
      Value onFalse = emit(*plan.children[2], fourState);
      Value ones = arith::ConstantOp::create(
          builder, loc, type,
          builder.getIntegerAttr(type, APInt::getAllOnes(plan.width)));
      Value inverse = arith::XOrIOp::create(builder, loc, condition, ones);
      return arith::OrIOp::create(
          builder, loc, arith::AndIOp::create(builder, loc, condition, onTrue),
          arith::AndIOp::create(builder, loc, inverse, onFalse));
    }
    case Plan::Reduce: {
      Value result;
      for (auto &child : plan.children) {
        Value column = emit(*child, fourState);
        result = result ? binaryOp(plan.binary, result, column, fourState)
                        : column;
      }
      return result;
    }
    }
    llvm_unreachable("unknown plan");
  }

  OpBuilder &builder;
  Location loc;
  const DenseMap<Value, std::pair<BlockArgument, Slice>> &leaves;
  const DenseMap<BlockArgument, uint64_t> &argumentLows;
  unsigned nodes = 0;
};

/// Operations that only lane `v` uses, up to `limit`: the scalar code a
/// word replaces.
unsigned exclusiveCone(Value v, unsigned limit) {
  unsigned count = 0;
  SmallVector<Value> work{v};
  DenseSet<Operation *> seen;
  while (!work.empty() && count < limit) {
    Value value = work.pop_back_val();
    Operation *def = value.getDefiningOp();
    if (!def || def->getNumResults() != 1 ||
        !(value == v ? def->getResult(0).hasOneUse() ||
                           def->getResult(0).use_empty()
                     : def->getResult(0).hasOneUse()) ||
        def->getNumRegions() || !seen.insert(def).second)
      continue;
    ++count;
    for (Value operand : def->getOperands())
      work.push_back(operand);
  }
  return count;
}

class TalosSimCoalesceContinuousDriversPass
    : public impl::TalosSimCoalesceContinuousDriversPassBase<
          TalosSimCoalesceContinuousDriversPass> {
public:
  using Base::Base;

private:
  void runOnOperation() override;
  std::optional<Member> match(sim::SimFuncOp function,
                              const analysis::HandleFacts &facts,
                              std::string &why);
  void merge(sim::SimDesignOp design, ArrayRef<Member *> run,
             const DenseMap<Operation *, analysis::HandleFacts> &facts,
             bool forwarding, SymbolTable &symbols);
  void compactDriverIds(sim::SimDesignOp design);

  DenseMap<uint64_t, sim::SimDriverDeclOp> driverDecls;
  DenseMap<uint64_t, unsigned> contextDriverCount;
  DenseSet<uint64_t> namedDrivers;
  llvm::StringMap<SmallVector<Operation *, 1>> usersOf;
  /// Driver IDs whose declarations were merged away.
  SmallVector<uint64_t> freedDrivers;
};

std::optional<Member>
TalosSimCoalesceContinuousDriversPass::match(sim::SimFuncOp function,
                                             const analysis::HandleFacts &facts,
                                             std::string &why) {
  if (function.isExternal() || !function.isPrivate() ||
      function.getHomeRegion() != sim::EventRegion::Active ||
      function.getEntryKind() != sim::EntryKind::Continuous ||
      function.getBody().getBlocks().size() < 2) {
    why = "shape";
    return std::nullopt;
  }
  for (NamedAttribute attr : function->getAttrs()) {
    StringRef name = attr.getName().getValue();
    // Delayed continuous assignments (10.3.3) schedule each update.
    if (name.contains("primitive") || name.contains("timing") ||
        name.contains("path") || name.contains("pulse") ||
        name.contains("propagation_delays")) {
      why = "special process";
      return std::nullopt;
    }
  }
  Block &entry = function.getBody().front();
  auto branch = dyn_cast<cf::BranchOp>(entry.getTerminator());
  if (!branch || !branch.getDestOperands().empty() ||
      branch.getDest()->getNumArguments()) {
    why = "entry";
    return std::nullopt;
  }
  Block *header = branch.getDest();
  for (Operation &op : entry.without_terminator())
    if (!isViewOp(&op) && !isPureValueOp(op)) {
      why = "entry op";
      return std::nullopt;
    }
  Member member;
  member.function = function;
  // The body: an acyclic CFG of plain branches from the header to the one
  // block that suspends back to it (topological order, Kahn).
  Block *exit = nullptr;
  {
    DenseMap<Block *, unsigned> incoming;
    for (Block &block : function.getBody()) {
      if (&block == &entry)
        continue;
      Operation *terminator = block.getTerminator();
      if (isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp>(terminator)) {
        if (exit) {
          why = "exits";
          return std::nullopt;
        }
        exit = &block;
        continue;
      }
      if (!isa<cf::BranchOp, cf::CondBranchOp>(terminator)) {
        why = "terminator";
        return std::nullopt;
      }
      for (Block *successor : block.getSuccessors()) {
        if (successor == header || successor == &entry) {
          why = "loop";
          return std::nullopt;
        }
        ++incoming[successor];
      }
    }
    if (!exit || incoming.count(header)) {
      why = "body";
      return std::nullopt;
    }
    SmallVector<Block *> ready{header};
    while (!ready.empty()) {
      Block *block = ready.pop_back_val();
      member.blocks.push_back(block);
      if (block == exit)
        continue;
      for (Block *successor : block->getSuccessors())
        if (--incoming[successor] == 0)
          ready.push_back(successor);
    }
    if (member.blocks.size() + 1 != function.getBody().getBlocks().size() ||
        member.blocks.back() != exit) {
      why = "cfg";
      return std::nullopt;
    }
  }
  int driverArgument = -1;
  for (unsigned i = 0; i < entry.getNumArguments(); ++i) {
    auto kind = function.getArgAttrOfType<IntegerAttr>(
        i, sim::metadata::CaptureKind::getNameStr());
    if (!kind) {
      why = "capture";
      return std::nullopt;
    }
    if (DictionaryAttr attrs = function.getArgAttrDict(i))
      for (NamedAttribute attr : attrs)
        if (attr.getName() != sim::metadata::CaptureKind::getNameStr() &&
            attr.getName() != sim::metadata::DescriptorId::getNameStr()) {
          why = "capture view";
          return std::nullopt;
        }
    switch (sim::CaptureKind(kind.getInt())) {
    case sim::CaptureKind::Context:
    case sim::CaptureKind::Storage:
    case sim::CaptureKind::Net:
      break;
    case sim::CaptureKind::Driver:
      if (driverArgument >= 0) {
        why = "drivers";
        return std::nullopt;
      }
      driverArgument = int(i);
      break;
    default:
      why = "capture";
      return std::nullopt;
    }
  }
  // Every block but the header and the exit runs only on some paths, so its
  // operations must be safe to speculate: 11.4.11 evaluates only the chosen
  // operand, and evaluating the other is allowed only when it has no side
  // effect and no run-time error (11.3.5). Array element reads at an invalid
  // index yield the Table 7-1 default (7.4.5).
  bool converted = member.blocks.size() > 1;
  for (Block *block : member.blocks) {
    bool always = block == header || block == exit;
    // If-conversion selects among values, never among handles.
    if (llvm::any_of(block->getArgumentTypes(), [](Type type) {
          return isa<sim::RefType, sim::NetType, sim::DriverType>(type);
        })) {
      why = "handle argument";
      return std::nullopt;
    }
    for (Operation &op : block->without_terminator()) {
      if (isViewOp(&op) || isa<sim::SimRefArrayElementOp>(op))
        continue;
      if (isa<sim::SimNetReadOp, sim::SimRefLoadOp>(op)) {
        std::optional<Slice> slice = sliceOf(facts, op.getOperand(0));
        if (!slice) {
          // A dynamic selection (an array element at a run-time index)
          // reads somewhere in its root: model it as the whole root.
          auto fact = facts.find(op.getOperand(0));
          if (fact == facts.end() || !fact->second.descriptor ||
              (fact->second.resource !=
                   schedule::ComputeResourceKind::Storage &&
               fact->second.resource != schedule::ComputeResourceKind::Net)) {
            why = "read";
            return std::nullopt;
          }
          slice = Slice{fact->second.resource ==
                            schedule::ComputeResourceKind::Net,
                        *fact->second.descriptor, 0, UINT64_MAX / 2};
          member.dynamicReads.insert(&op);
        } else if (!viewRoot(op.getOperand(0))) {
          why = "read";
          return std::nullopt;
        }
        member.readSlices[&op] = *slice;
        continue;
      }
      bool store = isa<sim::SimRefStoreOp>(op) &&
                   sim::has<sim::metadata::ContinuousStore>(&op);
      if (isa<sim::SimDriverDriveOp>(op) || store) {
        if (member.write || block != exit) {
          why = "writes";
          return std::nullopt;
        }
        member.write = &op;
        member.variable = store;
        member.writeValue = op.getOperand(store ? 0 : 1);
        member.writeTarget = op.getOperand(store ? 1 : 0);
        continue;
      }
      // Speculated operations must not trap (division) or produce poison
      // that the predicates, an eager and/or, would not stop.
      if (!isPureValueOp(op) || (!always && !isPure(&op)) ||
          (converted && mayProducePoison(&op))) {
        why = "op";
        return std::nullopt;
      }
    }
  }
  if (!member.write) {
    why = "no write";
    return std::nullopt;
  }
  std::optional<Slice> target = sliceOf(facts, member.writeTarget);
  auto valueWidth = sim::getPackedWidth(member.writeValue.getType());
  BlockArgument root = viewRoot(member.writeTarget);
  if (!target || target->net == member.variable || !valueWidth ||
      *valueWidth != target->width || !root || root.getOwner() != &entry) {
    why = "write slice";
    return std::nullopt;
  }
  if (!member.variable) {
    // The drive is the only use of the driver capture.
    if (driverArgument < 0 || root != entry.getArgument(driverArgument)) {
      why = "drive target";
      return std::nullopt;
    }
    member.driverArgument = unsigned(driverArgument);
    SmallVector<Value> work{root};
    while (!work.empty()) {
      Value v = work.pop_back_val();
      for (Operation *user : v.getUsers()) {
        if (user == member.write)
          continue;
        if (!isViewOp(user)) {
          why = "driver use";
          return std::nullopt;
        }
        work.push_back(user->getResult(0));
      }
    }
  } else if (driverArgument >= 0) {
    why = "drivers";
    return std::nullopt;
  }
  member.net = target->id;
  member.low = target->low;
  member.width = target->width;
  member.fourState = isa<sim::LogicType>(
      sim::getPackedScalarType(member.writeValue.getType()));
  for (auto [op, slice] : member.readSlices)
    if (slice.net != member.variable && slice.id == member.net)
      member.ownReads.push_back({op, slice});
  // Change waits only (10.3.2): edges and qualifiers keep the process.
  Operation *terminator = exit->getTerminator();
  SmallVector<Value> watched;
  if (auto wait = dyn_cast<sim::SimSuspendChangeOp>(terminator)) {
    if (wait.getContinuation() != header ||
        !wait.getContinuationOperands().empty()) {
      why = "wait";
      return std::nullopt;
    }
    watched.push_back(wait.getWatched());
  } else if (auto wait = dyn_cast<sim::SimSuspendAnyOp>(terminator)) {
    if (wait.getContinuation() != header || wait.getResumeRegionAttr() ||
        llvm::any_of(wait.getEdges(), [](int32_t edge) { return edge != 0; }) ||
        wait.getValues().size() != wait.getEdges().size()) {
      why = "wait";
      return std::nullopt;
    }
    llvm::append_range(watched, wait.getValues());
  } else {
    why = "wait";
    return std::nullopt;
  }
  for (Value v : watched)
    member.waits.push_back({v, sliceOf(facts, v)});
  // Spawned once, unconditionally, by a root initializer.
  auto users = usersOf.find(function.getSymName());
  if (users == usersOf.end() || users->second.size() != 1) {
    why = "users";
    return std::nullopt;
  }
  member.spawn = dyn_cast<sim::SimSpawnOp>(users->second.front());
  auto parent = member.spawn
                    ? member.spawn->getParentOfType<sim::SimFuncOp>()
                    : sim::SimFuncOp();
  if (!member.spawn || member.spawn.getCallee() != function.getSymName() ||
      !parent || parent.getEntryKind() != sim::EntryKind::RootInitializer ||
      member.spawn->getBlock() != &parent.getBody().front() ||
      member.spawn.getOperands().size() != entry.getNumArguments() ||
      !member.spawn.getProcess().use_empty() ||
      member.spawn.getArgAttrsAttr() || member.spawn.getResAttrsAttr() ||
      member.spawn->getAttrDictionary().size() != 1) {
    why = "spawn";
    return std::nullopt;
  }
  if (member.variable)
    return member;
  member.contextDriver =
      member.spawn.getOperands()[member.driverArgument]
          .getDefiningOp<sim::SimContextDriverOp>();
  auto descriptor = function.getArgAttrOfType<IntegerAttr>(
      member.driverArgument, sim::metadata::DescriptorId::getNameStr());
  if (!member.contextDriver || !descriptor ||
      uint64_t(member.contextDriver.getId()) !=
          descriptor.getValue().getZExtValue() ||
      !member.contextDriver->hasOneUse() ||
      contextDriverCount.lookup(member.contextDriver.getId()) != 1 ||
      namedDrivers.contains(member.contextDriver.getId())) {
    why = "driver handle";
    return std::nullopt;
  }
  member.decl = driverDecls.lookup(member.contextDriver.getId());
  if (!member.decl || uint64_t(member.decl.getNetId()) != member.net ||
      member.decl.getStrength0() != sim::Strength::Strong ||
      member.decl.getStrength1() != sim::Strength::Strong ||
      member.decl.getLifetime() != sim::Lifetime::Design ||
      !member.decl.getDrivenWidth() || !member.decl.getDrivenLow() ||
      *member.decl.getDrivenLow() != member.low ||
      *member.decl.getDrivenWidth() != member.width) {
    why = "driver declaration";
    return std::nullopt;
  }
  return member;
}

/// Source rewrites must precede frozen scheduling (see ForwardCopyProcesses).
bool hasFrozenSchedule(sim::SimDesignOp design) {
  if (design.getComputeGraphAttr())
    return true;
  return design
      .walk([&](Operation *op) {
        if (auto function = dyn_cast<sim::SimFuncOp>(op))
          if (function.getEffectSummaryAttr() || function.getFragmentAbiAttr())
            return WalkResult::interrupt();
        if (schedule::has<schedule::Field::ComputeKernels>(op) ||
            schedule::has<schedule::Field::StaticBodyFusion>(op) ||
            schedule::has<schedule::Field::StaticFusion>(op))
          return WalkResult::interrupt();
        return WalkResult::advance();
      })
      .wasInterrupted();
}

void TalosSimCoalesceContinuousDriversPass::merge(
    sim::SimDesignOp design, ArrayRef<Member *> run,
    const DenseMap<Operation *, analysis::HandleFacts> &facts,
    bool forwarding, SymbolTable &symbols) {
  MLIRContext *context = design.getContext();
  Member &first = *run.front();
  sim::SimFuncOp head = first.function;
  Location loc = head.getLoc();
  uint64_t runLow = first.low;
  uint64_t runWidth = run.back()->low + run.back()->width - runLow;
  bool fourState = isa<sim::LogicType>(
      sim::getPackedScalarType(first.writeValue.getType()));

  // Captures, deduplicated by the spawn operand, and whole declared roots by
  // their context handle's kind and ID (each spawn has its own handle op).
  DenseMap<Value, unsigned> captureOf; // spawn operand -> argument
  std::map<std::pair<int, uint64_t>, unsigned> rootCapture;
  SmallVector<Value> captureOperands;
  SmallVector<Type> types;
  SmallVector<DictionaryAttr> argAttrs;
  auto rootKey = [](Value operand) -> std::optional<std::pair<int, uint64_t>> {
    if (auto handle = operand.getDefiningOp<sim::SimContextNetOp>())
      return std::make_pair(0, uint64_t(handle.getId()));
    if (auto handle = operand.getDefiningOp<sim::SimContextStorageOp>())
      return std::make_pair(1, uint64_t(handle.getId()));
    return std::nullopt;
  };
  auto capture = [&](Member &m, unsigned i) {
    Value operand = m.spawn.getOperands()[i];
    if (auto found = captureOf.find(operand); found != captureOf.end())
      return found->second;
    std::optional<std::pair<int, uint64_t>> key = rootKey(operand);
    if (key)
      if (auto found = rootCapture.find(*key); found != rootCapture.end()) {
        captureOf[operand] = found->second;
        return found->second;
      }
    unsigned index = types.size();
    captureOf[operand] = index;
    if (key)
      rootCapture[*key] = index;
    captureOperands.push_back(operand);
    types.push_back(operand.getType());
    argAttrs.push_back(m.function.getArgAttrDict(i)
                           ? m.function.getArgAttrDict(i)
                           : DictionaryAttr::get(context));
    return index;
  };
  // Context first; dead captures are dropped.
  for (Member *m : run) {
    Block &memberEntry = m->function.getBody().front();
    for (unsigned i = 0; i < m->spawn.getOperands().size(); ++i) {
      bool isContext =
          isa<sim::ContextType>(memberEntry.getArgument(i).getType());
      if ((m == &first && (i == m->driverArgument || isContext)) ||
          (i != m->driverArgument && !memberEntry.getArgument(i).use_empty()))
        capture(*m, i);
    }
  }

  // The merged function keeps the first member's attributes, except its
  // argument bindings, which name arguments by index.
  SmallVector<NamedAttribute> attrs;
  for (NamedAttribute attr : head->getAttrs())
    if (attr.getName() != SymbolTable::getSymbolAttrName() &&
        attr.getName() != head.getFunctionTypeAttrName() &&
        attr.getName() != head.getArgAttrsAttrName() &&
        attr.getName() != head.getResAttrsAttrName() &&
        attr.getName() != head.getEntryKindAttrName() &&
        attr.getName() != sim::metadata::Bindings::getNameStr())
      attrs.push_back(attr);
  // Every member's bindings, rebased onto the merged captures. A binding of
  // an argument the merged function does not capture is dropped, and the
  // first binding of each argument and of each source path is kept (one
  // provider per path and per argument).
  SmallVector<Attribute> bindings;
  // (path, role): Direct, FormalLocal, constant, descriptor and local
  // bindings all provide the path's value; the other kinds have own roles.
  llvm::DenseSet<std::pair<Attribute, unsigned>> boundPaths;
  llvm::DenseSet<uint64_t> boundArguments;
  constexpr unsigned kProvider = ~0u;
  for (Member *m : run) {
    ArrayAttr memberBindings = sim::get<sim::metadata::Bindings>(m->function);
    if (!memberBindings)
      continue;
    for (Attribute attr : memberBindings) {
      Attribute path;
      unsigned role = kProvider;
      std::optional<uint64_t> bound;
      if (auto argument = dyn_cast<sim::ArgumentBindingAttr>(attr)) {
        uint64_t index = argument.getArgument();
        if (index >= m->spawn.getOperands().size())
          continue;
        auto found = captureOf.find(m->spawn.getOperands()[index]);
        if (found == captureOf.end() || boundArguments.contains(found->second))
          continue;
        bound = found->second;
        attr = sim::ArgumentBindingAttr::get(
            context, argument.getPath(), found->second, argument.getKind(),
            argument.getCopyOut(), argument.getLvalueNode(),
            argument.getCopyIn(), argument.getVpiLocal());
        path = argument.getPath();
        if (argument.getKind() != sim::UnitArgumentKind::Direct &&
            argument.getKind() != sim::UnitArgumentKind::FormalLocal)
          role = unsigned(argument.getKind());
      } else if (auto constant = dyn_cast<sim::ConstantBindingAttr>(attr)) {
        path = constant.getPath();
      } else if (auto descriptor = dyn_cast<sim::DescriptorBindingAttr>(attr)) {
        path = descriptor.getPath();
      } else if (auto local = dyn_cast<sim::LocalBindingAttr>(attr)) {
        path = local.getPath();
      }
      if (path && !boundPaths.insert({path, role}).second)
        continue;
      if (bound)
        boundArguments.insert(*bound);
      bindings.push_back(attr);
    }
  }
  if (!bindings.empty())
    attrs.push_back(NamedAttribute(
        StringAttr::get(context, sim::metadata::Bindings::getNameStr()),
        ArrayAttr::get(context, bindings)));
  OpBuilder builder(head);
  auto merged = sim::SimFuncOp::create(
      builder, loc, (head.getSymName() + ".coalesced").str(),
      FunctionType::get(context, types, {}), sim::EntryKind::Continuous, attrs,
      argAttrs);
  symbols.insert(merged);
  Block *entry = &merged.getBody().front();
  Block *body = new Block();
  merged.getBody().push_back(body);
  // The handle the run writes through: the first member's driver, or the
  // storage it stores to.
  BlockArgument target = entry->getArgument(captureOf.lookup(
      first.spawn.getOperands()[first.variable
                                    ? viewRoot(first.writeTarget).getArgNumber()
                                    : first.driverArgument]));

  // Members in dependence order: a member that reads a slice another member
  // drives runs after it.
  SmallVector<Member *> order;
  {
    DenseSet<Member *> placed;
    while (order.size() < run.size())
      for (Member *m : run) {
        if (placed.contains(m))
          continue;
        bool ready = llvm::all_of(m->ownReads, [&](auto &read) {
          return llvm::all_of(run, [&](Member *other) {
            return placed.contains(other) ||
                   !read.second.overlaps(
                       other->slice());
          });
        });
        if (ready) {
          placed.insert(m);
          order.push_back(m);
        }
      }
  }

  DenseMap<Member *, Value> laneOf;
  DenseMap<Value, std::pair<BlockArgument, Slice>> leaves;
  DenseMap<BlockArgument, uint64_t> argumentLows;
  SmallVector<Value> watched;
  DenseSet<Value> watchedSet;
  llvm::MapVector<BlockArgument, SmallVector<std::pair<uint64_t, uint64_t>>>
      rangesOf;
  OpBuilder entryBuilder = OpBuilder::atBlockEnd(entry);
  OpBuilder bodyBuilder = OpBuilder::atBlockEnd(body);
  for (Member *m : order) {
    const analysis::HandleFacts &memberFacts = facts.at(m->function);
    Block &memberEntry = m->function.getBody().front();
    IRMapping mapping;
    for (unsigned i = 0; i < memberEntry.getNumArguments(); ++i) {
      if (m != &first && i == m->driverArgument)
        continue;
      auto index = captureOf.find(m->spawn.getOperands()[i]);
      if (index == captureOf.end())
        continue; // dead capture
      BlockArgument argument = entry->getArgument(index->second);
      mapping.map(memberEntry.getArgument(i), argument);
      auto fact = memberFacts.find(memberEntry.getArgument(i));
      if (fact != memberFacts.end())
        argumentLows[argument] = fact->second.low;
    }
    auto touchesDriver = [](Operation &op) {
      return llvm::any_of(op.getResultTypes(), [](Type type) {
        return isa<sim::DriverType>(type);
      });
    };
    for (Operation &op : memberEntry.without_terminator())
      if (!touchesDriver(op))
        entryBuilder.clone(op, mapping);
    // If-conversion of the member's acyclic body (11.4.11): every block runs,
    // each under the predicate of the paths reaching it; a block argument
    // selects the value of the edge taken. Exactly one path executes, so the
    // select chains yield the same values; the blocks hold only operations
    // that are safe to speculate (see match).
    struct Edge {
      Value predicate; // null: always
      SmallVector<Value> operands;
    };
    DenseMap<Block *, SmallVector<Edge>> edgesInto;
    auto conjoin = [&](Value predicate, Value condition) -> Value {
      if (!predicate)
        return condition;
      return arith::AndIOp::create(bodyBuilder, loc, predicate, condition);
    };
    for (Block *block : m->blocks) {
      Value predicate;
      if (block != m->blocks.front()) {
        SmallVector<Edge> &edges = edgesInto[block];
        bool always = llvm::any_of(edges, [](Edge &edge) {
          return !edge.predicate;
        });
        for (Edge &edge : edges)
          if (!always)
            predicate = predicate ? Value(arith::OrIOp::create(
                                        bodyBuilder, loc, predicate,
                                        edge.predicate))
                                  : edge.predicate;
        for (unsigned a = 0; a < block->getNumArguments(); ++a) {
          Value value = edges.back().operands[a];
          for (unsigned e = edges.size() - 1; e-- > 0;)
            value = edges[e].predicate
                        ? Value(arith::SelectOp::create(
                              bodyBuilder, loc, edges[e].predicate,
                              edges[e].operands[a], value))
                        : edges[e].operands[a]; // always taken
          mapping.map(block->getArgument(a), value);
        }
      }
      for (Operation &op : block->without_terminator()) {
      if (&op == m->write || touchesDriver(op))
        continue;
      auto slice = m->readSlices.find(&op);
      if (forwarding && slice != m->readSlices.end() &&
          slice->second.net != first.variable &&
          slice->second.id == first.net &&
          slice->second.within(runLow, runWidth)) {
        // The value a member of this run drives on these bits.
        Member *source = nullptr;
        for (Member *other : run)
          if (slice->second.within(other->low, other->width))
            source = other;
        assert(source && laneOf.count(source) && "forwarded slice is ordered");
        Value value = laneOf.lookup(source);
        Type scalar = sim::getPackedScalarType(value.getType());
        Value flat = value.getType() == scalar
                         ? value
                         : Value(sim::SimPackedFlattenOp::create(
                               bodyBuilder, op.getLoc(), scalar, value));
        uint64_t offset = slice->second.low - source->low;
        unsigned partWidth = unsigned(slice->second.width);
        Type part = fourState ? Type(sim::LogicType::get(context, partWidth))
                              : Type(bodyBuilder.getIntegerType(partWidth));
        if (part != flat.getType()) {
          if (fourState) {
            flat = sim::SimLogicExtractOp::create(bodyBuilder, op.getLoc(),
                                                  part, flat, offset);
          } else {
            if (offset)
              flat = arith::ShRUIOp::create(
                  bodyBuilder, op.getLoc(), flat,
                  arith::ConstantOp::create(
                      bodyBuilder, op.getLoc(), flat.getType(),
                      bodyBuilder.getIntegerAttr(flat.getType(), offset)));
            flat = arith::TruncIOp::create(bodyBuilder, op.getLoc(), part,
                                           flat);
          }
        }
        Type target = op.getResult(0).getType();
        if (target != flat.getType())
          flat = sim::SimPackedUnflattenOp::create(bodyBuilder, op.getLoc(),
                                                   target, flat);
        mapping.map(op.getResult(0), flat);
        continue;
      }
      Operation *clone = bodyBuilder.clone(op, mapping);
      if (slice != m->readSlices.end() && !m->dynamicReads.contains(&op))
        if (BlockArgument root = viewRoot(clone->getOperand(0)))
          if (packedRootDomain(root) == std::optional<bool>(fourState))
            leaves[clone->getResult(0)] = {root, slice->second};
      }
      // Successor edges and their predicates.
      Operation *terminator = block->getTerminator();
      auto mapped = [&](OperandRange operands) {
        SmallVector<Value> values;
        for (Value operand : operands)
          values.push_back(mapping.lookup(operand));
        return values;
      };
      if (auto branch = dyn_cast<cf::BranchOp>(terminator)) {
        edgesInto[branch.getDest()].push_back(
            {predicate, mapped(branch.getDestOperands())});
      } else if (auto branch = dyn_cast<cf::CondBranchOp>(terminator)) {
        Value condition = mapping.lookup(branch.getCondition());
        Value inverse = arith::XOrIOp::create(
            bodyBuilder, loc, condition,
            arith::ConstantOp::create(bodyBuilder, loc,
                                      bodyBuilder.getBoolAttr(true)));
        edgesInto[branch.getTrueDest()].push_back(
            {conjoin(predicate, condition),
             mapped(branch.getTrueDestOperands())});
        edgesInto[branch.getFalseDest()].push_back(
            {conjoin(predicate, inverse),
             mapped(branch.getFalseDestOperands())});
      }
    }
    laneOf[m] = mapping.lookup(m->writeValue);
    for (auto &[value, slice] : m->waits) {
      // Waits on bits the run computes itself are subsumed by forwarding.
      if (forwarding && slice && slice->net != first.variable &&
          slice->id == first.net && slice->within(runLow, runWidth))
        continue;
      Value mappedValue = mapping.lookupOrNull(value);
      assert(mappedValue && "every watched handle is a capture or a view");
      BlockArgument root = viewRoot(mappedValue);
      // Ranges of packed roots in their own state domain; other watches
      // (unpacked arrays, whose slices count padded provenance bits) stay.
      if (slice && root && root.getOwner() == entry && packedRootDomain(root)) {
        uint64_t rootLow = argumentLows.lookup(root);
        if (slice->low >= rootLow) {
          rangesOf[root].push_back({slice->low - rootLow, slice->width});
          continue;
        }
      }
      if (watchedSet.insert(mappedValue).second)
        watched.push_back(mappedValue);
    }
  }
  // One watch per maximal contiguous watched range of each root: a change of
  // any bit in it is a change of a watched bit (9.4.2).
  for (auto &[root, ranges] : rangesOf) {
    llvm::sort(ranges);
    Type element = isa<sim::NetType>(root.getType())
                       ? cast<sim::NetType>(root.getType()).getElementType()
                       : cast<sim::RefType>(root.getType()).getElementType();
    std::optional<unsigned> rootWidth = sim::getPackedWidth(element);
    SmallVector<std::pair<uint64_t, uint64_t>> spans;
    for (auto range : ranges) {
      if (!spans.empty() &&
          range.first <= spans.back().first + spans.back().second) {
        uint64_t end = std::max(spans.back().first + spans.back().second,
                                range.first + range.second);
        spans.back().second = end - spans.back().first;
        continue;
      }
      spans.push_back(range);
    }
    for (auto [low, width] : spans) {
      if (rootWidth && low == 0 && width == *rootWidth) {
        if (watchedSet.insert(root).second)
          watched.push_back(root);
        continue;
      }
      // Views of at most 128 bits (flat integer types wider than i128 are
      // avoided throughout the native lowering).
      bool rootFourState = *packedRootDomain(root);
      for (uint64_t at = low; at < low + width; at += 128) {
        unsigned piece = unsigned(std::min<uint64_t>(128, low + width - at));
        Type type = rootFourState ? Type(sim::LogicType::get(context, piece))
                                  : Type(entryBuilder.getIntegerType(piece));
        Value view;
        if (isa<sim::NetType>(root.getType()))
          view = sim::SimNetExtractOp::create(
              entryBuilder, loc, sim::NetType::get(context, type), root, at);
        else
          view = sim::SimRefExtractOp::create(
              entryBuilder, loc, sim::RefType::get(context, type), root, at);
        watched.push_back(view);
      }
    }
  }
  cf::BranchOp::create(entryBuilder, loc, body);

  // Drive the run: wide lanes as they are, narrow lanes packed into words.
  // Bit offset of the target capture within its root.
  uint64_t targetLow = argumentLows.lookup(target);
  auto driveSlice = [&](uint64_t low, Value value) {
    if (first.variable) {
      // One continuous store of the run (6.5: each written bit has one
      // continuous writer).
      Value view = target;
      if (low != targetLow ||
          value.getType() != cast<sim::RefType>(target.getType())
                                 .getElementType())
        view = sim::SimRefExtractOp::create(
            bodyBuilder, loc, sim::RefType::get(context, value.getType()),
            target, low - targetLow);
      auto store = sim::SimRefStoreOp::create(bodyBuilder, loc, value, view);
      sim::mark<sim::metadata::ContinuousStore>(store);
      return;
    }
    Value view = target;
    if (low != targetLow || value.getType() !=
                                cast<sim::DriverType>(target.getType())
                                    .getElementType())
      view = sim::SimDriverExtractOp::create(
          bodyBuilder, loc,
          sim::DriverType::get(context, value.getType()), target,
          low - targetLow);
    sim::SimDriverDriveOp::create(bodyBuilder, loc, view, value);
  };
  LaneVectorizer vectorizer(bodyBuilder, loc, leaves, argumentLows);
  auto flatten = [&](Value v) -> Value {
    Type scalar = sim::getPackedScalarType(v.getType());
    if (v.getType() == scalar)
      return v;
    return sim::SimPackedFlattenOp::create(bodyBuilder, loc, scalar, v);
  };
  // Concatenates pieces (least significant first) into one flat value.
  auto concat = [&](ArrayRef<Value> pieces, unsigned width) -> Value {
    if (pieces.size() == 1)
      return pieces.front();
    if (fourState) {
      SmallVector<Value> msbFirst(pieces.rbegin(), pieces.rend());
      return sim::SimLogicConcatOp::create(
          bodyBuilder, loc, sim::LogicType::get(context, width), msbFirst);
    }
    Type bits = bodyBuilder.getIntegerType(width);
    Value result;
    unsigned offset = 0;
    for (Value piece : pieces) {
      unsigned pieceWidth = cast<IntegerType>(piece.getType()).getWidth();
      Value part = piece.getType() == bits
                       ? piece
                       : Value(arith::ExtUIOp::create(bodyBuilder, loc, bits,
                                                      piece));
      if (offset)
        part = arith::ShLIOp::create(
            bodyBuilder, loc, part,
            arith::ConstantOp::create(
                bodyBuilder, loc, bits,
                bodyBuilder.getIntegerAttr(bits, offset)));
      result = result ? Value(arith::OrIOp::create(bodyBuilder, loc, result,
                                                   part))
                      : part;
      offset += pieceWidth;
    }
    return result;
  };
  // Lanes of one word: vectorized runs where they match, scalars otherwise.
  std::function<void(ArrayRef<Value>, unsigned, SmallVectorImpl<Value> &)>
      pack = [&](ArrayRef<Value> lanes, unsigned laneWidth,
                 SmallVectorImpl<Value> &pieces) {
        if (lanes.size() > 1) {
          unsigned scalarCost = 3 * lanes.size();
          for (Value lane : lanes)
            scalarCost += exclusiveCone(lane, 256);
          if (Value word = vectorizer.vectorize(lanes, laneWidth, fourState,
                                                scalarCost)) {
            pieces.push_back(word);
            return;
          }
          unsigned half = lanes.size() / 2;
          pack(lanes.take_front(half), laneWidth, pieces);
          pack(lanes.drop_front(half), laneWidth, pieces);
          return;
        }
        pieces.push_back(lanes.front());
      };
  SmallVector<std::pair<uint64_t, Value>> slices;
  for (unsigned i = 0; i < run.size();) {
    Member *m = run[i];
    Value lane = laneOf.lookup(m);
    if (m->width >= kWordBits) {
      slices.push_back({m->low, lane});
      ++i;
      continue;
    }
    // Narrow lanes of one width, up to a word.
    unsigned j = i;
    SmallVector<Value> lanes;
    uint64_t width = 0;
    while (j < run.size() && run[j]->width == m->width &&
           width + run[j]->width <= kWordBits) {
      lanes.push_back(flatten(laneOf.lookup(run[j])));
      width += run[j]->width;
      ++j;
    }
    SmallVector<Value> pieces;
    pack(lanes, unsigned(m->width), pieces);
    slices.push_back({m->low, concat(pieces, unsigned(width))});
    i = j;
  }
  // Every value is computed (and every new read issued) before any drive.
  for (auto &[low, value] : slices)
    driveSlice(low, value);
  SmallVector<int32_t> edges(watched.size(), 0);
  sim::SimSuspendAnyOp::create(bodyBuilder, loc, watched,
                               bodyBuilder.getDenseI32ArrayAttr(edges),
                               /*site=*/nullptr, /*resume_region=*/nullptr,
                               body);

  // One spawn of the merged process replaces the members' spawns.
  // After the last member spawn, where every captured handle is defined.
  Operation *last = first.spawn;
  for (Member *m : run)
    if (last->isBeforeInBlock(m->spawn))
      last = m->spawn;
  OpBuilder spawnBuilder(last);
  SmallVector<Value> operands;
  llvm::append_range(operands, captureOperands);
  sim::SimSpawnOp::create(spawnBuilder, first.spawn.getLoc(),
                          merged.getSymName(), operands,
                          /*arg_attrs=*/nullptr, /*res_attrs=*/nullptr);
  if (!first.variable) {
    first.decl.setDrivenLowAttr(
        IntegerAttr::get(IntegerType::get(context, 64), runLow));
    first.decl.setDrivenWidthAttr(
        IntegerAttr::get(IntegerType::get(context, 64), runWidth));
  }
  for (Member *m : run) {
    m->spawn.erase();
    if (m != &first && !m->variable) {
      freedDrivers.push_back(m->contextDriver.getId());
      m->contextDriver.erase();
      m->decl.erase();
    }
    symbols.erase(m->function);
  }
}

/// Driver IDs stay dense from zero: the highest remaining IDs move into the
/// freed ones. A driver ID is named by its declaration, context handles, the
/// descriptor of driver captures, and `*driver_id` attributes.
void TalosSimCoalesceContinuousDriversPass::compactDriverIds(
    sim::SimDesignOp design) {
  if (freedDrivers.empty())
    return;
  llvm::sort(freedDrivers);
  DenseSet<uint64_t> freed(freedDrivers.begin(), freedDrivers.end());
  uint64_t count = 0;
  for (auto decl : design.getBody().front().getOps<sim::SimDriverDeclOp>()) {
    (void)decl;
    ++count;
  }
  // IDs at or above `count` move down into freed IDs below `count`.
  DenseMap<uint64_t, uint64_t> remap;
  uint64_t next = count + freedDrivers.size();
  for (uint64_t hole : freedDrivers) {
    if (hole >= count)
      continue;
    do
      --next;
    while (freed.contains(next));
    remap[next] = hole;
  }
  if (remap.empty())
    return;
  MLIRContext *context = design.getContext();
  auto id64 = [&](uint64_t id) {
    return IntegerAttr::get(IntegerType::get(context, 64), id);
  };
  design.walk([&](Operation *op) {
    if (auto decl = dyn_cast<sim::SimDriverDeclOp>(op)) {
      if (auto it = remap.find(decl.getId()); it != remap.end())
        decl.setIdAttr(id64(it->second));
    } else if (auto handle = dyn_cast<sim::SimContextDriverOp>(op)) {
      if (auto it = remap.find(handle.getId()); it != remap.end())
        handle.setIdAttr(id64(it->second));
    } else if (auto function = dyn_cast<sim::SimFuncOp>(op)) {
      for (unsigned i = 0; i < function.getNumArguments(); ++i) {
        if (!isa<sim::DriverType>(function.getArgumentTypes()[i]))
          continue;
        auto descriptor = function.getArgAttrOfType<IntegerAttr>(
            i, sim::metadata::DescriptorId::getNameStr());
        if (!descriptor)
          continue;
        if (auto it = remap.find(descriptor.getValue().getZExtValue());
            it != remap.end())
          function.setArgAttr(i, sim::metadata::DescriptorId::getNameStr(),
                              id64(it->second));
      }
    }
    for (NamedAttribute attr : op->getAttrs())
      if (attr.getName().getValue().ends_with("driver_id"))
        if (auto id = dyn_cast<IntegerAttr>(attr.getValue()))
          if (auto it = remap.find(id.getValue().getZExtValue());
              it != remap.end())
            op->setAttr(attr.getName(),
                        IntegerAttr::get(id.getType(), it->second));
  });
}

void TalosSimCoalesceContinuousDriversPass::runOnOperation() {
  sim::SimDesignOp design = getOperation();
  if (hasFrozenSchedule(design)) {
    markAllAnalysesPreserved();
    return;
  }
  Block &designBlock = design.getBody().front();
  driverDecls.clear();
  contextDriverCount.clear();
  namedDrivers.clear();
  usersOf.clear();
  freedDrivers.clear();
  bool dumpPorts = false, overrides = false;
  DenseMap<uint64_t, sim::SimNetDeclOp> nets;
  DenseMap<uint64_t, sim::SimStorageDeclOp> storages;
  for (Operation &op : designBlock) {
    if (auto decl = dyn_cast<sim::SimDriverDeclOp>(op)) {
      driverDecls[decl.getId()] = decl;
      continue;
    }
    if (auto decl = dyn_cast<sim::SimNetDeclOp>(op)) {
      nets[decl.getId()] = decl;
      continue;
    }
    if (auto decl = dyn_cast<sim::SimStorageDeclOp>(op)) {
      storages[decl.getId()] = decl;
      continue;
    }
  }
  design.walk([&](Operation *op) {
    // Any operation naming a driver by ID keeps that driver (its ID would
    // otherwise be retargeted by the compaction below).
    if (!isa<sim::SimDriverDeclOp>(op))
      for (NamedAttribute attr : op->getAttrs())
        if (attr.getName().getValue().ends_with("driver_id"))
          if (auto id = dyn_cast<IntegerAttr>(attr.getValue()))
            namedDrivers.insert(id.getValue().getZExtValue());
    if (auto handle = dyn_cast<sim::SimContextDriverOp>(op))
      ++contextDriverCount[handle.getId()];
    else if (isa<sim::SimDumpPortsOp, sim::SimDumpPortsControlOp>(op))
      dumpPorts = true;
    else if (isa<sim::SimOverrideOp, sim::SimDynamicOverrideOp,
                 sim::SimReleaseOverrideOp>(op))
      overrides = true;
  });
  if (dumpPorts) {
    markAllAnalysesPreserved();
    return;
  }
  if (std::optional<SymbolTable::UseRange> uses =
          analysis::getSymbolUsesConcurrently(&design.getBody())) {
    DenseSet<std::pair<StringAttr, Operation *>> indexed;
    for (const SymbolTable::SymbolUse &use : *uses) {
      StringAttr name = use.getSymbolRef().getRootReference();
      if (indexed.insert({name, use.getUser()}).second)
        usersOf[name.getValue()].push_back(use.getUser());
    }
  } else {
    markAllAnalysesPreserved();
    return;
  }
  analysis::HandleDataflowAnalysis handles(design);

  // IEEE 1800-2023 38.34 and 10.6.2: a deposit or force on a slice that
  // another member reads is visible to that member, so forwarding requires
  // that neither can happen.
  bool forwarding = vpi != "full" && !overrides;
  DenseMap<Operation *, analysis::HandleFacts> facts;
  // Members by written root: (variable, ID).
  std::map<std::pair<bool, uint64_t>, std::vector<Member>> byNet;
  unsigned candidates = 0;
  for (auto function : designBlock.getOps<sim::SimFuncOp>()) {
    if (function.isExternal() ||
        function.getEntryKind() != sim::EntryKind::Continuous ||
        function.getBody().getBlocks().size() < 2)
      continue;
    // Structural prefilter before solving handle facts: one write.
    unsigned writes = 0;
    function.walk([&](Operation *op) {
      writes += isa<sim::SimDriverDriveOp>(op) ||
                (isa<sim::SimRefStoreOp>(op) &&
                 sim::has<sim::metadata::ContinuousStore>(op));
    });
    if (writes != 1)
      continue;
    ++candidates;
    analysis::HandleFacts functionFacts = handles.derive(function);
    std::string why;
    std::optional<Member> member = match(function, functionFacts, why);
    if (!member)
      continue;
    if (member->variable) {
      // A design variable written by continuous assignment (6.5). A VPI
      // deposit is a write (38.34) lasting until the next write of that bit
      // (6.5); a merged store would rewrite the bit earlier (10.3.2).
      auto storage = storages.find(member->net);
      if (vpi == "full" || storage == storages.end() ||
          storage->second.getLifetime() != sim::Lifetime::Design ||
          !sim::getPackedWidth(storage->second.getType()))
        continue;
      facts[function] = std::move(functionFacts);
      byNet[{true, member->net}].push_back(std::move(*member));
      continue;
    }
    // Each bit of the slice has this member as its only contribution, also
    // across port-collapsed nets (6.6.1, 23.3.3.7).
    auto net = nets.find(member->net);
    if (net == nets.end() || !sim::getPackedWidth(net->second.getType()) ||
        net->second.getNettypeAttr() ||
        net->second.getResolutionKind() != sim::NetResolutionKind::Wire ||
        !handles.hasExclusiveDriverSlice(member->net, member->low,
                                         member->width))
      continue;
    // IEEE 1800-2023 28.16: a net delay schedules each driver change.
    if (auto delays = net->second.getPropagationDelays())
      if (llvm::any_of(*delays, [](int64_t delay) { return delay != -1; }))
        continue;
    facts[function] = std::move(functionFacts);
    byNet[{false, member->net}].push_back(std::move(*member));
  }

  SymbolTable symbols(design);
  unsigned merged = 0, runs = 0;
  for (auto &netMembers : byNet) {
    bool variable = netMembers.first.first;
    uint64_t net = netMembers.first.second;
    std::vector<Member> &members = netMembers.second;
    llvm::sort(members, [](const Member &a, const Member &b) {
      return a.low < b.low;
    });
    SmallVector<bool> excluded(members.size(), false);
    // Members of maximal contiguous runs; a member reading bits of its run
    // must read within one member, and without forwarding not at all.
    bool changed = true;
    SmallVector<SmallVector<Member *>> runList;
    while (changed) {
      changed = false;
      runList.clear();
      for (unsigned i = 0; i < members.size(); ++i) {
        if (excluded[i])
          continue;
        if (!runList.empty() &&
            runList.back().back()->low + runList.back().back()->width ==
                members[i].low &&
            runList.back().back()->fourState == members[i].fourState &&
            !excluded[i - 1])
          runList.back().push_back(&members[i]);
        else
          runList.push_back({&members[i]});
      }
      for (auto &run : runList) {
        uint64_t low = run.front()->low;
        uint64_t width = run.back()->low + run.back()->width - low;
        // Port-collapsed aliases of every bit the run drives (23.3.3.7). A
        // member reading one would read bits the merged process drives later
        // in the same activation, through a net the forwarding cannot see,
        // and its own drive does not wake it again.
        SmallVector<Slice> aliases;
        if (!variable)
          for (Member *m : run)
            for (const auto &alias :
                 handles.getExclusiveDriveAliases(net, m->low, m->width))
              aliases.push_back(Slice{true, alias.net, alias.low, alias.width});
        for (Member *m : run) {
          bool bad = false;
          for (auto &read : m->readSlices)
            for (const Slice &alias : aliases)
              bad |= read.second.overlaps(alias);
          for (auto &read : m->ownReads) {
            const Slice &slice = read.second;
            if (!slice.overlaps(Slice{!variable, net, low, width}))
              continue;
            if (!forwarding || !slice.within(low, width) ||
                slice.within(m->low, m->width) ||
                llvm::none_of(run, [&](Member *other) {
                  return slice.within(other->low, other->width);
                }))
              bad = true;
          }
          if (bad) {
            excluded[m - members.data()] = true;
            changed = true;
          }
        }
      }
      if (changed)
        continue;
      // Forwarding cycles among members of a run.
      for (auto &run : runList) {
        DenseSet<Member *> placed;
        bool progress = true;
        while (progress) {
          progress = false;
          for (Member *m : run) {
            if (placed.contains(m))
              continue;
            bool ready = llvm::all_of(m->ownReads, [&](auto &read) {
              return llvm::all_of(run, [&](Member *other) {
                return placed.contains(other) ||
                       !read.second.overlaps(
                           Slice{!variable, net, other->low, other->width});
              });
            });
            if (ready) {
              placed.insert(m);
              progress = true;
            }
          }
        }
        for (Member *m : run)
          if (!placed.contains(m)) {
            excluded[m - members.data()] = true;
            changed = true;
          }
      }
    }
    for (auto &run : runList) {
      if (run.size() < 2)
        continue;
      // One spawn replaces the members' spawns, so they share a block.
      if (llvm::any_of(run, [&](Member *m) {
            return m->spawn->getBlock() != run.front()->spawn->getBlock();
          }))
        continue;
      merge(design, run, facts, forwarding, symbols);
      merged += run.size();
      ++runs;
    }
  }
  compactDriverIds(design);
  numMerged += merged;
  numRuns += runs;
  if (native::has<native::DebugTiming>(design->getParentOfType<ModuleOp>()))
    llvm::errs() << "talos coalesce-drivers: candidates=" << candidates
                 << " merged=" << merged << " runs=" << runs << '\n';
}

} // namespace
} // namespace talos
