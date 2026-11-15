//===- SAIFDialect.cpp - SAIF exchange data and validation ---------------===//

#include "talos/Dialect/SAIF/SAIFOps.h"

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
    if (!getCellAttr() || getCellAttr().getValue().empty() ||
        !hasSingleElement(getBody().front()) ||
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

LogicalResult FileOp::verifyRegions() {
  std::array<HeaderOp, 10> headers{};
  unsigned next = 0;
  bool records = false;
  bool library = false;
  unsigned libraryCount = 0;
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
      if (isa<LibraryOp>(op)) {
        library = true;
        ++libraryCount;
      }
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
  Form form = backward ? Form::Backward : library ? Form::Library : Form::RTL;
  if (form == Form::Library && libraryCount != 1)
    return emitOpError(
        "library forward file requires exactly one LIBRARY record");
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
