//===- SAIFDialect.cpp - SAIF exchange data and validation ---------------===//

#include "talos/Dialect/SAIF/SAIFOps.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "llvm/ADT/APFloat.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/Support/Error.h"

#include <array>

using namespace mlir;
using llvm::all_of;
using llvm::any_of;
using llvm::APFloat;
using llvm::consumeError;
using llvm::hasSingleElement;
using llvm::isDigit;
using llvm::isSpace;

#include "talos/Dialect/SAIF/SAIFDialect.cpp.inc"
#include "talos/Dialect/SAIF/SAIFEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "talos/Dialect/SAIF/SAIFAttrs.cpp.inc"

#define GET_OP_CLASSES
#include "talos/Dialect/SAIF/SAIFOps.cpp.inc"

namespace talos::saif {

LogicalResult BindingAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                  uint64_t sourceId, bool sourceIsNet,
                                  uint64_t sourceLow, PathAttr instance,
                                  IdentifierAttr signal, bool port,
                                  uint32_t initial, StringAttr virtualType) {
  if (!instance || !signal || initial > 3)
    return emitError()
           << "binding requires an instance, signal and 0/1/X/Z initial value";
  if (virtualType && !port)
    return emitError() << "virtual instance bindings must be ports";
  return success();
}

void SAIFDialect::initialize() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "talos/Dialect/SAIF/SAIFAttrs.cpp.inc"
      >();
  addOperations<
#define GET_OP_LIST
#include "talos/Dialect/SAIF/SAIFOps.cpp.inc"
      >();
}

LogicalResult NumberAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                 StringAttr spelling) {
  return spelling ? success()
                  : emitError() << "number requires a spelling attribute";
}

LogicalResult
IdentifierAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                       StringAttr name, StringAttr index) {
  return name ? success()
              : emitError() << "identifier requires a name attribute";
}

LogicalResult PathAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                               ArrayAttr components) {
  return components ? success()
                    : emitError() << "path requires a component array";
}

LogicalResult
ConditionAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                      ArrayAttr tokens) {
  return tokens ? success() : emitError() << "condition requires a token array";
}

LogicalResult
TimeScaleAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                      NumberAttr amount, StringAttr unit) {
  return amount && unit
             ? success()
             : emitError() << "TIMESCALE requires an amount and unit";
}

static bool decimalSyntax(StringRef value) {
  if (value.empty() || value.size() > 16 * 1024)
    return false;
  size_t cursor = 0;
  bool digit = false;
  while (cursor < value.size() && isDigit(value[cursor])) {
    digit = true;
    ++cursor;
  }
  if (cursor < value.size() && value[cursor] == '.') {
    ++cursor;
    while (cursor < value.size() && isDigit(value[cursor])) {
      digit = true;
      ++cursor;
    }
  }
  if (!digit)
    return false;
  if (cursor < value.size() && (value[cursor] == 'e' || value[cursor] == 'E')) {
    ++cursor;
    if (cursor < value.size() && (value[cursor] == '+' || value[cursor] == '-'))
      ++cursor;
    size_t start = cursor;
    while (cursor < value.size() && isDigit(value[cursor]))
      ++cursor;
    if (cursor == start)
      return false;
  }
  return cursor == value.size();
}

static LogicalResult verifyNumber(function_ref<InFlightDiagnostic()> emitError,
                                  StringAttr spelling) {
  if (!spelling || !decimalSyntax(spelling.getValue()))
    return emitError() << "expected a bounded nonnegative decimal spelling";
  APFloat value(APFloat::IEEEdouble());
  auto status = value.convertFromString(spelling.getValue(),
                                        APFloat::rmNearestTiesToEven);
  if (!status) {
    consumeError(status.takeError());
    return emitError() << "number is not a binary64 representation";
  }
  if (!value.isFinite())
    return emitError() << "number must be finite in binary64";
  return success();
}

static LogicalResult
verifyIdentifier(function_ref<InFlightDiagnostic()> emitError, StringAttr name,
                 StringAttr index) {
  if (!name || name.getValue().empty() || name.getValue().size() > 16 * 1024 ||
      any_of(name.getValue(), [](char c) { return !c || isSpace(c); }))
    return emitError()
           << "identifier must contain 1..16384 non-whitespace characters";
  if (index) {
    StringRef value = index.getValue();
    if (value.empty() || value.size() > 16 * 1024 ||
        !all_of(value, [](char c) { return isDigit(c); }) ||
        (value.size() > 1 && value.front() == '0'))
      return emitError()
             << "bit index must have canonical unsigned decimal spelling";
  }
  return success();
}

static LogicalResult verifyPath(function_ref<InFlightDiagnostic()> emitError,
                                ArrayAttr components) {
  if (!components || components.empty() || components.size() > 4096 ||
      !all_of(components, [](Attribute a) { return isa<IdentifierAttr>(a); }))
    return emitError() << "path requires 1..4096 identifier components";
  return success();
}

static LogicalResult
verifyConditionToken(function_ref<InFlightDiagnostic()> emitError,
                     ConditionOpcode opcode, IdentifierAttr pin) {
  switch (opcode) {
  case ConditionOpcode::Pin:
    return pin ? success() : emitError() << "pin token requires an identifier";
  case ConditionOpcode::Not:
  case ConditionOpcode::And:
  case ConditionOpcode::Xor:
  case ConditionOpcode::Or:
    return !pin ? success() : emitError() << "operator cannot carry a pin";
  }
  return emitError() << "unknown condition opcode";
}

static LogicalResult
verifyCondition(function_ref<InFlightDiagnostic()> emitError,
                ArrayAttr tokens) {
  if (!tokens || tokens.empty() || tokens.size() > 4096)
    return emitError() << "condition requires 1..4096 postfix tokens";
  unsigned depth = 0;
  for (Attribute attribute : tokens) {
    auto token = dyn_cast<ConditionTokenAttr>(attribute);
    if (!token)
      return emitError() << "condition contains a non-token attribute";
    if (!symbolizeConditionOpcode(static_cast<uint32_t>(token.getOpcode())))
      return emitError() << "unknown condition opcode";
    switch (token.getOpcode()) {
    case ConditionOpcode::Pin:
      ++depth;
      break;
    case ConditionOpcode::Not:
      if (!depth)
        return emitError() << "condition postfix stack underflow";
      break;
    case ConditionOpcode::And:
    case ConditionOpcode::Xor:
    case ConditionOpcode::Or:
      if (depth < 2)
        return emitError() << "condition postfix stack underflow";
      --depth;
      break;
    }
  }
  return depth == 1 ? success()
                    : emitError() << "condition must produce exactly one value";
}

static LogicalResult
verifyTimeScale(function_ref<InFlightDiagnostic()> emitError, NumberAttr amount,
                StringAttr unit) {
  if (!amount || !amount.getSpelling() || !unit)
    return emitError() << "TIMESCALE requires an amount and unit";
  StringRef value = amount.getSpelling().getValue();
  value = value.ltrim('0');
  if (value != "1" && value != "10" && value != "100")
    return emitError() << "TIMESCALE amount must be the integer 1, 10, or 100";
  if (!StringSwitch<bool>(unit.getValue())
           .Cases({"s", "ms", "us", "ns", "ps", "fs"}, true)
           .Default(false))
    return emitError() << "TIMESCALE unit must be s, ms, us, ns, ps, or fs";
  return success();
}

template <typename... Children, typename Container>
static LogicalResult bodyContains(Container op) {
  if (!hasSingleElement(op.getBody()))
    return op.emitOpError("requires exactly one body block");
  for (Operation &child : op.getBody().front())
    if (!isa<Children...>(child))
      return child.emitOpError("is not permitted in ") << op->getName();
  return success();
}

template <typename... Parents> static LogicalResult parentIs(Operation *op) {
  if (!op->getParentOp() || !isa<Parents...>(op->getParentOp()))
    return op->emitOpError("has an illegal parent");
  return success();
}

static bool simpleName(PathAttr name) {
  return name && name.getComponents() && name.getComponents().size() == 1;
}

static bool toggleMetric(MetricKind kind) { return kind >= MetricKind::TC; }

static LogicalResult singleLineString(Operation *op, StringAttr value) {
  if (value && any_of(value.getValue(),
                      [](char c) { return !c || c == '\n' || c == '\r'; }))
    return op->emitOpError(
        "SAIF strings must be single-line and contain no NUL");
  return success();
}

LogicalResult FileOp::verify() {
  if (failed(parentIs<mlir::ModuleOp>(*this)))
    return failure();
  return bodyContains<HeaderOp, InstanceOp, LibraryOp>(*this);
}

LogicalResult HeaderOp::verify() {
  if (failed(parentIs<FileOp>(*this)) ||
      failed(singleLineString(*this, getTextAttr())) ||
      failed(singleLineString(*this, getQualifierAttr())))
    return failure();
  bool text = static_cast<bool>(getTextAttr());
  bool qualifier = static_cast<bool>(getQualifierAttr());
  bool scale = static_cast<bool>(getScaleAttr());
  bool value = static_cast<bool>(getValueAttr());
  switch (getKind()) {
  case HeaderKind::Version:
    if (!text || getTextAttr().getValue() != "2.0")
      return emitOpError("SAIFVERSION must be '2.0'");
    if (qualifier && getQualifierAttr().getValue() != "lib" &&
        getQualifierAttr().getValue() != "LIB")
      return emitOpError("SAIFVERSION qualifier must be 'lib' or 'LIB'");
    break;
  case HeaderKind::Direction:
    if (!text || (getTextAttr().getValue() != "forward" &&
                  getTextAttr().getValue() != "backward"))
      return emitOpError("DIRECTION must be 'forward' or 'backward'");
    break;
  case HeaderKind::Divider:
    if (text && getTextAttr().getValue() != "." &&
        getTextAttr().getValue() != "/")
      return emitOpError("DIVIDER must be '.' or '/'");
    break;
  case HeaderKind::TimeScale:
    if (text || qualifier || value)
      return emitOpError("TIMESCALE permits only a scale attribute");
    return success();
  case HeaderKind::Duration:
    if (!value || text || qualifier || scale)
      return emitOpError("DURATION requires only a number value");
    return success();
  default:
    break;
  }
  if (scale || value || (qualifier && getKind() != HeaderKind::Version))
    return emitOpError("header has incompatible value attributes");
  return success();
}

LogicalResult InstanceOp::verifyRegions() {
  if (failed(parentIs<FileOp, InstanceOp>(*this)) ||
      failed(singleLineString(*this, getCellAttr())) ||
      failed(bodyContains<PortsOp, NetsOp, LeakageOp, InstanceOp>(*this)))
    return failure();
  bool children = false;
  DenseSet<Attribute> names;
  DenseSet<Attribute> portNames;
  DenseSet<Attribute> netNames;
  for (Operation &child : getBody().front()) {
    if (auto instance = dyn_cast<InstanceOp>(child)) {
      children = true;
      if (!names.insert(instance.getName()).second)
        return instance.emitOpError("duplicate sibling instance name");
    } else if (children) {
      return child.emitOpError("instance data must precede nested instances");
    } else if (isa<PortsOp, NetsOp>(child)) {
      // An instance may split its data over multiple PORT/NET records. Enforce
      // uniqueness across all records of each kind, preserving distinct port
      // and net namespaces and permitting child instances to reuse names.
      auto &signalNames = isa<PortsOp>(child) ? portNames : netNames;
      for (auto signal : child.getRegion(0).front().getOps<SignalOp>())
        if (!signalNames.insert(signal.getName()).second)
          return signal.emitOpError("duplicate signal name");
    }
  }
  if (getIsVirtual()) {
    // Syntax 22 requires the type string; I.2.5 permits it to be empty.
    if (!getCellAttr() || !hasSingleElement(getBody().front()) ||
        !isa<PortsOp>(getBody().front().front()))
      return emitOpError(
          "VIRTUAL_INSTANCE requires a type and exactly one PORT record");
  }
  return success();
}

LogicalResult LibraryOp::verifyRegions() {
  if (failed(parentIs<FileOp>(*this)) ||
      failed(singleLineString(*this, getNameAttr())) ||
      failed(singleLineString(*this, getDirectoryAttr())))
    return failure();
  return bodyContains<CellOp>(*this);
}

LogicalResult CellOp::verifyRegions() {
  if (failed(parentIs<LibraryOp>(*this)))
    return failure();
  if (!simpleName(getName()))
    return emitOpError("MODULE requires a simple identifier");
  return bodyContains<PortDirectiveOp, LeakageOp>(*this);
}

template <typename Container> static LogicalResult verifySignals(Container op) {
  if (failed(parentIs<InstanceOp>(op)) ||
      failed(bodyContains<SignalOp, MappingOp>(op)))
    return failure();
  return success();
}

LogicalResult PortsOp::verifyRegions() { return verifySignals(*this); }
LogicalResult NetsOp::verifyRegions() { return verifySignals(*this); }

LogicalResult SignalOp::verifyRegions() {
  if (failed(parentIs<PortsOp, NetsOp>(*this)) ||
      failed(bodyContains<MetricOp, ConditionsOp, PathsOp>(*this)))
    return failure();
  if (!simpleName(getName()))
    return emitOpError("backward signal name must be a simple identifier");
  unsigned metrics = 0;
  for (Operation &child : getBody().front()) {
    if (auto metric = dyn_cast<MetricOp>(child)) {
      unsigned mask = 1u << static_cast<unsigned>(metric.getKind());
      if (metrics & mask)
        return metric.emitOpError("duplicate signal metric");
      metrics |= mask;
    } else if (isa<NetsOp>((*this)->getParentOp())) {
      return child.emitOpError(
          "NET permits only simple timing and toggle attributes");
    }
  }
  return success();
}

LogicalResult PortDirectiveOp::verifyRegions() {
  if (failed(parentIs<CellOp>(*this)))
    return failure();
  if (!simpleName(getName()))
    return emitOpError("library PORT requires a simple identifier");
  return bodyContains<ConditionsOp, PathsOp>(*this);
}

LogicalResult MappingOp::verify() {
  if (failed(parentIs<PortsOp, NetsOp>(*this)) ||
      failed(singleLineString(*this, getVirtualTypeAttr())))
    return failure();
  if (getVirtualTypeAttr() && isa<NetsOp>((*this)->getParentOp()))
    return emitOpError(
        "virtual instance type is permitted only on PORT mappings");
  return success();
}

LogicalResult LeakageOp::verifyRegions() {
  if (failed(parentIs<InstanceOp, CellOp>(*this)))
    return failure();
  return bodyContains<ConditionsOp>(*this);
}

LogicalResult MetricOp::verify() {
  return parentIs<SignalOp, WhenOp, PathOp>(*this);
}

LogicalResult ConditionsOp::verifyRegions() {
  if (failed(parentIs<SignalOp, PortDirectiveOp, LeakageOp>(*this)) ||
      failed(bodyContains<WhenOp>(*this)))
    return failure();
  bool condition = false;
  unsigned defaults = 0;
  unsigned defaultEdges = 0;
  for (auto when : getBody().front().getOps<WhenOp>()) {
    if (when.getConditionAttr()) {
      if (defaults)
        return when.emitOpError("COND must precede COND_DEFAULT");
      condition = true;
      continue;
    }
    ++defaults;
    unsigned mask = 1u << static_cast<unsigned>(when.getEdge());
    if (defaultEdges & mask)
      return when.emitOpError("duplicate COND_DEFAULT edge restriction");
    defaultEdges |= mask;
  }
  if (!condition)
    return emitOpError("requires at least one COND item");
  if (defaults > 1 &&
      (defaults != 2 || defaultEdges != ((1u << unsigned(Edge::Rise)) |
                                         (1u << unsigned(Edge::Fall)))))
    return emitOpError(
        "two COND_DEFAULT items require distinct RISE and FALL restrictions");
  return success();
}

LogicalResult WhenOp::verifyRegions() {
  if (failed(parentIs<ConditionsOp>(*this)))
    return failure();
  return bodyContains<MetricOp, PathsOp>(*this);
}

LogicalResult PathsOp::verifyRegions() {
  if (failed(parentIs<SignalOp, PortDirectiveOp, WhenOp>(*this)) ||
      failed(bodyContains<PathOp>(*this)))
    return failure();
  DenseSet<Attribute> pins;
  bool related = false;
  bool fallback = false;
  for (auto path : getBody().front().getOps<PathOp>()) {
    if (fallback)
      return path.emitOpError(
          "IOPATH_DEFAULT must be last and occur at most once");
    if (path.getIsDefault()) {
      fallback = true;
      continue;
    }
    related = true;
    for (Attribute pin : path.getPins())
      if (!pins.insert(pin).second)
        return path.emitOpError(
            "IOPATH related-pin lists must be mutually exclusive");
  }
  return related ? success() : emitOpError("requires at least one IOPATH item");
}

LogicalResult PathOp::verifyRegions() {
  if (failed(parentIs<PathsOp>(*this)) || failed(bodyContains<MetricOp>(*this)))
    return failure();
  if (getIsDefault() != getPins().empty())
    return emitOpError("IOPATH requires pins and IOPATH_DEFAULT forbids pins");
  if (!all_of(getPins(),
              [](Attribute pin) { return isa<IdentifierAttr>(pin); }))
    return emitOpError("related pins must be simple identifiers");
  return success();
}

namespace {
// Cache validation of immutable values once per file. Repeated zero counts,
// pin names and conditions do not repeatedly parse decimals or scan tokens.
// Each operation and each distinct attribute is visited a constant number of
// times. No per-record ancestor walk or pairwise path comparison is needed.
class AttributeVerifier {
public:
  LogicalResult verify(Attribute attr, Operation *owner) {
    if (!attr || !seen.insert(attr).second)
      return success();
    auto emit = [&] {
      // Release callers can violate an attribute's construction contract with
      // get() instead of getChecked(). Do not invoke its printer while
      // diagnosing malformed storage: printing a null nested attribute can
      // crash before the verifier reports the error.
      auto diagnostic = mlir::emitError(owner->getLoc());
      diagnostic << "'" << owner->getName() << "' op ";
      return diagnostic;
    };
    return TypeSwitch<Attribute, LogicalResult>(attr)
        .Case<NumberAttr>(
            [&](NumberAttr a) { return verifyNumber(emit, a.getSpelling()); })
        .Case<IdentifierAttr>([&](IdentifierAttr a) {
          return verifyIdentifier(emit, a.getName(), a.getIndex());
        })
        .Case<PathAttr>([&](PathAttr a) {
          if (failed(verifyPath(emit, a.getComponents())))
            return failure();
          return verify(a.getComponents(), owner);
        })
        .Case<ConditionTokenAttr>([&](ConditionTokenAttr a) {
          if (failed(verifyConditionToken(emit, a.getOpcode(), a.getPin())))
            return failure();
          return verify(a.getPin(), owner);
        })
        .Case<ConditionAttr>([&](ConditionAttr a) {
          if (failed(verifyCondition(emit, a.getTokens())))
            return failure();
          return verify(a.getTokens(), owner);
        })
        .Case<TimeScaleAttr>([&](TimeScaleAttr a) {
          if (failed(verifyTimeScale(emit, a.getAmount(), a.getUnit())))
            return failure();
          return verify(a.getAmount(), owner);
        })
        .Case<ArrayAttr>([&](ArrayAttr a) {
          for (Attribute element : a)
            if (failed(verify(element, owner)))
              return failure();
          return success();
        })
        .Default([](Attribute) { return success(); });
  }

private:
  DenseSet<Attribute> seen;
};

enum class Form { Backward, Library, RTL };

static LogicalResult verifyContext(Operation *op, Form form) {
  bool backward = form == Form::Backward;
  if (isa<SignalOp, MetricOp>(op) && !backward)
    return op->emitOpError("activity attributes require a backward file");
  if (isa<MappingOp>(op) && form != Form::RTL)
    return op->emitOpError("name mappings require an RTL forward file");
  if (isa<LibraryOp, CellOp, PortDirectiveOp>(op) && form != Form::Library)
    return op->emitOpError(
        "library declarations require a library forward file");
  if (auto instance = dyn_cast<InstanceOp>(op)) {
    if (form == Form::Library || (instance.getIsVirtual() && !backward))
      return instance.emitOpError(
          "instance kind is incompatible with this file");
  }
  if (isa<PortsOp, NetsOp>(op) && backward && op->getRegion(0).front().empty())
    return op->emitOpError(
        "backward PORT and NET records require at least one signal");
  if (auto leakage = dyn_cast<LeakageOp>(op)) {
    if (form == Form::RTL)
      return leakage.emitOpError(
          "LEAKAGE is not permitted in RTL forward files");
    if (backward && leakage.getBody().front().empty())
      return leakage.emitOpError("backward LEAKAGE requires timing attributes");
  }
  if (auto when = dyn_cast<WhenOp>(op)) {
    Operation *owner = op->getParentOp()->getParentOp();
    bool leakage = isa<LeakageOp>(owner);
    Edge edge = when.getEdge();
    if ((leakage && edge != Edge::None) ||
        (backward && edge == Edge::RiseFall) ||
        (!backward && (edge == Edge::Rise || edge == Edge::Fall)))
      return when.emitOpError(
          "edge restriction is incompatible with this SAIF usage");
    Block &body = when.getBody().front();
    if (leakage) {
      for (Operation &child : body) {
        auto metric = dyn_cast<MetricOp>(child);
        if (!backward || !metric ||
            (metric.getKind() != MetricKind::T0 &&
             metric.getKind() != MetricKind::T1))
          return child.emitOpError(
              "LEAKAGE permits only backward T0/T1 attributes");
      }
      unsigned metrics = 0;
      for (auto metric : body.getOps<MetricOp>()) {
        unsigned mask = 1u << unsigned(metric.getKind());
        if (metrics & mask)
          return metric.emitOpError("duplicate leakage timing metric");
        metrics |= mask;
      }
    } else if (backward) {
      if (!hasSingleElement(body))
        return when.emitOpError(
            "backward toggle item requires exactly one metric or path group");
      if (auto metric = dyn_cast<MetricOp>(body.front()))
        if (!toggleMetric(metric.getKind()))
          return metric.emitOpError(
              "conditional port attributes must be toggle metrics");
    } else {
      if (!body.empty() &&
          (!hasSingleElement(body) || !isa<PathsOp>(body.front())))
        return when.emitOpError(
            "forward toggle item permits only one optional path directive");
    }
  }
  if (auto path = dyn_cast<PathOp>(op)) {
    Block &body = path.getBody().front();
    if (!backward)
      return body.empty()
                 ? success()
                 : path.emitOpError(
                       "forward IOPATH cannot contain activity metrics");
    if (!hasSingleElement(body) ||
        !toggleMetric(cast<MetricOp>(body.front()).getKind()))
      return path.emitOpError(
          "backward IOPATH requires exactly one toggle metric");
  }
  return success();
}
} // namespace

LogicalResult SAIFDialect::verifyOperationAttribute(Operation *operation,
                                                    NamedAttribute attr) {
  // Malformed unchecked attributes may not have a printable representation.
  // Report by location without MLIR's automatic operation dump.
  auto error = [&] {
    auto diagnostic = mlir::emitError(operation->getLoc());
    diagnostic << "'" << operation->getName() << "' op ";
    return diagnostic;
  };
  StringRef name = attr.getName().strref();
  if (name != Output::getNameStr() && name != Bindings::getNameStr() &&
      name != Cells::getNameStr())
    return error() << "unknown SAIF attribute " << name;
  if (!isa<ModuleOp>(operation))
    return error() << "SAIF collection attributes belong on a module";
  if (name == Output::getNameStr()) {
    auto path = dyn_cast<StringAttr>(attr.getValue());
    if (!path || path.getValue().empty() || path.getValue().contains('\0'))
      return error() << "saif.output requires a nonempty file path";
    return success();
  }
  if (name == Cells::getNameStr()) {
    auto cells = dyn_cast<ArrayAttr>(attr.getValue());
    auto observations = get<Bindings>(operation);
    if (!cells || !observations || cells.size() > (1 << 20))
      return error()
             << "saif.cells requires a bounded cell plan and saif.bindings";
    AttributeVerifier verifier;
    DenseSet<PathAttr> instances;
    uint64_t resources = 0;
    for (Attribute value : cells) {
      auto cell = dyn_cast<CellBindingAttr>(value);
      if (!cell || !cell.getInstance() || !cell.getCell() || !cell.getPins() ||
          !cell.getGroups())
        return error() << "invalid SAIF cell binding shape";
      if (cell.getCell().getValue().find_first_of("\"\n\r") != StringRef::npos)
        return error() << "SAIF cell type must be a single-line literal string";
      if (failed(verifier.verify(cell.getInstance(), operation)))
        return failure();
      if (!instances.insert(cell.getInstance()).second)
        return error() << "duplicate SAIF cell instance";
      DenseSet<IdentifierAttr> pins;
      DenseSet<uint64_t> pinObservations;
      DenseSet<IdentifierAttr> inputPins;
      DenseSet<uint64_t> outputObservations;
      for (Attribute pinValue : cell.getPins()) {
        auto pin = dyn_cast<PinBindingAttr>(pinValue);
        if (!pin || !pin.getName() ||
            pin.getObservation() >= observations.size())
          return error() << "invalid SAIF cell pin binding";
        if (failed(verifier.verify(pin.getName(), operation)))
          return failure();
        auto observation =
            dyn_cast<BindingAttr>(observations[pin.getObservation()]);
        if (!observation || !observation.getPort() ||
            observation.getInstance() != cell.getInstance() ||
            observation.getSignal() != pin.getName() ||
            !pins.insert(pin.getName()).second)
          return error()
                 << "SAIF cell pins must name distinct ports of that instance";
        pinObservations.insert(pin.getObservation());
        if (pin.getOutput())
          outputObservations.insert(pin.getObservation());
        else
          inputPins.insert(pin.getName());
      }
      for (Attribute groupValue : cell.getGroups()) {
        auto group = dyn_cast<GroupAttr>(groupValue);
        if (!group || !group.getRules() || group.getRules().empty() ||
            (group.getLeakage()
                 ? group.getObservation() != UINT64_MAX
                 : !pinObservations.contains(group.getObservation())) ||
            (!group.getConditional() && group.getRules().size() != 1))
          return error() << "invalid SAIF characterization group";
        if (group.getLeakage() && !group.getConditional())
          return error() << "SAIF leakage groups require conditions";
        bool seenDefault = false;
        bool hasCondition = false;
        for (Attribute ruleValue : group.getRules()) {
          auto rule = dyn_cast<RuleAttr>(ruleValue);
          if (!rule || !rule.getPaths() || seenDefault ||
              (group.getLeakage() &&
               (rule.getSplitEdges() || !rule.getPaths().empty())) ||
              (!group.getConditional() && rule.getCondition()))
            return error() << "invalid SAIF priority rule";
          if (rule.getSplitEdges() && !group.getConditional())
            return error() << "SAIF edge splitting requires conditions";
          if (!rule.getPaths().empty() &&
              !outputObservations.contains(group.getObservation()))
            return error() << "SAIF path groups require an output pin";
          seenDefault = group.getConditional() && !rule.getCondition();
          if (auto condition = rule.getCondition()) {
            hasCondition = true;
            if (failed(verifier.verify(condition, operation)))
              return failure();
            for (Attribute tokenValue : condition.getTokens()) {
              auto token = cast<ConditionTokenAttr>(tokenValue);
              if (token.getOpcode() == ConditionOpcode::Pin &&
                  !pins.contains(token.getPin()))
                return error() << "SAIF condition names an unbound cell pin";
            }
            resources += condition.getTokens().size();
          }
          DenseSet<IdentifierAttr> relatedPins;
          bool pathDefault = false;
          bool hasRelated = false;
          for (Attribute relatedValue : rule.getPaths()) {
            auto related = dyn_cast<RelatedAttr>(relatedValue);
            if (!related || !related.getPins() || pathDefault ||
                related.getIsDefault() != related.getPins().empty())
              return error() << "invalid SAIF related pin list";
            pathDefault = related.getIsDefault();
            hasRelated |= !related.getIsDefault();
            for (Attribute pinValue : related.getPins()) {
              auto pin = dyn_cast<IdentifierAttr>(pinValue);
              if (!pin || !inputPins.contains(pin) ||
                  !relatedPins.insert(pin).second)
                return error()
                       << "SAIF related pins must be distinct bound input pins";
            }
            resources += related.getPins().size() + 1;
          }
          if (!rule.getPaths().empty() && !hasRelated)
            return error() << "SAIF paths require a named related input";
          resources += 1;
        }
        if (group.getConditional() && !hasCondition)
          return error() << "SAIF conditions require a nondefault rule";
        resources += 1;
      }
      resources += cell.getPins().size() + 1;
      if (resources > (1 << 20))
        return error()
               << "SAIF characterization plan exceeds its resource limit";
    }
    return success();
  }
  auto bindings = dyn_cast<ArrayAttr>(attr.getValue());
  if (!bindings || bindings.size() > (1 << 20))
    return error() << "saif.bindings requires at most 1048576 bindings";
  if (!has<Output>(operation))
    return error() << "saif.bindings requires saif.output";
  struct InstanceNode {
    DenseMap<Attribute, unsigned> children;
    DenseSet<std::pair<Attribute, uint32_t>> signals;
    StringAttr virtualType;
    bool hasNets = false;
  };
  SmallVector<InstanceNode> instances(1);
  DenseMap<PathAttr, unsigned> instanceIndices;
  AttributeVerifier verifier;
  for (Attribute value : bindings) {
    auto binding = dyn_cast<BindingAttr>(value);
    if (!binding || !binding.getInstance() || !binding.getSignal() ||
        binding.getInitial() > 3 || binding.getSourceLow() > INT32_MAX ||
        (binding.getVirtualType() && !binding.getPort()))
      return error() << "invalid SAIF observation binding";
    if (failed(verifier.verify(binding.getInstance(), operation)) ||
        failed(verifier.verify(binding.getSignal(), operation)))
      return failure();
    auto components = binding.getInstance().getComponents();
    if (components.size() > 128)
      return error() << "SAIF output instance hierarchy exceeds 128 components";
    auto [found, first] = instanceIndices.try_emplace(binding.getInstance(), 0);
    unsigned node = found->second;
    if (first) {
      for (Attribute component : components) {
        if (instances[node].virtualType)
          return error() << "SAIF virtual instance cannot have child instances";
        auto [it, inserted] =
            instances[node].children.try_emplace(component, instances.size());
        node = it->second;
        if (inserted)
          instances.emplace_back();
      }
      found->second = node;
    }
    auto &instance = instances[node];
    if (auto type = binding.getVirtualType()) {
      if (any_of(type.getValue(),
                 [](char c) { return !c || c == '\n' || c == '\r'; }))
        return error() << "SAIF strings must be single-line and contain no NUL";
      if (type.getValue().contains('"') ||
          (instance.virtualType && instance.virtualType != type))
        return error() << "inconsistent SAIF virtual instance type";
      instance.virtualType = type;
    }
    instance.hasNets |= !binding.getPort();
    if (instance.virtualType &&
        (instance.hasNets || !instance.children.empty()))
      return error() << "SAIF virtual instance may contain only ports";
    if (!instance.signals.insert({binding.getSignal(), binding.getPort()})
             .second)
      return error() << "duplicate SAIF mapped output signal";
  }
  return success();
}

LogicalResult FileOp::verifyRegions() {
  std::array<HeaderOp, 10> headers{};
  unsigned next = 0;
  bool records = false;
  bool library = false;
  DenseSet<Attribute> instances;
  for (Operation &op : getBody().front()) {
    if (auto header = dyn_cast<HeaderOp>(op)) {
      unsigned kind = static_cast<unsigned>(header.getKind());
      if (records || kind != next)
        return header.emitOpError(
            "headers must appear once in Annex I order before data");
      headers[kind] = header;
      ++next;
    } else {
      records = true;
      if (isa<LibraryOp>(op))
        library = true;
      if (auto instance = dyn_cast<InstanceOp>(op))
        if (!instances.insert(instance.getName()).second)
          return instance.emitOpError("duplicate root instance name");
    }
  }
  if (next < 8)
    return emitOpError("requires SAIFVERSION, DIRECTION, DESIGN, DATE, VENDOR, "
                       "PROGRAM_NAME, PROGRAM_VERSION, and DIVIDER headers");
  bool backward = headers[1].getTextAttr().getValue() == "backward";
  if (next != (backward ? 10u : 8u))
    return emitOpError(
        backward ? "backward files require TIMESCALE and DURATION headers"
                 : "forward files forbid TIMESCALE and DURATION headers");
  if (headers[0].getQualifierAttr()) {
    if (backward)
      return headers[0].emitOpError(
          "library qualifier requires a forward file");
    library = true;
  }
  // Annex I leaves lforward_saif_info undefined; I.4.9 lists the cell
  // declarations in "the library SDPD info constructs", so any number of
  // LIBRARY records may follow the header.
  Form form = backward ? Form::Backward : library ? Form::Library : Form::RTL;
  AttributeVerifier attributes;
  WalkResult result = getOperation()->walk([&](Operation *op) {
    for (NamedAttribute attr : op->getAttrs())
      if (failed(attributes.verify(attr.getValue(), op)))
        return WalkResult::interrupt();
    return failed(verifyContext(op, form)) ? WalkResult::interrupt()
                                           : WalkResult::advance();
  });
  return failure(result.wasInterrupted());
}

} // namespace talos::saif
