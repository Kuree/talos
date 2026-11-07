//===- BalloonRetention.cpp - Event-time balloon storage lowering -------===//

#include "BalloonRetention.h"
#include "ClockSnapshot.h"
#include "PowerState.h"
#include "PublicationCallback.h"
#include "RetentionReadback.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/IR/DerivedTypes.h"

#include <map>
#include <tuple>

using namespace mlir;
namespace talos {
namespace {
using namespace upf_detail;

// Snapshot payloads lower to packed integers, one per four-state plane.
// Check the LLVM backend limit before constructing concatenated types.
constexpr uint64_t maxPackedWidth = llvm::IntegerType::MAX_INT_BITS;

using Callback = PublicationCallback;
struct State {
  BalloonRegister source;
  Descriptor normal, saved, visible;
};
struct Clock {
  sim::SimFuncOp writer;
  Descriptor epoch, valid;
};

struct BalloonLowering {
  RetentionLoweringOptions o;
  upf::RetentionAttr strategy;
  ArrayRef<upf::UPFSupplySetOp> primarySets, retentionSets;
  ArrayRef<BalloonRegister> registers;
  Operation *rootBoundary;
  SmallVectorImpl<RetentionWrite> &writes;
  OpBuilder b;
  Location loc;
  std::string name;
  SmallVector<State> states;
  SmallVector<Clock> clocks;
  SmallVector<Descriptor> dependencies;
  Descriptor destructiveEpoch, priorityEpoch, previousSave, previousRestore;
  sim::SimFuncOp nbaPredicate;

  BalloonLowering(const RetentionLoweringOptions &o,
                  upf::RetentionAttr strategy,
                  ArrayRef<upf::UPFSupplySetOp> primary,
                  ArrayRef<upf::UPFSupplySetOp> retention,
                  ArrayRef<BalloonRegister> registers, Operation *rootBoundary,
                  SmallVectorImpl<RetentionWrite> &writes)
      : o(o), strategy(strategy), primarySets(primary),
        retentionSets(retention), registers(registers),
        rootBoundary(rootBoundary), writes(writes),
        b(this->o.design.getContext()),
        loc(strategy.getDeclaration() ? Location(strategy.getDeclaration())
                                      : this->o.domain.getLoc()),
        name("__upf_balloon." + this->o.domain.getSymName().str() + "." +
             strategy.getName().getValue().str()) {}

  Value bit(bool value) {
    return arith::ConstantIntOp::create(b, loc, value, 1);
  }
  Value integer(uint64_t value) {
    return arith::ConstantIntOp::create(b, loc, value, 64);
  }
  Value not_(Value value) {
    return arith::XOrIOp::create(b, loc, value, bit(true));
  }
  Value and_(Value a, Value c) { return arith::AndIOp::create(b, loc, a, c); }
  Value or_(Value a, Value c) { return arith::OrIOp::create(b, loc, a, c); }
  Value choose(Value test, Value yes, Value no) {
    return arith::SelectOp::create(b, loc, test, yes, no);
  }
  Value read(Value ctx, Descriptor d) {
    return load(b, loc, handle(b, loc, ctx, d));
  }
  void write(Value ctx, Descriptor d, Value value) {
    store(b, loc, handle(b, loc, ctx, d), value);
  }
  void root() { b.setInsertionPoint(rootBoundary); }
  Value logic(Value value) {
    value = flatten(b, loc, value);
    if (auto type = dyn_cast<IntegerType>(value.getType()))
      return sim::SimLogicFromBitsOp::create(
          b, loc, sim::LogicType::get(b.getContext(), type.getWidth()), value);
    return value;
  }
  Value slice(Value value, uint64_t offset, uint64_t width) {
    return sim::SimLogicExtractOp::create(
        b, loc, sim::LogicType::get(b.getContext(), width), value, offset);
  }
  Value pack(ValueRange values) {
    SmallVector<Value> parts;
    uint64_t width = 0;
    for (Value value : llvm::reverse(values)) {
      value = logic(value);
      width += cast<sim::LogicType>(value.getType()).getWidth();
      parts.push_back(value);
    }
    if (parts.size() == 1)
      return parts.front();
    return sim::SimLogicConcatOp::create(
        b, loc, sim::LogicType::get(b.getContext(), width), parts);
  }
  Value predicate(Value ctx, upf::ExpressionAttr expression) {
    return expression
               ? Expression(expression).predicate(b, loc, ctx, o.descriptors)
               : bit(true);
  }
  Value normal(Value ctx, ArrayRef<upf::UPFSupplySetOp> sets) {
    Value result = bit(true);
    for (auto set : sets)
      result = and_(result,
                    evaluateSupplySet(set, b, loc, [&](FlatSymbolRefAttr ref) {
                      return o.readSupply(b, loc, ctx, ref);
                    }).normal);
    return result;
  }
  Value primary(Value ctx) {
    return and_(o.domainNormal(b, loc, ctx), normal(ctx, primarySets));
  }
  Value control(Value ctx, upf::RetentionTriggerAttr trigger) {
    return trigger ? Expression::reference(b, loc, ctx, o.descriptors,
                                           trigger.getControl())
                   : logic(bit(false));
  }
  bool level(upf::RetentionTriggerAttr trigger) const {
    return trigger && (trigger.getKind() == upf::RetentionTriggerKind::High ||
                       trigger.getKind() == upf::RetentionTriggerKind::Low);
  }
  Value asserted(Value current, upf::RetentionTriggerAttr trigger) {
    return level(trigger) ? equalsLevel(b, loc, current,
                                        trigger.getKind() ==
                                            upf::RetentionTriggerKind::High)
                          : bit(false);
  }
  Value rawEdge(Value before, Value after, sim::EdgeKind kind) {
    return clockEdge(b, loc, before, after, kind);
  }
  Value event(Value before, Value after, upf::RetentionTriggerAttr trigger) {
    if (!trigger)
      return bit(false);
    if (level(trigger))
      return and_(asserted(before, trigger), not_(asserted(after, trigger)));
    return rawEdge(before, after,
                   trigger.getKind() == upf::RetentionTriggerKind::Posedge
                       ? sim::EdgeKind::Posedge
                       : sim::EdgeKind::Negedge);
  }
  Value overlap(Value ctx) {
    if (!level(strategy.getSave()) || !level(strategy.getRestore()))
      return bit(false);
    return and_(
        and_(asserted(control(ctx, strategy.getSave()), strategy.getSave()),
             predicate(ctx, strategy.getSaveCondition())),
        and_(asserted(control(ctx, strategy.getRestore()),
                      strategy.getRestore()),
             predicate(ctx, strategy.getRestoreCondition())));
  }
  Value writable(Value ctx) {
    Value supply = strategy.getRetentionSupplyCorrupt()
                       ? normal(ctx, retentionSets)
                       : bit(true);
    Value collision =
        strategy.getSaveRestoreCorrupt() ? overlap(ctx) : bit(false);
    return and_(and_(primary(ctx), supply), not_(collision));
  }

  // Make every persistent capture explicit. Snapshot callback closures never
  // perform unbound context lookups, even for policy expressions and supplies.
  FailureOr<Callback> callback(StringRef suffix,
                               llvm::function_ref<Value(Value)> body) {
    auto fn = o.function(loc, name + suffix.str(),
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
  SmallVector<Value> arguments(Value ctx, const Callback &cb) {
    return publicationArguments(b, loc, ctx, cb);
  }
  Value call(Value ctx, Callback cb) {
    return sim::SimCallOp::create(b, loc, cb.function.getResultTypes(),
                                  cb.function.getSymNameAttr(),
                                  arguments(ctx, cb), ArrayAttr{}, ArrayAttr{})
        .getResult(0);
  }
  Value bind(Value ctx, Callback cb, bool dependencies) {
    return bindPublication(b, loc, ctx, cb, dependencies);
  }
  void unpack(Value ctx, Value payload, ArrayRef<Descriptor> targets) {
    uint64_t offset = 0;
    for (auto target : targets) {
      uint64_t width = *sim::getPackedWidth(target.type);
      Value value = slice(payload, offset, width);
      Type scalar = sim::getPackedScalarType(target.type);
      if (isa<IntegerType>(scalar))
        value = sim::SimLogicToBitsOp::create(b, loc, scalar, value);
      if (scalar != target.type)
        value = sim::SimPackedUnflattenOp::create(b, loc, target.type, value);
      write(ctx, target, value);
      offset += width;
    }
  }
  LogicalResult registerSnapshot(StringRef suffix, const Callback &primary,
                                 const Callback &sampler,
                                 ArrayRef<Descriptor> targets) {
    auto owner = o.function(loc, name + suffix.str() + ".owner",
                            {sim::ContextType::get(b.getContext())},
                            sim::EntryKind::Fork);
    sim::mark<sim::metadata::PowerMonitor>(owner);
    schedule::set<schedule::Field::DetachedControls>(owner, b.getUnitAttr());
    schedule::set<schedule::Field::PrimeOnSpawn>(owner, b.getUnitAttr());
    b.setInsertionPointToEnd(&owner.getBody().front());
    Value ctx = owner.getArgument(0);
    Value initial = call(ctx, primary);
    SmallVector<Value> values{bind(ctx, primary, true), initial,
                              bind(ctx, sampler, false)};
    for (auto target : targets)
      values.push_back(handle(b, loc, ctx, target));
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
    root();
    sim::SimSpawnOp::create(b, loc, owner.getSymNameAttr(),
                            ValueRange{o.root.getArgument(0)}, ArrayAttr{},
                            ArrayAttr{});
    return success();
  }

  LogicalResult policy() {
    auto primaryCallback = callback(".policy", [&](Value ctx) {
      SmallVector<Value> inputs;
      for (auto d : dependencies)
        inputs.push_back(read(ctx, d));
      return pack(inputs);
    });
    if (failed(primaryCallback))
      return failure();
    auto sampler = callback(".transfer", [&](Value ctx) {
      Value p = primary(ctx), r = normal(ctx, retentionSets);
      Value ss = control(ctx, strategy.getSave()),
            rs = control(ctx, strategy.getRestore());
      Value sc = predicate(ctx, strategy.getSaveCondition());
      Value rc = predicate(ctx, strategy.getRestoreCondition());
      Value save =
          and_(event(read(ctx, previousSave), ss, strategy.getSave()), sc);
      Value restore = and_(
          event(read(ctx, previousRestore), rs, strategy.getRestore()), rc);
      Value saveAttempt = or_(save, and_(asserted(ss, strategy.getSave()), sc));
      Value restoreAttempt =
          or_(restore, and_(asserted(rs, strategy.getRestore()), rc));
      Value overlapping =
          strategy.getSaveRestoreCorrupt() ? overlap(ctx) : bit(false);
      Value normalBad =
          or_(or_(not_(p),
                  strategy.getRetentionSupplyCorrupt() ? not_(r) : bit(false)),
              overlapping);
      // 6.50 and Figure 6: default RET_SUP_COR destroys normal storage too.
      // Table 10's PARTIAL_CORRUPT comment conflicts with that parameter rule;
      // Figure 6 reserves that transition for NO_RET_SUP_COR.
      Value savedBad =
          or_(or_(not_(r), overlapping),
              and_(not_(p), or_(not_(predicate(ctx, strategy.getCondition())),
                                or_(saveAttempt, restoreAttempt))));
      // A NO_RET_SUP_COR retention-supply loss can destroy only B. Normal
      // clock activations and already issued writes must remain valid.
      Value destructive = normalBad;
      Value levelRestore = level(strategy.getRestore())
                               ? and_(restore, not_(normalBad))
                               : bit(false);
      Value nextEpoch = arith::AddIOp::create(
          b, loc, read(ctx, destructiveEpoch),
          arith::ExtUIOp::create(b, loc, b.getI64Type(), destructive));
      Value nextPriority = arith::AddIOp::create(
          b, loc, read(ctx, priorityEpoch),
          arith::ExtUIOp::create(b, loc, b.getI64Type(),
                                 or_(destructive, levelRestore)));
      SmallVector<Value> outputs{ss, rs, nextEpoch, nextPriority};
      for (auto &state : states) {
        Value before = read(ctx, state.normal),
              retained = read(ctx, state.saved);
        Value restoreValue =
            choose(savedBad, corrupt(b, loc, state.saved.type), retained);
        Value nextNormal = choose(normalBad, corrupt(b, loc, state.normal.type),
                                  choose(restore, restoreValue, before));
        Value nextSaved = choose(savedBad, corrupt(b, loc, state.saved.type),
                                 choose(save, before, retained));
        outputs.append(
            {nextNormal, nextSaved,
             choose(p, nextNormal, corrupt(b, loc, state.visible.type))});
      }
      return pack(outputs);
    });
    if (failed(sampler))
      return failure();
    SmallVector<Descriptor> targets{previousSave, previousRestore,
                                    destructiveEpoch, priorityEpoch};
    for (auto &state : states)
      targets.append({state.normal, state.saved, state.visible});
    root();
    Value ctx = o.root.getArgument(0);
    write(ctx, previousSave, control(ctx, strategy.getSave()));
    write(ctx, previousRestore, control(ctx, strategy.getRestore()));
    write(ctx, destructiveEpoch, integer(0));
    write(ctx, priorityEpoch, integer(0));
    for (auto &state : states) {
      write(ctx, state.normal, read(ctx, state.visible));
      write(ctx, state.saved, corrupt(b, loc, state.saved.type));
    }
    unpack(ctx, call(ctx, *sampler), targets);
    return registerSnapshot(".policy", *primaryCallback, *sampler, targets);
  }

  Operation *guard(Operation *op, Value valid,
                   llvm::function_ref<void()> body) {
    auto *before = op->getBlock();
    auto *execute = before->splitBlock(Block::iterator(op));
    auto *next = execute->splitBlock(std::next(execute->begin()));
    b.setInsertionPointToEnd(before);
    auto branch = cf::CondBranchOp::create(b, loc, valid, execute, next);
    b.setInsertionPoint(op);
    body();
    b.setInsertionPointToEnd(b.getInsertionBlock());
    cf::BranchOp::create(b, loc, next);
    return branch;
  }
  Value viewRoot(Value value) {
    while (auto view = value.getDefiningOp<ViewLikeOpInterface>())
      value = view.getViewSource();
    return value;
  }
  FailureOr<Value> normalView(Value value, Value ctx, Descriptor normal) {
    SmallVector<Operation *> projections;
    Value source = value;
    while (auto view = source.getDefiningOp<ViewLikeOpInterface>()) {
      projections.push_back(view.getOperation());
      source = view.getViewSource();
    }
    Value replacement = handle(b, loc, ctx, normal);
    if (source.getType() != replacement.getType())
      return failure();
    IRMapping mapping;
    mapping.map(source, replacement);
    for (auto *projection : llvm::reverse(projections))
      b.clone(*projection, mapping);
    return mapping.lookup(value);
  }
  bool refersTo(Value reference, uint64_t id) {
    Value root = viewRoot(reference);
    if (auto storage = root.getDefiningOp<sim::SimContextStorageOp>())
      return storage.getId() == id;
    auto argument = dyn_cast<BlockArgument>(root);
    if (!argument)
      return false;
    auto fn = dyn_cast<sim::SimFuncOp>(argument.getOwner()->getParentOp());
    if (!fn || argument.getOwner() != &fn.getBody().front())
      return false;
    auto descriptor = fn.getArgAttrOfType<IntegerAttr>(
        argument.getArgNumber(), sim::metadata::DescriptorId::getNameStr());
    return descriptor && descriptor.getUInt() == id;
  }
  LogicalResult initializeReads(State &state) {
    llvm::SetVector<sim::SimFuncOp> initializers;
    for (auto *op : state.source.writers) {
      auto fn = op->getParentOfType<sim::SimFuncOp>();
      if (fn.getEntryKind() == sim::EntryKind::Initial)
        initializers.insert(fn);
    }
    for (auto fn : initializers) {
      if (failed(validateRetentionReadbackHelpers(
              fn, state.visible.id,
              "balloon retention initialization readback")))
        return failure();
      SmallVector<sim::SimRefLoadOp> loads;
      fn.walk([&](sim::SimRefLoadOp load) {
        if (refersTo(load.getReference(), state.visible.id))
          loads.push_back(load);
      });
      for (auto load : loads) {
        b.setInsertionPoint(load);
        auto reference =
            normalView(load.getReference(), fn.getArgument(0), state.normal);
        if (failed(reference))
          return load.emitError("balloon retention initialization through a "
                                "partial captured alias is not implemented");
        load.getReferenceMutable().assign(*reference);
      }
    }
    return success();
  }
  LogicalResult run() {
    if (strategy.getUseRetentionAsPrimary())
      return emitError(loc)
             << "balloon retention with -use_retention_as_primary requires "
                "resolved storage/output supply semantics and is not "
                "implemented";
    llvm::SetVector<sim::SimFuncOp> writers;
    uint64_t payloadWidth = 130;
    for (auto reg : registers) {
      auto visible =
          Descriptor{reg.declaration.getId(), reg.declaration.getType()};
      uint64_t width = *sim::getPackedWidth(visible.type);
      if (width > (maxPackedWidth - payloadWidth) / 3)
        return emitError(loc)
               << "balloon retention snapshot exceeds supported packed width";
      payloadWidth += 3 * width;
      std::string suffix = "." + std::to_string(visible.id);
      states.push_back(
          {reg, o.storage(loc, name + ".normal" + suffix, visible.type),
           o.storage(loc, name + ".saved" + suffix, visible.type), visible});
      for (Operation *op : reg.writers) {
        auto fn = op->getParentOfType<sim::SimFuncOp>();
        if (fn == o.root && (op->getBlock() != rootBoundary->getBlock() ||
                             !op->isBeforeInBlock(rootBoundary)))
          return op->emitError("balloon retention root initialization after "
                               "startup is not implemented");
        if (fn.getEntryKind() == sim::EntryKind::Always ||
            fn.getEntryKind() == sim::EntryKind::AlwaysFF)
          writers.insert(fn);
      }
    }
    destructiveEpoch = o.storage(loc, name + ".epoch", b.getI64Type());
    priorityEpoch = o.storage(loc, name + ".priority", b.getI64Type());
    previousSave = o.storage(loc, name + ".save_previous",
                             sim::LogicType::get(b.getContext(), 1));
    previousRestore = o.storage(loc, name + ".restore_previous",
                                sim::LogicType::get(b.getContext(), 1));
    llvm::DenseSet<std::pair<uint64_t, uint32_t>> seen;
    auto add = [&](Descriptor d) {
      if (seen.insert({d.id, uint32_t(d.net)}).second)
        dependencies.push_back(d);
    };
    for (auto d : o.domainDependencies)
      add(d);
    for (auto set :
         llvm::concat<const upf::UPFSupplySetOp>(primarySets, retentionSets))
      for (auto ref : getSupplySetReferences(set))
        for (auto d : o.supplyDependencies(ref))
          add(d);
    llvm::SetVector<StringRef> paths;
    for (auto expression :
         {strategy.getCondition(), strategy.getSaveCondition(),
          strategy.getRestoreCondition()})
      for (StringRef path : Expression(expression).controls)
        paths.insert(path);
    for (auto trigger : {strategy.getSave(), strategy.getRestore()})
      if (trigger)
        paths.insert(trigger.getControl().getControl().getValue());
    for (StringRef path : paths) {
      auto found = o.descriptors.find(path);
      if (found == o.descriptors.end() || found->second.driver ||
          !supportedState(found->second.type))
        return emitError(loc) << "retention control is absent from supported "
                                 "simulation storage: "
                              << path;
      add(found->second);
    }
    uint64_t policyWidth = 0;
    for (auto dependency : dependencies) {
      auto width = sim::getPackedWidth(dependency.type);
      if (!width || *width > maxPackedWidth - policyWidth)
        return emitError(loc)
               << "balloon retention policy exceeds supported packed width";
      policyWidth += *width;
    }
    if (failed(policy()))
      return failure();
    for (auto writer : writers) {
      std::string suffix = ".clock." + std::to_string(clocks.size());
      auto frozen = o.clocks->freeze(
          writer, name + suffix, priorityEpoch,
          [&](OpBuilder &sampleBuilder, Location, Value ctx) {
            OpBuilder::InsertionGuard guard(b);
            b.restoreInsertionPoint(sampleBuilder.saveInsertionPoint());
            return writable(ctx);
          });
      if (failed(frozen))
        return failure();
      clocks.push_back({writer, frozen->epoch, frozen->valid});
    }
    nbaPredicate = o.function(loc, name + ".nba_allowed",
                              {sim::ContextType::get(b.getContext())},
                              sim::EntryKind::Observer);
    nbaPredicate.setFunctionType(
        b.getFunctionType(nbaPredicate.getArgumentTypes(), {b.getI1Type()}));
    schedule::set<schedule::Field::ObserverWidth>(nbaPredicate,
                                                  b.getI32IntegerAttr(1));
    schedule::set<schedule::Field::ObserverFourState>(nbaPredicate,
                                                      b.getBoolAttr(false));
    b.setInsertionPointToEnd(&nbaPredicate.getBody().front());
    sim::SimReturnOp::create(b, loc, writable(nbaPredicate.getArgument(0)));
    for (auto &state : states) {
      if (failed(initializeReads(state)))
        return failure();
      for (Operation *op : state.source.writers) {
        auto fn = op->getParentOfType<sim::SimFuncOp>();
        b.setInsertionPoint(op);
        Value ctx = fn.getArgument(0);
        auto clock = llvm::find_if(
            clocks, [&](const Clock &item) { return item.writer == fn; });
        if (clock == clocks.end()) {
          auto write = cast<sim::SimRefStoreOp>(op);
          auto target = normalView(write.getReference(), ctx, state.normal);
          if (failed(target))
            return write.emitError("balloon retention initialization through a "
                                   "partial captured alias is not implemented");
          store(b, loc, *target, write.getValue());
          // 9.2.1 exempts model initialization in initial blocks. Preserve
          // that write to normal storage, but the inferred output driver
          // still requires power (6.50/9.7.2).
          if (fn.getEntryKind() == sim::EntryKind::Initial)
            write.getValueMutable().assign(choose(
                and_(primary(ctx), strategy.getRetentionSupplyCorrupt()
                                       ? normal(ctx, retentionSets)
                                       : bit(true)),
                write.getValue(), corrupt(b, loc, write.getValue().getType())));
          continue;
        }
        Value valid =
            and_(writable(ctx),
                 and_(read(ctx, clock->valid),
                      arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq,
                                            read(ctx, clock->epoch),
                                            read(ctx, priorityEpoch))));
        Value destructive, priority, domain;
        if (isa<sim::SimNBAEnqueueOp>(op)) {
          destructive = read(ctx, destructiveEpoch);
          if (level(strategy.getRestore()))
            priority = read(ctx, priorityEpoch);
          domain = read(ctx, o.domainEpoch);
        }
        SmallVector<Operation *> enqueues;
        auto *branch = guard(op, valid, [&] {
          if (auto write = dyn_cast<sim::SimRefStoreOp>(op))
            this->write(ctx, state.normal, write.getValue());
          else {
            auto enqueue = cast<sim::SimNBAEnqueueOp>(op);
            SmallVector<Value> watched;
            for (auto d : dependencies)
              watched.push_back(handle(b, loc, ctx, d));
            Value predicate = sim::SimObserverBindOp::create(
                b, loc, sim::ObserverType::get(b.getContext(), b.getI1Type()),
                nbaPredicate.getSymNameAttr(), watched, 0);
            auto issue = [&](Descriptor epoch, Value captured) {
              enqueues.push_back(sim::SimPowerNBAOp::create(
                  b, loc, ctx, enqueue.getValue(),
                  handle(b, loc, ctx, state.normal),
                  handle(b, loc, ctx, state.visible), predicate,
                  handle(b, loc, ctx, o.domainEpoch), domain,
                  handle(b, loc, ctx, epoch), captured, enqueue.getDelay()));
            };
            // Carry level-restore priority through a current-step NBA as
            // well as its clock activation (6.50, LRM 4.9.4/10.4.2). Future
            // timed writes retain only destructive-corruption validity.
            if (!priority) {
              issue(destructiveEpoch, destructive);
            } else if (!enqueue.getDelay()) {
              issue(priorityEpoch, priority);
            } else {
              Value zero =
                  sim::SimTimeIsZeroOp::create(b, loc, enqueue.getDelay());
              Block *before = enqueue->getBlock();
              Block *join = before->splitBlock(Block::iterator(enqueue));
              auto *current = new Block;
              auto *future = new Block;
              auto &blocks = before->getParent()->getBlocks();
              blocks.insert(join->getIterator(), current);
              blocks.insert(join->getIterator(), future);
              b.setInsertionPointToEnd(before);
              cf::CondBranchOp::create(b, loc, zero, current, future);
              b.setInsertionPointToEnd(current);
              issue(priorityEpoch, priority);
              cf::BranchOp::create(b, loc, join);
              b.setInsertionPointToEnd(future);
              issue(destructiveEpoch, destructive);
              cf::BranchOp::create(b, loc, join);
            }
            b.setInsertionPoint(enqueue);
            enqueue.erase();
          }
        });
        writes.push_back({o.domainEpoch, branch, std::move(enqueues)});
      }
    }
    return success();
  }
};
} // namespace

LogicalResult lowerBalloonRetention(const RetentionLoweringOptions &options,
                                    upf::RetentionAttr strategy,
                                    ArrayRef<upf::UPFSupplySetOp> primary,
                                    ArrayRef<upf::UPFSupplySetOp> retention,
                                    ArrayRef<BalloonRegister> registers,
                                    Operation *rootBoundary,
                                    SmallVectorImpl<RetentionWrite> &writes) {
  return BalloonLowering(options, strategy, primary, retention, registers,
                         rootBoundary, writes)
      .run();
}
} // namespace talos
