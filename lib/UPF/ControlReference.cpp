#include "ControlReference.h"
#include "talos/Dialect/Slang/SlangTypes.h"
#include <algorithm>
#include <limits>
#include <optional>

using namespace mlir;
using llvm::StringRef;
namespace talos {
namespace {
uint64_t distance(int64_t a, int64_t b) {
  // Unsigned subtraction also handles negative ranges without signed overflow.
  return a >= b ? uint64_t(a) - uint64_t(b) : uint64_t(b) - uint64_t(a);
}
bool index(StringRef spelling, int64_t &value) {
  spelling = spelling.trim();
  if (spelling.consume_front("+") && spelling.starts_with('-'))
    return false;
  return !spelling.empty() && !spelling.getAsInteger(10, value);
}
std::optional<unsigned> packedWidth(Type type) {
  uint64_t width = 1;
  while (true) {
    if (auto enumeration = dyn_cast_or_null<slangir::EnumType>(type)) {
      type = enumeration.getBaseType();
      continue;
    }
    if (auto array = dyn_cast_or_null<slangir::PackedArrayType>(type)) {
      uint64_t span = distance(array.getLeft(), array.getRight());
      if (span >= 4096 || width > 4096 / (span + 1))
        return std::nullopt;
      width *= span + 1;
      type = array.getElementType();
      continue;
    }
    auto integral = dyn_cast_or_null<slangir::IntegralType>(type);
    if (!integral || !integral.getWidth() || width > 4096 / integral.getWidth())
      return std::nullopt;
    return width * integral.getWidth();
  }
}
} // namespace
FailureOr<ControlReference>
ControlReference::create(StringRef path, Type type, ArrayAttr types,
                         DenseBoolArrayAttr signs,
                         llvm::function_ref<void(const llvm::Twine &)> report) {
  ControlReference result;
  result.path = path.str();
  auto width = packedWidth(type);
  if (!width) {
    report("UPF control requires a packed integral design object of 1..4096 "
           "bits: " +
           path);
    return failure();
  }
  if (!types || !signs || types.empty() || types.size() > 257 ||
      static_cast<int64_t>(types.size()) != signs.size()) {
    report("UPF control requires declared HDL selection metadata: " + path);
    return failure();
  }
  for (auto attr : types) {
    auto selected = dyn_cast<TypeAttr>(attr);
    if (!selected || !packedWidth(selected.getValue())) {
      report("UPF control has invalid HDL selection metadata: " + path);
      return failure();
    }
  }
  if (cast<TypeAttr>(types[0]).getValue() != type) {
    report("UPF control selection metadata disagrees with its declared type: " +
           path);
    return failure();
  }
  result.types = types;
  result.signs = signs;
  result.isSigned = signs[0];
  result.width = result.sourceWidth = *width;
  return result;
}
LogicalResult
ControlReference::select(StringRef selectors,
                         llvm::function_ref<void(const llvm::Twine &)> report) {
  auto error = [&](const llvm::Twine &message) {
    report("UPF control selection for " + path + ": " + message);
    return failure();
  };
  while (!(selectors = selectors.trim()).empty()) {
    if (!selectors.consume_front("["))
      return error("expected a packed selector");
    size_t close = selectors.find(']');
    if (close == StringRef::npos)
      return error("missing closing bracket");
    StringRef contents = selectors.take_front(close).trim();
    selectors = selectors.drop_front(close + 1);
    Type type = cast<TypeAttr>(types[stage]).getValue();
    int64_t declaredLeft, declaredRight;
    if (auto array = dyn_cast<slangir::PackedArrayType>(type)) {
      declaredLeft = array.getLeft();
      declaredRight = array.getRight();
    } else if (isa<slangir::EnumType>(type)) {
      // IEEE 1801-2018 5.4 inherits enum's flat SV bit-vector range,
      // independently of the underlying base type's declared bounds.
      declaredLeft = width - 1;
      declaredRight = 0;
    } else if (auto integral = dyn_cast<slangir::IntegralType>(type);
               integral && integral.getWidth() > 1) {
      declaredLeft = integral.getLeft();
      declaredRight = integral.getRight();
    } else {
      return error("cannot select a scalar control");
    }
    uint64_t span = distance(declaredLeft, declaredRight);
    if (span >= width || width % (span + 1))
      return error("invalid declared packed range");
    bool descending = declaredLeft >= declaredRight;
    unsigned stride = width / (span + 1);
    if (stage + 1 >= types.size() ||
        packedWidth(cast<TypeAttr>(types[stage + 1]).getValue()) != stride)
      return error("element-selection metadata is incomplete or inconsistent");
    int64_t left, right;
    size_t colon = contents.find(':');
    if (colon == StringRef::npos) {
      if (!index(contents, left))
        return error("requires constant decimal indices");
      right = left;
    } else {
      StringRef first = contents.take_front(colon).rtrim();
      StringRef last = contents.drop_front(colon + 1).trim();
      bool plus = first.ends_with('+'), minus = first.ends_with('-');
      if (plus || minus)
        first = first.drop_back();
      if (!index(first, left) || !index(last, right))
        return error("requires constant decimal indices");
      if (plus || minus) {
        if (right < 1 || right > 4096)
          return error("indexed part-select width must be 1..4096");
        int64_t delta = right - 1;
        if ((plus && left > std::numeric_limits<int64_t>::max() - delta) ||
            (minus && left < std::numeric_limits<int64_t>::min() + delta))
          return error("indexed part-select overflows its index");
        int64_t low = minus ? left - delta : left;
        int64_t high = plus ? left + delta : left;
        left = descending ? high : low;
        right = descending ? low : high;
      }
      if (left != right && (left > right) != descending)
        return error("part-select direction disagrees with the HDL range");
      if (!selectors.trim().empty())
        return error("a part-select must be the final selector");
    }
    auto inRange = [&](int64_t i) {
      return i >= std::min(declaredLeft, declaredRight) &&
             i <= std::max(declaredLeft, declaredRight);
    };
    if (!inRange(left) || !inRange(right))
      return error("index is outside the HDL range");
    // IEEE 1801-2018 5.4: the right declared bound is the least significant
    // element, for either direction. Resolve before expression context sizing.
    offset += distance(right, declaredRight) * stride;
    width = (distance(left, right) + 1) * stride;
    ++stage;
    // The frontend retained nominal element types before canonicalization
    // (IEEE 1801-2018 5.4 / IEEE 1800-2017 7.4 and 11.8).
    isSigned = colon == StringRef::npos && signs[stage];
  }
  return success();
}
upf::ExpressionTokenAttr ControlReference::token(MLIRContext *context) const {
  return upf::ExpressionTokenAttr::get(
      context, upf::ExpressionOpcode::Control, StringAttr::get(context, path),
      {}, {}, isSigned, false, width, sourceWidth, offset);
}
} // namespace talos
