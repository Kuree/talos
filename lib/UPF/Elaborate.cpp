// Power guards and corruption writes remain visible to subsequent analyses.
#include "ClockSnapshot.h"
#include "ControlValue.h"
#include "ElaborateSupply.h"
#include "OrdinaryWrites.h"
#include "PowerState.h"
#include "PublicationCallback.h"
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
#include "llvm/IR/DerivedTypes.h"
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
      // A snapshot flush publishes that helper's completed synchronous
      // write. It leaves no asynchronous work owned by the helper.
      // Ordinary-write lowering attaches the caller's lifetime to NBAs.
      if (isa<sim::SimSupplyReadOp, sim::SimEventSnapshotFlushOp,
              sim::SimNBAEnqueueOp>(op))
        return WalkResult::advance();
      if (isa<sim::SimSupplyControlOp>(op)) {
        op->emitError("power-control calls from a switched actor require "
                      "caller-continuation analysis and are not implemented");
        return WalkResult::interrupt();
      }
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
  llvm::DenseSet<uint64_t> referencedStorage, immutableSupplies;
  bool preserveStorage;
  llvm::StringMap<uint64_t> unitIDs;
  sim::SimFuncOp root;
  std::unique_ptr<ReferenceWindows> nbaWindows;
  std::unique_ptr<ClockSnapshots> clocks;
  SmallVector<sim::SimFuncOp> originalFunctions;
  llvm::DenseSet<uint64_t> originalStorage;
  SmallVector<WriteDomain> writeDomains;
  SmallVector<RetentionWrite> retainedWrites;
  RetentionPlans retentionPlans;
  Lowering(sim::SimDesignOp design, bool preserveStorage)
      : design(design), builder(design.getContext()),
        preserveStorage(preserveStorage) {
    for (auto scope : design.getOps<sim::SimScopeDeclOp>())
      if (auto name = scope.getHierarchicalName())
        scopePaths[scope.getId()] = name->str();
    for (auto decl : design.getOps<sim::SimStorageDeclOp>()) {
      nextStorage = std::max(nextStorage, decl.getId() + 1);
      originalStorage.insert(decl.getId());
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
    for (auto fn : design.getOps<sim::SimFuncOp>()) {
      originalFunctions.push_back(fn);
      if (fn.getEntryKind() == sim::EntryKind::RootInitializer)
        root = fn;
    }
    if (!preserveStorage)
      collectReferencedStorage();
    if (root)
      clocks = std::make_unique<ClockSnapshots>(
          ClockSnapshotOptions{root,
                               [&](Location loc, StringRef name, Type type) {
                                 return storage(loc, name, type);
                               },
                               [&](Location loc, StringRef name,
                                   ArrayRef<Type> inputs, sim::EntryKind kind) {
                                 return function(loc, name, inputs, kind);
                               }});
  }
  void collectReferencedStorage() {
    SymbolTableCollection retentionSymbols;
    design.walk([&](sim::SimContextStorageOp ref) {
      referencedStorage.insert(ref.getId());
    });
    for (auto fn : design.getOps<sim::SimFuncOp>())
      for (unsigned index = 0; index != fn.getNumArguments(); ++index) {
        if (!isa<sim::RefType>(fn.getArgumentTypes()[index]))
          continue;
        if (auto id = fn.getArgAttrOfType<IntegerAttr>(
                index, sim::metadata::DescriptorId::getNameStr()))
          referencedStorage.insert(id.getUInt());
      }
    for (auto anchor : design.getOps<sim::SimVPIObjectAnchorOp>())
      if (auto backing = anchor.getBackingAttr())
        if (backing.getKind() == sim::VPIObjectBackingKind::Storage)
          referencedStorage.insert(backing.getId().getInt());
    // UPF expressions can observe HDL state without an HDL reference. Keep
    // those roots, while declarations elided from executable/VPI use need no
    // corruption owner merely because they remain in source inventory.
    SmallVector<Attribute> attributes;
    for (Operation &op : design->getParentOp()->getRegion(0).front())
      if (isa<upf::UPFDomainOp>(op)) {
        for (auto attr : op.getAttrs())
          attributes.push_back(attr.getValue());
        if (auto domain = dyn_cast<upf::UPFDomainOp>(op))
          if (auto path = domain.getIsolationControl())
            if (auto found = descriptors.find(*path);
                found != descriptors.end())
              if (!found->second.net && !found->second.driver)
                referencedStorage.insert(found->second.id);
      }
    llvm::DenseSet<Attribute> seen;
    while (!attributes.empty()) {
      Attribute attr = attributes.pop_back_val();
      if (!seen.insert(attr).second)
        continue;
      if (auto retention = dyn_cast<upf::RetentionAttr>(attr))
        if (retention.getNoRetention() ||
            upf::isStaticallyEmptyRetention(retention, design->getParentOp(),
                                            &retentionSymbols))
          continue;
      if (auto token = dyn_cast<upf::ExpressionTokenAttr>(attr))
        if (token.getOpcode() == upf::ExpressionOpcode::Control)
          if (auto found = descriptors.find(token.getControl().getValue());
              found != descriptors.end())
            if (!found->second.net && !found->second.driver)
              referencedStorage.insert(found->second.id);
      attr.walkImmediateSubElements(
          [&](Attribute child) { attributes.push_back(child); }, [](Type) {});
    }
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
      if (supply.getAlwaysOn())
        immutableSupplies.insert(d.id);
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
                     Descriptor restoration, Descriptor epoch,
                     bool qualifyClock, bool inlineOutput = true) {
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
    std::optional<FrozenClock> frozen;
    if (edgeSensitive && qualifyClock) {
      auto clock = clocks->freeze(
          fn, "__upf_clock." + std::to_string(fn.getCodeUnitId().value_or(0)),
          epoch, [&](OpBuilder &b, Location loc, Value ctx) {
            return condition.normal(b, loc, ctx, false);
          });
      if (failed(clock))
        return failure();
      frozen = *clock;
    }
    Block *body = gate->splitBlock(gate->begin());
    builder.setInsertionPointToEnd(gate);
    Value ctx = fn.getArgument(0);
    Value on;
    if (frozen) {
      on = arith::AndIOp::create(
          builder, fn.getLoc(),
          load(builder, fn.getLoc(),
               handle(builder, fn.getLoc(), ctx, frozen->valid)),
          arith::CmpIOp::create(
              builder, fn.getLoc(), arith::CmpIPredicate::eq,
              load(builder, fn.getLoc(),
                   handle(builder, fn.getLoc(), ctx, frozen->epoch)),
              load(builder, fn.getLoc(),
                   handle(builder, fn.getLoc(), ctx, epoch))));
    } else {
      on = condition.normal(builder, fn.getLoc(), ctx, inlineOutput);
    }
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
  LogicalResult exactLoss(const PowerCondition &condition, StringRef prefix,
                          Descriptor epoch, Descriptor restoration,
                          ArrayRef<Descriptor> ordinary) {
    Location loc = root.getLoc();
    llvm::DenseSet<uint64_t> owned;
    for (auto target : ordinary)
      owned.insert(target.id);
    WalkResult overrides =
        owned.empty() ? WalkResult::advance() : design.walk([&](Operation *op) {
          Value target;
          if (auto force = dyn_cast<sim::SimOverrideOp>(op))
            target = force.getTarget();
          if (auto force = dyn_cast<sim::SimDynamicOverrideOp>(op))
            target = force.getTarget();
          if (auto release = dyn_cast<sim::SimReleaseOverrideOp>(op))
            target = release.getTarget();
          if (!target || !isa<sim::RefType>(target.getType()))
            return WalkResult::advance();
          auto fn = op->getParentOfType<sim::SimFuncOp>();
          auto id = storageID(target, fn);
          if (!id) {
            if (!nbaWindows)
              nbaWindows = std::make_unique<ReferenceWindows>(design);
            auto resolved = nbaWindows->getRoot(target);
            if (failed(resolved))
              return WalkResult::interrupt();
            id = resolved->id;
          }
          if (!owned.contains(*id))
            return WalkResult::advance();
          op->emitError(
              "force, procedural assign and release on exact power-loss "
              "storage are not implemented");
          return WalkResult::interrupt();
        });
    if (overrides.wasInterrupted())
      return failure();
    SmallVector<SmallVector<Descriptor>> groups{{epoch, restoration}};
    uint64_t width = 65;
    for (auto target : ordinary) {
      uint64_t bits = *sim::getPackedWidth(target.type);
      if (bits > llvm::IntegerType::MAX_INT_BITS)
        return emitError(loc)
               << "domain loss target exceeds supported packed width";
      if (bits > llvm::IntegerType::MAX_INT_BITS - width) {
        groups.emplace_back();
        width = 0;
      }
      groups.back().push_back(target);
      width += bits;
    }
    for (auto group : llvm::enumerate(groups)) {
      size_t index = group.index();
      auto &targets = group.value();
      std::string name = (prefix + ".loss." + Twine(index)).str();
      auto callback = [&](StringRef suffix,
                          llvm::function_ref<Value(Value)> body)
          -> FailureOr<PublicationCallback> {
        auto fn = function(loc, name + suffix.str(),
                           {sim::ContextType::get(builder.getContext())},
                           sim::EntryKind::Observer);
        sim::mark<sim::metadata::PowerMonitor>(fn);
        builder.setInsertionPointToEnd(&fn.getBody().front());
        Value result = body(fn.getArgument(0));
        fn.setFunctionType(
            builder.getFunctionType(fn.getArgumentTypes(), {result.getType()}));
        schedule::set<schedule::Field::ObserverWidth>(
            fn,
            builder.getI32IntegerAttr(*sim::getPackedWidth(result.getType())));
        schedule::set<schedule::Field::ObserverFourState>(
            fn, builder.getBoolAttr(isa<sim::LogicType>(result.getType())));
        sim::SimReturnOp::create(builder, loc, result);
        return closePublicationCallback(fn, builder);
      };
      auto primary = callback(".power", [&](Value ctx) {
        return condition.normal(builder, loc, ctx, false);
      });
      auto value = [&](Value ctx, Descriptor target) -> Value {
        if (target.id == epoch.id)
          return arith::AddIOp::create(
              builder, loc,
              load(builder, loc, handle(builder, loc, ctx, epoch)),
              arith::ConstantIntOp::create(builder, loc, 1, 64));
        if (target.id == restoration.id)
          return arith::ConstantIntOp::create(builder, loc, 0, 1);
        return corrupt(builder, loc, target.type);
      };
      auto sampler = callback(".capture", [&](Value ctx) -> Value {
        SmallVector<Value> parts;
        uint64_t bits = 0;
        for (auto target : llvm::reverse(targets)) {
          Value part = flatten(builder, loc, value(ctx, target));
          unsigned partWidth = *sim::getPackedWidth(part.getType());
          if (isa<IntegerType>(part.getType()))
            part = sim::SimLogicFromBitsOp::create(
                builder, loc,
                sim::LogicType::get(builder.getContext(), partWidth), part);
          parts.push_back(part);
          bits += partWidth;
        }
        return parts.size() == 1
                   ? parts.front()
                   : sim::SimLogicConcatOp::create(
                         builder, loc,
                         sim::LogicType::get(builder.getContext(), bits),
                         parts);
      });
      if (failed(primary) || failed(sampler))
        return failure();
      auto initializer = function(loc, name + ".initialize",
                                  {sim::ContextType::get(builder.getContext())},
                                  sim::EntryKind::Function);
      sim::mark<sim::metadata::PowerMonitor>(initializer);
      Block *off = new Block, *done = new Block;
      initializer.getBody().push_back(off);
      initializer.getBody().push_back(done);
      builder.setInsertionPointToEnd(&initializer.getBody().front());
      Value ctx = initializer.getArgument(0);
      cf::CondBranchOp::create(
          builder, loc, condition.normal(builder, loc, ctx, false), done, off);
      builder.setInsertionPointToEnd(off);
      SmallVector<int32_t> cancel;
      for (auto [at, target] : llvm::enumerate(targets)) {
        Value reference = handle(builder, loc, ctx, target);
        if (target.id != epoch.id && target.id != restoration.id) {
          cancel.push_back(at);
          sim::SimPowerCancelNBAOp::create(builder, loc, ctx, reference,
                                           *sim::getPackedWidth(target.type));
        }
        store(builder, loc, reference, value(ctx, target));
      }
      cf::BranchOp::create(builder, loc, done);
      builder.setInsertionPointToEnd(done);
      sim::SimReturnOp::create(builder, loc, ValueRange{});
      auto owner = function(loc, name + ".owner",
                            {sim::ContextType::get(builder.getContext())},
                            sim::EntryKind::Fork);
      sim::mark<sim::metadata::PowerMonitor>(owner);
      schedule::set<schedule::Field::DetachedControls>(owner,
                                                       builder.getUnitAttr());
      schedule::set<schedule::Field::PrimeOnSpawn>(owner,
                                                   builder.getUnitAttr());
      builder.setInsertionPointToEnd(&owner.getBody().front());
      ctx = owner.getArgument(0);
      sim::SimCallOp::create(builder, loc, TypeRange{},
                             initializer.getSymNameAttr(), ValueRange{ctx},
                             ArrayAttr{}, ArrayAttr{});
      Value initial = sim::SimCallOp::create(
                          builder, loc, primary->function.getResultTypes(),
                          primary->function.getSymNameAttr(),
                          publicationArguments(builder, loc, ctx, *primary),
                          ArrayAttr{}, ArrayAttr{})
                          .getResult(0);
      SmallVector<Value> values{
          bindPublication(builder, loc, ctx, *primary, true), initial,
          bindPublication(builder, loc, ctx, *sampler, false)};
      for (auto target : targets)
        values.push_back(handle(builder, loc, ctx, target));
      sim::SimEventSnapshotRegisterOp::create(
          builder, loc, ctx, values, targets.size(), 0,
          builder.getDenseI32ArrayAttr(
              {static_cast<int32_t>(sim::EdgeKind::Negedge)}),
          builder.getDenseI32ArrayAttr({-1}),
          builder.getDenseI32ArrayAttr(cancel));
      auto *park = new Block;
      owner.getBody().push_back(park);
      sim::SimSuspendForeverOp::create(builder, loc, ValueRange{},
                                       schedule::ContinuationSiteAttr{},
                                       sim::EventRegionAttr{}, park);
      builder.setInsertionPointToEnd(park);
      sim::SimReturnOp::create(builder, loc, ValueRange{});
      auto spawn = llvm::find_if(root.getBody().front(), [](Operation &op) {
        return isa<sim::SimSpawnOp>(op);
      });
      builder.setInsertionPoint(spawn == root.getBody().front().end()
                                    ? root.getBody().front().getTerminator()
                                    : &*spawn);
      sim::SimSpawnOp::create(builder, loc, owner.getSymNameAttr(),
                              ValueRange{root.getArgument(0)}, ArrayAttr{},
                              ArrayAttr{});
    }
    return success();
  }
  void reportSwitchConflict(upf::UPFDomainOp domain,
                            const PowerCondition &condition, Value context) {
    if (condition.off.nodes.empty())
      return;
    Location loc = domain.getLoc();
    Value conflict = condition.conflict(builder, loc, context);
    Region *body = builder.getInsertionBlock()->getParent();
    Block *report = new Block, *evaluate = new Block;
    body->push_back(report);
    body->push_back(evaluate);
    cf::CondBranchOp::create(builder, loc, conflict, report, evaluate);
    builder.setInsertionPointToEnd(report);
    sim::SimErrorOp::create(builder, loc, context);
    Value descriptor =
        arith::ConstantIntOp::create(builder, loc, 0x80000002u, 32);
    Value message = sim::SimBytesConstantOp::create(
        builder, loc,
        "UPF domain " + domain.getSymName().str() +
            ": ON/PARTIAL and OFF conditions are simultaneously true (IEEE "
            "1801-2018 6.22)");
    sim::SimDisplayOp::create(builder, loc, context, descriptor,
                              ValueRange{message}, true, sim::Radix::Decimal,
                              builder.getDenseI32ArrayAttr({0}), StringAttr{},
                              StringAttr{}, IntegerAttr{}, IntegerAttr{});
    cf::BranchOp::create(builder, loc, evaluate);
    builder.setInsertionPointToEnd(evaluate);
  }

  void switchOnly(upf::UPFDomainOp domain, const PowerCondition &condition) {
    Location loc = domain.getLoc();
    auto monitor = function(
        loc, "__upf_" + domain.getSymName().str() + ".switch",
        {sim::ContextType::get(builder.getContext())}, sim::EntryKind::Always);
    sim::mark<sim::metadata::PowerMonitor>(monitor);
    Block &entry = monitor.getBody().front();
    Block *loop = new Block, *wait = new Block;
    monitor.getBody().push_back(loop);
    monitor.getBody().push_back(wait);
    builder.setInsertionPointToEnd(&entry);
    Value context = entry.getArgument(0);
    SmallVector<Value> watched;
    std::set<std::tuple<uint64_t, bool, bool>> seen;
    auto watch = [&](Descriptor descriptor) {
      if (seen.emplace(descriptor.id, descriptor.net, descriptor.driver).second)
        watched.push_back(handle(builder, loc, context, descriptor));
    };
    for (StringRef path : condition.controls)
      watch(descriptors.lookup(path));
    watch(*condition.input);
    cf::BranchOp::create(builder, loc, loop);
    builder.setInsertionPointToEnd(loop);
    // 6.20 permits an empty extent. The abstract switch remains a real supply
    // driver (6.22/9.2.2), independent of whether any RTL needs corruption.
    store(builder, loc, handle(builder, loc, context, condition.power),
          condition.drivenSupply(builder, loc, context));
    reportSwitchConflict(domain, condition, context);
    cf::BranchOp::create(builder, loc, wait);
    builder.setInsertionPointToEnd(wait);
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
    sim::SimSpawnOp::create(builder, loc, monitor.getSymNameAttr(),
                            ValueRange{root.getArgument(0)}, ArrayAttr{},
                            ArrayAttr{});
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
    if (domain.getExtentAttr().getIncluded().empty()) {
      if (condition.input)
        switchOnly(domain, condition);
      domain.erase();
      return success();
    }
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
    if (domain.getIsolationControl() &&
        (boundaries.size() != 1 ||
         !domain.getExtentAttr().getExcluded().empty()))
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
        // Direct helper execution inherits its procedural caller's power and
        // initialization context; ordinary writes are handled globally below.
        break;
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
          decl.getLifetime() == sim::Lifetime::Automatic ||
          !contains(domain, *decl.getHierarchicalName()) ||
          inputStorage.contains(decl.getId()) ||
          (!preserveStorage && !referencedStorage.contains(decl.getId()) &&
           !decl.getObservabilityAttr()))
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
      if (condition.input)
        switchOnly(domain, condition);
      domain.erase();
      return success();
    }
    // A producer may update only foreign roots. Its published source policy
    // and epoch still cancel those activations and already-issued NBAs.
    if (targets.empty() && processes.empty())
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
    bool exact = llvm::none_of(targets, [](Descriptor d) { return d.driver; });
    Descriptor previous{0, {}};
    if (!exact)
      previous = storage(loc, prefix + ".previous", builder.getI1Type());
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
          clocks.get(),
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
          },
          retentionPlans[domain]};
      if (failed(lowerRetentions(options, retention)))
        return failure();
      llvm::append_range(retainedWrites, retention.writes);
    }
    // Ordinary procedural updates are handled once after all physical domain
    // owners and final retained roots are known. Preserve both source and
    // destination policy rather than rewriting in domain declaration order.
    // Protected roots cannot publish a loss after startup. Avoid clock
    // snapshots when every input to the primary policy is immutable.
    auto immutable = [&](Descriptor d) {
      return immutableSupplies.contains(d.id) && !computed.contains(d.id);
    };
    bool qualifyClock = condition.input || !immutable(condition.power) ||
                        (condition.ground && !immutable(*condition.ground)) ||
                        !llvm::all_of(condition.required, immutable) ||
                        !llvm::all_of(condition.policyInputs, immutable);
    WriteDomain writes;
    writes.name = domain.getSymName().str();
    writes.epoch = epoch;
    writes.exact = exact;
    writes.immutable = !qualifyClock;
    writes.dependencies = dependencies;
    writes.normal = [condition](OpBuilder &b, Location loc, Value ctx) {
      return condition.normal(b, loc, ctx, false);
    };
    writes.retained = retention.storage;
    for (auto target : targets)
      if (!target.driver && !retention.storage.contains(target.id))
        writes.ordinary.insert(target.id);
    for (auto process : processes)
      writes.actors.insert(process);
    writeDomains.push_back(std::move(writes));
    for (auto process : processes) {
      if (failed(gate(process, condition, restoration, epoch,
                      exact && qualifyClock,
                      !retention.publishedProcesses.contains(process))))
        return failure();
    }
    if (exact) {
      SmallVector<Descriptor> ordinary;
      for (auto target : targets)
        if (!retention.storage.contains(target.id))
          ordinary.push_back(target);
      if (failed(exactLoss(condition, prefix, epoch, restoration, ordinary)))
        return failure();
    }
    auto monitor = function(loc, prefix + ".monitor",
                            {sim::ContextType::get(builder.getContext())},
                            sim::EntryKind::Always);
    sim::mark<sim::metadata::PowerMonitor>(monitor);
    Block &entry = monitor.getBody().front();
    Block *loop = new Block, *loss = exact ? nullptr : new Block,
          *wait = new Block;
    monitor.getBody().push_back(loop);
    if (loss)
      monitor.getBody().push_back(loss);
    monitor.getBody().push_back(wait);
    builder.setInsertionPointToEnd(&entry);
    Value context = entry.getArgument(0),
          epochRef = handle(builder, loc, context, epoch);
    Value previousRef;
    if (!exact)
      previousRef = handle(builder, loc, context, previous);
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
    if (condition.input)
      store(builder, loc, handle(builder, loc, context, condition.power),
            condition.drivenSupply(builder, loc, context));
    Value on = condition.normal(builder, loc, context, !exact);
    // Exact retention policy snapshots publish restored values before this
    // aggregate NORMAL readiness can reactivate level-sensitive consumers.
    store(builder, loc, normalRef, on);
    // 6.22: explicit ON/PARTIAL and OFF conflicts also diagnose when no
    // functional target needs corruption (the switch-only path above).
    reportSwitchConflict(domain, condition, context);
    if (exact) {
      cf::BranchOp::create(builder, loc, wait);
    } else {
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
    }
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
    if (!exact)
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
  ElaborateUPFPass() = default;
  ElaborateUPFPass(const ElaborateUPFPass &other) : PassWrapper(other) {}
  explicit ElaborateUPFPass(bool preserve) { preserveVPIStorage = preserve; }
  Option<bool> preserveVPIStorage{
      *this, "preserve-vpi-storage",
      llvm::cl::desc("Retain storage observable through VPI inventory"),
      llvm::cl::init(true)};
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
    SmallVector<upf::UPFCompositeDomainOp> composites(
        getOperation().getOps<upf::UPFCompositeDomainOp>());
    SmallVector<upf::UPFHierarchyOp> hierarchies(
        getOperation().getOps<upf::UPFHierarchyOp>());
    SmallVector<upf::UPFRetentionElementsOp> retentionElements(
        getOperation().getOps<upf::UPFRetentionElementsOp>());
    SmallVector<upf::UPFModelAttributesOp> modelAttributes(
        getOperation().getOps<upf::UPFModelAttributesOp>());
    SmallVector<upf::UPFDesignAttributesOp> designAttributes(
        getOperation().getOps<upf::UPFDesignAttributesOp>());
    bool accesses = false;
    getOperation().walk([&](Operation *op) {
      accesses |= isa<sim::SimSupplyControlOp, sim::SimSupplyReadOp>(op);
    });
    if (domains.empty() && composites.empty() && supplies.empty() &&
        sets.empty() && hierarchies.empty() && retentionElements.empty() &&
        modelAttributes.empty() && designAttributes.empty() && !accesses) {
      getOperation()->removeAttr(upf::partialOnTranslationName);
      return;
    }
    if (failed(resolveUPFDomainExtents(getOperation()))) {
      signalPassFailure();
      return;
    }
    if (failed(validateUPFDesignAttributeBehavior(getOperation()))) {
      signalPassFailure();
      return;
    }
    auto designs = getOperation().getOps<sim::SimDesignOp>();
    if (!llvm::hasSingleElement(designs)) {
      getOperation().emitError("UPF requires exactly one simulation design");
      signalPassFailure();
      return;
    }
    bool preserve = preserveVPIStorage;
    getOperation().walk([&](Operation *op) {
      preserve |=
          isa<sim::SimDumpOpenOp, sim::SimDumpOpenStringOp, sim::SimDumpVarsOp,
              sim::SimDumpPortsOp, sim::SimDumpAllOp>(op);
    });
    Lowering lowering(*designs.begin(), preserve);
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
    if (failed(planRetentions(lowering.design, lowering.root,
                              lowering.descriptors, lowering.supplies,
                              lowering.retentionPlans))) {
      signalPassFailure();
      return;
    }
    for (auto domain : domains)
      if (failed(lowering.apply(domain))) {
        signalPassFailure();
        return;
      }
    if (lowering.clocks &&
        failed(lowerOrdinaryUPFWrites(OrdinaryWriteOptions{
            lowering.design, lowering.root, lowering.originalFunctions,
            lowering.originalStorage, lowering.writeDomains,
            lowering.retainedWrites, *lowering.clocks,
            [&](Location loc, StringRef name, Type type) {
              return lowering.storage(loc, name, type);
            },
            [&](Location loc, StringRef name, ArrayRef<Type> inputs,
                sim::EntryKind kind) {
              return lowering.function(loc, name, inputs, kind);
            }}))) {
      signalPassFailure();
      return;
    }
    if (lowering.clocks && failed(lowering.clocks->finalize())) {
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
    for (auto composite : composites)
      composite.erase();
    for (auto hierarchy : hierarchies)
      hierarchy.erase();
    for (auto list : retentionElements)
      list.erase();
    for (auto model : modelAttributes)
      model.erase();
    for (auto annotation : designAttributes)
      annotation.erase();
    for (auto set : sets)
      set.erase();
    for (auto supply : supplies)
      supply.erase();
    getOperation()->removeAttr(upf::partialOnTranslationName);
  }
};
} // namespace
std::unique_ptr<Pass> createElaborateUPFPass(bool preserveVPIStorage) {
  return std::make_unique<ElaborateUPFPass>(preserveVPIStorage);
}
} // namespace talos
