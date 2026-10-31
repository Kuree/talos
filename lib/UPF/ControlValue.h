#ifndef TALOS_UPF_CONTROLVALUE_H
#define TALOS_UPF_CONTROLVALUE_H
// Shared simulation lowering of IEEE 1801-2018 5.4 control expressions.
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "talos/Dialect/Simulation/SimulationMetadata.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/StringMap.h"
#include <optional>
namespace talos::upf_detail {
using namespace mlir;
struct Descriptor {
  uint64_t id;
  Type type;
  bool net = false, driver = false;
};
inline bool within(StringRef path, StringRef prefix) {
  return path == prefix || (path.starts_with(prefix) &&
                            path.drop_front(prefix.size()).starts_with('.'));
}
inline bool contains(upf::UPFDomainOp domain, StringRef path) {
  for (Attribute element : domain.getElements()) {
    StringRef prefix = cast<StringAttr>(element).getValue();
    if (within(path, prefix))
      return true;
  }
  return false;
}
inline SmallVector<StringRef> boundaryInstances(upf::UPFDomainOp domain) {
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
inline Value handle(OpBuilder &b, Location loc, Value context, Descriptor d) {
  if (d.driver)
    return sim::SimContextDriverOp::create(
        b, loc, sim::DriverType::get(b.getContext(), d.type), context, d.id);
  if (d.net)
    return sim::SimContextNetOp::create(
        b, loc, sim::NetType::get(b.getContext(), d.type), context, d.id);
  return sim::SimContextStorageOp::create(
      b, loc, sim::RefType::get(b.getContext(), d.type), context, d.id);
}
inline Value load(OpBuilder &b, Location loc, Value reference) {
  if (auto net = dyn_cast<sim::NetType>(reference.getType()))
    return sim::SimNetReadOp::create(b, loc, net.getElementType(), reference);
  return sim::SimRefLoadOp::create(
      b, loc, cast<sim::RefType>(reference.getType()).getElementType(),
      reference);
}
inline void store(OpBuilder &b, Location loc, Value reference, Value value) {
  if (isa<sim::DriverType>(reference.getType()))
    sim::SimDriverDriveOp::create(b, loc, reference, value);
  else if (isa<sim::NetType>(reference.getType()))
    sim::SimNetWriteOp::create(b, loc, reference, value);
  else
    sim::SimRefStoreOp::create(b, loc, value, reference);
}
inline Value logicConstant(OpBuilder &b, Location loc, sim::LogicType type,
                           bool value, bool unknown = false) {
  auto integer = b.getIntegerType(type.getWidth());
  return sim::SimLogicConstantOp::create(
      b, loc, type,
      b.getIntegerAttr(integer, value ? APInt::getAllOnes(type.getWidth())
                                      : APInt(type.getWidth(), 0)),
      b.getIntegerAttr(integer, unknown ? APInt::getAllOnes(type.getWidth())
                                        : APInt(type.getWidth(), 0)));
}
inline bool supportedState(Type type) {
  if (auto array = dyn_cast<sim::PackedArrayType>(type))
    return supportedState(array.getElementType());
  return isa<sim::LogicType, IntegerType>(type);
}
inline Value flatten(OpBuilder &b, Location loc, Value value) {
  Type scalar = sim::getPackedScalarType(value.getType());
  if (scalar == value.getType())
    return value;
  return sim::SimPackedFlattenOp::create(b, loc, scalar, value);
}
inline Value corrupt(OpBuilder &b, Location loc, Type type) {
  if (Type scalar = sim::getPackedScalarType(type); scalar != type) {
    Value value = corrupt(b, loc, scalar);
    return sim::SimPackedUnflattenOp::create(b, loc, type, value);
  }
  if (auto logic = dyn_cast<sim::LogicType>(type))
    return logicConstant(b, loc, logic, false, true);
  return arith::ConstantOp::create(b, loc, type, b.getZeroAttr(type));
}
inline Value equalsLevel(OpBuilder &b, Location loc, Value value, bool high) {
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
inline std::optional<uint64_t> storageID(Value reference,
                                         sim::SimFuncOp function) {
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
} // namespace talos::upf_detail
#endif
