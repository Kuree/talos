// Power guards and corruption writes remain visible to subsequent analyses.
#include "ControlValue.h"
#include "ElaborateSupply.h"
#include "PowerState.h"
#include "ReferenceWindow.h"
#include "Retention.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "mlir/Pass/Pass.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "talos/Frontend/UPF.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringSet.h"
#include <memory>
#include <set>
#include <tuple>
using namespace mlir;
namespace talos {
namespace {
using namespace upf_detail;
struct PowerCondition {
  SmallVector<Expression> on, partial, errors;
  Expression off;
  llvm::SetVector<StringRef> controls;
  llvm::SetVector<upf::ExpressionTokenAttr> references, onReferences;
  const llvm::StringMap<Descriptor> &descriptors;
  const llvm::StringMap<Descriptor> &supplies;
  SmallVector<upf::UPFSupplySetOp> policies;
  SmallVector<Descriptor> policyInputs;
  Descriptor power;
  std::optional<Descriptor> input, ground;
  SmallVector<Descriptor> required;
  std::optional<upf::PartialOnTranslation> translation;
  PowerCondition(upf::UPFDomainOp domain,
                 const llvm::StringMap<Descriptor> &descriptors,
                 const llvm::StringMap<Descriptor> &supplies)
      : off(domain.getOffAttr() ? domain.getOffAttr().getCondition()
                                : upf::ExpressionAttr{}),
        descriptors(descriptors), supplies(supplies),
        power(supplies.lookup(domain.getPowerAttr().getValue())),
        translation(upf::getPartialOnTranslation(domain)) {
    if (auto attr = domain.getInputAttr())
      input = supplies.lookup(attr.getValue());
    if (auto attr = domain.getGroundAttr())
      ground = supplies.lookup(attr.getValue());
    if (auto attrs = domain.getPoliciesAttr()) {
      for (auto attr : attrs)
        policies.push_back(
            SymbolTable::lookupNearestSymbolFrom<upf::UPFSupplySetOp>(
                domain, cast<FlatSymbolRefAttr>(attr)));
    } else if (auto primary = domain.getPrimaryAttr())
      policies.push_back(
          SymbolTable::lookupNearestSymbolFrom<upf::UPFSupplySetOp>(domain,
                                                                    primary));
    llvm::DenseSet<uint64_t> policyIDs;
    for (auto policy : policies)
      for (auto ref : getSupplySetReferences(policy)) {
        auto descriptor = supplies.lookup(ref.getValue());
        if (policyIDs.insert(descriptor.id).second)
          policyInputs.push_back(descriptor);
      }
    if (auto primary = domain.getPrimaryAttr()) {
      auto set = SymbolTable::lookupNearestSymbolFrom<upf::UPFSupplySetOp>(
          domain, primary);
      llvm::DenseSet<uint64_t> seen;
      for (auto attr : set.getRequired()) {
        auto name = cast<StringAttr>(attr).getValue();
        if (name != "power" && name != "ground") {
          auto supply = supplies.lookup(
              cast<FlatSymbolRefAttr>(set.getFunctions().get(name)).getValue());
          if (seen.insert(supply.id).second)
            required.push_back(supply);
        }
      }
    }
    auto collect = [&](const Expression &expression, bool onState) {
      for (auto path : expression.controls)
        controls.insert(path);
      for (auto token : expression.references) {
        references.insert(token);
        if (onState)
          onReferences.insert(token);
      }
    };
    for (auto attr : domain.getOn()) {
      on.emplace_back(cast<upf::SwitchStateAttr>(attr).getCondition());
      collect(on.back(), true);
    }
    if (auto states = domain.getPartialAttr())
      for (auto attr : states) {
        partial.emplace_back(cast<upf::SwitchStateAttr>(attr).getCondition());
        collect(partial.back(), true);
      }
    collect(off, false);
    if (auto states = domain.getErrorsAttr())
      for (auto attr : states) {
        errors.emplace_back(cast<upf::SwitchStateAttr>(attr).getCondition());
        collect(errors.back(), false);
      }
  }
  Value any(OpBuilder &b, Location loc, Value context,
            ArrayRef<Expression> expressions) const {
    Value result = arith::ConstantIntOp::create(b, loc, 0, 1);
    for (const auto &expression : expressions)
      result = arith::OrIOp::create(
          b, loc, result, expression.predicate(b, loc, context, descriptors));
    return result;
  }
  Value knownOn(OpBuilder &b, Location loc, Value context) const {
    // IEEE 1801-2018 6.22: use the references before expression folding.
    // Any X/Z object referenced by ON/PARTIAL contributes UNDETERMINED, even
    // when masked by a constant or in an inactive ON/PARTIAL state. Unused,
    // OFF-only and ERROR-only controls do not participate in this knownness
    // check.
    Value result = arith::ConstantIntOp::create(b, loc, 1, 1);
    for (auto token : onReferences) {
      Value value = Expression::reference(b, loc, context, descriptors, token);
      auto logic = sim::LogicType::get(b.getContext(), 1);
      Value x = logicConstant(b, loc, logic, false, true);
      Value z = logicConstant(b, loc, logic, true, true);
      Value count = sim::SimLogicCountBitsOp::create(b, loc, b.getI32Type(),
                                                     value, ValueRange{x, z});
      Value known =
          arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, count,
                                arith::ConstantIntOp::create(b, loc, 0, 32));
      result = arith::AndIOp::create(b, loc, result, known);
    }
    return result;
  }
  Value normal(OpBuilder &b, Location loc, Value context,
               bool inlineOutput = true) const {
    if (!policies.empty()) {
      Value result = arith::ConstantIntOp::create(b, loc, 1, 1);
      for (auto policy : policies) {
        auto value = evaluateSupplySet(
            policy, b, loc, [&](FlatSymbolRefAttr ref) -> Value {
              auto source = supplies.lookup(ref.getValue());
              // Evaluate our output inline, preserving clock/NBA ordering when
              // source voltage or controls changed in this same activation.
              if (inlineOutput && input && source.id == power.id)
                return drivenSupply(b, loc, context);
              return load(b, loc, handle(b, loc, context, source));
            });
        result = arith::AndIOp::create(b, loc, result, value.normal);
      }
      return result;
    }
    auto fullValue = [&](Value value) -> Value {
      Value state = interpretedSupplyState(b, loc, value, translation);
      return arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, state,
                                   arith::ConstantIntOp::create(b, loc, 1, 32));
    };
    auto full = [&](Descriptor supply) -> Value {
      return fullValue(load(b, loc, handle(b, loc, context, supply)));
    };
    // Legacy textual IR without supply sets still interprets the computed
    // output state, including current-limited contributions (6.22/6.47).
    Value result = input && inlineOutput
                       ? fullValue(drivenSupply(b, loc, context))
                       : full(power);
    // IEEE 1801-2018 4.7.4: every required primary function must be FULL_ON.
    // Ground at zero volts is powered; voltage itself is not an ON predicate.
    if (ground)
      result = arith::AndIOp::create(b, loc, result, full(*ground));
    for (auto supply : required)
      if (supply.id != power.id && (!ground || supply.id != ground->id))
        result = arith::AndIOp::create(b, loc, result, full(supply));
    return result;
  }
  Value drivenSupply(OpBuilder &b, Location loc, Value context) const {
    auto integer = [&](int64_t v) -> Value {
      return arith::ConstantIntOp::create(b, loc, v, 64);
    };
    Value value = load(b, loc, handle(b, loc, context, *input));
    Value state = arith::AndIOp::create(b, loc, value, integer(3));
    // 6.22: ON passes the input; PARTIAL degrades only FULL_ON. A full
    // contribution wins over a partial one from this same input supply.
    Value degraded = arith::SelectOp::create(
        b, loc,
        arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, state,
                              integer(1)),
        integer(2), state);
    Value output = arith::SelectOp::create(
        b, loc, any(b, loc, context, partial), degraded, integer(0));
    output = arith::SelectOp::create(b, loc, any(b, loc, context, on), state,
                                     output);
    Value notOff = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ne,
                                         state, integer(0));
    Value unknown =
        arith::XOrIOp::create(b, loc, knownOn(b, loc, context),
                              arith::ConstantIntOp::create(b, loc, 1, 1));
    unknown = arith::AndIOp::create(b, loc, unknown, notOff);
    // IEEE 1801-2018 6.22: unknown ON/PARTIAL controls contribute UNDETERMINED
    // only when the input is not OFF. ERROR and explicit OFF conflicts take
    // precedence regardless of the input state.
    Value invalid = any(b, loc, context, errors);
    if (!off.nodes.empty())
      invalid =
          arith::OrIOp::create(b, loc, invalid, conflict(b, loc, context));
    invalid = arith::OrIOp::create(b, loc, invalid, unknown);
    output = arith::SelectOp::create(b, loc, invalid, integer(3), output);
    Value powered = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq,
                                          output, integer(1));
    Value partial = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq,
                                          output, integer(2));
    powered = arith::OrIOp::create(b, loc, powered, partial);
    Value volts = arith::AndIOp::create(b, loc, value, integer(0x3fffffffcULL));
    volts = arith::SelectOp::create(b, loc, powered, volts, integer(0));
    return arith::OrIOp::create(b, loc, output, volts);
  }
  Value conflict(OpBuilder &b, Location loc, Value context) const {
    Value active = arith::OrIOp::create(b, loc, any(b, loc, context, on),
                                        any(b, loc, context, partial));
    return arith::AndIOp::create(b, loc, active,
                                 off.predicate(b, loc, context, descriptors));
  }
};
Value logicSelect(OpBuilder &b, Location loc, Value condition, Value yes,
                  Value no) {
  Value logic = sim::SimLogicFromBitsOp::create(
      b, loc, sim::LogicType::get(b.getContext(), 1), condition);
  return sim::SimLogicMuxOp::create(b, loc, yes.getType(), logic, yes, no);
}
bool levelProcess(sim::EntryKind kind) {
  return kind == sim::EntryKind::AlwaysComb ||
         kind == sim::EntryKind::AlwaysLatch ||
         kind == sim::EntryKind::Continuous ||
         kind == sim::EntryKind::PortInput ||
         kind == sim::EntryKind::PortInitialize;
}
LogicalResult synchronousHelper(sim::SimCallOp call) {
  // IEEE 1801-2018 9.5.3: a guarded activation can call a synchronous helper,
  // but work queued by that helper needs separate power-loss cancellation.
  // Inspect the complete direct-call closure, including recursive functions.
  SmallVector<sim::SimCallOp> pending{call};
  llvm::DenseSet<Operation *> visited;
  while (!pending.empty()) {
    auto site = pending.pop_back_val();
    auto target = SymbolTable::lookupNearestSymbolFrom<sim::SimFuncOp>(
        site, site.getCalleeAttr());
    if (!target || target.getEntryKind() != sim::EntryKind::Function ||
        target.getBody().empty())
      return site.emitError("UPF calls require a defined synchronous helper");
    if (!visited.insert(target).second)
      continue;
    WalkResult result = target.walk([&](Operation *op) {
      if (auto nested = dyn_cast<sim::SimCallOp>(op)) {
        pending.push_back(nested);
        return WalkResult::advance();
      }
      // IEEE 1801-2018 11.2.3.2.6 samples synchronously. Its conditional
      // diagnostic records failure but queues no work needing cancellation.
      // Keep the op's scheduler/IO effects for optimization and error handling.
      if (isa<sim::SimSupplyReadOp>(op))
        return WalkResult::advance();
      bool asynchronous =
          sim::isSuspensionOp(op) ||
          isa<sim::SimSpawnOp, sim::SimTaskCallOp,
              sim::SimClassVirtualTaskCallOp, sim::SimDPICallOp,
              sim::SimClassDirectCallOp, sim::SimClassVirtualCallOp>(op);
      if (auto interface = dyn_cast<MemoryEffectOpInterface>(op)) {
        SmallVector<MemoryEffects::EffectInstance> effects;
        interface.getEffects(effects);
        asynchronous |= llvm::any_of(effects, [](const auto &effect) {
          return !isa<MemoryEffects::Read>(effect.getEffect()) &&
                 isa<sim::SchedulerResource, sim::ProcessResource>(
                     effect.getResource());
        });
      }
      if (asynchronous) {
        op->emitError(
            "asynchronous work in a UPF helper call is not implemented");
        return WalkResult::interrupt();
      }
      return WalkResult::advance();
    });
    if (result.wasInterrupted())
      return failure();
  }
  return success();
}
struct Lowering {
  sim::SimDesignOp design;
  OpBuilder builder;
  uint64_t nextStorage = 0, nextUnit = 0;
  llvm::StringMap<Descriptor> descriptors;
  llvm::StringMap<Descriptor> supplies;
  llvm::DenseMap<uint64_t, std::unique_ptr<PowerCondition>> computed;
  SmallVector<SupplyTableEntry> supplyTable;
  llvm::DenseMap<uint64_t, std::string> unitPaths;
  llvm::DenseMap<uint64_t, std::string> scopePaths;
  llvm::DenseMap<uint64_t, sim::SimCodeUnitDeclOp> units;
  llvm::StringMap<uint64_t> unitIDs;
  sim::SimFuncOp root;
  std::unique_ptr<ReferenceWindows> nbaWindows;
  Lowering(sim::SimDesignOp design)
      : design(design), builder(design.getContext()) {
    for (auto scope : design.getOps<sim::SimScopeDeclOp>())
      if (auto name = scope.getHierarchicalName())
        scopePaths[scope.getId()] = name->str();
    for (auto decl : design.getOps<sim::SimStorageDeclOp>()) {
      nextStorage = std::max(nextStorage, decl.getId() + 1);
      if (auto name = decl.getHierarchicalName())
        descriptors[*name] = {decl.getId(), decl.getType()};
    }
    for (auto decl : design.getOps<sim::SimNetDeclOp>())
      if (auto name = decl.getHierarchicalName())
        descriptors[*name] = {decl.getId(), decl.getType(), true};
    for (auto decl : design.getOps<sim::SimCodeUnitDeclOp>()) {
      nextUnit = std::max(nextUnit, decl.getId() + 1);
      unitPaths[decl.getId()] = decl.getHierarchicalName().str();
      units[decl.getId()] = decl;
      unitIDs[decl.getHierarchicalName()] = decl.getId();
    }
    for (auto fn : design.getOps<sim::SimFuncOp>())
      if (fn.getEntryKind() == sim::EntryKind::RootInitializer)
        root = fn;
  }
  sim::SimFuncOp function(Location loc, StringRef name, ArrayRef<Type> inputs,
                          sim::EntryKind kind) {
    builder.setInsertionPointToEnd(&design.getBody().front());
    uint64_t id = nextUnit++;
    sim::SimCodeUnitDeclOp::create(
        builder, loc, id, uint64_t{0}, kind, builder.getStringAttr(name),
        builder.getStringAttr(name), builder.getUnitAttr());
    SmallVector<NamedAttribute> attrs{
        builder.getNamedAttr("code_unit_id", builder.getI64IntegerAttr(id)),
        builder.getNamedAttr("internal", builder.getUnitAttr()),
        sim::named<sim::metadata::HierarchicalName>(
            builder.getStringAttr(name))};
    SmallVector<DictionaryAttr> args;
    for (size_t i = 0; i < inputs.size(); ++i)
      args.push_back(builder.getDictionaryAttr(
          {sim::named<sim::metadata::CaptureKind>(sim::CaptureKindAttr::get(
              builder.getContext(), i == 0 ? sim::CaptureKind::Context
                                           : sim::CaptureKind::Formal))}));
    auto fn = sim::SimFuncOp::create(builder, loc, name,
                                     builder.getFunctionType(inputs, {}), kind,
                                     attrs, args);
    SymbolTable::setSymbolVisibility(fn, SymbolTable::Visibility::Private);
    sim::mark<sim::metadata::Lowered>(fn);
    return fn;
  }
  Descriptor storage(Location loc, StringRef name, Type type) {
    builder.setInsertionPointToStart(&design.getBody().front());
    Descriptor result{nextStorage++, type};
    sim::SimStorageDeclOp::create(
        builder, loc, result.id, uint64_t{0}, type, sim::Lifetime::Design,
        builder.getStringAttr(name), builder.getStringAttr(name),
        schedule::ComputeObservabilityKindAttr{}, sim::VPITypeSemanticsAttr{});
    return result;
  }
  SmallVector<Descriptor> supplyInputs(Descriptor source) {
    SmallVector<Descriptor> result;
    std::set<std::tuple<uint64_t, bool, bool>> seen;
    SmallVector<Descriptor> pending{source};
    while (!pending.empty()) {
      Descriptor value = pending.pop_back_val();
      if (!seen.emplace(value.id, value.net, value.driver).second)
        continue;
      auto found = computed.find(value.id);
      if (value.net || value.driver || found == computed.end()) {
        result.push_back(value);
        continue;
      }
      // IEEE 1801-2018 9.2.2: computed state is observed at the source
      // publication, independently of the switch-monitor's dispatch order.
      const PowerCondition &condition = *found->second;
      for (auto path : condition.controls)
        pending.push_back(descriptors.lookup(path));
      if (condition.input)
        pending.push_back(*condition.input);
      if (condition.ground)
        pending.push_back(*condition.ground);
      for (Descriptor input : condition.required)
        if (input.id != condition.power.id)
          pending.push_back(input);
      for (Descriptor input : condition.policyInputs)
        if (input.id != condition.power.id)
          pending.push_back(input);
    }
    return result;
  }
  LogicalResult monitorStates(ArrayRef<upf::UPFSupplySetOp> sets) {
    for (auto set : sets) {
      if (!set.getStatesAttr() || set.getStatesAttr().empty())
        continue;
      Location loc = set.getLoc();
      auto monitor = function(loc, "__upf_states." + set.getSymName().str(),
                              {sim::ContextType::get(builder.getContext())},
                              sim::EntryKind::Always);
      sim::mark<sim::metadata::PowerMonitor>(monitor);
      auto &entry = monitor.getBody().front();
      auto *loop = new Block, *wait = new Block;
      monitor.getBody().push_back(loop);
      monitor.getBody().push_back(wait);
      builder.setInsertionPointToEnd(&entry);
      Value context = entry.getArgument(0);
      cf::BranchOp::create(builder, loc, loop);
      builder.setInsertionPointToEnd(loop);
      auto state =
          evaluateSupplySet(set, builder, loc, [&](FlatSymbolRefAttr ref) {
            auto supply = supplies.lookup(ref.getValue());
            if (auto condition = computed.find(supply.id);
                condition != computed.end())
              return condition->second->drivenSupply(builder, loc, context);
            return load(builder, loc, handle(builder, loc, context, supply));
          });
      auto report = [&](Value error, StringRef reason, StringRef clause) {
        auto *message = new Block, *next = new Block;
        monitor.getBody().push_back(message);
        monitor.getBody().push_back(next);
        cf::CondBranchOp::create(builder, loc, error, message, next);
        builder.setInsertionPointToEnd(message);
        sim::SimErrorOp::create(builder, loc, context);
        Value text = sim::SimBytesConstantOp::create(
            builder, loc,
            "UPF supply set " + set.getSymName().str() + ": " + reason.str() +
                " (IEEE 1801-2018 " + clause.str() + ")");
        sim::SimDisplayOp::create(
            builder, loc, context,
            arith::ConstantIntOp::create(builder, loc, 0x80000002u, 32),
            ValueRange{text}, true, sim::Radix::Decimal,
            builder.getDenseI32ArrayAttr({0}), StringAttr{}, StringAttr{},
            IntegerAttr{}, IntegerAttr{});
        cf::BranchOp::create(builder, loc, next);
        builder.setInsertionPointToEnd(next);
      };
      // 4.7.3/6.5.6(n): diagnose overlap/illegality independently. An illegal
      // NORMAL row still has NORMAL behavior; only current ERROR corrupts.
      report(state.conflict, "overlapping power states", "4.7.3/9.3.2");
      report(state.illegal, "illegal power state", "6.5.6n");
      cf::BranchOp::create(builder, loc, wait);
      builder.setInsertionPointToEnd(wait);
      std::set<std::tuple<uint64_t, bool, bool>> ids;
      SmallVector<Value> watched;
      auto watch = [&](Descriptor supply) {
        if (ids.emplace(supply.id, supply.net, supply.driver).second)
          watched.push_back(handle(builder, loc, context, supply));
      };
      for (auto ref : getSupplySetReferences(set)) {
        auto supply = supplies.lookup(ref.getValue());
        if (auto condition = computed.find(supply.id);
            condition != computed.end()) {
          watch(*condition->second->input);
          for (auto path : condition->second->controls)
            watch(descriptors.lookup(path));
        } else
          watch(supply);
      }
      if (watched.empty())
        sim::SimReturnOp::create(builder, loc, ValueRange{});
      else
        sim::SimSuspendAnyOp::create(
            builder, loc, watched,
            builder.getDenseI32ArrayAttr(
                SmallVector<int32_t>(watched.size(), 0)),
            schedule::ContinuationSiteAttr{}, sim::EventRegionAttr{}, loop);
      Operation *first = root.getBody().front().getTerminator();
      for (auto &op : root.getBody().front())
        if (isa<sim::SimSpawnOp>(op)) {
          first = &op;
          break;
        }
      builder.setInsertionPoint(first);
      sim::SimSpawnOp::create(builder, loc, monitor.getSymNameAttr(),
                              ValueRange{root.getArgument(0)}, ArrayAttr{},
                              ArrayAttr{});
    }
    return success();
  }
  LogicalResult prepareSupplies(ArrayRef<upf::UPFSupplyOp> roots) {
    if (roots.empty())
      return success();
    if (!root)
      return design.emitError("UPF needs an executable design root");
    llvm::StringSet<> names;
    for (auto supply : roots)
      for (auto name : supply.getNames())
        if (!names.insert(cast<StringAttr>(name).getValue()).second)
          return supply.emitError("ambiguous supply handle name: ") << name;
    for (auto supply : roots) {
      auto d =
          storage(supply.getLoc(), supply.getSymName(), builder.getI64Type());
      supplies[supply.getSymName()] = d;
      for (auto name : supply.getNames())
        supplyTable.push_back(
            {cast<StringAttr>(name), d.id, supply.getWritable()});
      // IEEE 1801-2018 9.2.1 initializes supplies before HDL model
      // initialization. Declaration initializers can already read or write a
      // supply (11.2.3.2.6/11.2.3.3.4); initializing only before the first
      // process spawn would sample the wrong value or overwrite such a write.
      builder.setInsertionPointToStart(&root.getBody().front());
      Value ref = handle(builder, supply.getLoc(), root.getArgument(0), d);
      store(builder, supply.getLoc(), ref,
            arith::ConstantIntOp::create(builder, supply.getLoc(),
                                         supply.getInitialValue(), 64));
    }
    return success();
  }
  LogicalResult watch(sim::SimFuncOp fn, Descriptor descriptor) {
    builder.setInsertionPointToStart(&fn.getBody().front());
    Value reference =
        handle(builder, fn.getLoc(), fn.getArgument(0), descriptor);
    SmallVector<Operation *> waits;
    fn.walk([&](Operation *op) {
      if (isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp>(op))
        waits.push_back(op);
    });
    for (Operation *op : waits) {
      if (auto any = dyn_cast<sim::SimSuspendAnyOp>(op)) {
        SmallVector<Value> values(any.getWatched());
        values.push_back(reference);
        llvm::append_range(values, any.getContinuationOperands());
        SmallVector<int32_t> edges(any.getEdges());
        edges.push_back(0);
        any.getValuesMutable().assign(values);
        any.setEdgesAttr(builder.getDenseI32ArrayAttr(edges));
      } else {
        auto change = cast<sim::SimSuspendChangeOp>(op);
        builder.setInsertionPoint(op);
        SmallVector<Value> values{change.getWatched(), reference};
        llvm::append_range(values, change.getContinuationOperands());
        sim::SimSuspendAnyOp::create(
            builder, op->getLoc(), values, builder.getDenseI32ArrayAttr({0, 0}),
            change.getSiteAttr(), change.getResumeRegionAttr(),
            change.getContinuation());
        op->erase();
      }
    }
    return success();
  }
  LogicalResult isolation(sim::SimFuncOp fn, upf::UPFDomainOp domain,
                          Descriptor control) {
    // IEEE 1801-2018 9.8: an unknown isolation control corrupts the output,
    // even when data equals the clamp. Explicit known-level tests avoid the
    // equal-bit merging that an ordinary SystemVerilog conditional would use.
    if (failed(watch(fn, control)))
      return failure();
    SmallVector<Operation *> writes;
    fn.walk([&](Operation *op) {
      if (isa<sim::SimDriverDriveOp, sim::SimRefStoreOp, sim::SimNetWriteOp>(
              op))
        writes.push_back(op);
    });
    if (writes.empty())
      return fn.emitError(
          "UPF isolation requires an explicit scalar output connection");
    for (Operation *op : writes) {
      Value value;
      if (auto drive = dyn_cast<sim::SimDriverDriveOp>(op))
        value = drive.getValue();
      if (auto write = dyn_cast<sim::SimRefStoreOp>(op))
        value = write.getValue();
      if (auto write = dyn_cast<sim::SimNetWriteOp>(op))
        value = write.getValue();
      Type outputType = value.getType();
      auto logic = dyn_cast_or_null<sim::LogicType>(
          sim::getPackedScalarType(outputType));
      if (!logic || !supportedState(outputType))
        return op->emitError(
            "initial UPF isolation requires four-state packed outputs");
      builder.setInsertionPoint(op);
      value = flatten(builder, op->getLoc(), value);
      Value input =
          load(builder, op->getLoc(),
               handle(builder, op->getLoc(), fn.getArgument(0), control));
      Value active =
          equalsLevel(builder, op->getLoc(), input, domain.getIsolationHigh());
      Value inactive =
          equalsLevel(builder, op->getLoc(), input, !domain.getIsolationHigh());
      Value data = logicSelect(builder, op->getLoc(), inactive, value,
                               corrupt(builder, op->getLoc(), logic));
      Value result = logicSelect(
          builder, op->getLoc(), active,
          logicConstant(builder, op->getLoc(), logic, domain.getClamp() != 0),
          data);
      if (result.getType() != outputType)
        result = sim::SimPackedUnflattenOp::create(builder, op->getLoc(),
                                                   outputType, result);
      if (auto drive = dyn_cast<sim::SimDriverDriveOp>(op))
        drive.getValueMutable().assign(result);
      if (auto write = dyn_cast<sim::SimRefStoreOp>(op))
        write.getValueMutable().assign(result);
      if (auto write = dyn_cast<sim::SimNetWriteOp>(op))
        write.getValueMutable().assign(result);
    }
    return success();
  }
  LogicalResult gate(sim::SimFuncOp fn, const PowerCondition &condition,
                     Descriptor restoration) {
    SmallVector<Operation *> waits;
    fn.walk([&](Operation *op) {
      if (op->getName().getStringRef().starts_with("simulation.suspend."))
        waits.push_back(op);
    });
    if (waits.empty() && levelProcess(fn.getEntryKind())) {
      // IEEE 1801-2018 9.6.7: even a constant expression must reevaluate on
      // restoration. Keep its original body behind the guard, and replace
      // returns with a power-control wait. Never branch into the region entry.
      Block &entry = fn.getBody().front();
      Block *body = entry.splitBlock(entry.begin());
      Block *activation = new Block, *wait = new Block;
      fn.getBody().push_back(activation);
      fn.getBody().push_back(wait);
      SmallVector<sim::SimReturnOp> returns;
      fn.walk([&](sim::SimReturnOp op) { returns.push_back(op); });
      for (auto op : returns) {
        builder.setInsertionPoint(op);
        cf::BranchOp::create(builder, op.getLoc(), wait);
        op.erase();
      }
      builder.setInsertionPointToEnd(&entry);
      Value watched =
          handle(builder, fn.getLoc(), fn.getArgument(0), restoration);
      cf::BranchOp::create(builder, fn.getLoc(), activation);
      builder.setInsertionPointToEnd(activation);
      Value on = condition.normal(builder, fn.getLoc(), fn.getArgument(0));
      on = arith::AndIOp::create(builder, fn.getLoc(), on,
                                 load(builder, fn.getLoc(), watched));
      cf::CondBranchOp::create(builder, fn.getLoc(), on, body, wait);
      builder.setInsertionPointToEnd(wait);
      sim::SimSuspendChangeOp::create(
          builder, fn.getLoc(), watched, ValueRange{},
          schedule::ContinuationSiteAttr{}, sim::EventRegionAttr{}, activation);
      return success();
    }
    if (waits.size() != 1)
      return fn.emitError("initial UPF domain requires one repeating event "
                          "control per process");
    Operation *wait = waits.front();
    if (!isa<sim::SimSuspendChangeOp, sim::SimSuspendAnyOp,
             sim::SimSuspendEdgeOp, sim::SimSuspendEdgeIffOp>(wait))
      return wait->emitError(
          "blocking timing inside a switchable domain is not implemented");
    // IEEE 1801-2018 9.5.3/9.6.2 suppress the complete activation, including
    // branches preceding the wait. The wait's continuation is the activation
    // entry for both explicit event controls and implicit combinational loops.
    Block *skip;
    Block *gate = wait->getSuccessor(0);
    bool leadingWait = wait->hasAttr("schedule.repeating_always_wait") ||
                       wait->hasAttr("schedule.top_level_wildcard_wait");
    if (leadingWait) {
      skip = wait->getBlock();
    } else {
      if (!levelProcess(fn.getEntryKind()))
        return fn.emitError("UPF requires a top-level repeating event control");
      Block *last = wait->getBlock();
      skip = last->splitBlock(Block::iterator(wait));
      builder.setInsertionPointToEnd(last);
      cf::BranchOp::create(builder, fn.getLoc(), skip);
    }
    if (skip->getNumArguments() != 0 || gate == &fn.getBody().front())
      return fn.emitError("initial UPF process requires an explicit repeating "
                          "sensitivity loop");
    // IEEE 1801-2018 9.6.7: restoration reevaluates combinational/level logic,
    // but must not invent an edge activation for edge-sensitive state.
    bool edgeSensitive =
        isa<sim::SimSuspendEdgeOp, sim::SimSuspendEdgeIffOp>(wait);
    if (auto any = dyn_cast<sim::SimSuspendAnyOp>(wait)) {
      bool level = llvm::is_contained(any.getEdges(), 0);
      bool edge =
          llvm::any_of(any.getEdges(), [](int32_t kind) { return kind != 0; });
      if (edge && level)
        return fn.emitError("mixed level/edge sensitivity in a switchable "
                            "domain is not implemented");
      edgeSensitive = edge;
    }
    Block *body = gate->splitBlock(gate->begin());
    builder.setInsertionPointToEnd(gate);
    Value on = condition.normal(builder, fn.getLoc(), fn.getArgument(0));
    if (!edgeSensitive) {
      // IEEE 1801-2018 9.2.1/9.6.7: control-net routing can settle after the
      // root's initial aggregate snapshot. Wait for publication before the
      // first level activation, avoiding a second startup "restoration" run.
      Value published =
          load(builder, fn.getLoc(),
               handle(builder, fn.getLoc(), fn.getArgument(0), restoration));
      on = arith::AndIOp::create(builder, fn.getLoc(), on, published);
    }
    cf::CondBranchOp::create(builder, fn.getLoc(), on, body, ValueRange{}, skip,
                             ValueRange{});
    // Only aggregate power transitions wake level logic. A raw control can
    // change while the domain remains NORMAL without activating HDL code.
    return edgeSensitive ? success() : watch(fn, restoration);
  }
  LogicalResult nba(sim::SimNBAEnqueueOp enqueue, sim::SimFuncOp predicate,
                    ArrayRef<Descriptor> dependencies, Descriptor epoch) {
    // IEEE 1801-2018 9.5.3: events queued before CORRUPT have no effect.
    // Capturing the epoch also prevents an OFF/ON cycle from reviving an old
    // delayed event merely because the domain is NORMAL again at commit time.
    sim::SimFuncOp caller = enqueue->getParentOfType<sim::SimFuncOp>();
    Location loc = enqueue.getLoc();
    if (!isa<sim::RefType>(enqueue.getDestination().getType()))
      return enqueue.emitError("guarded UPF NBA requires a storage reference");
    auto window = nbaWindows->get(enqueue.getDestination());
    if (failed(window))
      return failure();
    Type rootScalar = sim::getPackedScalarType(window->root.type);
    if (!rootScalar)
      return enqueue.emitError(
          "guarded UPF NBA requires a packed integral root");
    builder.setInsertionPoint(enqueue);
    Value context = caller.getArgument(0);
    Value data = flatten(builder, loc, enqueue.getValue());
    // The view primitive writes the root's state planes. In mixed packed
    // aggregates a two-state selected field still clears its old unknown bits.
    if (isa<sim::LogicType>(rootScalar) && isa<IntegerType>(data.getType()))
      data = sim::SimLogicFromBitsOp::create(
          builder, loc,
          sim::LogicType::get(builder.getContext(),
                              *sim::getPackedWidth(data.getType())),
          data);
    else if (isa<IntegerType>(rootScalar) &&
             isa<sim::LogicType>(data.getType()))
      data = sim::SimLogicToBitsOp::create(
          builder, loc,
          builder.getIntegerType(*sim::getPackedWidth(data.getType())), data);
    SmallVector<Value> watched;
    for (auto dependency : dependencies)
      watched.push_back(handle(builder, loc, context, dependency));
    Value guard = sim::SimObserverBindOp::create(
        builder, loc,
        sim::ObserverType::get(builder.getContext(), builder.getI1Type()),
        predicate.getSymNameAttr(), watched, uint32_t{0});
    Value reference = handle(builder, loc, context, epoch);
    Value snapshot = load(builder, loc, reference);
    // IEEE 1800-2023 4.6(b)/10.4.2: enqueue at the original statement,
    // preserving order with retained writes, including dynamic zero delays.
    sim::SimPowerNBAViewOp::create(builder, loc, context, data,
                                   handle(builder, loc, context, window->root),
                                   window->start, window->lower, window->upper,
                                   window->valid, guard, reference, snapshot,
                                   reference, snapshot, enqueue.getDelay());
    enqueue.erase();
    return success();
  }
  LogicalResult apply(upf::UPFDomainOp domain) {
    if (!root)
      return domain.emitError("UPF needs an executable design root");
    PowerCondition condition(domain, descriptors, supplies);
    const auto &controls = condition.controls;
    for (StringRef path : controls) {
      auto found = descriptors.find(path);
      if (found == descriptors.end())
        return domain.emitError(
                   "power control is absent from the simulation design: ")
               << path;
      if (!supportedState(found->second.type))
        return domain.emitError("power control must be packed integral: ")
               << path;
      if (contains(domain, path))
        return domain.emitError(
                   "power control must be outside the switchable domain: ")
               << path;
    }
    for (auto token : condition.references)
      if (sim::getPackedWidth(
              descriptors.lookup(token.getControl().getValue()).type) !=
          token.getSourceWidth())
        return domain.emitError("power control source width disagrees with "
                                "simulation storage: ")
               << token.getControl().getValue();
    llvm::DenseSet<uint64_t> computedInputs;
    for (auto unit : design.getOps<sim::SimCodeUnitDeclOp>())
      if (sim::has<sim::metadata::ComputedPortInput>(unit) &&
          contains(domain, scopePaths.lookup(unit.getScopeId())))
        computedInputs.insert(unit.getId());
    SmallVector<StringRef> boundaries = boundaryInstances(domain);
    // IEEE 1801-2018 6.45 applies isolation only on the domain interface.
    // Multiple boundary instances can exchange internal same-domain traffic;
    // even diff_supply_only FALSE needs that interface/path classification.
    // A whole-output mux cannot yet represent these multiple-boundary paths.
    if (domain.getIsolationControl() && boundaries.size() != 1)
      return domain.emitError(
          "isolation across multiple boundary instances "
          "requires per-path handling and is not implemented");
    llvm::DenseSet<uint64_t> boundaryScopes;
    for (auto scope : design.getOps<sim::SimScopeDeclOp>()) {
      auto path = scope.getHierarchicalName();
      if (path && scope.getDefinitionName() &&
          llvm::is_contained(boundaries, *path))
        boundaryScopes.insert(scope.getId());
    }
    if (boundaryScopes.size() != boundaries.size())
      return domain.emitError(
          "power-domain element has no simulation instance scope");
    SmallVector<sim::SimFuncOp> processes, outputs;
    for (auto fn : design.getOps<sim::SimFuncOp>()) {
      if (!fn.getCodeUnitId() ||
          !contains(domain, unitPaths.lookup(*fn.getCodeUnitId())))
        continue;
      switch (fn.getEntryKind()) {
      case sim::EntryKind::Always:
      case sim::EntryKind::AlwaysFF:
      case sim::EntryKind::AlwaysComb:
      case sim::EntryKind::AlwaysLatch:
      case sim::EntryKind::Continuous:
        processes.push_back(fn);
        break;
      case sim::EntryKind::PortOutput:
        // The immutable connection identity names its CHILD instance. Its
        // code-unit scope ID is the parent and cannot select this boundary.
        // IEEE 1801-2018 6.20/6.45 and 8.3.3(g),(j): leave internal
        // same-domain module connections transparent.
        if (llvm::is_contained(boundaries,
                               StringRef(unitPaths.lookup(*fn.getCodeUnitId()))
                                   .rsplit('.')
                                   .first))
          outputs.push_back(fn);
        break;
      case sim::EntryKind::PortInput:
      case sim::EntryKind::PortInitialize:
        if (computedInputs.contains(*fn.getCodeUnitId())) {
          // The restored constant actor is no longer a one-time initializer.
          // Keep executable and inventory kinds equal; steady-state analyses
          // use this distinction independently of the actor's new CFG.
          fn.setEntryKind(sim::EntryKind::PortInput);
          units.lookup(*fn.getCodeUnitId())
              .setCodeUnitKind(sim::EntryKind::PortInput);
          processes.push_back(fn);
        }
        break;
      case sim::EntryKind::Observer:
        break;
      case sim::EntryKind::Initial:
        break; // IEEE 1801 9.2.1: model initialization is unaffected.
      case sim::EntryKind::Function:
        if (auto path = sim::get<sim::metadata::HierarchicalName>(fn))
          if (descriptors.count(path.getValue()))
            break;
        return fn.emitError(
            "user subroutines inside a switchable domain are not implemented");
      default:
        return fn.emitError(
            "initial UPF slice supports event-controlled RTL and combinational "
            "processes; this code-unit kind is not implemented");
      }
    }
    llvm::DenseSet<uint64_t> inputStorage, computedStorage;
    for (auto port : design.getOps<sim::SimPortDeclOp>()) {
      if (!contains(domain, port.getHierarchicalName()))
        continue;
      if (port.getDirection() == sim::PortDirection::InOut)
        return port.emitError(
            "inout ports in a switchable domain are not implemented");
      if (port.getDirection() == sim::PortDirection::Input &&
          !port.getSourceIsNet()) {
        inputStorage.insert(port.getSourceId());
        std::string connection = scopePaths.lookup(port.getScopeId()) +
                                 ".$port_connection_" +
                                 std::to_string(port.getOrdinal());
        auto found = unitIDs.find(connection);
        if (found != unitIDs.end() && computedInputs.contains(found->second))
          computedStorage.insert(port.getSourceId());
      }
      if (domain.getIsolationControl() &&
          boundaryScopes.contains(port.getScopeId()) &&
          port.getDirection() == sim::PortDirection::Output &&
          port.getSourceIsNet())
        return port.emitError(
            "isolation on collapsed output nets is not implemented");
    }
    for (uint64_t id : computedStorage)
      inputStorage.erase(id);
    SmallVector<Descriptor> targets;
    llvm::DenseSet<uint64_t> continuouslyDriven, ownedDrivers;
    for (auto process : processes) {
      // IEEE 1801-2018 9.5.3/9.6.2 corrupt contributions of powered logic,
      // not every driver of an aliased net. Descendant input ports can name
      // nets driven inside this domain; their port status must not exempt
      // those contributions. Port routing processes stay transparent.
      for (auto [index, argument] : llvm::enumerate(process.getArguments()))
        if (isa<sim::DriverType>(argument.getType()))
          if (auto id = process.getArgAttrOfType<IntegerAttr>(
                  index, sim::metadata::DescriptorId::getNameStr()))
            ownedDrivers.insert(id.getUInt());
      process.walk([&](sim::SimContextDriverOp driver) {
        ownedDrivers.insert(driver.getId());
      });
      process.walk([&](sim::SimRefStoreOp write) {
        auto id = storageID(write.getReference(), process);
        if (id && computedInputs.contains(*process.getCodeUnitId()) &&
            computedStorage.contains(*id))
          sim::mark<sim::metadata::ContinuousStore>(write);
        if (process.getEntryKind() != sim::EntryKind::Continuous &&
            !sim::has<sim::metadata::ContinuousStore>(write))
          return;
        if (id)
          continuouslyDriven.insert(*id);
      });
    }
    for (auto decl : design.getOps<sim::SimStorageDeclOp>()) {
      if (!decl.getHierarchicalName() ||
          !contains(domain, *decl.getHierarchicalName()) ||
          inputStorage.contains(decl.getId()))
        continue;
      if (!supportedState(decl.getType()))
        return decl.emitError(
            "initial UPF corruption supports packed integral state");
      targets.push_back({decl.getId(), decl.getType()});
    }
    for (auto decl : design.getOps<sim::SimDriverDeclOp>()) {
      if (!ownedDrivers.contains(decl.getId()))
        continue;
      if (!supportedState(decl.getType()) ||
          !isa_and_nonnull<sim::LogicType>(
              sim::getPackedScalarType(decl.getType())))
        return decl.emitError(
            "initial UPF corruption supports packed logic drivers");
      targets.push_back({decl.getId(), decl.getType(), false, true});
    }
    // A domain's elements (IEEE 1801-2018 6.20) may hold nothing a power state
    // can corrupt, such as an empty leaf, so there is nothing to lower.
    if (targets.empty() && processes.empty() &&
        !domain.getIsolationControl()) {
      domain.erase();
      return success();
    }
    if (targets.empty())
      return domain.emitError(
          "switchable domain has no supported state or drivers");
    if (auto isoName = domain.getIsolationControl()) {
      auto found = descriptors.find(*isoName);
      if (found == descriptors.end() || contains(domain, *isoName))
        return domain.emitError("parent isolation requires a control outside "
                                "the switchable domain");
      if (outputs.empty())
        return domain.emitError(
            "isolation has no explicit output boundary to apply to");
      for (auto output : outputs)
        if (failed(isolation(output, domain, found->second)))
          return failure();
    }
    Location loc = domain.getLoc();
    std::string prefix = "__upf_" + domain.getSymName().str();
    Descriptor epoch = storage(loc, prefix + ".epoch", builder.getI64Type());
    Descriptor previous =
        storage(loc, prefix + ".previous", builder.getI1Type());
    Descriptor restoration =
        storage(loc, prefix + ".normal", builder.getI1Type());
    for (auto process : processes) {
      WalkResult supported = process.walk([&](Operation *op) {
        StringRef name = op->getName().getStringRef();
        // IEEE 1801-2018 9.5.3 invalidates old delayed driver events too.
        // Those cancellation queues are outside the initial packed-NBA slice.
        if (name.contains("drive_inertial") ||
            name.contains("drive_delayed_net") ||
            name == "simulation.ref.store_inertial_path" ||
            isa<sim::SimOverrideOp, sim::SimDynamicOverrideOp,
                sim::SimReleaseOverrideOp>(op)) {
          op->emitError("delayed drivers and force/release inside a switchable "
                        "domain are not implemented");
          return WalkResult::interrupt();
        }
        if (auto enqueue = dyn_cast<sim::SimNBAEnqueueOp>(op))
          if (enqueue.getClockingOutputAttr()) {
            // IEEE 1801-2018 9.5.2 preserves HDL clocking semantics in NORMAL.
            enqueue.emitError("clocking-output NBAs in a switchable domain are "
                              "not implemented");
            return WalkResult::interrupt();
          }
        if (auto spawn = dyn_cast<sim::SimSpawnOp>(op)) {
          auto target = SymbolTable::lookupNearestSymbolFrom<sim::SimFuncOp>(
              spawn, spawn.getCalleeAttr());
          bool clockingOutput = false;
          if (target)
            target.walk([&](sim::SimNBAEnqueueOp enqueue) {
              clockingOutput |= bool(enqueue.getClockingOutputAttr());
            });
          // Clocking drives are outlined before this pass; their helper's
          // synthetic hierarchy is not a power-domain membership proof.
          if (clockingOutput)
            spawn.emitError("clocking-output NBAs in a switchable domain are "
                            "not implemented");
          else
            spawn.emitError("forked or outlined work inside a switchable "
                            "domain is not implemented");
          return WalkResult::interrupt();
        }
        if (auto call = dyn_cast<sim::SimCallOp>(op))
          if (failed(synchronousHelper(call)))
            return WalkResult::interrupt();
        if (isa<sim::SimClassDirectCallOp, sim::SimClassVirtualCallOp,
                sim::SimClassVirtualTaskCallOp, sim::SimTaskCallOp,
                sim::SimDPICallOp>(op)) {
          // These calls do not expose the closed synchronous body audited
          // above. In particular an indirect method can enqueue an NBA that
          // would escape this domain's epoch and cancellation instrumentation.
          op->emitError("asynchronous or indirect calls inside a switchable "
                        "domain are not implemented");
          return WalkResult::interrupt();
        }
        return WalkResult::advance();
      });
      if (supported.wasInterrupted())
        return failure();
    }
    SmallVector<Descriptor> dependencies;
    {
      std::set<std::tuple<uint64_t, bool, bool>> seen;
      auto watch = [&](Descriptor descriptor) {
        for (auto source : supplyInputs(descriptor))
          if (seen.emplace(source.id, source.net, source.driver).second)
            dependencies.push_back(source);
      };
      for (auto path : controls)
        watch(descriptors.lookup(path));
      watch(condition.input.value_or(condition.power));
      if (condition.ground)
        watch(*condition.ground);
      for (auto source : condition.required)
        watch(source);
      for (auto source : condition.policyInputs)
        watch(source);
    }
    RetentionLoweringResult retention;
    if (domain.getRetentionsAttr() && !domain.getRetentionsAttr().empty()) {
      // IEEE 1801-2018 9.2.2/9.2.3: retention observes evaluated supply
      // publications. Raw switch-input writes may coalesce before evaluation;
      // an inline prediction must not latch a loss that never propagated.
      SmallVector<Descriptor> retentionDependencies{condition.power};
      if (condition.ground)
        retentionDependencies.push_back(*condition.ground);
      retentionDependencies.append(condition.required);
      retentionDependencies.append(condition.policyInputs);
      RetentionLoweringOptions options{
          design,
          domain,
          root,
          descriptors,
          supplies,
          epoch,
          retentionDependencies,
          [&](Location loc, StringRef name, Type type) {
            return storage(loc, name, type);
          },
          [&](Location loc, StringRef name, ArrayRef<Type> inputs,
              sim::EntryKind kind) {
            return function(loc, name, inputs, kind);
          },
          [&](OpBuilder &b, Location loc, Value ctx) {
            return condition.normal(b, loc, ctx, false);
          },
          [&](OpBuilder &b, Location loc, Value ctx, FlatSymbolRefAttr ref) {
            return load(b, loc,
                        handle(b, loc, ctx, supplies.lookup(ref.getValue())));
          },
          [&](FlatSymbolRefAttr ref) {
            return SmallVector<Descriptor>{supplies.lookup(ref.getValue())};
          }};
      if (failed(lowerRetentions(options, retention)))
        return failure();
    }
    // Validate original actors before adding feature-local helpers; only
    // ordinary remaining NBAs use the domain-only epoch path below.
    SmallVector<sim::SimNBAEnqueueOp> enqueues;
    for (auto process : processes)
      process.walk([&](sim::SimNBAEnqueueOp op) { enqueues.push_back(op); });
    if (!enqueues.empty()) {
      if (!nbaWindows)
        nbaWindows = std::make_unique<ReferenceWindows>(design);
      SmallVector<Value> references;
      for (auto enqueue : enqueues)
        references.push_back(enqueue.getDestination());
      if (failed(nbaWindows->prepare(references)))
        return failure();
      auto predicate = function(loc, prefix + ".nba_allowed",
                                {sim::ContextType::get(builder.getContext())},
                                sim::EntryKind::Observer);
      predicate.setFunctionType(
          builder.getFunctionType({sim::ContextType::get(builder.getContext())},
                                  {builder.getI1Type()}));
      schedule::set<schedule::Field::ObserverWidth>(
          predicate, builder.getI32IntegerAttr(1));
      schedule::set<schedule::Field::ObserverFourState>(
          predicate, builder.getBoolAttr(false));
      builder.setInsertionPointToEnd(&predicate.getBody().front());
      sim::SimReturnOp::create(
          builder, loc,
          condition.normal(builder, loc, predicate.getArgument(0)));
      for (auto enqueue : enqueues)
        if (failed(nba(enqueue, predicate, dependencies, epoch)))
          return failure();
    }
    for (auto process : processes) {
      if (failed(gate(process, condition, restoration)))
        return failure();
    }
    auto monitor = function(loc, prefix + ".monitor",
                            {sim::ContextType::get(builder.getContext())},
                            sim::EntryKind::Always);
    sim::mark<sim::metadata::PowerMonitor>(monitor);
    Block &entry = monitor.getBody().front();
    Block *loop = new Block, *loss = new Block, *wait = new Block;
    monitor.getBody().push_back(loop);
    monitor.getBody().push_back(loss);
    monitor.getBody().push_back(wait);
    builder.setInsertionPointToEnd(&entry);
    Value context = entry.getArgument(0),
          epochRef = handle(builder, loc, context, epoch);
    Value previousRef = handle(builder, loc, context, previous);
    Value normalRef = handle(builder, loc, context, restoration);
    SmallVector<Value> watched;
    for (StringRef path : controls)
      watched.push_back(
          handle(builder, loc, context, descriptors.lookup(path)));
    llvm::DenseSet<uint64_t> supplyIDs;
    auto watch = [&](Descriptor supply) {
      if (supplyIDs.insert(supply.id).second)
        watched.push_back(handle(builder, loc, context, supply));
    };
    watch(condition.input.value_or(condition.power));
    if (condition.ground)
      watch(*condition.ground);
    for (auto supply : condition.required)
      if (!condition.input || supply.id != condition.power.id)
        watch(supply);
    for (auto supply : condition.policyInputs)
      if (!condition.input || supply.id != condition.power.id)
        watch(supply);
    cf::BranchOp::create(builder, loc, loop);
    builder.setInsertionPointToEnd(loop);
    Value on = condition.normal(builder, loc, context);
    if (condition.input)
      store(builder, loc, handle(builder, loc, context, condition.power),
            condition.drivenSupply(builder, loc, context));
    // IEEE 1801-2018 9.7.3: publish restored retained values before NORMAL
    // can reactivate level-sensitive consumers of this domain.
    for (auto update : retention.updates)
      sim::SimCallOp::create(builder, loc, TypeRange{}, update,
                             ValueRange{context}, ArrayAttr{}, ArrayAttr{});
    store(builder, loc, normalRef, on);
    // IEEE 1801-2018 6.22: an explicit OFF simultaneously true with ON
    // reports an error and contributes UNDETERMINED (CORRUPT in this slice).
    if (!condition.off.nodes.empty()) {
      Value conflict = condition.conflict(builder, loc, context);
      Block *report = new Block, *evaluate = new Block;
      monitor.getBody().push_back(report);
      monitor.getBody().push_back(evaluate);
      cf::CondBranchOp::create(builder, loc, conflict, report, evaluate);
      builder.setInsertionPointToEnd(report);
      sim::SimErrorOp::create(builder, loc, context);
      Value descriptor =
          arith::ConstantIntOp::create(builder, loc, 0x80000002u, 32);
      Value message = sim::SimBytesConstantOp::create(
          builder, loc,
          "UPF domain " + domain.getSymName().str() +
              ": ON/PARTIAL and OFF conditions are simultaneously true (IEEE "
              "1801-2018 "
              "6.22)");
      sim::SimDisplayOp::create(builder, loc, context, descriptor,
                                ValueRange{message}, true, sim::Radix::Decimal,
                                builder.getDenseI32ArrayAttr({0}), StringAttr{},
                                StringAttr{}, IntegerAttr{}, IntegerAttr{});
      cf::BranchOp::create(builder, loc, evaluate);
      builder.setInsertionPointToEnd(evaluate);
    }
    Value wasOn = load(builder, loc, previousRef);
    store(builder, loc, previousRef, on);
    Value off = arith::XOrIOp::create(
        builder, loc, on, arith::ConstantIntOp::create(builder, loc, 1, 1));
    Value falling = arith::AndIOp::create(builder, loc, wasOn, off);
    cf::CondBranchOp::create(builder, loc, falling, loss, wait);
    builder.setInsertionPointToEnd(loss);
    Value oldEpoch = load(builder, loc, epochRef);
    Value nextEpoch = arith::AddIOp::create(
        builder, loc, oldEpoch,
        arith::ConstantIntOp::create(builder, loc, 1, 64));
    store(builder, loc, epochRef, nextEpoch);
    for (Descriptor target : targets) {
      if (!target.driver && retention.storage.contains(target.id))
        continue;
      // IEEE 1801-2018 9.5.1/9.6.2: corruption uses the HDL type's default
      // initial value, independently of explicit declaration initializers.
      Value reference = handle(builder, loc, context, target);
      if (!target.driver) {
        uint64_t width = *sim::getPackedWidth(target.type);
        sim::SimPowerCancelNBAOp::create(builder, loc, context, reference,
                                         width);
      }
      store(builder, loc, reference, corrupt(builder, loc, target.type));
      if (!target.driver && continuouslyDriven.contains(target.id))
        sim::mark<sim::metadata::ContinuousStore>(
            &*std::prev(builder.getInsertionPoint()));
    }
    cf::BranchOp::create(builder, loc, wait);
    builder.setInsertionPointToEnd(wait);
    // IEEE 1801-2018 9.2.2: referenced ON/PARTIAL/OFF/ERROR controls and input
    // supplies reevaluate the switch, including voltage-only changes.
    if (watched.empty())
      sim::SimReturnOp::create(builder, loc, ValueRange{});
    else
      sim::SimSuspendAnyOp::create(
          builder, loc, watched,
          builder.getDenseI32ArrayAttr(SmallVector<int32_t>(watched.size(), 0)),
          schedule::ContinuationSiteAttr{}, sim::EventRegionAttr{}, loop);
    Operation *firstSpawn = nullptr;
    for (Operation &op : root.getBody().front())
      if (isa<sim::SimSpawnOp>(op)) {
        firstSpawn = &op;
        break;
      }
    builder.setInsertionPoint(
        firstSpawn ? firstSpawn : root.getBody().front().getTerminator());
    Value rootContext = root.getArgument(0);
    store(builder, loc, handle(builder, loc, rootContext, epoch),
          arith::ConstantIntOp::create(builder, loc, 0, 64));
    store(builder, loc, handle(builder, loc, rootContext, previous),
          arith::ConstantIntOp::create(builder, loc, 1, 1));
    // Seed before spawning HDL actors, avoiding a false restoration event
    // when the domain starts NORMAL. Guards still evaluate raw controls inline
    // so clock/NBA execution never depends on monitor scheduling order.
    store(builder, loc, handle(builder, loc, rootContext, restoration),
          condition.normal(builder, loc, rootContext));
    sim::SimSpawnOp::create(builder, loc, monitor.getSymNameAttr(),
                            ValueRange{rootContext}, ArrayAttr{}, ArrayAttr{});
    domain.erase();
    return success();
  }
};
struct ElaborateUPFPass
    : PassWrapper<ElaborateUPFPass, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ElaborateUPFPass)
  StringRef getArgument() const final { return "elaborate-upf"; }
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<sim::TalosSimulationDialect, arith::ArithDialect,
                    cf::ControlFlowDialect>();
  }
  void runOnOperation() override {
    SmallVector<upf::UPFDomainOp> domains(
        getOperation().getOps<upf::UPFDomainOp>());
    SmallVector<upf::UPFSupplyOp> supplies(
        getOperation().getOps<upf::UPFSupplyOp>());
    SmallVector<upf::UPFSupplySetOp> sets(
        getOperation().getOps<upf::UPFSupplySetOp>());
    bool accesses = false;
    getOperation().walk([&](Operation *op) {
      accesses |= isa<sim::SimSupplyControlOp, sim::SimSupplyReadOp>(op);
    });
    if (domains.empty() && supplies.empty() && sets.empty() && !accesses) {
      getOperation()->removeAttr(upf::partialOnTranslationName);
      return;
    }
    // IEEE 1801-2018 6.20 assigns an instance to exactly one effective extent.
    // Until nested-domain extent partitioning exists, require disjoint roots;
    // validate the entire inventory before adding any guards or corruption.
    for (auto [index, domain] : llvm::enumerate(domains))
      for (auto other : ArrayRef(domains).take_front(index))
        for (Attribute element : domain.getElements())
          for (Attribute otherElement : other.getElements()) {
            StringRef path = cast<StringAttr>(element).getValue();
            StringRef otherPath = cast<StringAttr>(otherElement).getValue();
            if (within(path, otherPath) || within(otherPath, path)) {
              auto diagnostic = domain.emitError();
              if (path == otherPath)
                diagnostic << "design instance is selected by multiple "
                              "switchable domains: "
                           << path;
              else
                diagnostic << "nested switchable domains are not implemented: "
                           << domain.getSymName() << " and "
                           << other.getSymName();
              signalPassFailure();
              return;
            }
          }
    auto designs = getOperation().getOps<sim::SimDesignOp>();
    if (!llvm::hasSingleElement(designs)) {
      getOperation().emitError("UPF requires exactly one simulation design");
      signalPassFailure();
      return;
    }
    Lowering lowering(*designs.begin());
    if (failed(lowering.prepareSupplies(supplies))) {
      signalPassFailure();
      return;
    }
    for (auto domain : domains)
      if (domain.getInputAttr()) {
        auto condition = std::make_unique<PowerCondition>(
            domain, lowering.descriptors, lowering.supplies);
        lowering.computed.try_emplace(condition->power.id,
                                      std::move(condition));
      }
    for (auto domain : domains)
      if (failed(lowering.apply(domain))) {
        signalPassFailure();
        return;
      }
    if (failed(lowerSupplyAccesses(*designs.begin(), lowering.supplyTable))) {
      signalPassFailure();
      return;
    }
    if (failed(lowering.monitorStates(sets))) {
      signalPassFailure();
      return;
    }
    for (auto set : sets)
      set.erase();
    for (auto supply : supplies)
      supply.erase();
    getOperation()->removeAttr(upf::partialOnTranslationName);
  }
};
} // namespace
std::unique_ptr<Pass> createElaborateUPFPass() {
  return std::make_unique<ElaborateUPFPass>();
}
} // namespace talos
