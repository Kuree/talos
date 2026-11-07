//===- ClockSnapshot.cpp - Event-time qualification of pending actors ---===//
#include "ClockSnapshot.h"
#include "PublicationCallback.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/IR/DerivedTypes.h"

using namespace mlir;
namespace talos::upf_detail {
Value clockEdge(OpBuilder &b, Location loc, Value before, Value after,
                sim::EdgeKind kind) {
  if (kind == sim::EdgeKind::Change)
    return sim::SimLogicCompareOp::create(
        b, loc, b.getI1Type(), sim::CompareKind::CaseNe, before, after);
  auto bit = [&](bool v) -> Value {
    return arith::ConstantIntOp::create(b, loc, v, 1);
  };
  auto not_ = [&](Value v) -> Value {
    return arith::XOrIOp::create(b, loc, v, bit(true));
  };
  auto and_ = [&](Value a, Value c) -> Value {
    return arith::AndIOp::create(b, loc, a, c);
  };
  auto or_ = [&](Value a, Value c) -> Value {
    return arith::OrIOp::create(b, loc, a, c);
  };
  Value beforeZero = equalsLevel(b, loc, before, false);
  Value beforeOne = equalsLevel(b, loc, before, true);
  Value afterZero = equalsLevel(b, loc, after, false);
  Value afterOne = equalsLevel(b, loc, after, true);
  Value unknown = not_(or_(beforeZero, beforeOne));
  Value posedge =
      or_(and_(beforeZero, not_(afterZero)), and_(unknown, afterOne));
  Value negedge =
      or_(and_(beforeOne, not_(afterOne)), and_(unknown, afterZero));
  return kind == sim::EdgeKind::Posedge   ? posedge
         : kind == sim::EdgeKind::Negedge ? negedge
                                          : or_(posedge, negedge);
}
struct ClockSnapshots::Impl {
  struct Consumer {
    Descriptor source;
    FrozenClock frozen;
  };
  struct Source {
    sim::SimFuncOp writer, sampler;
    Operation *wait = nullptr;
    std::string name;
    Descriptor history, armed;
    SmallVector<Value> controls;
    SmallVector<sim::EdgeKind> edges;
    SmallVector<uint64_t> widths;
    Value condition, accepted;
    PublicationCallback primary;
    SmallVector<Value> parts;
    SmallVector<Descriptor> targets;
    SmallVector<Consumer> consumers;
    uint64_t width = 0;
    bool twoState = true;
  };
  ClockSnapshotOptions o;
  OpBuilder b;
  Location loc;
  llvm::MapVector<Operation *, std::unique_ptr<Source>> sources;
  explicit Impl(ClockSnapshotOptions options)
      : o(std::move(options)), b(o.root.getContext()), loc(o.root.getLoc()) {}
  Value bit(bool v) { return arith::ConstantIntOp::create(b, loc, v, 1); }
  Value and_(Value a, Value c) { return arith::AndIOp::create(b, loc, a, c); }
  Value not_(Value v) { return arith::XOrIOp::create(b, loc, v, bit(true)); }
  Value read(Value ctx, Descriptor d) {
    return load(b, loc, handle(b, loc, ctx, d));
  }
  void write(Value ctx, Descriptor d, Value v) {
    store(b, loc, handle(b, loc, ctx, d), v);
  }
  Value logic(Value v) {
    v = flatten(b, loc, v);
    if (auto type = dyn_cast<IntegerType>(v.getType()))
      return sim::SimLogicFromBitsOp::create(
          b, loc, sim::LogicType::get(b.getContext(), type.getWidth()), v);
    return v;
  }
  Value slice(Value v, uint64_t offset, uint64_t width) {
    return sim::SimLogicExtractOp::create(
        b, loc, sim::LogicType::get(b.getContext(), width), v, offset);
  }
  Value pack(ValueRange values) {
    SmallVector<Value> parts;
    uint64_t width = 0;
    for (Value v : llvm::reverse(values)) {
      v = logic(v);
      width += cast<sim::LogicType>(v.getType()).getWidth();
      parts.push_back(v);
    }
    if (parts.size() == 1)
      return parts.front();
    return sim::SimLogicConcatOp::create(
        b, loc, sim::LogicType::get(b.getContext(), width), parts);
  }
  void finishCallback(sim::SimFuncOp fn, Value result) {
    fn.setFunctionType(
        b.getFunctionType(fn.getArgumentTypes(), {result.getType()}));
    schedule::set<schedule::Field::ObserverWidth>(
        fn, b.getI32IntegerAttr(*sim::getPackedWidth(result.getType())));
    schedule::set<schedule::Field::ObserverFourState>(
        fn, b.getBoolAttr(isa<sim::LogicType>(result.getType())));
    sim::SimReturnOp::create(b, loc, result);
  }
  sim::SimFuncOp observer(StringRef name) {
    auto fn = o.function(loc, name, {sim::ContextType::get(b.getContext())},
                         sim::EntryKind::Observer);
    sim::mark<sim::metadata::PowerMonitor>(fn);
    b.setInsertionPointToEnd(&fn.getBody().front());
    return fn;
  }
  FailureOr<Value> clone(Value value, Value ctx, IRMapping &mapping) {
    if (auto known = mapping.lookupOrNull(value))
      return known;
    if (auto argument = dyn_cast<BlockArgument>(value)) {
      auto fn = dyn_cast<sim::SimFuncOp>(argument.getOwner()->getParentOp());
      if (!fn || argument.getOwner() != &fn.getBody().front())
        return failure();
      if (isa<sim::ContextType>(value.getType()))
        return ctx;
      auto id = fn.getArgAttrOfType<IntegerAttr>(
          argument.getArgNumber(), sim::metadata::DescriptorId::getNameStr());
      if (!id)
        return failure();
      bool net = isa<sim::NetType>(value.getType());
      if (!net && !isa<sim::RefType>(value.getType()))
        return failure();
      Type element = net ? cast<sim::NetType>(value.getType()).getElementType()
                         : cast<sim::RefType>(value.getType()).getElementType();
      auto rootType = fn.getArgAttrOfType<TypeAttr>(
          argument.getArgNumber(),
          sim::metadata::DescriptorRootType::getNameStr());
      if (rootType)
        element = rootType.getValue();
      Value copy = handle(b, loc, ctx, {id.getUInt(), element, net});
      if (rootType) {
        if (net || !fn.getArgAttr(argument.getArgNumber(),
                                  sim::metadata::DescriptorLow::getNameStr()))
          return failure();
        if (auto indices = fn.getArgAttrOfType<DenseI64ArrayAttr>(
                argument.getArgNumber(),
                sim::metadata::DescriptorIndices::getNameStr())) {
          auto aggregate = fn.getArgAttrOfType<TypeAttr>(
              argument.getArgNumber(),
              sim::metadata::DescriptorAggregateType::getNameStr());
          if (!aggregate)
            return failure();
          copy = sim::SimRefSubelementOp::create(
              b, loc, sim::RefType::get(b.getContext(), aggregate.getValue()),
              copy, indices);
        }
        if (copy.getType() != value.getType()) {
          auto low = fn.getArgAttrOfType<IntegerAttr>(
              argument.getArgNumber(),
              sim::metadata::DescriptorPackedLow::getNameStr());
          if (!low)
            return failure();
          copy =
              sim::SimRefExtractOp::create(b, loc, value.getType(), copy, low);
        }
      }
      mapping.map(value, copy);
      return copy;
    }
    Operation *op = value.getDefiningOp();
    if (!op || (!isMemoryEffectFree(op) &&
                !isa<sim::SimContextStorageOp, sim::SimContextNetOp>(op)))
      return failure();
    for (Value operand : op->getOperands()) {
      auto input = clone(operand, ctx, mapping);
      if (failed(input))
        return failure();
      mapping.map(operand, *input);
    }
    auto *copy = b.clone(*op, mapping);
    mapping.map(op->getResults(), copy->getResults());
    return mapping.lookup(value);
  }

  FailureOr<Value> levels(Source &s, Value ctx, IRMapping &mapping) {
    SmallVector<Value> values;
    for (auto [reference, width] : llvm::zip(s.controls, s.widths)) {
      if (!isa<sim::RefType, sim::NetType>(reference.getType()))
        return failure();
      auto copied = clone(reference, ctx, mapping);
      if (failed(copied))
        return failure();
      Value value = logic(load(b, loc, *copied));
      if (*sim::getPackedWidth(value.getType()) != width)
        value = slice(value, 0, width);
      values.push_back(value);
    }
    return pack(values);
  }
  LogicalResult initialize(Source &s) {
    s.writer.walk([&](Operation *op) {
      if (auto edge = dyn_cast<sim::SimSuspendEdgeOp>(op)) {
        s.wait = op;
        s.controls.push_back(edge.getWatched());
        s.edges.push_back(edge.getEdge());
      } else if (auto edge = dyn_cast<sim::SimSuspendEdgeIffOp>(op)) {
        s.wait = op;
        s.controls.push_back(edge.getWatched());
        s.edges.push_back(edge.getEdge());
        s.condition = edge.getCondition();
      } else if (auto any = dyn_cast<sim::SimSuspendAnyOp>(op)) {
        s.wait = op;
        llvm::append_range(s.controls, any.getWatched());
        for (int32_t edge : any.getEdges())
          s.edges.push_back(static_cast<sim::EdgeKind>(edge));
      }
    });
    if (!s.wait || s.controls.empty())
      return s.writer.emitError(
          "UPF clock qualification requires an edge event control");
    uint64_t width = 0;
    for (auto [control, edge] : llvm::zip(s.controls, s.edges)) {
      Type element;
      if (auto ref = dyn_cast<sim::RefType>(control.getType()))
        element = ref.getElementType();
      if (auto net = dyn_cast<sim::NetType>(control.getType()))
        element = net.getElementType();
      auto bits = element ? sim::getPackedWidth(element) : std::nullopt;
      if (!bits)
        return s.wait->emitError(
            "UPF requires persistent directly addressable clock controls");
      s.twoState &= isa<IntegerType>(sim::getPackedScalarType(element));
      uint64_t count = edge == sim::EdgeKind::Change ? *bits : 1;
      if (count > llvm::IntegerType::MAX_INT_BITS - 66 - width)
        return s.wait->emitError(
            "UPF clock inventory exceeds supported packed width");
      s.widths.push_back(count);
      width += count;
    }
    s.width = width + 1;
    Type historyType = s.twoState
                           ? Type(b.getIntegerType(width))
                           : Type(sim::LogicType::get(b.getContext(), width));
    s.history = o.storage(loc, s.name + ".history", historyType);
    s.armed = o.storage(loc, s.name + ".armed", b.getI1Type());
    auto primary = observer(s.name);
    IRMapping mapping;
    auto current = levels(s, primary.getArgument(0), mapping);
    if (failed(current))
      return s.wait->emitError(
          "UPF requires persistent directly addressable clock controls");
    Value initial = *current;
    if (s.twoState)
      initial = sim::SimLogicToBitsOp::create(b, loc, historyType, initial);
    finishCallback(primary, initial);
    auto closed = closePublicationCallback(primary, b);
    if (failed(closed))
      return failure();
    s.primary = *closed;
    s.sampler = observer(s.name + ".capture");
    Value ctx = s.sampler.getArgument(0);
    mapping.clear();
    current = levels(s, ctx, mapping);
    assert(succeeded(current));
    Value previous = logic(read(ctx, s.history)), triggered = bit(false);
    uint64_t offset = 0;
    for (auto [edge, count] : llvm::zip(s.edges, s.widths)) {
      Value event = clockEdge(b, loc, slice(previous, offset, count),
                              slice(*current, offset, count), edge);
      triggered = arith::OrIOp::create(b, loc, triggered, event);
      offset += count;
    }
    if (s.condition) {
      if (!isa<sim::RefType, sim::NetType>(s.condition.getType()))
        return s.wait->emitError("UPF requires a persistent directly "
                                 "addressable clock iff condition");
      auto reference = clone(s.condition, ctx, mapping);
      if (failed(reference))
        return s.wait->emitError("UPF requires a persistent directly "
                                 "addressable clock iff condition");
      triggered =
          and_(triggered,
               sim::SimLogicIsTrueOp::create(b, loc, b.getI1Type(),
                                             logic(load(b, loc, *reference))));
    }
    Value armed = read(ctx, s.armed);
    s.accepted = and_(armed, triggered);
    Value history = *current;
    if (s.twoState)
      history = sim::SimLogicToBitsOp::create(b, loc, historyType, history);
    s.parts = {history, and_(armed, not_(s.accepted))};
    s.targets = {s.history, s.armed};
    // Keep a well-formed placeholder until every consumer has added its fields.
    finishCallback(s.sampler, s.twoState ? bit(false) : logic(bit(false)));
    b.setInsertionPoint(s.wait);
    write(s.writer.getArgument(0), s.armed, bit(true));
    return success();
  }
  FailureOr<FrozenClock>
  freeze(sim::SimFuncOp writer, StringRef name, Descriptor epoch,
         llvm::function_ref<Value(OpBuilder &, Location, Value)> eligible) {
    loc = writer.getLoc();
    auto &source = sources[writer];
    if (!source) {
      source = std::make_unique<Source>();
      source->writer = writer;
      source->name = name.str();
      if (failed(initialize(*source)))
        return failure();
    }
    auto &s = *source;
    if (s.width > llvm::IntegerType::MAX_INT_BITS - 65)
      return s.wait->emitError(
          "UPF clock qualification exceeds supported packed width");
    FrozenClock frozen{o.storage(loc, name.str() + ".epoch", b.getI64Type()),
                       o.storage(loc, name.str() + ".valid", b.getI1Type())};
    b.setInsertionPoint(s.sampler.getBody().front().getTerminator());
    Value ctx = s.sampler.getArgument(0);
    Value allowed = eligible(b, loc, ctx);
    s.parts.push_back(arith::SelectOp::create(
        b, loc, s.accepted, read(ctx, epoch), read(ctx, frozen.epoch)));
    s.parts.push_back(arith::SelectOp::create(b, loc, s.accepted, allowed,
                                              read(ctx, frozen.valid)));
    s.targets.push_back(frozen.epoch);
    s.targets.push_back(frozen.valid);
    s.consumers.push_back({epoch, frozen});
    s.width += 65;
    return frozen;
  }
  LogicalResult finalize() {
    for (auto &entry : sources) {
      auto &s = *entry.second;
      loc = s.writer.getLoc();
      auto ret =
          cast<sim::SimReturnOp>(s.sampler.getBody().front().getTerminator());
      b.setInsertionPoint(ret);
      Value packed = pack(s.parts);
      if (s.twoState)
        packed = sim::SimLogicToBitsOp::create(
            b, loc, b.getIntegerType(s.width), packed);
      ret.erase();
      b.setInsertionPointToEnd(&s.sampler.getBody().front());
      finishCallback(s.sampler, packed);
      auto sampler = closePublicationCallback(s.sampler, b);
      if (failed(sampler))
        return failure();
      auto owner = o.function(loc, s.name + ".owner",
                              {sim::ContextType::get(b.getContext())},
                              sim::EntryKind::Fork);
      sim::mark<sim::metadata::PowerMonitor>(owner);
      schedule::set<schedule::Field::DetachedControls>(owner, b.getUnitAttr());
      schedule::set<schedule::Field::PrimeOnSpawn>(owner, b.getUnitAttr());
      b.setInsertionPointToEnd(&owner.getBody().front());
      Value ctx = owner.getArgument(0);
      Value initial =
          sim::SimCallOp::create(b, loc, s.primary.function.getResultTypes(),
                                 s.primary.function.getSymNameAttr(),
                                 publicationArguments(b, loc, ctx, s.primary),
                                 ArrayAttr{}, ArrayAttr{})
              .getResult(0);
      write(ctx, s.history, initial);
      write(ctx, s.armed, bit(false));
      for (auto consumer : s.consumers) {
        write(ctx, consumer.frozen.epoch, read(ctx, consumer.source));
        write(ctx, consumer.frozen.valid, bit(false));
      }
      SmallVector<Value> values{bindPublication(b, loc, ctx, s.primary, true),
                                initial,
                                bindPublication(b, loc, ctx, *sampler, false)};
      for (auto target : s.targets)
        values.push_back(handle(b, loc, ctx, target));
      sim::SimEventSnapshotRegisterOp::create(
          b, loc, ctx, values, s.targets.size(), 0, b.getDenseI32ArrayAttr({0}),
          b.getDenseI32ArrayAttr({-1}), DenseI32ArrayAttr{});
      auto *parked = new Block;
      owner.getBody().push_back(parked);
      sim::SimSuspendForeverOp::create(b, loc, ValueRange{},
                                       schedule::ContinuationSiteAttr{},
                                       sim::EventRegionAttr{}, parked);
      b.setInsertionPointToEnd(parked);
      sim::SimReturnOp::create(b, loc, ValueRange{});
      auto &root = o.root.getBody().front();
      auto spawn = llvm::find_if(
          root, [](Operation &op) { return isa<sim::SimSpawnOp>(op); });
      b.setInsertionPoint(spawn == root.end() ? root.getTerminator() : &*spawn);
      sim::SimSpawnOp::create(b, loc, owner.getSymNameAttr(),
                              ValueRange{o.root.getArgument(0)}, ArrayAttr{},
                              ArrayAttr{});
    }
    return success();
  }
};
ClockSnapshots::ClockSnapshots(ClockSnapshotOptions options)
    : impl(std::make_unique<Impl>(std::move(options))) {}
ClockSnapshots::~ClockSnapshots() = default;
FailureOr<FrozenClock> ClockSnapshots::freeze(
    sim::SimFuncOp writer, StringRef name, Descriptor epoch,
    llvm::function_ref<Value(OpBuilder &, Location, Value)> eligible) {
  return impl->freeze(writer, name, epoch, eligible);
}
LogicalResult ClockSnapshots::finalize() { return impl->finalize(); }
} // namespace talos::upf_detail
