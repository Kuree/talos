#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/DialectImplementation.h"
#include "talos/Dialect/UPF/UPFOps.h"
#include "llvm/ADT/DenseSet.h"
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
std::optional<PartialOnTranslation>
getPartialOnTranslation(mlir::Operation *operation) {
  auto module = mlir::dyn_cast<mlir::ModuleOp>(operation);
  if (!module)
    module = operation->getParentOfType<mlir::ModuleOp>();
  if (module)
    if (auto value = module->getAttrOfType<PartialOnTranslationAttr>(
            partialOnTranslationName))
      return value.getValue();
  return std::nullopt;
}
mlir::LogicalResult PartialOnTranslationAttr::verify(
    llvm::function_ref<mlir::InFlightDiagnostic()> error,
    PartialOnTranslation value) {
  if (value != PartialOnTranslation::Off &&
      value != PartialOnTranslation::FullOn)
    return error() << "PARTIAL_ON translation must be OFF or FULL_ON";
  return mlir::success();
}
mlir::LogicalResult
UPFDialect::verifyOperationAttribute(mlir::Operation *operation,
                                     mlir::NamedAttribute attribute) {
  if (attribute.getName().strref() == partialOnTranslationName &&
      (!mlir::isa<mlir::ModuleOp>(operation) ||
       !mlir::isa<PartialOnTranslationAttr>(attribute.getValue())))
    return operation->emitOpError(
        "upf.partial_on_translation requires a typed module-level policy");
  return mlir::success();
}
mlir::LogicalResult SupplyExpressionTokenAttr::verify(
    llvm::function_ref<mlir::InFlightDiagnostic()> error,
    SupplyExpressionOpcode opcode, mlir::FlatSymbolRefAttr supply,
    mlir::StringAttr function, mlir::IntegerAttr value, mlir::FloatAttr real) {
  using O = SupplyExpressionOpcode;
  if (opcode == O::State || opcode == O::Voltage) {
    if (!supply || value || real ||
        (function &&
         !llvm::is_contained(getSupplyFunctionNames(), function.getValue())))
      return error() << "supply reference requires a root and optional "
                        "standard function only";
  } else if (opcode == O::StateValue || opcode == O::Boolean) {
    unsigned width = opcode == O::Boolean ? 1 : 32;
    if (supply || function || real || !value ||
        !value.getType().isSignlessInteger(width) ||
        (opcode == O::StateValue && (value.getInt() < 0 || value.getInt() > 3)))
      return error()
             << "supply state/bool literal has an invalid type or value";
  } else if (opcode == O::Real) {
    if (supply || function || value || !real || !real.getType().isF64() ||
        !real.getValue().isFinite())
      return error() << "supply real literal requires one finite f64 value";
  } else if (opcode > O::Or || supply || function || value || real)
    return error() << "supply operator cannot carry operand fields";
  return mlir::success();
}
mlir::LogicalResult SupplyExpressionAttr::verify(
    llvm::function_ref<mlir::InFlightDiagnostic()> error,
    mlir::ArrayAttr tokens) {
  using O = SupplyExpressionOpcode;
  enum Kind { Boolean, State, Real };
  llvm::SmallVector<std::pair<Kind, unsigned>> stack;
  if (tokens.empty() || tokens.size() > 4096)
    return error() << "supply expression requires 1..4096 tokens";
  for (auto attr : tokens) {
    auto token = mlir::dyn_cast<SupplyExpressionTokenAttr>(attr);
    if (!token)
      return error() << "supply expression contains a non-token attribute";
    O code = token.getOpcode();
    if (code <= O::Boolean) {
      stack.emplace_back(code == O::State || code == O::StateValue ? State
                         : code == O::Voltage || code == O::Real   ? Real
                                                                   : Boolean,
                         1);
      continue;
    }
    bool unary = code == O::Not || code == O::BitNot;
    if (stack.size() < (unary ? 1u : 2u))
      return error() << "supply expression postfix stack underflow";
    auto right = stack.pop_back_val(),
         left = unary ? right : stack.pop_back_val();
    bool comparison = code >= O::Less && code <= O::NotEqual;
    if (comparison) {
      if (left.first != right.first ||
          (code != O::Equal && code != O::NotEqual && left.first != Real))
        return error() << "supply comparison requires compatible operand types";
    } else if (left.first != Boolean || right.first != Boolean)
      return error() << "supply Boolean operator requires Boolean operands";
    unsigned height = std::max(left.second, right.second) + 1;
    if (height > 256)
      return error() << "supply expression tree exceeds 256 levels";
    stack.emplace_back(Boolean, height);
  }
  if (stack.size() != 1 || stack.back().first != Boolean)
    return error() << "supply expression must produce one Boolean value";
  return mlir::success();
}
mlir::LogicalResult
PowerStateAttr::verify(llvm::function_ref<mlir::InFlightDiagnostic()> error,
                       mlir::StringAttr name, SupplyExpressionAttr condition,
                       Simstate simstate, bool illegal) {
  if (!name || name.getValue().empty() || name.getValue().contains('.') ||
      name.getValue() == "ERROR" || name.getValue() == "UNDEFINED")
    return error() << "power state requires a supported simple state name";
  if (simstate > Simstate::NotNormal ||
      (condition && simstate == Simstate::Unspecified))
    return error()
           << "active power-state predicates require a supported simstate";
  if ((name.getValue() == "ON" && simstate != Simstate::Normal) ||
      (name.getValue() == "OFF" && simstate != Simstate::Corrupt))
    return error() << "predefined ON/OFF simstates are fixed NORMAL/CORRUPT";
  return mlir::success();
}
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
  if (auto owner = getOwnerAttr();
      owner && !symbols.lookupNearestSymbolFrom<UPFDomainOp>(*this, owner))
    return emitOpError("references an unknown owning domain");
  if (auto links = getAssociatedAttr())
    for (auto attr : links) {
      auto other = symbols.lookupNearestSymbolFrom<UPFSupplySetOp>(
          *this, mlir::cast<mlir::FlatSymbolRefAttr>(attr));
      if (!other)
        return emitOpError("references an unknown associated supply set");
      for (auto function : getSupplyFunctionNames())
        if (getFunctions().get(function) != other.getFunctions().get(function))
          return emitOpError(
              "associated supply sets must share corresponding function roots");
      for (auto required : other.getRequired())
        if (!llvm::is_contained(getRequired(), required))
          return emitOpError(
              "associated required functions must propagate to both sets");
      for (auto required : getRequired())
        if (!llvm::is_contained(other.getRequired(), required))
          return emitOpError(
              "associated required functions must propagate to both sets");
      auto back = other.getAssociatedAttr();
      if (!back || !llvm::is_contained(back, mlir::FlatSymbolRefAttr::get(
                                                 getContext(), getSymName())))
        return emitOpError(
            "supply-set associations must record reciprocal links");
    }
  if (auto states = getStatesAttr())
    for (auto attr : states) {
      auto state = mlir::cast<PowerStateAttr>(attr);
      if (!state.getCondition())
        continue;
      bool powerOrGround = false;
      for (auto attr : state.getCondition().getTokens()) {
        auto token = mlir::cast<SupplyExpressionTokenAttr>(attr);
        if (!token.getSupply())
          continue;
        auto root = symbols.lookupNearestSymbolFrom<UPFSupplyOp>(
            *this, token.getSupply());
        if (!root)
          return emitOpError("predicate references an unknown supply root");
        if (!root.getWritable() &&
            token.getSupply() != getFunctions().get("power"))
          return emitOpError("predicates on other computed switch outputs are "
                             "not implemented");
        if (auto function = token.getFunction()) {
          if (getFunctions().get(function.getValue()) != token.getSupply())
            return emitOpError(
                "predicate function origin must match this supply set");
          if (!llvm::is_contained(getRequired(), function))
            return emitOpError(
                "predicate functions must be required functions");
          powerOrGround |=
              function.getValue() == "power" || function.getValue() == "ground";
        } else {
          powerOrGround |= token.getSupply() == getFunctions().get("power") ||
                           token.getSupply() == getFunctions().get("ground");
          for (auto function : getSupplyFunctionNames())
            if (getFunctions().get(function) == token.getSupply() &&
                !llvm::is_contained(getRequired(), mlir::StringAttr::get(
                                                       getContext(), function)))
              return emitOpError("raw predicate references must preserve "
                                 "required function usage");
        }
      }
      if (!powerOrGround)
        return emitOpError(
            "predicate must reference this set's power or ground function");
    }
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
  if (auto states = getStatesAttr()) {
    llvm::StringSet<> names;
    size_t tokens = 0;
    if (states.size() > 256)
      return emitOpError("power-state catalog exceeds 256 states");
    for (auto attr : states) {
      auto state = mlir::cast<PowerStateAttr>(attr);
      if (!names.insert(state.getName().getValue()).second)
        return emitOpError("duplicate power-state name");
      if (state.getCondition())
        tokens += state.getCondition().getTokens().size();
    }
    if (tokens > 65536)
      return emitOpError("power-state catalog exceeds 65536 tokens");
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
    if (auto owner = set.getOwnerAttr();
        owner && owner.getValue() != getSymName())
      return emitOpError("primary supply handle must be owned by this domain");
    llvm::StringSet<> applicable;
    llvm::DenseSet<mlir::Operation *> visited;
    llvm::SmallVector<UPFSupplySetOp> work{set};
    while (!work.empty()) {
      auto current = work.pop_back_val();
      if (!visited.insert(current.getOperation()).second)
        continue;
      bool otherPrimary = false;
      if (auto owner = current.getOwnerAttr()) {
        auto domain =
            symbols.lookupNearestSymbolFrom<UPFDomainOp>(*this, owner);
        if (!domain)
          return emitOpError("policy set references an unknown owning domain");
        otherPrimary =
            current != set && domain.getPrimaryAttr() &&
            domain.getPrimaryAttr().getValue() == current.getSymName();
      }
      if (!otherPrimary)
        applicable.insert(current.getSymName());
      if (auto links = current.getAssociatedAttr())
        for (auto attr : links) {
          auto next = symbols.lookupNearestSymbolFrom<UPFSupplySetOp>(
              *this, mlir::cast<mlir::FlatSymbolRefAttr>(attr));
          if (!next)
            return emitOpError("references an unknown associated policy set");
          work.push_back(next);
        }
    }
    if (auto policies = getPoliciesAttr()) {
      llvm::StringSet<> names;
      for (auto attr : policies) {
        auto ref = mlir::cast<mlir::FlatSymbolRefAttr>(attr);
        auto policy =
            symbols.lookupNearestSymbolFrom<UPFSupplySetOp>(*this, ref);
        if (!policy || !names.insert(ref.getValue()).second)
          return emitOpError("policies require unique supply-set references");
        if (auto owner = policy.getOwnerAttr(); owner && ref != primary) {
          auto domain =
              symbols.lookupNearestSymbolFrom<UPFDomainOp>(*this, owner);
          if (!domain || domain.getPrimaryAttr() == ref)
            return emitOpError("another domain's primary handle is not a "
                               "policy for this domain");
        }
        for (auto function : getSupplyFunctionNames())
          if (policy.getFunctions().get(function) !=
              set.getFunctions().get(function))
            return emitOpError("primary policies must have the same "
                               "corresponding function roots");
      }
      if (!names.contains(primary.getValue()))
        return emitOpError("policies must include the primary supply set");
      if (names.size() != applicable.size())
        return emitOpError(
            "primary policies must enumerate the applicable associated sets");
      for (auto &name : applicable)
        if (!names.contains(name.getKey()))
          return emitOpError(
              "primary policies must enumerate the applicable associated sets");
    } else if (applicable.size() > 1)
      return emitOpError(
          "associated primary supplies require an explicit policy list");
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
  if (getPoliciesAttr() && !getPrimaryAttr())
    return emitOpError(
        "primary policies require a primary supply-set reference");
  if (getElements().empty())
    return emitOpError("requires domain elements");
  for (auto element : getElements())
    if (mlir::cast<mlir::StringAttr>(element).getValue().empty())
      return emitOpError("domain element must not be empty");
  if (auto isolation = getIsolationControl(); isolation && isolation->empty())
    return emitOpError("isolation control must not be empty");
  if (getClamp() != 0 && getClamp() != 1)
    return emitOpError("isolation clamp must be zero or one");
  if (!getInputAttr() &&
      (!getOn().empty() || (getPartialAttr() && !getPartialAttr().empty()) ||
       getOffAttr() || (getErrorsAttr() && !getErrorsAttr().empty())))
    return emitOpError("switch conditions require an input supply root");
  if (getInputAttr() == getPowerAttr())
    return emitOpError("switch input and output supply roots must differ");
  // IEEE 1801-2018 6.22: state names share one namespace for this switch.
  // Bound the combined inventory, not only each individual expression.
  llvm::SmallVector<SwitchStateAttr> states;
  for (auto attr : getOn())
    states.push_back(mlir::cast<SwitchStateAttr>(attr));
  if (auto partial = getPartialAttr())
    for (auto attr : partial)
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
