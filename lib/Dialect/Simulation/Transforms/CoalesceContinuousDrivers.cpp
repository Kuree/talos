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
// merged process would read those bits before it drives them.
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

/// A continuous assignment process `cf.br ^b; ^b: reads, pure ops, one drive;
/// suspend on change`, spawned once at startup from the root initializer.
struct Member {
  sim::SimFuncOp function;
  sim::SimSpawnOp spawn;
  sim::SimDriverDriveOp drive;
  sim::SimDriverDeclOp decl;
  sim::SimContextDriverOp contextDriver;
  unsigned driverArgument = 0;
  uint64_t net = 0, low = 0, width = 0;
  /// Reads of the member's own net, by read operation.
  SmallVector<std::pair<Operation *, Slice>> ownReads;
  /// Every read and its slice (null slice when unknown).
  DenseMap<Operation *, Slice> readSlices;
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
    if (a == b)
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
      function.getBody().getBlocks().size() != 2) {
    why = "shape";
    return std::nullopt;
  }
  for (NamedAttribute attr : function->getAttrs()) {
    StringRef name = attr.getName().getValue();
    if (name.contains("primitive") || name.contains("timing") ||
        name.contains("path") || name.contains("pulse")) {
      why = "special process";
      return std::nullopt;
    }
  }
  Block &entry = function.getBody().front();
  Block &body = function.getBody().back();
  auto branch = dyn_cast<cf::BranchOp>(entry.getTerminator());
  if (!branch || branch.getDest() != &body || body.getNumArguments() ||
      !branch.getDestOperands().empty()) {
    why = "entry";
    return std::nullopt;
  }
  for (Operation &op : entry.without_terminator())
    if (!isViewOp(&op) && !isPureValueOp(op)) {
      why = "entry op";
      return std::nullopt;
    }
  Member member;
  member.function = function;
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
  if (driverArgument < 0) {
    why = "no driver";
    return std::nullopt;
  }
  member.driverArgument = unsigned(driverArgument);
  for (Operation &op : body.without_terminator()) {
    if (isViewOp(&op))
      continue;
    if (isa<sim::SimNetReadOp, sim::SimRefLoadOp>(op)) {
      std::optional<Slice> slice = sliceOf(facts, op.getOperand(0));
      if (!slice || !viewRoot(op.getOperand(0))) {
        why = "read";
        return std::nullopt;
      }
      member.readSlices[&op] = *slice;
      continue;
    }
    if (auto drive = dyn_cast<sim::SimDriverDriveOp>(op)) {
      if (member.drive) {
        why = "writes";
        return std::nullopt;
      }
      member.drive = drive;
      continue;
    }
    if (!isPureValueOp(op)) {
      why = "op";
      return std::nullopt;
    }
  }
  if (!member.drive) {
    why = "no drive";
    return std::nullopt;
  }
  // The drive is the only use of the driver capture.
  BlockArgument driver = entry.getArgument(member.driverArgument);
  if (viewRoot(member.drive.getDriver()) != driver) {
    why = "drive target";
    return std::nullopt;
  }
  {
    SmallVector<Value> work{driver};
    while (!work.empty()) {
      Value v = work.pop_back_val();
      for (Operation *user : v.getUsers()) {
        if (user == member.drive)
          continue;
        if (!isViewOp(user)) {
          why = "driver use";
          return std::nullopt;
        }
        work.push_back(user->getResult(0));
      }
    }
  }
  std::optional<Slice> target = sliceOf(facts, member.drive.getDriver());
  auto valueWidth = sim::getPackedWidth(member.drive.getValue().getType());
  if (!target || !target->net || !valueWidth ||
      *valueWidth != target->width) {
    why = "drive slice";
    return std::nullopt;
  }
  member.net = target->id;
  member.low = target->low;
  member.width = target->width;
  for (auto [op, slice] : member.readSlices)
    if (slice.net && slice.id == member.net)
      member.ownReads.push_back({op, slice});
  // Change waits only (10.3.2): edges and qualifiers keep the process.
  Operation *terminator = body.getTerminator();
  SmallVector<Value> watched;
  if (auto wait = dyn_cast<sim::SimSuspendChangeOp>(terminator)) {
    if (wait.getContinuation() != &body ||
        !wait.getContinuationOperands().empty()) {
      why = "wait";
      return std::nullopt;
    }
    watched.push_back(wait.getWatched());
  } else if (auto wait = dyn_cast<sim::SimSuspendAnyOp>(terminator)) {
    if (wait.getContinuation() != &body || wait.getResumeRegionAttr() ||
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
  bool fourState =
      isa<sim::LogicType>(sim::getPackedScalarType(first.decl.getType()));

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

  // The merged function keeps the first member's attributes.
  SmallVector<NamedAttribute> attrs;
  for (NamedAttribute attr : head->getAttrs())
    if (attr.getName() != SymbolTable::getSymbolAttrName() &&
        attr.getName() != head.getFunctionTypeAttrName() &&
        attr.getName() != head.getArgAttrsAttrName() &&
        attr.getName() != head.getResAttrsAttrName() &&
        attr.getName() != head.getEntryKindAttrName())
      attrs.push_back(attr);
  OpBuilder builder(head);
  auto merged = sim::SimFuncOp::create(
      builder, loc, (head.getSymName() + ".coalesced").str(),
      FunctionType::get(context, types, {}), sim::EntryKind::Continuous, attrs,
      argAttrs);
  symbols.insert(merged);
  Block *entry = &merged.getBody().front();
  Block *body = new Block();
  merged.getBody().push_back(body);
  BlockArgument driver = entry->getArgument(captureOf.lookup(
      first.spawn.getOperands()[first.driverArgument]));

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
                       Slice{true, other->net, other->low, other->width});
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
    Block &memberBody = m->function.getBody().back();
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
    for (Operation &op : memberBody.without_terminator()) {
      if (&op == m->drive || touchesDriver(op))
        continue;
      auto slice = m->readSlices.find(&op);
      if (forwarding && slice != m->readSlices.end() && slice->second.net &&
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
      if (slice != m->readSlices.end())
        if (BlockArgument root = viewRoot(clone->getOperand(0)))
          if (packedRootDomain(root) == std::optional<bool>(fourState))
            leaves[clone->getResult(0)] = {root, slice->second};
    }
    laneOf[m] = mapping.lookup(m->drive.getValue());
    for (auto &[value, slice] : m->waits) {
      // Waits on bits the run computes itself are subsumed by forwarding.
      if (forwarding && slice && slice->net && slice->id == first.net &&
          slice->within(runLow, runWidth))
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
  // Bit offset of the driver capture within its net.
  uint64_t driverLow = argumentLows.lookup(driver);
  auto driveSlice = [&](uint64_t low, Value value) {
    Value target = driver;
    if (low != driverLow || value.getType() !=
                                cast<sim::DriverType>(driver.getType())
                                    .getElementType())
      target = sim::SimDriverExtractOp::create(
          bodyBuilder, loc,
          sim::DriverType::get(context, value.getType()), driver,
          low - driverLow);
    sim::SimDriverDriveOp::create(bodyBuilder, loc, target, value);
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
  first.decl.setDrivenLowAttr(
      IntegerAttr::get(IntegerType::get(context, 64), runLow));
  first.decl.setDrivenWidthAttr(
      IntegerAttr::get(IntegerType::get(context, 64), runWidth));
  for (Member *m : run) {
    m->spawn.erase();
    if (m != &first) {
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
  for (Operation &op : designBlock) {
    if (auto decl = dyn_cast<sim::SimDriverDeclOp>(op)) {
      driverDecls[decl.getId()] = decl;
      continue;
    }
    if (auto decl = dyn_cast<sim::SimNetDeclOp>(op)) {
      nets[decl.getId()] = decl;
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
  std::map<uint64_t, SmallVector<Member>> byNet;
  unsigned candidates = 0;
  for (auto function : designBlock.getOps<sim::SimFuncOp>()) {
    if (function.isExternal() ||
        function.getEntryKind() != sim::EntryKind::Continuous ||
        function.getBody().getBlocks().size() != 2)
      continue;
    // Structural prefilter before solving handle facts: one driver capture
    // and one drive.
    unsigned drives = 0;
    for (Operation &op : function.getBody().back())
      drives += isa<sim::SimDriverDriveOp>(op);
    if (drives != 1)
      continue;
    ++candidates;
    analysis::HandleFacts functionFacts = handles.derive(function);
    std::string why;
    std::optional<Member> member = match(function, functionFacts, why);
    if (!member)
      continue;
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
    byNet[member->net].push_back(std::move(*member));
  }

  SymbolTable symbols(design);
  unsigned merged = 0, runs = 0;
  for (auto &netMembers : byNet) {
    uint64_t net = netMembers.first;
    SmallVector<Member> &members = netMembers.second;
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
            if (!slice.overlaps(Slice{true, net, low, width}))
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
                           Slice{true, net, other->low, other->width});
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
