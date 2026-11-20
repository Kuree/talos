//===- DPIDialect.cpp - SystemVerilog DPI-C boundary ----------------------===//

#include "talos/Dialect/DPI/DPIDialect.h"
#include "talos/Dialect/DPI/DPIAttrs.h"
#include "talos/Runtime/Runtime.h"
#include "talos/Runtime/StableHash.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/DialectImplementation.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/TypeSwitch.h"

#include <cstdint>

using namespace mlir;
using namespace talos::dpi;

#include "talos/Dialect/DPI/DPIDialect.cpp.inc"
#include "talos/Dialect/DPI/DPIEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "talos/Dialect/DPI/DPIAttrs.cpp.inc"

void DPIDialect::initialize() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "talos/Dialect/DPI/DPIAttrs.cpp.inc"
      >();
}

LogicalResult DPIDialect::verifyOperationAttribute(Operation *operation,
                                                   NamedAttribute attribute) {
  if (failed(discardable::verify<Import, Export, ExportBridge, ExportBody, Task,
                                 Pure, Context, ImportId, ExportId, CIdentifier,
                                 ScopeId, LexicalScopes, ABISignature,
                                 AggregateLayouts, LogicalInputs, ElidedInputs,
                                 ABIHash, ExportBridgeSymbol, ExportBodySymbol,
                                 HasExports, TransparentExports>(operation,
                                                                 attribute)))
    return failure();
  StringRef name = attribute.getName().strref();
  Attribute value = attribute.getValue();
  auto error = [&]() {
    return operation->emitOpError("attribute '") << name << "' ";
  };
  if (name == ImportId::getNameStr() || name == ExportId::getNameStr()) {
    const APInt &id = cast<IntegerAttr>(value).getValue();
    if (id.isZero() || id.getActiveBits() > 32)
      return error() << "must be a nonzero 32-bit identity";
  } else if (name == LexicalScopes::getNameStr()) {
    // The DPI dialect is independent of the simulation dialect that owns the
    // scope operation. The design verifier checks IDs across the inventory.
    auto id = operation->getAttrOfType<IntegerAttr>("id");
    auto *owner = operation->getParentOp();
    if (operation->getName().getStringRef() != "simulation.scope.decl" || !id ||
        !id.getValue().isZero() || operation->hasAttr("parent") || !owner ||
        owner->getName().getStringRef() != "simulation.design")
      return error() << "belongs on the root scope of a simulation design";
    if (!llvm::all_of(cast<ArrayAttr>(value), llvm::IsaPred<ScopeAttr>))
      return error() << "must contain only #dpi.scope entries";
  } else if (name == ABISignature::getNameStr()) {
    if (!llvm::all_of(cast<ArrayAttr>(value), llvm::IsaPred<ABIAttr>))
      return error() << "must contain only #dpi.abi entries";
  } else if (name == AggregateLayouts::getNameStr()) {
    if (!llvm::all_of(cast<ArrayAttr>(value),
                      llvm::IsaPred<AggregateABIAttr, UnitAttr>))
      return error() << "must contain #dpi.aggregate_abi or unit entries";
    if (ArrayAttr signature = get<ABISignature>(operation);
        signature && signature.size() != cast<ArrayAttr>(value).size())
      return error() << "must have one entry per ABI signature entry";
  } else if (name == LogicalInputs::getNameStr()) {
    if (ArrayAttr signature = get<ABISignature>(operation);
        signature && cast<IntegerAttr>(value).getValue().ugt(signature.size()))
      return error() << "exceeds the ABI signature";
  } else if (name == ElidedInputs::getNameStr()) {
    ArrayRef<int64_t> indices = cast<DenseI64ArrayAttr>(value).asArrayRef();
    for (auto [index, element] : llvm::enumerate(indices))
      if (element < 0 || (index != 0 && indices[index - 1] >= element))
        return error() << "must be strictly increasing formal indices";
  } else if (name == HasExports::getNameStr()) {
    if (!isa<ModuleOp>(operation))
      return error() << "belongs on a module";
  }
  return success();
}

std::optional<int32_t> talos::dpi::getTimeExponent(uint64_t femtoseconds) {
  for (int32_t exponent = -15; exponent <= 2; ++exponent) {
    if (femtoseconds == 1)
      return exponent;
    if (!femtoseconds || femtoseconds % 10)
      break;
    femtoseconds /= 10;
  }
  return std::nullopt;
}

LogicalResult ScopeAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                                uint64_t, StringAttr name, uint64_t unitFs,
                                uint64_t precisionFs) {
  if (name.empty() || name.getValue().contains('\0'))
    return emitError()
           << "DPI scope requires a nonempty name without NUL bytes";
  if (!getTimeExponent(unitFs) || !getTimeExponent(precisionFs))
    return emitError()
           << "DPI time scales must be decimal powers from 1 fs to 100 s";
  if (unitFs < precisionFs)
    return emitError() << "DPI scope time unit is finer than its precision";
  return success();
}

LogicalResult ABIAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                              ABIKind kind, ArgumentDirection, uint32_t width,
                              bool fourState, bool isSigned) {
  if (width == 0)
    return emitError() << "DPI ABI width must be nonzero";
  auto require = [&](uint32_t expectedWidth,
                     bool expectedFourState) -> LogicalResult {
    if (width != expectedWidth)
      return emitError() << "DPI ABI category requires width " << expectedWidth;
    if (fourState != expectedFourState)
      return emitError() << "DPI ABI category has incompatible state kind";
    return success();
  };
  switch (kind) {
  case ABIKind::Bit:
    return require(1, false);
  case ABIKind::Logic:
    // svLogic carries either state kind: two-state data arrives with no X/Z.
    return width == 1 ? success()
                      : emitError() << "DPI ABI category requires width 1";
  case ABIKind::Byte:
    return require(8, false);
  case ABIKind::ShortInt:
    return require(16, false);
  case ABIKind::Int:
    return require(32, false);
  case ABIKind::LongInt:
    return require(64, false);
  case ABIKind::BitVector:
    return fourState
               ? emitError() << "bit-vector DPI ABI category must be two-state"
               : success();
  case ABIKind::LogicVector:
    // C still receives svLogicVecVal when simulator storage is two-state;
    // marshalling supplies zero bval words and projects incoming X/Z to zero.
    return success();
  case ABIKind::String:
  case ABIKind::Chandle:
    if (isSigned)
      return emitError() << "DPI handle category cannot be signed";
    return require(64, false);
  case ABIKind::ShortReal:
    if (isSigned)
      return emitError() << "DPI floating category cannot be signed";
    return require(32, false);
  case ABIKind::Real:
    if (isSigned)
      return emitError() << "DPI floating category cannot be signed";
    return require(64, false);
  case ABIKind::OpenArray:
    if (isSigned)
      return emitError() << "DPI open-array category cannot be signed";
    return success();
  case ABIKind::UnpackedAggregate:
    return success();
  }
  llvm_unreachable("unknown DPI ABI category");
}

LogicalResult OpenArrayABIAttr::verify(
    function_ref<InFlightDiagnostic()> emitError, uint32_t storage,
    ABIKind elementKind, uint32_t elementWidth, uint64_t transportWidth,
    bool transportFourState, bool fourState, uint64_t elementCSize,
    uint32_t elementCAlignment, uint64_t elementStringCount,
    DenseI64ArrayAttr elementLeaves, int64_t packedLeft, int64_t packedRight,
    DenseI64ArrayAttr ranges, DenseI64ArrayAttr sourceRanges,
    DenseI64ArrayAttr shapePlan) {
  if (storage > 2)
    return emitError() << "DPI open-array storage kind is invalid";
  if (elementWidth == 0)
    return emitError() << "DPI open-array element width must be nonzero";
  if (!ranges || (ranges.size() & 1) != 0)
    return emitError() << "DPI open-array ranges must be left/right pairs";
  if (ranges.size() / 2 > UINT32_MAX)
    return emitError() << "DPI open-array dimension count is too large";
  if (!sourceRanges || sourceRanges.size() != ranges.size())
    return emitError() << "DPI open-array source ranges are incomplete";
  if (transportWidth == 0 || transportWidth > UINT32_MAX)
    return emitError()
           << "DPI open-array transport width must fit a nonzero 32-bit width";
  if (storage == 1 && transportWidth != 64)
    return emitError() << "dynamic DPI open-array transport must be a handle";
  if (storage == 1 && transportFourState)
    return emitError() << "dynamic DPI open-array handle cannot be four-state";
  if (storage == 1 && ranges.size() != 2)
    return emitError()
           << "dynamic DPI open-array handle requires one unpacked dimension";
  if (!shapePlan || shapePlan.size() % 8 != 0)
    return emitError()
           << "DPI open-array shape plan must use eight-word records";
  if (storage == 2 &&
      (shapePlan.empty() || shapePlan.size() / 8 != ranges.size() / 2))
    return emitError() << "recursive DPI open-array shape is incomplete";
  if (storage != 2 && !shapePlan.empty())
    return emitError() << "non-recursive DPI open-array has a shape plan";
  if (fourState && elementKind != ABIKind::UnpackedAggregate &&
      elementKind != ABIKind::BitVector && elementKind != ABIKind::Logic &&
      elementKind != ABIKind::LogicVector)
    return emitError() << "DPI open-array element state kind is inconsistent";
  if (elementCSize == 0 || elementCAlignment == 0 ||
      (elementCAlignment & (elementCAlignment - 1)) != 0)
    return emitError() << "DPI open-array element C layout is invalid";
  if (!elementLeaves || elementLeaves.empty() || elementLeaves.size() % 8 != 0)
    return emitError() << "DPI open-array element plan is incomplete";
  if (elementKind == ABIKind::OpenArray)
    return emitError()
           << "DPI open-array elements require a concrete C representation";
  if (failed(AggregateABIAttr::verify(emitError, elementCSize,
                                      elementCAlignment, elementStringCount,
                                      elementLeaves)))
    return failure();
  if (elementStringCount > (UINT64_MAX - elementCSize) / 8)
    return emitError() << "DPI open-array element string layout overflows";
  if (packedLeft < INT32_MIN || packedLeft > INT32_MAX ||
      packedRight < INT32_MIN || packedRight > INT32_MAX)
    return emitError() << "DPI packed range exceeds the standardized C ABI";
  auto verifyBounds = [&](ArrayRef<int64_t> bounds) {
    return llvm::all_of(bounds, [](int64_t bound) {
      return bound >= INT32_MIN && bound <= INT32_MAX;
    });
  };
  if (!verifyBounds(ranges.asArrayRef()) ||
      !verifyBounds(sourceRanges.asArrayRef()))
    return emitError() << "DPI unpacked range exceeds the standardized C ABI";
  if (storage == 0) {
    uint64_t remaining = transportWidth;
    auto extent = [](int64_t left, int64_t right) -> uint64_t {
      return std::max(left, right) - std::min(left, right) + 1;
    };
    for (int64_t i = 0; i < ranges.size(); i += 2) {
      uint64_t size = extent(ranges[i], ranges[i + 1]);
      if (size != extent(sourceRanges[i], sourceRanges[i + 1]) ||
          remaining % size)
        return emitError()
               << "fixed DPI open-array extents disagree with the transport";
      remaining /= size;
    }
    if (remaining != elementWidth)
      return emitError()
             << "fixed DPI open-array elements do not cover the transport";
  }
  for (int64_t index = 0; index != shapePlan.size(); index += 8) {
    ArrayRef<int64_t> record = shapePlan.asArrayRef().slice(index, 8);
    int64_t dimension = index / 8;
    if (record[1] != ranges[2 * dimension] ||
        record[2] != ranges[2 * dimension + 1])
      return emitError()
             << "recursive DPI shape bounds disagree with the descriptor";
    if (record[0] < 0 || record[0] > 2 || record[1] < INT32_MIN ||
        record[1] > INT32_MAX || record[2] < INT32_MIN ||
        record[2] > INT32_MAX || record[3] < 0 || record[5] <= 0 ||
        (record[6] != 0 && record[6] != 1) ||
        record[7] < TALOS_RT_DPI_SHAPE_OPEN ||
        record[7] > TALOS_RT_DPI_SHAPE_SIZED_REVERSE ||
        (record[7] == TALOS_RT_DPI_SHAPE_SIZED_REVERSE && record[0] == 0))
      return emitError() << "DPI open-array shape record " << index / 8
                         << " is malformed";
    if (record[0] == 0 && record[4] == 0)
      return emitError() << "fixed DPI open-array shape has zero stride";
    if (record[0] != 0 && (record[3] != 0 || record[4] != 0))
      return emitError() << "runtime DPI open-array shape has fixed offsets";
  }
  return success();
}

LogicalResult
AggregateABIAttr::verify(function_ref<InFlightDiagnostic()> emitError,
                         uint64_t cSize, uint32_t cAlignment,
                         uint64_t stringCount, DenseI64ArrayAttr leaves) {
  if (cSize == 0 || cAlignment == 0 || (cAlignment & (cAlignment - 1)) != 0)
    return emitError() << "requires nonzero power-of-two C layout";
  ArrayRef<int64_t> words = leaves.asArrayRef();
  if (words.empty() || words.size() % 8 != 0)
    return emitError() << "requires complete eight-word layout records";
  for (size_t index = 0; index != words.size(); index += 8) {
    if (words[index] == 0) {
      if (words[index + 1] < 0 || words[index + 2] < 0 ||
          words[index + 3] < 0 ||
          words[index + 3] > static_cast<int64_t>(ABIKind::Real) ||
          words[index + 4] <= 0 || words[index + 4] > UINT32_MAX ||
          (words[index + 5] != 0 && words[index + 5] != 1) ||
          (words[index + 6] != 0 && words[index + 6] != 1) ||
          words[index + 7] != 0)
        return emitError() << "has malformed leaf record " << index / 8;
    } else if (words[index] == 1) {
      if (words[index + 1] < 0 || words[index + 2] < 0 ||
          words[index + 3] <= 0 || words[index + 4] == 0 ||
          words[index + 5] <= 0 || words[index + 6] != 0 ||
          words[index + 7] <= 0)
        return emitError() << "has malformed repeat record " << index / 8;
    } else {
      return emitError() << "has unknown layout opcode " << words[index];
    }
  }
  if (stringCount > (UINT64_MAX - cSize) / 8)
    return emitError() << "has an unrepresentable string scratch layout";
  return success();
}

uint64_t talos::dpi::getSignatureHash(ArrayAttr signature,
                                      uint64_t logicalInputs) {
  uint64_t hash = TALOS_STABLE_HASH_OFFSET_BASIS;
  hash = talos_stable_hash_append_uint_le(hash, logicalInputs, 8);
  hash = talos_stable_hash_append_uint_le(hash,
                                          signature.size() - logicalInputs, 8);
  for (Attribute attribute : signature) {
    auto abi = cast<ABIAttr>(attribute);
    hash = talos_stable_hash_append_uint_le(
        hash, static_cast<uint32_t>(abi.getKind()), 4);
    hash = talos_stable_hash_append_uint_le(
        hash, static_cast<uint32_t>(abi.getDirection()), 4);
    hash = talos_stable_hash_append_uint_le(hash, abi.getWidth(), 4);
    hash =
        talos_stable_hash_append_uint_le(hash, abi.getFourState() ? 1 : 0, 1);
    hash = talos_stable_hash_append_uint_le(hash, abi.getIsSigned() ? 1 : 0, 1);
  }
  return hash ? hash : 1;
}
