#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/ADT/TypeSwitch.h"

#include "talos/Dialect/UPF/UPFDialect.cpp.inc"
#include "talos/Dialect/UPF/UPFEnums.cpp.inc"
#define GET_ATTRDEF_CLASSES
#include "talos/Dialect/UPF/UPFAttrs.cpp.inc"
#define GET_OP_CLASSES
#include "talos/Dialect/UPF/UPFOps.cpp.inc"
namespace talos::upf {
mlir::LogicalResult UPFSupplyOp::verify() {
  // IEEE 1801-2018 9.2.1 and 11.2: one packed value per root, not per name.
  // Bits [1:0] are supply state; [33:2] are signed32 microvolt bits.
  if (getNames().empty())
    return emitOpError("requires at least one absolute supply handle name");
  llvm::StringSet<> names;
  for (auto attr : getNames()) {
    auto name = mlir::cast<mlir::StringAttr>(attr).getValue();
    if (!name.starts_with('/') || name.size() < 2 || !names.insert(name).second)
      return emitOpError("supply names must be unique absolute handle IDs");
  }
  if ((uint64_t(getInitialValue()) >> 34) != 0)
    return emitOpError(
        "initial supply value exceeds the packed state/voltage layout");
  return mlir::success();
}
mlir::LogicalResult
UPFSupplySetOp::verifySymbolUses(mlir::SymbolTableCollection &symbols) {
  for (auto binding : getFunctions())
    if (!symbols.lookupNearestSymbolFrom<UPFSupplyOp>(
            *this, mlir::cast<mlir::FlatSymbolRefAttr>(binding.getValue())))
      return emitOpError("references an unknown function supply root");
  return mlir::success();
}
mlir::LogicalResult UPFSupplySetOp::verify() {
  // IEEE 1801-2018 6.26: all six functions exist; requiredness is separate
  // and usage-derived (4.5.4.7). Set identity survives electrical association.
  if (getFunctions().size() != getSupplyFunctionNames().size())
    return emitOpError("requires exactly the six standard supply functions");
  for (auto binding : getFunctions())
    if (!llvm::is_contained(getSupplyFunctionNames(),
                            binding.getName().strref()) ||
        !mlir::isa<mlir::FlatSymbolRefAttr>(binding.getValue()))
      return emitOpError("function bindings must map standard functions to "
                         "flat supply root references");
  llvm::StringSet<> required;
  for (auto attr : getRequired()) {
    auto name = mlir::cast<mlir::StringAttr>(attr).getValue();
    if (!llvm::is_contained(getSupplyFunctionNames(), name) ||
        !required.insert(name).second)
      return emitOpError(
          "required functions must be unique standard supply functions");
  }
  return mlir::success();
}
mlir::LogicalResult
UPFDomainOp::verifySymbolUses(mlir::SymbolTableCollection &symbols) {
  for (auto ref : {getPowerAttr(), getGroundAttr(), getInputAttr()})
    if (ref && !symbols.lookupNearestSymbolFrom<UPFSupplyOp>(*this, ref))
      return emitOpError("references an unknown supply root: ") << ref;
  if (auto primary = getPrimaryAttr()) {
    auto set = symbols.lookupNearestSymbolFrom<UPFSupplySetOp>(*this, primary);
    if (!set)
      return emitOpError("references an unknown primary supply set");
    if (set.getFunctions().get("power") != getPowerAttr() ||
        set.getFunctions().get("ground") != getGroundAttr())
      return emitOpError(
          "primary power and ground must match the supply-set functions");
    llvm::StringSet<> required;
    for (auto function : set.getRequired())
      required.insert(mlir::cast<mlir::StringAttr>(function).getValue());
    if (!required.contains("power") || !required.contains("ground"))
      return emitOpError(
          "primary supply set requires power and ground functions");
    for (auto &function : required) {
      auto ref = mlir::dyn_cast<mlir::FlatSymbolRefAttr>(
          set.getFunctions().get(function.getKey()));
      auto root = ref ? symbols.lookupNearestSymbolFrom<UPFSupplyOp>(*this, ref)
                      : UPFSupplyOp{};
      if (root && ref != getPowerAttr() && !root.getWritable())
        return emitOpError("required auxiliary functions must have independent "
                           "writable roots");
    }
  }
  // This runtime slice supports independent root drivers and one abstract
  // switch per domain (IEEE 1801-2018 9.1/9.2.2). Preserve that contract for
  // textual IR as well as Tcl: an HDL supply call must never write a computed
  // switch output, and a computed output cannot act as another root input.
  auto writable = [&](mlir::FlatSymbolRefAttr ref) {
    return symbols.lookupNearestSymbolFrom<UPFSupplyOp>(*this, ref)
        .getWritable();
  };
  if (auto input = getInputAttr()) {
    if (writable(getPowerAttr()))
      return emitOpError("switch output supply root must not be writable");
    if (!writable(input))
      return emitOpError("switch input supply root must be writable");
    for (auto other : (*this)->getBlock()->getOps<UPFDomainOp>())
      if (other != *this && other.getInputAttr() &&
          other.getPowerAttr() == getPowerAttr())
        return emitOpError("multiple switches drive the same supply root");
  } else if (!writable(getPowerAttr())) {
    return emitOpError("direct domain power supply root must be writable");
  }
  if (getGroundAttr() && !writable(getGroundAttr()))
    return emitOpError("primary ground supply root must be writable");
  return mlir::success();
}
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
  if (!getInputAttr() && (!getOn().empty() || getOffAttr() ||
                          (getErrorsAttr() && !getErrorsAttr().empty())))
    return emitOpError("switch conditions require an input supply root");
  if (getInputAttr() == getPowerAttr())
    return emitOpError("switch input and output supply roots must differ");
  // IEEE 1801-2018 6.22: state names share one namespace for this switch.
  // Bound the combined inventory, not only each individual expression.
  llvm::SmallVector<SwitchStateAttr> states;
  for (auto attr : getOn())
    states.push_back(mlir::cast<SwitchStateAttr>(attr));
  if (auto off = getOffAttr())
    states.push_back(off);
  if (auto errors = getErrorsAttr())
    for (auto attr : errors)
      states.push_back(mlir::cast<SwitchStateAttr>(attr));
  if (states.size() > 256)
    return emitOpError("power switch exceeds 256 states");
  llvm::StringSet<> names;
  size_t tokens = 0;
  for (auto state : states) {
    if (!names.insert(state.getName().getValue()).second)
      return emitOpError("duplicate power-switch state name: ")
             << state.getName();
    tokens += state.getCondition().getTokens().size();
    if (tokens > 65536)
      return emitOpError("power switch exceeds 65536 expression tokens");
  }
  return mlir::success();
}

mlir::LogicalResult SwitchStateAttr::verify(
    llvm::function_ref<mlir::InFlightDiagnostic()> emitError,
    mlir::StringAttr name, ExpressionAttr condition) {
  if (!name || name.getValue().empty())
    return emitError() << "switch state requires a nonempty name";
  if (!condition)
    return emitError() << "switch state requires a Boolean expression";
  return mlir::success();
}

mlir::LogicalResult ExpressionTokenAttr::verify(
    llvm::function_ref<mlir::InFlightDiagnostic()> emitError,
    ExpressionOpcode opcode, mlir::StringAttr control, mlir::IntegerAttr value,
    mlir::IntegerAttr unknown, bool isSigned, bool fill, unsigned width,
    unsigned sourceWidth, unsigned offset) {
  if (opcode == ExpressionOpcode::Control) {
    if (!control || control.getValue().empty() || value || unknown || fill)
      return emitError() << "control token requires a nonempty path only";
    if (!width || sourceWidth > 4096 || width > sourceWidth ||
        offset > sourceWidth - width)
      return emitError()
             << "control selection must fit a source of 1..4096 bits";
    return mlir::success();
  }
  if (width != 1 || sourceWidth != 1 || offset != 0)
    return emitError() << "only control tokens carry selection dimensions";
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
                           ? token.getWidth()
                           : token.getValue().getValue().getBitWidth();
      bool boolean = width == 1 || (opcode == ExpressionOpcode::Constant &&
                                    token.getUnknown().getValue().isZero() &&
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
