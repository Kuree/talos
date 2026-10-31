#include "ReferenceWindow.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include <algorithm>
#include <limits>

using namespace mlir;
namespace talos::upf_detail {
namespace {
OperandRange arguments(Operation *op) {
  if (auto task = dyn_cast<sim::SimTaskCallOp>(op))
    return task.getArguments();
  return op->getOperands();
}
MutableOperandRange argumentsMutable(Operation *op) {
  if (auto task = dyn_cast<sim::SimTaskCallOp>(op))
    return task.getValuesMutable().slice(0, task.getArgumentCount());
  return MutableOperandRange(op);
}
SmallVector<Value, 4> fields(const ReferenceWindow &window) {
  return {window.start, window.lower, window.upper, window.valid};
}
struct Edge {
  Operation *branch;
  unsigned successor;
  Value reference;
};
FailureOr<SmallVector<Edge>> incoming(BlockArgument argument) {
  SmallVector<Edge> edges;
  llvm::DenseSet<std::pair<Operation *, unsigned>> seen;
  Block *block = argument.getOwner();
  for (Block *predecessor : block->getPredecessors()) {
    auto branch = dyn_cast<BranchOpInterface>(predecessor->getTerminator());
    if (!branch)
      return failure();
    for (unsigned index = 0; index != branch->getNumSuccessors(); ++index) {
      if (branch->getSuccessor(index) != block ||
          !seen.insert({branch, index}).second)
        continue;
      auto operands = branch.getSuccessorOperands(index);
      unsigned lane = argument.getArgNumber();
      if (lane >= operands.size() || operands.isOperandProduced(lane))
        return failure();
      edges.push_back({branch, index, operands[lane]});
    }
  }
  return edges.empty() ? FailureOr<SmallVector<Edge>>(failure())
                       : FailureOr<SmallVector<Edge>>(std::move(edges));
}
} // namespace

struct ReferenceWindows::Impl {
  sim::SimDesignOp design;
  OpBuilder b;
  llvm::DenseMap<uint64_t, sim::SimStorageDeclOp> storages;
  llvm::DenseMap<Operation *, SmallVector<Operation *>> callers;
  llvm::DenseSet<Operation *> opaqueUsers;
  llvm::DenseMap<Value, Descriptor> roots;
  llvm::DenseMap<Value, bool> whole;
  llvm::DenseMap<Value, ReferenceWindow> windows;

  Impl(sim::SimDesignOp design) : design(design), b(design.getContext()) {
    llvm::StringMap<sim::SimFuncOp> functions;
    for (auto fn : design.getOps<sim::SimFuncOp>())
      functions[fn.getSymName()] = fn;
    for (auto storage : design.getOps<sim::SimStorageDeclOp>())
      storages[storage.getId()] = storage;
    design.walk([&](Operation *op) {
      if (!isa<sim::SimSpawnOp, sim::SimCallOp, sim::SimTaskCallOp>(op))
        return;
      auto callee = op->getAttrOfType<FlatSymbolRefAttr>("callee");
      auto found = callee ? functions.find(callee.getValue()) : functions.end();
      if (found != functions.end())
        callers[found->second].push_back(op);
    });
    // A singleton proved from direct users is insufficient if an exported or
    // indirect user can supply another reference (1801-2018 9.5.3).
    if (auto uses = SymbolTable::getSymbolUses(design)) {
      for (const auto &use : *uses) {
        auto found =
            functions.find(use.getSymbolRef().getRootReference().getValue());
        if (found == functions.end())
          continue;
        Operation *user = use.getUser();
        auto callee = user->getAttrOfType<FlatSymbolRefAttr>("callee");
        if (!isa<sim::SimSpawnOp, sim::SimCallOp, sim::SimTaskCallOp>(user) ||
            !callee || callee.getValue() != found->getKey())
          opaqueUsers.insert(found->second);
      }
    } else {
      for (auto fn : design.getOps<sim::SimFuncOp>())
        opaqueUsers.insert(fn);
    }
  }
  LogicalResult error(Value reference, StringRef reason) {
    emitError(reference.getLoc())
        << "guarded UPF NBA " << reason << " (IEEE 1801-2018 9.5.3)";
    return failure();
  }
  FailureOr<SmallVector<Value>> sources(BlockArgument argument) {
    auto fn = dyn_cast<sim::SimFuncOp>(argument.getOwner()->getParentOp());
    if (fn && argument.getOwner() == &fn.getBody().front()) {
      auto found = callers.find(fn);
      if (opaqueUsers.contains(fn) || found == callers.end() ||
          found->second.empty())
        return failure();
      SmallVector<Value> values;
      for (auto *call : found->second) {
        auto inputs = arguments(call);
        if (argument.getArgNumber() >= inputs.size())
          return failure();
        values.push_back(inputs[argument.getArgNumber()]);
      }
      return values;
    }
    auto edges = incoming(argument);
    if (failed(edges))
      return failure();
    SmallVector<Value> values;
    for (auto edge : *edges)
      values.push_back(edge.reference);
    return values;
  }
  FailureOr<Descriptor> rootOf(Value reference) {
    auto cached = roots.find(reference);
    if (cached != roots.end())
      return cached->second;
    SmallVector<Value> pending{reference};
    llvm::DenseSet<Value> seen;
    std::optional<Descriptor> result;
    while (!pending.empty()) {
      Value value = pending.pop_back_val();
      if (!seen.insert(value).second)
        continue;
      std::optional<Descriptor> candidate;
      if (auto found = roots.find(value); found != roots.end())
        candidate = found->second;
      else if (auto lookup = value.getDefiningOp<sim::SimContextStorageOp>()) {
        auto storage = storages.lookup(lookup.getId());
        if (!storage || storage.getLifetime() == sim::Lifetime::Automatic) {
          (void)error(reference, "requires persistent storage roots");
          return failure();
        }
        candidate = Descriptor{storage.getId(), storage.getType()};
      } else if (auto view = value.getDefiningOp<ViewLikeOpInterface>()) {
        if (!isMemoryEffectFree(view.getOperation())) {
          (void)error(reference,
                      "reference projection has unsupported effects");
          return failure();
        }
        pending.push_back(view.getViewSource());
      } else if (auto argument = dyn_cast<BlockArgument>(value)) {
        auto inputs = sources(argument);
        if (failed(inputs)) {
          (void)error(
              reference,
              "reference has unsupported external or produced provenance");
          return failure();
        }
        pending.append(*inputs);
      } else {
        (void)error(reference, "reference has unsupported provenance");
        return failure();
      }
      if (!candidate)
        continue;
      if (result &&
          (result->id != candidate->id || result->type != candidate->type)) {
        auto diagnostic =
            emitError(reference.getLoc())
            << "guarded UPF NBA reference selects different persistent roots; "
               "reference specialization is not implemented (IEEE 1801-2018 "
               "9.5.3)";
        diagnostic.attachNote(storages.lookup(result->id).getLoc())
            << "first root";
        diagnostic.attachNote(storages.lookup(candidate->id).getLoc())
            << "other root";
        return failure();
      }
      result = *candidate;
    }
    if (!result) {
      (void)error(reference, "reference has no persistent root");
      return failure();
    }
    for (Value value : seen)
      roots[value] = *result;
    return *result;
  }
  bool isWhole(Value reference) {
    if (auto found = whole.find(reference); found != whole.end())
      return found->second;
    SmallVector<Value> pending{reference};
    llvm::DenseSet<Value> seen;
    bool root = false, result = true;
    while (!pending.empty()) {
      Value value = pending.pop_back_val();
      if (!seen.insert(value).second)
        continue;
      if (value.getDefiningOp<sim::SimContextStorageOp>())
        root = true;
      else if (auto argument = dyn_cast<BlockArgument>(value)) {
        auto inputs = sources(argument);
        if (failed(inputs)) {
          result = false;
          break;
        }
        pending.append(*inputs);
      } else {
        result = false;
        break;
      }
    }
    return whole[reference] = result && root;
  }
  Value integer(Location loc, int64_t value, unsigned width = 64) {
    return b.createOrFold<arith::ConstantOp>(
        loc, b.getIntegerType(width),
        b.getIntegerAttr(b.getIntegerType(width), value));
  }
  Value boolean(Location loc, bool value) { return integer(loc, value, 1); }
  Value wide(Location loc, Value value) {
    return b.createOrFold<arith::ExtSIOp>(loc, b.getIntegerType(128), value);
  }
  Value both(Location loc, Value a, Value c) {
    return b.createOrFold<arith::AndIOp>(loc, a, c);
  }
  struct Index {
    Value value, valid;
  };
  FailureOr<Index> index(Value source, Location loc) {
    Value value = flatten(b, loc, source);
    Value valid = boolean(loc, true);
    if (auto logic = dyn_cast<sim::LogicType>(value.getType())) {
      Value bits = sim::SimLogicToBitsOp::create(
          b, loc, b.getIntegerType(logic.getWidth()), value);
      Value known = sim::SimLogicFromBitsOp::create(b, loc, logic, bits);
      valid = sim::SimLogicCompareOp::create(
          b, loc, b.getI1Type(), sim::CompareKind::CaseEq, value, known);
      value = bits;
    }
    auto type = dyn_cast<IntegerType>(value.getType());
    if (!type)
      return failure();
    if (type.getWidth() > 64) {
      Value narrow =
          b.createOrFold<arith::TruncIOp>(loc, b.getI64Type(), value);
      Value roundtrip = b.createOrFold<arith::ExtSIOp>(loc, type, narrow);
      valid = both(loc, valid,
                   b.createOrFold<arith::CmpIOp>(loc, arith::CmpIPredicate::eq,
                                                 value, roundtrip));
      value = narrow;
    } else if (type.getWidth() < 64)
      value = b.createOrFold<arith::ExtSIOp>(loc, b.getI64Type(), value);
    return Index{wide(loc, value), valid};
  }
  FailureOr<ReferenceWindow> project(ReferenceWindow parent, Value offset,
                                     uint64_t width, Value valid,
                                     Location loc) {
    if (!width || width > INT64_MAX)
      return failure();
    Value start =
        b.createOrFold<arith::AddIOp>(loc, wide(loc, parent.start), offset);
    Value end =
        b.createOrFold<arith::AddIOp>(loc, start, integer(loc, width, 128));
    // Every level intersects its parent's already-clipped bounds. A later
    // negative selector cannot revive an invalid parent (1800-2023 7.4.5).
    Value lower =
        b.createOrFold<arith::MaxSIOp>(loc, wide(loc, parent.lower), start);
    Value upper =
        b.createOrFold<arith::MinSIOp>(loc, wide(loc, parent.upper), end);
    valid = both(loc, parent.valid, valid);
    valid = both(loc, valid,
                 b.createOrFold<arith::CmpIOp>(loc, arith::CmpIPredicate::slt,
                                               lower, upper));
    Value start64 = b.createOrFold<arith::TruncIOp>(loc, b.getI64Type(), start);
    valid = both(loc, valid,
                 b.createOrFold<arith::CmpIOp>(loc, arith::CmpIPredicate::eq,
                                               start, wide(loc, start64)));
    // Keep all stored bounds in the root even along an invalid CFG lane.
    auto span = sim::getProvenanceSpan(parent.root.type);
    if (!span || *span > INT64_MAX)
      return failure();
    auto clamp = [&](Value value) {
      value = b.createOrFold<arith::MaxSIOp>(loc, value, integer(loc, 0, 128));
      value =
          b.createOrFold<arith::MinSIOp>(loc, value, integer(loc, *span, 128));
      return b.createOrFold<arith::TruncIOp>(loc, b.getI64Type(), value);
    };
    return ReferenceWindow{parent.root, start64, clamp(lower), clamp(upper),
                           valid};
  }
  FailureOr<ReferenceWindow> materialize(Value reference) {
    if (auto found = windows.find(reference); found != windows.end())
      return found->second;
    auto root = rootOf(reference);
    if (failed(root))
      return failure();
    OpBuilder::InsertionGuard insertion(b);
    Location loc = reference.getLoc();
    auto fn = reference.getParentRegion()->getParentOfType<sim::SimFuncOp>();
    if (isWhole(reference)) {
      b.setInsertionPointToStart(&fn.getBody().front());
      auto width = sim::getProvenanceSpan(root->type);
      if (!width || *width > INT64_MAX)
        return failure();
      ReferenceWindow result{*root, integer(loc, 0), integer(loc, 0),
                             integer(loc, *width), boolean(loc, true)};
      windows[reference] = result;
      return result;
    }
    auto view = reference.getDefiningOp<ViewLikeOpInterface>();
    if (!view) {
      (void)error(reference,
                  "window was not planned for this reference argument");
      return failure();
    }
    auto parent = windows.find(view.getViewSource());
    if (parent == windows.end()) {
      (void)error(reference, "projection parent window was not materialized");
      return failure();
    }
    b.setInsertionPointAfter(view.getOperation());
    FailureOr<ReferenceWindow> result = failure();
    auto width = sim::getProvenanceSpan(
        cast<sim::RefType>(reference.getType()).getElementType());
    if (!width)
      return failure();
    if (auto extract = dyn_cast<sim::SimRefExtractOp>(view.getOperation()))
      result = project(parent->second, integer(loc, extract.getLowBit(), 128),
                       *width, boolean(loc, true), loc);
    else if (auto extract =
                 dyn_cast<sim::SimRefDynExtractOp>(view.getOperation())) {
      auto low = index(extract.getLowBit(), loc);
      if (succeeded(low))
        result = project(parent->second, low->value, *width, low->valid, loc);
    } else if (auto element =
                   dyn_cast<sim::SimRefArrayElementOp>(view.getOperation())) {
      Type array = element.getInput().getType().getElementType();
      auto at = index(element.getIndex(), loc);
      auto stride = sim::getArrayElementStorageStride(array);
      int64_t left, right;
      bool packed = isa<sim::PackedArrayType>(array);
      if (auto type = dyn_cast<sim::PackedArrayType>(array)) {
        left = type.getLeft();
        right = type.getRight();
      } else {
        auto unpacked = cast<sim::UnpackedArrayType>(array);
        left = unpacked.getLeft();
        right = unpacked.getRight();
      }
      if (succeeded(at) && stride) {
        Value valid = both(loc, at->valid,
                           b.createOrFold<arith::CmpIOp>(
                               loc, arith::CmpIPredicate::sge, at->value,
                               integer(loc, std::min(left, right), 128)));
        valid = both(loc, valid,
                     b.createOrFold<arith::CmpIOp>(
                         loc, arith::CmpIPredicate::sle, at->value,
                         integer(loc, std::max(left, right), 128)));
        Value ordinal = left >= right
                            ? b.createOrFold<arith::SubIOp>(
                                  loc, integer(loc, left, 128), at->value)
                            : b.createOrFold<arith::SubIOp>(
                                  loc, at->value, integer(loc, left, 128));
        if (packed)
          ordinal = b.createOrFold<arith::SubIOp>(
              loc, integer(loc, sim::getAggregateNumElements(array) - 1, 128),
              ordinal);
        Value offset = b.createOrFold<arith::MulIOp>(
            loc, ordinal, integer(loc, *stride, 128));
        result = project(parent->second, offset, *width, valid, loc);
      }
    } else if (auto element =
                   dyn_cast<sim::SimRefSubelementOp>(view.getOperation())) {
      Type type = element.getInput().getType().getElementType();
      result = parent->second;
      for (int64_t rawIndex : element.getIndices()) {
        unsigned ordinal = static_cast<unsigned>(rawIndex);
        auto selected = sim::getAggregateProvenanceSubelement(type, ordinal);
        if (!selected) {
          result = failure();
          break;
        }
        result = project(*result, integer(loc, selected->first, 128),
                         selected->second, boolean(loc, true), loc);
        if (failed(result))
          break;
        type = sim::getAggregateElementType(type, ordinal);
      }
    }
    if (failed(result))
      (void)error(reference, "reference projection is not implemented");
    else
      windows[reference] = *result;
    return result;
  }
  FailureOr<ReferenceWindow> get(Value reference) {
    SmallVector<Value> projections;
    Value current = reference;
    while (!windows.count(current)) {
      if (failed(rootOf(current)))
        return failure();
      if (isWhole(current)) {
        if (failed(materialize(current)))
          return failure();
        break;
      }
      auto view = current.getDefiningOp<ViewLikeOpInterface>();
      if (!view) {
        (void)error(current,
                    "window was not planned for this reference argument");
        return failure();
      }
      projections.push_back(current);
      current = view.getViewSource();
    }
    // Reference chains are unbounded IR, so materialize bottom-up without
    // consuming the host stack. Reserved CFG/formal lanes break SSA cycles.
    for (Value projection : llvm::reverse(projections))
      if (failed(materialize(projection)))
        return failure();
    return windows.lookup(reference);
  }
  struct Reservation {
    BlockArgument argument;
    unsigned first;
    SmallVector<Edge> edges;
    SmallVector<Operation *> calls;
  };
  LogicalResult prepare(ArrayRef<Value> references) {
    SmallVector<Value> pending(references);
    llvm::DenseSet<Value> seen, needed;
    while (!pending.empty()) {
      Value reference = pending.pop_back_val();
      if (!seen.insert(reference).second || windows.count(reference))
        continue;
      if (failed(rootOf(reference)))
        return failure();
      if (isWhole(reference))
        continue;
      if (auto view = reference.getDefiningOp<ViewLikeOpInterface>())
        pending.push_back(view.getViewSource());
      else if (auto argument = dyn_cast<BlockArgument>(reference)) {
        needed.insert(argument);
        auto inputs = sources(argument);
        if (failed(inputs))
          return error(reference,
                       "reference argument has unsupported provenance");
        pending.append(*inputs);
      } else
        return error(reference, "reference has unsupported provenance");
    }
    // Plan the complete fixed point before mutating signatures. Ordering is
    // source function/block/formal order, independent of which NBA is visited.
    SmallVector<BlockArgument> ordered;
    for (auto fn : design.getOps<sim::SimFuncOp>())
      for (Block &block : fn.getBody())
        for (BlockArgument argument : block.getArguments())
          if (needed.contains(argument))
            ordered.push_back(argument);
    SmallVector<Reservation> reservations;
    for (BlockArgument argument : ordered) {
      auto fn = cast<sim::SimFuncOp>(argument.getOwner()->getParentOp());
      Location loc = argument.getLoc();
      Reservation reservation{
          argument, argument.getOwner()->getNumArguments(), {}, {}};
      SmallVector<Value, 4> values;
      SmallVector<Type> types{b.getI64Type(), b.getI64Type(), b.getI64Type(),
                              b.getI1Type()};
      auto attrs = b.getDictionaryAttr(
          {sim::named<sim::metadata::CaptureKind>(sim::CaptureKindAttr::get(
              b.getContext(), sim::CaptureKind::Formal))});
      for (Type type : types) {
        if (argument.getOwner() == &fn.getBody().front()) {
          if (failed(fn.insertArgument(fn.getNumArguments(), type, attrs, loc)))
            return error(argument, "cannot extend captured reference windows");
          values.push_back(fn.getArguments().back());
        } else
          values.push_back(argument.getOwner()->addArgument(type, loc));
      }
      windows[argument] = ReferenceWindow{roots.lookup(argument), values[0],
                                          values[1], values[2], values[3]};
      if (argument.getOwner() == &fn.getBody().front()) {
        reservation.calls = callers.lookup(fn);
        for (Operation *call : reservation.calls) {
          b.setInsertionPoint(call);
          SmallVector<Value, 4> placeholder{integer(loc, 0), integer(loc, 0),
                                            integer(loc, 0),
                                            boolean(loc, false)};
          if (auto task = dyn_cast<sim::SimTaskCallOp>(call)) {
            unsigned count = task.getArgumentCount();
            task.getValuesMutable().slice(0, count).append(placeholder);
            task.setArgumentCount(count + 4);
          } else
            argumentsMutable(call).append(placeholder);
          if (auto old = call->getAttrOfType<ArrayAttr>("arg_attrs")) {
            SmallVector<Attribute> expanded(old.getValue());
            expanded.append(4, attrs);
            call->setAttr("arg_attrs", b.getArrayAttr(expanded));
          }
        }
      } else {
        auto edges = incoming(argument);
        if (failed(edges))
          return error(argument, "cannot forward a produced reference window");
        reservation.edges = std::move(*edges);
        for (auto edge : reservation.edges) {
          b.setInsertionPoint(edge.branch);
          SmallVector<Value, 4> placeholder{integer(loc, 0), integer(loc, 0),
                                            integer(loc, 0),
                                            boolean(loc, false)};
          cast<BranchOpInterface>(edge.branch)
              .getSuccessorOperands(edge.successor)
              .append(placeholder);
        }
      }
      reservations.push_back(std::move(reservation));
    }
    // All lane slots exist before recursively materializing windows. This
    // keeps mutually forwarded references and duplicate successor edges
    // correlated even when their geometry depends on one another.
    for (auto &reservation : reservations) {
      for (auto *call : reservation.calls) {
        auto window = get(arguments(call)[reservation.argument.getArgNumber()]);
        if (failed(window))
          return failure();
        argumentsMutable(call)
            .slice(reservation.first, 4)
            .assign(fields(*window));
      }
      for (auto edge : reservation.edges) {
        auto window = get(edge.reference);
        if (failed(window))
          return failure();
        cast<BranchOpInterface>(edge.branch)
            .getSuccessorOperands(edge.successor)
            .slice(reservation.first, 4)
            .assign(fields(*window));
      }
    }
    return success();
  }
};
ReferenceWindows::ReferenceWindows(sim::SimDesignOp design)
    : impl(std::make_unique<Impl>(design)) {}
ReferenceWindows::~ReferenceWindows() = default;
FailureOr<Descriptor> ReferenceWindows::getRoot(Value reference) {
  return impl->rootOf(reference);
}
bool ReferenceWindows::isWhole(Value reference) {
  return impl->isWhole(reference);
}
LogicalResult ReferenceWindows::prepare(ArrayRef<Value> references) {
  return impl->prepare(references);
}
FailureOr<ReferenceWindow> ReferenceWindows::get(Value reference) {
  return impl->get(reference);
}
} // namespace talos::upf_detail
