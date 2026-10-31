// Power guards and corruption writes remain visible to subsequent analyses.
#include "ElaborateSupply.h"
#include "PowerState.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/ControlFlow/IR/ControlFlowOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "mlir/Pass/Pass.h"
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
struct Descriptor {
  uint64_t id;
  Type type;
  bool net = false, driver = false;
};
bool within(StringRef path, StringRef prefix) {
  return path == prefix || (path.starts_with(prefix) &&
                            path.drop_front(prefix.size()).starts_with('.'));
}
bool contains(upf::UPFDomainOp domain, StringRef path) {
  for (Attribute element : domain.getElements()) {
    StringRef prefix = cast<StringAttr>(element).getValue();
    if (within(path, prefix))
      return true;
  }
  return false;
}
SmallVector<StringRef> boundaryInstances(upf::UPFDomainOp domain) {
  // IEEE 1801-2018 6.20: a boundary instance has a parent outside the extent.
  // Listing a descendant redundantly does not create an additional boundary.
  SmallVector<StringRef> roots;
  for (Attribute element : domain.getElements()) {
    StringRef path = cast<StringAttr>(element).getValue();
    if (llvm::any_of(roots, [&](StringRef root) { return within(path, root); }))
      continue;
    llvm::erase_if(roots, [&](StringRef root) { return within(root, path); });
    roots.push_back(path);
  }
  return roots;
}
Value handle(OpBuilder &b, Location loc, Value context, Descriptor d) {
  if (d.driver)
    return sim::SimContextDriverOp::create(
        b, loc, sim::DriverType::get(b.getContext(), d.type), context, d.id);
  if (d.net)
    return sim::SimContextNetOp::create(
        b, loc, sim::NetType::get(b.getContext(), d.type), context, d.id);
  return sim::SimContextStorageOp::create(
      b, loc, sim::RefType::get(b.getContext(), d.type), context, d.id);
}
Value load(OpBuilder &b, Location loc, Value reference) {
  if (auto net = dyn_cast<sim::NetType>(reference.getType()))
    return sim::SimNetReadOp::create(b, loc, net.getElementType(), reference);
  return sim::SimRefLoadOp::create(
      b, loc, cast<sim::RefType>(reference.getType()).getElementType(),
      reference);
}
void store(OpBuilder &b, Location loc, Value reference, Value value) {
  if (isa<sim::DriverType>(reference.getType()))
    sim::SimDriverDriveOp::create(b, loc, reference, value);
  else if (isa<sim::NetType>(reference.getType()))
    sim::SimNetWriteOp::create(b, loc, reference, value);
  else
    sim::SimRefStoreOp::create(b, loc, value, reference);
}
Value logicConstant(OpBuilder &b, Location loc, sim::LogicType type, bool value,
                    bool unknown = false) {
  auto integer = b.getIntegerType(type.getWidth());
  return sim::SimLogicConstantOp::create(
      b, loc, type,
      b.getIntegerAttr(integer, value ? APInt::getAllOnes(type.getWidth())
                                      : APInt(type.getWidth(), 0)),
      b.getIntegerAttr(integer, unknown ? APInt::getAllOnes(type.getWidth())
                                        : APInt(type.getWidth(), 0)));
}
bool supportedState(Type type) {
  if (auto array = dyn_cast<sim::PackedArrayType>(type))
    return supportedState(array.getElementType());
  return isa<sim::LogicType, IntegerType>(type);
}
Value flatten(OpBuilder &b, Location loc, Value value) {
  Type scalar = sim::getPackedScalarType(value.getType());
  if (scalar == value.getType())
    return value;
  return sim::SimPackedFlattenOp::create(b, loc, scalar, value);
}
Value corrupt(OpBuilder &b, Location loc, Type type) {
  if (Type scalar = sim::getPackedScalarType(type); scalar != type) {
    Value value = corrupt(b, loc, scalar);
    return sim::SimPackedUnflattenOp::create(b, loc, type, value);
  }
  if (auto logic = dyn_cast<sim::LogicType>(type))
    return logicConstant(b, loc, logic, false, true);
  return arith::ConstantOp::create(b, loc, type, b.getZeroAttr(type));
}
Value equalsLevel(OpBuilder &b, Location loc, Value value, bool high) {
  value = flatten(b, loc, value);
  if (auto logic = dyn_cast<sim::LogicType>(value.getType()))
    return sim::SimLogicCompareOp::create(b, loc, b.getI1Type(),
                                          sim::CompareKind::CaseEq, value,
                                          logicConstant(b, loc, logic, high));
  return arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, value,
                               arith::ConstantIntOp::create(b, loc, high, 1));
}
using Opcode = upf::ExpressionOpcode;
struct Expression {
  struct Node {
    upf::ExpressionTokenAttr token;
    unsigned left = 0, right = 0, width = 1;
    bool isSigned = false;
  };
  SmallVector<Node> nodes;
  llvm::SetVector<StringRef> controls;
  llvm::SetVector<upf::ExpressionTokenAttr> references;
  Expression(upf::ExpressionAttr expression) {
    if (!expression)
      return;
    SmallVector<unsigned> stack;
    for (auto attr : expression.getTokens()) {
      auto token = cast<upf::ExpressionTokenAttr>(attr);
      Node node{token};
      switch (token.getOpcode()) {
      case Opcode::Control:
        controls.insert(token.getControl().getValue());
        references.insert(token);
        node.width = token.getWidth();
        node.isSigned = token.getIsSigned();
        break;
      case Opcode::Constant:
        node.width = token.getValue().getValue().getBitWidth();
        node.isSigned = token.getIsSigned();
        break;
      case Opcode::Not:
      case Opcode::BitNot:
        node.left = stack.pop_back_val();
        if (token.getOpcode() == Opcode::BitNot) {
          node.width = nodes[node.left].width;
          node.isSigned = nodes[node.left].isSigned;
        }
        break;
      default:
        node.right = stack.pop_back_val();
        node.left = stack.pop_back_val();
        if (token.getOpcode() == Opcode::BitAnd ||
            token.getOpcode() == Opcode::BitXor ||
            token.getOpcode() == Opcode::BitOr) {
          node.width =
              std::max(nodes[node.left].width, nodes[node.right].width);
          node.isSigned =
              nodes[node.left].isSigned && nodes[node.right].isSigned;
        }
        break;
      }
      stack.push_back(nodes.size());
      nodes.push_back(node);
    }
  }
  static Value reference(OpBuilder &b, Location loc, Value context,
                         const llvm::StringMap<Descriptor> &descriptors,
                         upf::ExpressionTokenAttr token) {
    Value value = flatten(
        b, loc,
        load(b, loc,
             handle(b, loc, context,
                    descriptors.lookup(token.getControl().getValue()))));
    if (isa<IntegerType>(value.getType()))
      value = sim::SimLogicFromBitsOp::create(
          b, loc, sim::LogicType::get(b.getContext(), token.getSourceWidth()),
          value);
    // IEEE 1801-2018 5.4: select the named HDL object before propagating its
    // expression context. 6.22 knownness likewise observes only this selection.
    if (token.getWidth() != token.getSourceWidth() || token.getOffset())
      value = sim::SimLogicExtractOp::create(
          b, loc, sim::LogicType::get(b.getContext(), token.getWidth()), value,
          token.getOffset());
    return value;
  }
  Value emit(OpBuilder &b, Location loc, Value context,
             const llvm::StringMap<Descriptor> &descriptors, unsigned index,
             unsigned width = 0, bool isSigned = false) const {
    const Node &node = nodes[index];
    if (!width) {
      width = node.width;
      isSigned = node.isSigned;
    }
    auto type = sim::LogicType::get(b.getContext(), width);
    auto resize = [&](Value value, bool sign) -> Value {
      if (value.getType() == type)
        return value;
      return sim::SimLogicResizeOp::create(b, loc, type, value, sign);
    };
    auto child = [&](unsigned index, unsigned width = 0, bool sign = false) {
      return emit(b, loc, context, descriptors, index, width, sign);
    };
    switch (node.token.getOpcode()) {
    case Opcode::Control: {
      Value value = reference(b, loc, context, descriptors, node.token);
      return resize(value, isSigned);
    }
    case Opcode::Constant: {
      APInt value = node.token.getValue().getValue();
      APInt unknown = node.token.getUnknown().getValue();
      auto extend = [&](APInt plane) {
        return node.token.getFill() || isSigned ? plane.sextOrTrunc(width)
                                                : plane.zextOrTrunc(width);
      };
      auto integer = b.getIntegerType(width);
      return sim::SimLogicConstantOp::create(
          b, loc, type, b.getIntegerAttr(integer, extend(value)),
          b.getIntegerAttr(integer, extend(unknown)));
    }
    case Opcode::BitNot:
      // IEEE 1801-2018 5.4 uses SV expression sizing: the comparison/bitwise
      // context must reach the operand BEFORE applying ~, &, ^, or |.
      return sim::SimLogicUnaryOp::create(b, loc, type, sim::UnaryKind::BitNot,
                                          child(node.left, width, isSigned));
    case Opcode::Not: {
      auto resultType = sim::LogicType::get(b.getContext(), 1);
      Value value = sim::SimLogicUnaryOp::create(
          b, loc, resultType, sim::UnaryKind::LogicalNot, child(node.left));
      return resize(value, false);
    }
    case Opcode::BitAnd:
    case Opcode::BitXor:
    case Opcode::BitOr: {
      auto kind =
          node.token.getOpcode() == Opcode::BitAnd   ? sim::BinaryKind::And
          : node.token.getOpcode() == Opcode::BitXor ? sim::BinaryKind::Xor
                                                     : sim::BinaryKind::Or;
      return sim::SimLogicBinaryOp::create(b, loc, type, kind,
                                           child(node.left, width, isSigned),
                                           child(node.right, width, isSigned));
    }
    case Opcode::And:
    case Opcode::Or: {
      auto kind = node.token.getOpcode() == Opcode::And ? sim::LogicalKind::And
                                                        : sim::LogicalKind::Or;
      Value value = sim::SimLogicLogicalOp::create(
          b, loc, sim::LogicType::get(b.getContext(), 1), kind,
          child(node.left), child(node.right));
      return resize(value, false);
    }
    default: {
      unsigned operandWidth =
          std::max(nodes[node.left].width, nodes[node.right].width);
      bool sign = nodes[node.left].isSigned && nodes[node.right].isSigned;
      sim::CompareKind kind;
      switch (node.token.getOpcode()) {
      case Opcode::Equal:
        kind = sim::CompareKind::Eq;
        break;
      case Opcode::NotEqual:
        kind = sim::CompareKind::Ne;
        break;
      case Opcode::Less:
        kind = sign ? sim::CompareKind::SLT : sim::CompareKind::ULT;
        break;
      case Opcode::LessEqual:
        kind = sign ? sim::CompareKind::SLE : sim::CompareKind::ULE;
        break;
      case Opcode::Greater:
        kind = sign ? sim::CompareKind::SGT : sim::CompareKind::UGT;
        break;
      case Opcode::GreaterEqual:
        kind = sign ? sim::CompareKind::SGE : sim::CompareKind::UGE;
        break;
      default:
        llvm_unreachable("verified UPF expression opcode");
      }
      Value value = sim::SimLogicCompareOp::create(
          b, loc, sim::LogicType::get(b.getContext(), 1), kind,
          child(node.left, operandWidth, sign),
          child(node.right, operandWidth, sign));
      return resize(value, false);
    }
    }
  }
  Value predicate(OpBuilder &b, Location loc, Value context,
                  const llvm::StringMap<Descriptor> &descriptors) const {
    Value value = emit(b, loc, context, descriptors, nodes.size() - 1);
    unsigned width = cast<sim::LogicType>(value.getType()).getWidth();
    // IEEE 1801-2018 5.4 defines True as the known value 1, otherwise False.
    auto integer = b.getIntegerType(width);
    Value one = sim::SimLogicConstantOp::create(
        b, loc, value.getType(), b.getIntegerAttr(integer, APInt(width, 1)),
        b.getIntegerAttr(integer, APInt(width, 0)));
    return sim::SimLogicCompareOp::create(b, loc, b.getI1Type(),
                                          sim::CompareKind::CaseEq, value, one);
  }
};
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
  Value normal(OpBuilder &b, Location loc, Value context) const {
    if (!policies.empty()) {
      Value result = arith::ConstantIntOp::create(b, loc, 1, 1);
      for (auto policy : policies) {
        auto value = evaluateSupplySet(
            policy, b, loc, [&](FlatSymbolRefAttr ref) -> Value {
              auto source = supplies.lookup(ref.getValue());
              // Evaluate our output inline, preserving clock/NBA ordering when
              // source voltage or controls changed in this same activation.
              if (input && source.id == power.id)
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
    Value result =
        input ? fullValue(drivenSupply(b, loc, context)) : full(power);
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
std::optional<uint64_t> storageID(Value reference, sim::SimFuncOp function) {
  while (auto view = reference.getDefiningOp<ViewLikeOpInterface>())
    reference = view.getViewSource();
  if (auto storage = reference.getDefiningOp<sim::SimContextStorageOp>())
    return storage.getId();
  if (auto argument = dyn_cast<BlockArgument>(reference))
    if (argument.getOwner() == &function.getBody().front())
      if (auto id = function.getArgAttrOfType<IntegerAttr>(
              argument.getArgNumber(),
              sim::metadata::DescriptorId::getNameStr()))
        return id.getUInt();
  return std::nullopt;
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
  void nba(sim::SimNBAEnqueueOp enqueue, const PowerCondition &condition,
           Descriptor epoch) {
    // IEEE 1801-2018 9.5.3: events queued before CORRUPT have no effect.
    // Capturing the epoch also prevents an OFF/ON cycle from reviving an old
    // delayed event merely because the domain is NORMAL again at commit time.
    sim::SimFuncOp caller = enqueue->getParentOfType<sim::SimFuncOp>();
    Location loc = enqueue.getLoc();
    Type contextType = sim::ContextType::get(builder.getContext()),
         delayType = sim::TimeType::get(builder.getContext());
    auto commit = function(loc, (Twine("__upf_nba_") + Twine(nextUnit)).str(),
                           {contextType, enqueue.getDestination().getType(),
                            enqueue.getValue().getType(), builder.getI64Type(),
                            delayType},
                           sim::EntryKind::Fork);
    Block &entry = commit.getBody().front();
    Block *check = new Block, *publish = new Block, *done = new Block;
    commit.getBody().push_back(check);
    commit.getBody().push_back(publish);
    commit.getBody().push_back(done);
    builder.setInsertionPointToEnd(&entry);
    sim::SimSuspendDelayOp::create(builder, loc, entry.getArgument(4),
                                   schedule::TimingSiteAttr{}, ValueRange{},
                                   schedule::ContinuationSiteAttr{},
                                   sim::EventRegionAttr{}, check);
    builder.setInsertionPointToEnd(check);
    Value current =
        load(builder, loc, handle(builder, loc, entry.getArgument(0), epoch));
    Value same = arith::CmpIOp::create(builder, loc, arith::CmpIPredicate::eq,
                                       current, entry.getArgument(3));
    Value on = condition.normal(builder, loc, entry.getArgument(0));
    Value valid = arith::AndIOp::create(builder, loc, same, on);
    cf::CondBranchOp::create(builder, loc, valid, publish, done);
    builder.setInsertionPointToEnd(publish);
    Value zeroDelay =
        sim::SimTimeConstantOp::create(builder, loc, delayType, uint64_t{0});
    sim::SimNBAEnqueueOp::create(builder, loc, entry.getArgument(2),
                                 entry.getArgument(1), zeroDelay,
                                 schedule::NBASiteAttr{}, IntegerAttr{});
    cf::BranchOp::create(builder, loc, done);
    builder.setInsertionPointToEnd(done);
    sim::SimReturnOp::create(builder, loc, ValueRange{});
    builder.setInsertionPoint(enqueue);
    Value context = caller.getArgument(0);
    Value snapshot = load(builder, loc, handle(builder, loc, context, epoch));
    Value delay = enqueue.getDelay();
    if (!delay)
      delay =
          sim::SimTimeConstantOp::create(builder, loc, delayType, uint64_t{0});
    sim::SimSpawnOp::create(builder, loc, commit.getSymNameAttr(),
                            ValueRange{context, enqueue.getDestination(),
                                       enqueue.getValue(), snapshot, delay},
                            ArrayAttr{}, ArrayAttr{});
    enqueue.erase();
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
    // IEEE 1801-2018 6.45 applies isolation per path, with -diff_supply_only
    // TRUE by default. Multiple boundary instances can exchange same-domain
    // traffic, so a whole-output mux cannot yet represent their path filters.
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
      SmallVector<sim::SimNBAEnqueueOp> enqueues;
      process.walk([&](sim::SimNBAEnqueueOp op) { enqueues.push_back(op); });
      for (auto enqueue : enqueues)
        nba(enqueue, condition, epoch);
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
