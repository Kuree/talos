#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/TypeSwitch.h"

#include "talos/Dialect/UPF/UPFDialect.cpp.inc"
#include "talos/Dialect/UPF/UPFEnums.cpp.inc"
#define GET_ATTRDEF_CLASSES
#include "talos/Dialect/UPF/UPFAttrs.cpp.inc"
#define GET_OP_CLASSES
#include "talos/Dialect/UPF/UPFOps.cpp.inc"
namespace talos::upf {
void UPFDialect::initialize() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "talos/Dialect/UPF/UPFAttrs.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "talos/Dialect/UPF/UPFOps.cpp.inc"
      >();
}
mlir::LogicalResult UPFDomainOp::verify() {
  if (getElements().empty())
    return emitOpError("requires domain elements");
  for (auto element : getElements())
    if (mlir::cast<mlir::StringAttr>(element).getValue().empty())
      return emitOpError("domain element must not be empty");
  if (auto isolation = getIsolationControl(); isolation && isolation->empty())
    return emitOpError("isolation control must not be empty");
  if (getClamp() != 0 && getClamp() != 1)
    return emitOpError("isolation clamp must be zero or one");
  return mlir::success();
}

mlir::LogicalResult ExpressionTokenAttr::verify(
    llvm::function_ref<mlir::InFlightDiagnostic()> emitError,
    ExpressionOpcode opcode, mlir::StringAttr control, mlir::IntegerAttr value,
    mlir::IntegerAttr unknown, bool isSigned, bool fill) {
  if (opcode == ExpressionOpcode::Control) {
    if (!control || control.getValue().empty() || value || unknown || fill)
      return emitError() << "control token requires a nonempty path only";
    return mlir::success();
  }
  if (opcode == ExpressionOpcode::Constant) {
    if (control || !value || !unknown || value.getType() != unknown.getType())
      return emitError()
             << "constant requires equally typed value/unknown planes";
    auto type = mlir::dyn_cast<mlir::IntegerType>(value.getType());
    if (!type || !type.isSignless() || !type.getWidth() ||
        type.getWidth() > 4096)
      return emitError() << "constant requires signless planes of 1..4096 bits";
    if (fill && (type.getWidth() != 1 || isSigned))
      return emitError() << "fill constant requires one unsigned bit";
    return mlir::success();
  }
  if (control || value || unknown || isSigned || fill)
    return emitError() << "expression operator cannot carry an operand";
  if (static_cast<unsigned>(opcode) >
      static_cast<unsigned>(ExpressionOpcode::Or))
    return emitError() << "invalid expression opcode";
  return mlir::success();
}

mlir::LogicalResult
ExpressionAttr::verify(llvm::function_ref<mlir::InFlightDiagnostic()> emitError,
                       mlir::ArrayAttr tokens) {
  // IEEE 1801-2018 5.4: preserve the expression and every referenced object,
  // including operands masked by constants (the unknown rule in 6.22).
  if (!tokens || tokens.empty() || tokens.size() > 4096)
    return emitError() << "expression requires 1..4096 postfix tokens";
  struct State {
    unsigned height, width;
    bool boolean;
  };
  llvm::SmallVector<State> stack;
  for (auto attribute : tokens) {
    auto token = mlir::dyn_cast<ExpressionTokenAttr>(attribute);
    if (!token)
      return emitError() << "expression contains a non-token attribute";
    auto opcode = token.getOpcode();
    if (opcode == ExpressionOpcode::Control ||
        opcode == ExpressionOpcode::Constant) {
      unsigned width = opcode == ExpressionOpcode::Control
                           ? 1
                           : token.getValue().getValue().getBitWidth();
      bool boolean = width == 1 || (token.getUnknown().getValue().isZero() &&
                                    token.getValue().getValue().ule(1));
      stack.push_back({1, width, boolean});
      continue;
    }
    unsigned arity =
        opcode == ExpressionOpcode::Not || opcode == ExpressionOpcode::BitNot
            ? 1
            : 2;
    if (stack.size() < arity)
      return emitError() << "expression postfix stack underflow";
    State state = stack.pop_back_val();
    bool logical = opcode == ExpressionOpcode::Not ||
                   opcode == ExpressionOpcode::And ||
                   opcode == ExpressionOpcode::Or;
    if (logical && !state.boolean)
      return emitError()
             << "wide Boolean value requires an explicit comparison";
    if (arity == 2) {
      State left = stack.pop_back_val();
      if (logical && !left.boolean)
        return emitError()
               << "wide Boolean value requires an explicit comparison";
      state.height = std::max(state.height, left.height);
      state.width = std::max(state.width, left.width);
    }
    if (++state.height > 256)
      return emitError() << "expression tree exceeds 256 levels";
    if (opcode != ExpressionOpcode::BitNot &&
        opcode != ExpressionOpcode::BitAnd &&
        opcode != ExpressionOpcode::BitXor && opcode != ExpressionOpcode::BitOr)
      state.width = 1;
    state.boolean = state.width == 1;
    stack.push_back(state);
  }
  if (stack.size() != 1)
    return emitError() << "expression must produce exactly one value";
  // 5.4 defines Boolean values as 0/1. Keep wider SV values usable beneath
  // explicit comparisons without guessing how a bare wide result is coerced.
  if (!stack.back().boolean)
    return emitError() << "wide Boolean value requires an explicit comparison";
  return mlir::success();
}
} // namespace talos::upf
