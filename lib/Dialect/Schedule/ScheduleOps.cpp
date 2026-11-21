#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "talos/Dialect/Runtime/RuntimeOps.h"
#include "talos/Dialect/Schedule/ScheduleDialect.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Simulation/SimulationOps.h"
#include "llvm/ADT/StringSwitch.h"
#include "llvm/ADT/TypeSwitch.h"
using namespace mlir;
#define GET_OP_CLASSES
namespace talos::schedule {
// `[16]`, `[%d]` or `[%d + 16]`.
static ParseResult
parseStateOffset(OpAsmParser &parser,
                 std::optional<OpAsmParser::UnresolvedOperand> &dynamicOffset,
                 IntegerAttr &staticOffset) {
  uint64_t offset = 0;
  OpAsmParser::UnresolvedOperand operand;
  OptionalParseResult parsed = parser.parseOptionalOperand(operand);
  if (parsed.has_value()) {
    if (failed(*parsed))
      return failure();
    dynamicOffset = operand;
    if (succeeded(parser.parseOptionalPlus()) && parser.parseInteger(offset))
      return failure();
  } else if (parser.parseInteger(offset)) {
    return failure();
  }
  staticOffset = parser.getBuilder().getI64IntegerAttr(offset);
  return success();
}

static void printStateOffset(OpAsmPrinter &printer, Operation *,
                             Value dynamicOffset, IntegerAttr staticOffset) {
  uint64_t offset = staticOffset.getValue().getZExtValue();
  if (!dynamicOffset) {
    printer << offset;
    return;
  }
  printer << dynamicOffset;
  if (offset)
    printer << " + " << offset;
}

// `value`, or `value + 8` for a byte offset inside the field.
static ParseResult parseAccumulatorField(OpAsmParser &parser,
                                         NBAAccumulatorFieldAttr &field,
                                         IntegerAttr &offset) {
  StringRef keyword;
  SMLoc location = parser.getCurrentLocation();
  if (parser.parseKeyword(&keyword))
    return failure();
  std::optional<NBAAccumulatorField> parsed =
      symbolizeNBAAccumulatorField(keyword);
  if (!parsed)
    return parser.emitError(location, "unknown NBA accumulator field '")
           << keyword << "'";
  field = NBAAccumulatorFieldAttr::get(parser.getContext(), *parsed);
  uint64_t bytes = 0;
  if (succeeded(parser.parseOptionalPlus()) && parser.parseInteger(bytes))
    return failure();
  offset = parser.getBuilder().getI64IntegerAttr(bytes);
  return success();
}

static void printAccumulatorField(OpAsmPrinter &printer, Operation *,
                                  NBAAccumulatorFieldAttr field,
                                  IntegerAttr offset) {
  printer << stringifyNBAAccumulatorField(field.getValue());
  if (uint64_t bytes = offset.getValue().getZExtValue())
    printer << " + " << bytes;
}

} // namespace talos::schedule

#include "talos/Dialect/Schedule/ScheduleOps.cpp.inc"

namespace talos::schedule {
StringRef getStatePlaneGlobalName(StatePlane plane) {
  switch (plane) {
  case StatePlane::Value:
    return "__talos_state_value";
  case StatePlane::Unknown:
    return "__talos_state_unknown";
  case StatePlane::ContributionValue:
    return "__talos_continuous_value";
  case StatePlane::ContributionUnknown:
    return "__talos_continuous_unknown";
  case StatePlane::ContributionMask:
    return "__talos_continuous_mask";
  }
  llvm_unreachable("unknown state plane");
}

std::optional<StatePlane> getStatePlaneOfGlobal(StringRef name) {
  return llvm::StringSwitch<std::optional<StatePlane>>(name)
      .Case("__talos_state_value", StatePlane::Value)
      .Case("__talos_state_unknown", StatePlane::Unknown)
      .Case("__talos_continuous_value", StatePlane::ContributionValue)
      .Case("__talos_continuous_unknown", StatePlane::ContributionUnknown)
      .Case("__talos_continuous_mask", StatePlane::ContributionMask)
      .Default(std::nullopt);
}

static FlatSymbolRefAttr getStatePlaneSymbol(MLIRContext *context,
                                             StatePlane plane) {
  return FlatSymbolRefAttr::get(context, getStatePlaneGlobalName(plane));
}

bool isValidStateWindow(ArrayRef<int64_t> range) {
  return range.size() == 2 && range[0] >= 0 && range[1] >= range[0];
}

bool isValidStateWrittenBits(ArrayRef<int64_t> range) {
  return range.size() == 2 && range[0] >= 0 && range[1] > 0;
}

// A typed memory operation: only functions are lowered to LLVM accesses,
// and what native passes need to know about an access is a property; other
// dialects may still annotate it.
static LogicalResult verifyTypedMemoryOp(Operation *op) {
  if (!op->getParentOfType<FunctionOpInterface>())
    return op->emitOpError("must be in a function");
  for (NamedAttribute attribute : op->getDiscardableAttrs())
    if (attribute.getNameDialect() &&
        attribute.getNameDialect()->getNamespace() ==
            ScheduleDialect::getDialectNamespace())
      return op->emitOpError("carries the schedule fact '")
             << attribute.getName().getValue()
             << "' as a property, not an attribute";
  return success();
}

static LogicalResult verifyStateAccess(Operation *op, StringRef global) {
  if (!getStatePlaneOfGlobal(global))
    return op->emitOpError("names '") << global << "', no native state plane";
  return verifyTypedMemoryOp(op);
}

static LogicalResult verifyRange(Operation *op, StringRef name,
                                 DenseI64ArrayAttr range, bool width) {
  if (range && !(width ? isValidStateWrittenBits(range.asArrayRef())
                       : isValidStateWindow(range.asArrayRef())))
    return op->emitOpError("has a malformed ") << name;
  return success();
}

template <typename AccessOp>
static std::optional<uint64_t> getConstantOffsetOf(AccessOp access) {
  uint64_t base = access.getStaticOffset();
  Value dynamicOffset = access.getDynamicOffset();
  if (!dynamicOffset)
    return base;
  APInt constant;
  if (!matchPattern(dynamicOffset, m_ConstantInt(&constant)) ||
      constant.isNegative() || constant.getActiveBits() > 64 ||
      constant.getZExtValue() > UINT64_MAX - base)
    return std::nullopt;
  return base + constant.getZExtValue();
}

// The plane global resolves where llvm.mlir.addressof of it would.
static LogicalResult verifyStatePlaneUse(Operation *op,
                                         FlatSymbolRefAttr global,
                                         SymbolTableCollection &tables) {
  if (!tables.lookupNearestSymbolFrom<LLVM::GlobalOp>(op, global))
    return op->emitOpError("must reference the llvm.mlir.global of its plane");
  return success();
}

// A constant dynamic offset joins the static one.
template <typename AccessOp>
static bool foldConstantOffset(AccessOp access, Attribute dynamicOffset) {
  auto constant = dyn_cast_or_null<IntegerAttr>(dynamicOffset);
  if (!constant || constant.getValue().isNegative())
    return false;
  uint64_t base = access.getStaticOffset();
  uint64_t added = constant.getValue().getZExtValue();
  if (added > UINT64_MAX - base)
    return false;
  access.setStaticOffset(base + added);
  access.getDynamicOffsetMutable().clear();
  return true;
}

void NativeStateAddressOp::build(OpBuilder &builder, OperationState &state,
                                 StatePlane plane) {
  build(builder, state, LLVM::LLVMPointerType::get(builder.getContext()),
        getStatePlaneSymbol(builder.getContext(), plane));
}
StatePlane NativeStateAddressOp::getPlane() {
  return *getStatePlaneOfGlobal(getGlobal());
}
LogicalResult NativeStateAddressOp::verify() {
  if (failed(verifyStateAccess(*this, getGlobal())))
    return failure();
  // A contribution plane's address is loaded from its binding, no constant.
  if (!isCanonicalStatePlane(getPlane()))
    return emitOpError("names a contribution plane, whose address is no "
                       "constant; use schedule.state.window_address");
  return success();
}
LogicalResult
NativeStateAddressOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyStatePlaneUse(*this, getGlobalAttr(), tables);
}
OpFoldResult NativeStateAddressOp::fold(FoldAdaptor) {
  return StatePlaneAttr::get(getContext(), getPlane());
}

void NativeStateWindowAddressOp::build(OpBuilder &builder,
                                       OperationState &state, StatePlane plane,
                                       Value dynamicOffset,
                                       uint64_t staticOffset) {
  build(builder, state, LLVM::LLVMPointerType::get(builder.getContext()),
        getStatePlaneSymbol(builder.getContext(), plane), dynamicOffset,
        builder.getI64IntegerAttr(staticOffset));
}
std::optional<uint64_t> NativeStateWindowAddressOp::getConstantOffset() {
  return getConstantOffsetOf(*this);
}
StatePlane NativeStateWindowAddressOp::getPlane() {
  return *getStatePlaneOfGlobal(getGlobal());
}
LogicalResult NativeStateWindowAddressOp::verify() {
  return verifyStateAccess(*this, getGlobal());
}
LogicalResult
NativeStateWindowAddressOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyStatePlaneUse(*this, getGlobalAttr(), tables);
}
OpFoldResult NativeStateWindowAddressOp::fold(FoldAdaptor adaptor) {
  return foldConstantOffset(*this, adaptor.getDynamicOffset()) ? getResult()
                                                               : nullptr;
}

void NativeStateLoadOp::build(OpBuilder &builder, OperationState &state,
                              Type type, StatePlane plane, Value dynamicOffset,
                              uint64_t staticOffset, uint64_t alignment) {
  build(builder, state, type, getStatePlaneSymbol(builder.getContext(), plane),
        dynamicOffset, builder.getI64IntegerAttr(staticOffset),
        builder.getI64IntegerAttr(alignment), /*window=*/DenseI64ArrayAttr{},
        /*latch_destination=*/UnitAttr{}, /*owner=*/IntegerAttr{});
}
std::optional<uint64_t> NativeStateLoadOp::getConstantOffset() {
  return getConstantOffsetOf(*this);
}
StatePlane NativeStateLoadOp::getPlane() {
  return *getStatePlaneOfGlobal(getGlobal());
}
LogicalResult NativeStateLoadOp::verify() {
  if (failed(verifyStateAccess(*this, getGlobal())))
    return failure();
  return verifyRange(*this, "window", getWindowAttr(), /*width=*/false);
}
LogicalResult
NativeStateLoadOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyStatePlaneUse(*this, getGlobalAttr(), tables);
}
OpFoldResult NativeStateLoadOp::fold(FoldAdaptor adaptor) {
  return foldConstantOffset(*this, adaptor.getDynamicOffset()) ? getResult()
                                                               : nullptr;
}

void NativeStateStoreOp::build(OpBuilder &builder, OperationState &state,
                               Value value, StatePlane plane,
                               Value dynamicOffset, uint64_t staticOffset,
                               uint64_t alignment) {
  build(builder, state, value,
        getStatePlaneSymbol(builder.getContext(), plane), dynamicOffset,
        builder.getI64IntegerAttr(staticOffset),
        builder.getI64IntegerAttr(alignment), /*window=*/DenseI64ArrayAttr{},
        /*written_bits=*/DenseI64ArrayAttr{}, /*latch_destination=*/UnitAttr{},
        /*summary_reported=*/UnitAttr{}, /*owner=*/IntegerAttr{});
}
std::optional<uint64_t> NativeStateStoreOp::getConstantOffset() {
  return getConstantOffsetOf(*this);
}
StatePlane NativeStateStoreOp::getPlane() {
  return *getStatePlaneOfGlobal(getGlobal());
}
LogicalResult NativeStateStoreOp::verify() {
  if (failed(verifyStateAccess(*this, getGlobal())) ||
      failed(verifyRange(*this, "window", getWindowAttr(), /*width=*/false)))
    return failure();
  return verifyRange(*this, "written_bits", getWrittenBitsAttr(),
                     /*width=*/true);
}
LogicalResult
NativeStateStoreOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyStatePlaneUse(*this, getGlobalAttr(), tables);
}
LogicalResult NativeStateStoreOp::fold(FoldAdaptor adaptor,
                                       SmallVectorImpl<OpFoldResult> &) {
  return success(foldConstantOffset(*this, adaptor.getDynamicOffset()));
}

StringRef getNBAIndexGlobalName(NBAIndex index) {
  switch (index) {
  case NBAIndex::DirtyRoots:
    return "__talos_aot_nba_dirty_roots_v1";
  case NBAIndex::DirtySummary:
    return "__talos_aot_nba_dirty_summary_v1";
  }
  llvm_unreachable("unknown NBA index");
}

std::optional<NBAIndex> getNBAIndexOfGlobal(StringRef name) {
  return llvm::StringSwitch<std::optional<NBAIndex>>(name)
      .Case("__talos_aot_nba_dirty_roots_v1", NBAIndex::DirtyRoots)
      .Case("__talos_aot_nba_dirty_summary_v1", NBAIndex::DirtySummary)
      .Default(std::nullopt);
}

StringRef getReadySetGlobalName(ReadySet set) {
  switch (set) {
  case ReadySet::Ingress:
    return "__talos_aot_model_ingress_v1";
  case ReadySet::HeldWakes:
    return "__talos_eval_nba_held_wakes_v1";
  }
  llvm_unreachable("unknown ready set");
}

std::optional<ReadySet> getReadySetOfGlobal(StringRef name) {
  return llvm::StringSwitch<std::optional<ReadySet>>(name)
      .Case("__talos_aot_model_ingress_v1", ReadySet::Ingress)
      .Case("__talos_eval_nba_held_wakes_v1", ReadySet::HeldWakes)
      .Default(std::nullopt);
}

StringRef getEvalMaskGlobalName(EvalMask mask) {
  switch (mask) {
  case EvalMask::PromotionPending:
    return "__talos_eval_promotion_pending_mask_v1";
  case EvalMask::RoutePromotionPending:
    return "__talos_eval_route_promotion_pending_v1";
  case EvalMask::StepFourStateNBARoots:
    return "__talos_eval_step_four_state_nba_roots_v1";
  case EvalMask::FastNBARoots:
    return "__talos_eval_fast_nba_roots_v1";
  }
  llvm_unreachable("unknown eval mask");
}

std::optional<EvalMask> getEvalMaskOfGlobal(StringRef name) {
  return llvm::StringSwitch<std::optional<EvalMask>>(name)
      .Case("__talos_eval_promotion_pending_mask_v1",
            EvalMask::PromotionPending)
      .Case("__talos_eval_route_promotion_pending_v1",
            EvalMask::RoutePromotionPending)
      .Case("__talos_eval_step_four_state_nba_roots_v1",
            EvalMask::StepFourStateNBARoots)
      .Case("__talos_eval_fast_nba_roots_v1", EvalMask::FastNBARoots)
      .Default(std::nullopt);
}

// A root's own access is to the dirty word that holds its bit, or to the
// summary word that holds its dirty word's bit.
static LogicalResult verifyIndexAccess(Operation *op, StringRef global,
                                       Value dynamicWord, uint64_t staticWord,
                                       std::optional<uint32_t> root,
                                       bool canonicalCapture) {
  std::optional<NBAIndex> index = getNBAIndexOfGlobal(global);
  if (!index)
    return op->emitOpError("names '") << global << "', no NBA readiness index";
  if (failed(verifyTypedMemoryOp(op)))
    return failure();
  if (canonicalCapture && !root)
    return op->emitOpError("marks a canonical capture without its root");
  if (!root || dynamicWord)
    return success();
  uint64_t word =
      *index == NBAIndex::DirtyRoots ? *root / 64 : *root / (64 * 64);
  if (staticWord != word)
    return op->emitOpError("accesses word ")
           << staticWord << ", not the word " << word << " of root " << *root;
  return success();
}

static LogicalResult verifyIndexUse(Operation *op, FlatSymbolRefAttr global,
                                    SymbolTableCollection &tables) {
  if (!tables.lookupNearestSymbolFrom<LLVM::GlobalOp>(op, global))
    return op->emitOpError("must reference the llvm.mlir.global of its index");
  return success();
}

void NativeNBAIndexLoadOp::build(OpBuilder &builder, OperationState &state,
                                 NBAIndex index, Value dynamicWord,
                                 uint64_t staticWord) {
  build(builder, state, builder.getI64Type(),
        FlatSymbolRefAttr::get(builder.getContext(),
                               getNBAIndexGlobalName(index)),
        dynamicWord, builder.getI64IntegerAttr(staticWord),
        /*root=*/IntegerAttr{}, /*canonical_capture=*/UnitAttr{},
        /*owner=*/IntegerAttr{});
}
NBAIndex NativeNBAIndexLoadOp::getIndex() {
  return *getNBAIndexOfGlobal(getGlobal());
}
LogicalResult NativeNBAIndexLoadOp::verify() {
  return verifyIndexAccess(*this, getGlobal(), getDynamicWord(),
                           getStaticWord(), getRoot(), getCanonicalCapture());
}
LogicalResult
NativeNBAIndexLoadOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyIndexUse(*this, getGlobalAttr(), tables);
}

void NativeNBAIndexStoreOp::build(OpBuilder &builder, OperationState &state,
                                  Value value, NBAIndex index,
                                  Value dynamicWord, uint64_t staticWord) {
  build(builder, state, value,
        FlatSymbolRefAttr::get(builder.getContext(),
                               getNBAIndexGlobalName(index)),
        dynamicWord, builder.getI64IntegerAttr(staticWord),
        /*root=*/IntegerAttr{}, /*canonical_capture=*/UnitAttr{},
        /*capture=*/DenseI64ArrayAttr{}, /*owner=*/IntegerAttr{});
}
NBAIndex NativeNBAIndexStoreOp::getIndex() {
  return *getNBAIndexOfGlobal(getGlobal());
}
LogicalResult NativeNBAIndexStoreOp::verify() {
  if (failed(verifyIndexAccess(*this, getGlobal(), getDynamicWord(),
                               getStaticWord(), getRoot(),
                               getCanonicalCapture())))
    return failure();
  if (DenseI64ArrayAttr capture = getCaptureAttr()) {
    if (getIndex() != NBAIndex::DirtyRoots || !getRoot() ||
        getCanonicalCapture())
      return emitOpError("certifies a capture without marking a generated "
                         "capture's dirty root");
    if (capture.size() != 6 || capture[0] != int64_t(*getRoot()))
      return emitOpError("certifies a malformed capture of root ")
             << *getRoot();
  }
  return success();
}
LogicalResult
NativeNBAIndexStoreOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyIndexUse(*this, getGlobalAttr(), tables);
}

LogicalResult NativeNBAStageOp::verify() {
  if (!getOperation()->getParentOfType<FunctionOpInterface>())
    return emitOpError("must be in a function");
  if (getWidth() == 0)
    return emitOpError("stages no bits");
  return success();
}

// A handle-addressed access names a canonical plane; the runtime keeps the
// contribution planes itself.
static LogicalResult verifyHandleAccess(Operation *op, StringRef global,
                                        uint64_t width) {
  if (failed(verifyStateAccess(op, global)))
    return failure();
  if (!isCanonicalStatePlane(*getStatePlaneOfGlobal(global)))
    return op->emitOpError("names a contribution plane, which only the "
                           "runtime accesses through a handle");
  if (width == 0)
    return op->emitOpError("moves no bits");
  return success();
}

void NativeStateLoadHandleOp::build(OpBuilder &builder, OperationState &state,
                                    StatePlane plane, Value handle,
                                    Value buffer, uint64_t stateBits,
                                    uint64_t width) {
  build(builder, state, getStatePlaneGlobalName(plane), handle, buffer,
        stateBits, width);
}
StatePlane NativeStateLoadHandleOp::getPlane() {
  return *getStatePlaneOfGlobal(getGlobal());
}
LogicalResult NativeStateLoadHandleOp::verify() {
  return verifyHandleAccess(*this, getGlobal(), getWidth());
}
LogicalResult
NativeStateLoadHandleOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyStatePlaneUse(*this, getGlobalAttr(), tables);
}

void NativeStateStoreHandleOp::build(OpBuilder &builder, OperationState &state,
                                     Value buffer, StatePlane plane,
                                     Value handle, Value changed,
                                     uint64_t stateBits, uint64_t width,
                                     bool continuous) {
  build(builder, state, buffer, getStatePlaneGlobalName(plane), handle, changed,
        stateBits, width, continuous);
}
StatePlane NativeStateStoreHandleOp::getPlane() {
  return *getStatePlaneOfGlobal(getGlobal());
}
LogicalResult NativeStateStoreHandleOp::verify() {
  return verifyHandleAccess(*this, getGlobal(), getWidth());
}
LogicalResult
NativeStateStoreHandleOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyStatePlaneUse(*this, getGlobalAttr(), tables);
}

LogicalResult NativeStateFrameStoreOp::verify() {
  if (failed(verifyTypedMemoryOp(*this)))
    return failure();
  unsigned width = getValue().getType().getIntOrFloatBitWidth();
  if (width == 0 || width > 64)
    return emitOpError("writes ") << width << " bits, not 1 to 64";
  if (Value unknown = getUnknown()) {
    if (!getFourState())
      return emitOpError("has X/Z bits for a two-state destination");
    if (unknown.getType() != getValue().getType())
      return emitOpError("has X/Z bits of another width than its value");
  }
  return success();
}

LogicalResult NativeStateLoadAutomaticOp::verify() {
  if (failed(verifyTypedMemoryOp(*this)))
    return failure();
  if (getWidth() == 0)
    return emitOpError("moves no bits");
  return success();
}

OpFoldResult NativeHandleGuardOp::fold(FoldAdaptor adaptor) {
  // Fold as `arith.select %valid, %handle, %invalid` does for an
  // invalid-handle constant %invalid of its own.
  if (auto valid = dyn_cast_or_null<IntegerAttr>(adaptor.getValid()))
    return valid.getValue().isOne() ? OpFoldResult(getHandle())
                                    : OpFoldResult(IntegerAttr::get(
                                          getType(), APInt::getAllOnes(64)));
  // A validity that compares the handle itself with the invalid handle
  // decides the result: the handle, or the invalid handle.
  auto compare = getValid().getDefiningOp<arith::CmpIOp>();
  if (!compare || (compare.getPredicate() != arith::CmpIPredicate::ne &&
                   compare.getPredicate() != arith::CmpIPredicate::eq))
    return {};
  Value other;
  if (compare.getLhs() == getHandle())
    other = compare.getRhs();
  else if (compare.getRhs() == getHandle())
    other = compare.getLhs();
  APInt constant;
  if (!other || !matchPattern(other, m_ConstantInt(&constant)) ||
      constant.getBitWidth() != 64 || !constant.isAllOnes())
    return {};
  return compare.getPredicate() == arith::CmpIPredicate::ne
             ? OpFoldResult(getHandle())
             : OpFoldResult(other);
}

uint64_t getNBAAccumulatorFieldBytes(NBAAccumulatorField field) {
  switch (field) {
  case NBAAccumulatorField::Value:
  case NBAAccumulatorField::Unknown:
  case NBAAccumulatorField::WriteMask:
  case NBAAccumulatorField::Transient:
    return 4 * sizeof(uint64_t);
  case NBAAccumulatorField::Valid:
  case NBAAccumulatorField::ExecRegion:
    return sizeof(uint32_t);
  }
  llvm_unreachable("unknown NBA accumulator field");
}

// The accessed bytes lie inside the field.
static LogicalResult verifyAccumulatorAccess(Operation *op, Type type,
                                             NBAAccumulatorField field,
                                             uint64_t offset) {
  if (failed(verifyTypedMemoryOp(op)))
    return failure();
  unsigned width = cast<IntegerType>(type).getWidth();
  if (width % 8)
    return op->emitOpError("accesses a value of ")
           << width << " bits, not whole bytes";
  uint64_t bytes = getNBAAccumulatorFieldBytes(field);
  if (offset > bytes || width / 8 > bytes - offset)
    return op->emitOpError("accesses bytes outside its ")
           << stringifyNBAAccumulatorField(field) << " field";
  return success();
}

void NativeNBAAccumulatorAddressOp::build(OpBuilder &builder,
                                          OperationState &state,
                                          StringRef global) {
  build(builder, state, LLVM::LLVMPointerType::get(builder.getContext()),
        FlatSymbolRefAttr::get(builder.getContext(), global));
}
LogicalResult NativeNBAAccumulatorAddressOp::verify() {
  return verifyTypedMemoryOp(*this);
}
LogicalResult
NativeNBAAccumulatorAddressOp::verifySymbolUses(SymbolTableCollection &tables) {
  if (!tables.lookupNearestSymbolFrom<LLVM::GlobalOp>(*this, getGlobalAttr()))
    return emitOpError("must reference the llvm.mlir.global of its record");
  return success();
}

void NativeNBAAccumulatorLoadOp::build(OpBuilder &builder,
                                       OperationState &state, Type type,
                                       Value record, NBAAccumulatorField field,
                                       uint64_t offset, uint64_t alignment) {
  build(builder, state, type, record,
        NBAAccumulatorFieldAttr::get(builder.getContext(), field),
        builder.getI64IntegerAttr(offset), builder.getI64IntegerAttr(alignment),
        /*pending_root=*/IntegerAttr{},
        /*at_commit=*/UnitAttr{}, /*owner=*/IntegerAttr{});
}
LogicalResult NativeNBAAccumulatorLoadOp::verify() {
  if (failed(
          verifyAccumulatorAccess(*this, getType(), getField(), getOffset())))
    return failure();
  if (getPendingRoot() && getField() != NBAAccumulatorField::Valid)
    return emitOpError("tests a pending capture through a field other than "
                       "valid");
  if (getAtCommit() && getField() != NBAAccumulatorField::WriteMask)
    return emitOpError("reads a field other than write_mask at commit");
  return success();
}

void NativeNBAAccumulatorStoreOp::build(OpBuilder &builder,
                                        OperationState &state, Value value,
                                        Value record, NBAAccumulatorField field,
                                        uint64_t offset, uint64_t alignment) {
  build(builder, state, value, record,
        NBAAccumulatorFieldAttr::get(builder.getContext(), field),
        builder.getI64IntegerAttr(offset), builder.getI64IntegerAttr(alignment),
        /*owner=*/IntegerAttr{});
}
LogicalResult NativeNBAAccumulatorStoreOp::verify() {
  return verifyAccumulatorAccess(*this, getValue().getType(), getField(),
                                 getOffset());
}
} // namespace talos::schedule
namespace talos::schedule {
static LogicalResult verifyNativeUnpackedWord(Operation *op, Type input,
                                              Type result) {
  auto array = dyn_cast<sim::UnpackedArrayType>(input);
  if (!array || !sim::getPackedWidth(array.getElementType()) ||
      !isa<IntegerType, sim::LogicType>(result))
    return op->emitOpError(
        "requires an unpacked array of packed elements and a "
        "packed word result");
  if (auto integer = dyn_cast<IntegerType>(result);
      integer && !integer.isSignless())
    return op->emitOpError("requires a signless integer word");
  auto width = sim::getPackedWidth(result);
  bool logic =
      isa<sim::LogicType>(sim::getPackedScalarType(array.getElementType()));
  auto span = sim::getProvenanceSpan(array);
  if (!width || *width < 2 || *width > 64 || !span || *width > *span ||
      *span > INT64_MAX || logic != isa<sim::LogicType>(result))
    return op->emitOpError(
        "requires a contained native word with the same state domain");
  return success();
}
LogicalResult NativeWordViewOp::verify() {
  return verifyNativeUnpackedWord(*this, getInput().getType().getElementType(),
                                  getResult().getType().getElementType());
}
LogicalResult NativeWordExtractOp::verify() {
  return verifyNativeUnpackedWord(*this, getInput().getType(),
                                  getResult().getType());
}
LogicalResult NativeWordReverseOp::verify() {
  Type type = getInput().getType();
  if (getResult().getType() != type)
    return emitOpError("requires matching operand and result types");
  auto width = sim::getPackedWidth(type);
  if (!isa<IntegerType, sim::LogicType>(type) || !width || *width < 2 ||
      *width > 64)
    return emitOpError("requires a native integer or logic word");
  if (auto integer = dyn_cast<IntegerType>(type);
      integer && !integer.isSignless())
    return emitOpError("requires a signless integer word");
  if (getLaneWidth() < 1 || getLaneWidth() > *width || *width % getLaneWidth())
    return emitOpError("requires a lane width dividing the native word width");
  return success();
}
OpFoldResult NativeWordReverseOp::fold(FoldAdaptor) {
  // Reversing a single lane, or reversing the same lanes twice, keeps every
  // lane in place.
  // Folding may run before verification, so the width is not assumed.
  std::optional<unsigned> width = sim::getPackedWidth(getInput().getType());
  if (width && getLaneWidth() == *width)
    return getInput();
  if (auto inner = getInput().getDefiningOp<NativeWordReverseOp>();
      inner && inner.getLaneWidth() == getLaneWidth())
    return inner.getInput();
  return {};
}
OpFoldResult NativeWordResizeLanesOp::fold(FoldAdaptor) {
  if (getInputLaneWidth() == getResultLaneWidth() &&
      getInput().getType() == getResult().getType())
    return getInput();
  return {};
}
LogicalResult NativeWordResizeLanesOp::verify() {
  auto wordWidth = [](Type type) -> unsigned {
    if (auto integer = dyn_cast<IntegerType>(type))
      return integer.isSignless() ? integer.getWidth() : 0;
    if (auto logic = dyn_cast<sim::LogicType>(type))
      return logic.getWidth();
    return 0;
  };
  unsigned input = wordWidth(getInput().getType());
  unsigned result = wordWidth(getResult().getType());
  unsigned from = getInputLaneWidth(), to = getResultLaneWidth();
  if (input < 2 || input > 64 || result < 2 || result > 64 ||
      isa<sim::LogicType>(getInput().getType()) !=
          isa<sim::LogicType>(getResult().getType()))
    return emitOpError("requires native words with the same state domain");
  if (!from || !to || input % from || result % to || input / from < 2 ||
      input / from != result / to)
    return emitOpError("requires matching counts of complete lanes");
  return success();
}
LogicalResult NativeWordTableOp::verify() {
  auto laneWidth = [](Type type) -> unsigned {
    if (auto integer = dyn_cast<IntegerType>(type))
      return integer.isSignless() ? integer.getWidth() : 0;
    if (auto logic = dyn_cast<sim::LogicType>(type))
      return logic.getWidth();
    return 0;
  };
  unsigned width = laneWidth(getResult().getType());
  if (width < 2 || width > 64)
    return emitOpError("requires a native integer or logic word result");
  unsigned planes = 0;
  for (Value input : getInputs()) {
    if (laneWidth(input.getType()) != width)
      return emitOpError("requires matching native word operand widths");
    planes += isa<sim::LogicType>(input.getType()) ? 2 : 1;
  }
  if (planes > 6 || getValueTable().getBitWidth() != (1u << planes) ||
      getUnknownTable().getBitWidth() != (1u << planes))
    return emitOpError(
        "requires complete truth tables for at most six input planes");
  if (isa<IntegerType>(getResult().getType()) && !getUnknownTable().isZero())
    return emitOpError("integer results cannot have unknown bits");
  return success();
}
void NativeWordRegionOp::getSuccessorRegions(
    RegionBranchPoint point, SmallVectorImpl<RegionSuccessor> &regions) {
  if (point.isParent())
    regions.emplace_back(&getBody());
  else
    regions.emplace_back(getOperation(), getOperation()->getResults());
}

void NativeWordRegionOp::getRegionInvocationBounds(
    ArrayRef<Attribute>, SmallVectorImpl<InvocationBounds> &bounds) {
  bounds.emplace_back(1, 1);
}

MutableOperandRange
NativeWordYieldOp::getMutableSuccessorOperands(RegionSuccessor) {
  return MutableOperandRange(getOperation(), 0, 0);
}

LogicalResult NativeWordRegionOp::verify() {
  if (getWidth() < 2 || getWidth() > 64)
    return emitOpError("requires a native word width between 2 and 64");
  if (getLaneCount() && (getLaneCount() < 2 || getLaneCount() > getWidth() ||
                         getWidth() % getLaneCount()))
    return emitOpError("requires a lane count dividing the maximum word width");
  if (getBody().empty() || getBody().front().getNumArguments())
    return emitOpError("requires a nonempty CFG without entry arguments");
  for (Block &block : getBody()) {
    for (Operation &op : block) {
      if (op.getNumRegions())
        return emitOpError("does not permit nested regions");
      if (isa<CallOpInterface>(op))
        return emitOpError("does not permit calls");
      if (auto store = dyn_cast<sim::SimRefStoreOp>(op)) {
        auto width = sim::getPackedWidth(store.getValue().getType());
        if (!width || *width < 2 || *width > getWidth() ||
            (getLaneCount() ? *width % getLaneCount() != 0
                            : *width != getWidth()))
          return emitOpError("requires native-width packed stores");
      } else if (!isa<sim::SimRefLoadOp>(&op) && !isMemoryEffectFree(&op)) {
        return emitOpError(
            "permits only packed state accesses and pure computation");
      }
    }
    Operation *end = block.getTerminator();
    if (!isa<NativeWordYieldOp>(end) && !isa<BranchOpInterface>(end))
      return emitOpError("requires CFG branches or word.yield");
  }
  return success();
}
static LogicalResult verifyTransferABI(Operation *op, Type signature,
                                       uint32_t source, uint32_t destination,
                                       ArrayRef<int64_t> offsets) {
  auto type = dyn_cast<FunctionType>(signature);
  if (!type || type.getNumResults() || type.getNumInputs() < 3 ||
      !isa<sim::ContextType>(type.getInput(0)) ||
      offsets.size() != type.getNumInputs() || offsets.front() != -1)
    return op->emitOpError("requires a context and canonical storage captures");
  if (source == 0 || destination == 0 || source >= type.getNumInputs() ||
      destination >= type.getNumInputs() ||
      type.getInput(source) != type.getInput(destination))
    return op->emitOpError("requires matching source and destination captures");
  llvm::DenseSet<int64_t> occupied;
  for (unsigned index = 1; index < type.getNumInputs(); ++index) {
    auto reference = dyn_cast<sim::RefType>(type.getInput(index));
    if (!reference || !sim::getPackedWidth(reference.getElementType()) ||
        offsets[index] < 0 || offsets[index] % 8 != 0 ||
        !occupied.insert(offsets[index]).second)
      return op->emitOpError("requires distinct aligned storage capture slots");
  }
  return success();
}
LogicalResult TransferKernelOp::verify() {
  return verifyTransferABI(*this, getSignature(), getSource(), getDestination(),
                           getCaptureOffsets());
}
LogicalResult TransferActivationOp::verify() {
  return verifyTransferABI(*this, getSignature(), getSource(), getDestination(),
                           getCaptureOffsets());
}
LogicalResult
TransferActivationOp::verifySymbolUses(SymbolTableCollection &symbols) {
  if (auto name = getKernelAttr()) {
    auto kernel =
        symbols.lookupNearestSymbolFrom<TransferKernelOp>(*this, name);
    if (!kernel || kernel.getSignature() != getSignature() ||
        kernel.getSource() != getSource() ||
        kernel.getDestination() != getDestination() ||
        kernel.getCaptureOffsets() != getCaptureOffsets())
      return emitOpError(
          "requires a transfer kernel with the same capture ABI");
  }
  if (!symbols.lookupNearestSymbolFrom<sim::SimFuncOp>(*this, getActorAttr()))
    return emitOpError("requires an original simulation process actor");
  return success();
}
LogicalResult NativeKnownValueOp::verify() {
  if (!sim::hasFixedBitValue(getInput().getType()))
    return emitOpError("requires a fixed native bit value");
  return success();
}
LogicalResult NativeKnownRootsOp::verify() {
  if (getReferences().empty())
    return emitOpError("requires one or more storage roots");
  return success();
}
namespace {
/// An integer, a conversion from integer bits, and a logic constant without
/// X or Z have a known unknown plane, so the predicate is a constant.
struct FoldKnownValue final : OpRewritePattern<NativeKnownValueOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(NativeKnownValueOp op,
                                PatternRewriter &rewriter) const override {
    Value input = op.getInput();
    std::optional<bool> known;
    if (isa<IntegerType>(input.getType()) ||
        input.getDefiningOp<sim::SimLogicFromBitsOp>())
      known = true;
    else if (auto constant = input.getDefiningOp<sim::SimLogicConstantOp>())
      known = constant.getUnknown().isZero();
    if (!known)
      return failure();
    rewriter.replaceOpWithNewOp<arith::ConstantOp>(
        op, rewriter.getBoolAttr(*known));
    return success();
  }
};
} // namespace
void NativeKnownValueOp::getCanonicalizationPatterns(RewritePatternSet &results,
                                                     MLIRContext *context) {
  results.add<FoldKnownValue>(context);
}
LogicalResult NativeReadyRegionOp::verify() {
  if (getBody().empty() || getBody().front().getNumArguments())
    return emitOpError("requires a nonempty CFG without entry arguments");
  for (Block &block : getBody()) {
    for (Operation &op : block)
      if (op.getNumRegions())
        return emitOpError("does not permit nested regions");
    Operation *end = block.getTerminator();
    if (!isa<NativeReadyYieldOp>(end) &&
        (!isa<BranchOpInterface>(end) || !isMemoryEffectFree(end)))
      return emitOpError("requires non-suspending branches or ready.yield");
  }
  return success();
}
LogicalResult NativeReadyYieldOp::verify() {
  auto region = cast<NativeReadyRegionOp>((*this)->getParentOp());
  if (getOperandTypes() != region.getResultTypes())
    return emitOpError("operands must match the ready.region results");
  return success();
}
LogicalResult NativeNBABatchOp::verify() {
  if (getBody().empty() || getBody().front().getNumArguments())
    return emitOpError("requires one block without arguments");
  Block &body = getBody().front();
  if (body.empty() || !isa<NativeNBAYieldOp>(body.back()))
    return emitOpError("requires an nba.yield terminator");
  int64_t previous = -1;
  for (Operation &operation : body.without_terminator()) {
    auto commit = dyn_cast<NativeNBACommitOp>(operation);
    if (!commit)
      return emitOpError("body permits only nba.commit actions");
    if (static_cast<int64_t>(commit.getRoot()) <= previous)
      return emitOpError("requires distinct roots in increasing order");
    previous = commit.getRoot();
    if (bool(getLayoutAttr()) != bool(commit.getLayoutAttr()))
      return emitOpError("requires layouts on both batch and every commit");
  }
  if (previous == -1)
    return emitOpError("requires at least one commit");
  if (auto layout = getLayoutAttr())
    if (!layout.getBitCount() || !layout.getRootCount() ||
        uint64_t(previous) >= layout.getRootCount())
      return emitOpError("requires a nonempty layout covering every root");
  return success();
}
LogicalResult NativeNBACommitOp::verify() {
  if (getRootAttr().getValue().isNegative() || getRoot() >= UINT32_MAX)
    return emitOpError("root must be between 0 and UINT32_MAX - 1");
  if (auto layout = getLayoutAttr()) {
    auto batch = (*this)->getParentOfType<NativeNBABatchOp>();
    auto parent = batch ? batch.getLayoutAttr() : NBABatchLayoutAttr{};
    if (!parent || !layout.getWidth() ||
        layout.getOffset() > parent.getBitCount() ||
        layout.getWidth() > parent.getBitCount() - layout.getOffset())
      return emitOpError("commit range must lie within the batch state layout");
    if ((!layout.getAccumulator() && layout.getSlots().empty()) ||
        (layout.getAccumulator() && layout.getWidth() > 256))
      return emitOpError(
          "requires slots or an accumulator no wider than 256 bits");
    for (auto attr : layout.getSlots()) {
      auto slot = dyn_cast<NBASlotLayoutAttr>(attr);
      if (!slot || !slot.getWidth() || slot.getWidth() > 64)
        return emitOpError("requires fixed slots between 1 and 64 bits");
      if (auto offset = slot.getConstantOffset()) {
        const APInt &value = offset.getValue();
        if (value.isNegative() || value.getActiveBits() > 64 ||
            value.getZExtValue() > layout.getWidth() ||
            slot.getWidth() > layout.getWidth() - value.getZExtValue())
          return emitOpError("constant slot target must lie within its root");
      }
    }
    for (auto attr : layout.getConsumers()) {
      auto consumer = dyn_cast<NBAConsumerAttr>(attr);
      if (!consumer || !consumer.getWidth() ||
          consumer.getLow() >= layout.getWidth() ||
          consumer.getWidth() > layout.getWidth() - consumer.getLow() ||
          consumer.getBit() >= parent.getCapacity())
        return emitOpError("requires consumers within root and ready capacity");
    }
  }
  return success();
}
LogicalResult NativeTransitionOp::verify() {
  if (getStaticStateAttr().getValue().isNegative() ||
      getStaticState() > UINT32_MAX)
    return emitOpError(
        "static state must fit an unsigned 32-bit root identity");
  if (getWidth() < 1 || getWidth() > 64)
    return emitOpError("transition width must be between 1 and 64");
  if (auto owner = getSourceOwnerAttr()) {
    auto code = owner.getCodeUnit();
    auto continuation = owner.getContinuation();
    if (!code || !continuation || code.getValue().getBitWidth() > 64 ||
        continuation.getValue().getBitWidth() > 64 ||
        continuation.getUInt() > UINT32_MAX)
      return emitOpError("requires a canonical code-unit/continuation owner");
  }
  return success();
}
// A ready action names a generated eval ready set and, unless it merges a
// whole bitmap, one of its leaves within capacity.
static LogicalResult verifyReadyAction(Operation *op, StringRef set,
                                       uint64_t capacity,
                                       std::optional<IntegerAttr> word) {
  if (!getReadySetOfGlobal(set))
    return op->emitOpError("names '") << set << "', no generated ready set";
  if (capacity < 1 || capacity > UINT32_MAX)
    return op->emitOpError("ready capacity must be between 1 and UINT32_MAX");
  if (word && ((*word).getValue().isNegative() ||
               (*word).getValue().getZExtValue() >= (capacity + 63) / 64))
    return op->emitOpError("ready word must name a leaf within capacity");
  return success();
}

// The set's global holds whole 64-bit words, at least the leaves an action
// accesses. Producers may freeze different capacities for one set (a ranked
// group's is at least 64), so only those leaves are required.
static LogicalResult verifyReadySetUse(Operation *op, FlatSymbolRefAttr set,
                                       uint64_t words,
                                       SymbolTableCollection &tables) {
  auto global = tables.lookupNearestSymbolFrom<LLVM::GlobalOp>(op, set);
  auto array =
      global ? dyn_cast<LLVM::LLVMArrayType>(global.getType()) : nullptr;
  if (!array || !array.getElementType().isInteger(64))
    return op->emitOpError("must reference the llvm.mlir.global of its ready "
                           "set, an array of i64 words");
  if (array.getNumElements() < words)
    return op->emitOpError("accesses word ")
           << words - 1 << " of a ready set of " << array.getNumElements()
           << " words";
  return success();
}

// Read and write the named set, and inspect or change the pending
// activations it holds.
static void
addReadySetEffects(FlatSymbolRefAttr set, bool writes,
                   SmallVectorImpl<MemoryEffects::EffectInstance> &effects) {
  effects.emplace_back(MemoryEffects::Read::get(), set,
                       SideEffects::DefaultResource::get());
  if (writes)
    effects.emplace_back(MemoryEffects::Write::get(), set,
                         SideEffects::DefaultResource::get());
  effects.emplace_back(MemoryEffects::Read::get(),
                       sim::SchedulerResource::get());
  if (writes)
    effects.emplace_back(MemoryEffects::Write::get(),
                         sim::SchedulerResource::get());
}

void NativeReadyUpdateOp::build(OpBuilder &builder, OperationState &state,
                                ReadySet set, Value mask, uint64_t capacity,
                                uint64_t word, bool consume) {
  build(builder, state, getReadySetGlobalName(set), mask, capacity, word,
        consume);
}
ReadySet NativeReadyUpdateOp::getReadySet() {
  return *getReadySetOfGlobal(getSet());
}
LogicalResult NativeReadyUpdateOp::verify() {
  return verifyReadyAction(*this, getSet(), getCapacity(), getWordAttr());
}
LogicalResult
NativeReadyUpdateOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyReadySetUse(*this, getSetAttr(), getWord() + 1, tables);
}
void NativeReadyUpdateOp::getEffects(
    SmallVectorImpl<MemoryEffects::EffectInstance> &effects) {
  addReadySetEffects(getSetAttr(), /*writes=*/true, effects);
}

ReadySet NativeReadyCommitOp::getReadySet() {
  return *getReadySetOfGlobal(getSet());
}
LogicalResult NativeReadyCommitOp::verify() {
  return verifyReadyAction(*this, getSet(), getCapacity(), getWordAttr());
}
LogicalResult
NativeReadyCommitOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyReadySetUse(*this, getSetAttr(), getWord() + 1, tables);
}
void NativeReadyCommitOp::getEffects(
    SmallVectorImpl<MemoryEffects::EffectInstance> &effects) {
  addReadySetEffects(getSetAttr(), /*writes=*/true, effects);
}

void NativeReadyReadOp::build(OpBuilder &builder, OperationState &state,
                              ReadySet set, uint64_t capacity, uint64_t word) {
  build(builder, state, builder.getI64Type(), getReadySetGlobalName(set),
        capacity, word);
}
ReadySet NativeReadyReadOp::getReadySet() {
  return *getReadySetOfGlobal(getSet());
}
LogicalResult NativeReadyReadOp::verify() {
  return verifyReadyAction(*this, getSet(), getCapacity(), getWordAttr());
}
LogicalResult
NativeReadyReadOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyReadySetUse(*this, getSetAttr(), getWord() + 1, tables);
}
void NativeReadyReadOp::getEffects(
    SmallVectorImpl<MemoryEffects::EffectInstance> &effects) {
  addReadySetEffects(getSetAttr(), /*writes=*/false, effects);
}

void NativeReadyMergeOp::build(OpBuilder &builder, OperationState &state,
                               ReadySet set, Value source, uint64_t capacity) {
  build(builder, state, getReadySetGlobalName(set), source, capacity);
}
ReadySet NativeReadyMergeOp::getReadySet() {
  return *getReadySetOfGlobal(getSet());
}
LogicalResult NativeReadyMergeOp::verify() {
  return verifyReadyAction(*this, getSet(), getCapacity(), std::nullopt);
}
LogicalResult
NativeReadyMergeOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyReadySetUse(*this, getSetAttr(), (getCapacity() + 63) / 64,
                           tables);
}
void NativeReadyMergeOp::getEffects(
    SmallVectorImpl<MemoryEffects::EffectInstance> &effects) {
  effects.emplace_back(MemoryEffects::Read::get(),
                       &getOperation()->getOpOperand(0),
                       SideEffects::DefaultResource::get());
  addReadySetEffects(getSetAttr(), /*writes=*/true, effects);
}

// A word access names a generated ready set; its static word lies in the
// set's global (a dynamic word only moves past it).
static LogicalResult verifyReadyWord(Operation *op, StringRef set) {
  if (!getReadySetOfGlobal(set))
    return op->emitOpError("names '") << set << "', no generated ready set";
  return verifyTypedMemoryOp(op);
}

void NativeReadyWordLoadOp::build(OpBuilder &builder, OperationState &state,
                                  ReadySet set, Value dynamicWord,
                                  uint64_t staticWord) {
  build(
      builder, state, builder.getI64Type(),
      FlatSymbolRefAttr::get(builder.getContext(), getReadySetGlobalName(set)),
      dynamicWord, builder.getI64IntegerAttr(staticWord),
      /*activation_entry=*/IntegerAttr{}, /*owner=*/IntegerAttr{});
}
ReadySet NativeReadyWordLoadOp::getReadySet() {
  return *getReadySetOfGlobal(getSet());
}
LogicalResult NativeReadyWordLoadOp::verify() {
  return verifyReadyWord(*this, getSet());
}
LogicalResult
NativeReadyWordLoadOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyReadySetUse(*this, getSetAttr(), getStaticWord() + 1, tables);
}

void NativeReadyWordStoreOp::build(OpBuilder &builder, OperationState &state,
                                   Value value, ReadySet set, Value dynamicWord,
                                   uint64_t staticWord) {
  build(
      builder, state, value,
      FlatSymbolRefAttr::get(builder.getContext(), getReadySetGlobalName(set)),
      dynamicWord, builder.getI64IntegerAttr(staticWord),
      /*owner=*/IntegerAttr{});
}
ReadySet NativeReadyWordStoreOp::getReadySet() {
  return *getReadySetOfGlobal(getSet());
}
LogicalResult NativeReadyWordStoreOp::verify() {
  return verifyReadyWord(*this, getSet());
}
LogicalResult
NativeReadyWordStoreOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyReadySetUse(*this, getSetAttr(), getStaticWord() + 1, tables);
}

// A mask word access names a generated eval mask; its static word lies in
// the mask's global, an array of whole 64-bit words (a dynamic word only
// moves past it).
static LogicalResult verifyMaskWord(Operation *op, StringRef mask) {
  if (!getEvalMaskOfGlobal(mask))
    return op->emitOpError("names '") << mask << "', no generated eval mask";
  return verifyTypedMemoryOp(op);
}
static LogicalResult verifyMaskUse(Operation *op, FlatSymbolRefAttr mask,
                                   uint64_t staticWord,
                                   SymbolTableCollection &tables) {
  auto global = tables.lookupNearestSymbolFrom<LLVM::GlobalOp>(op, mask);
  auto array =
      global ? dyn_cast<LLVM::LLVMArrayType>(global.getType()) : nullptr;
  if (!array || !array.getElementType().isInteger(64))
    return op->emitOpError("must reference the llvm.mlir.global of its mask, "
                           "an array of i64 words");
  if (staticWord >= array.getNumElements())
    return op->emitOpError("accesses word ")
           << staticWord << " of a mask of " << array.getNumElements()
           << " words";
  return success();
}

void NativeMaskLoadOp::build(OpBuilder &builder, OperationState &state,
                             EvalMask mask, Value dynamicWord,
                             uint64_t staticWord) {
  build(
      builder, state, builder.getI64Type(),
      FlatSymbolRefAttr::get(builder.getContext(), getEvalMaskGlobalName(mask)),
      dynamicWord, builder.getI64IntegerAttr(staticWord),
      /*owner=*/IntegerAttr{});
}
EvalMask NativeMaskLoadOp::getEvalMask() {
  return *getEvalMaskOfGlobal(getMask());
}
LogicalResult NativeMaskLoadOp::verify() {
  return verifyMaskWord(*this, getMask());
}
LogicalResult
NativeMaskLoadOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyMaskUse(*this, getMaskAttr(), getStaticWord(), tables);
}

void NativeMaskStoreOp::build(OpBuilder &builder, OperationState &state,
                              Value value, EvalMask mask, Value dynamicWord,
                              uint64_t staticWord) {
  build(
      builder, state, value,
      FlatSymbolRefAttr::get(builder.getContext(), getEvalMaskGlobalName(mask)),
      dynamicWord, builder.getI64IntegerAttr(staticWord),
      /*owner=*/IntegerAttr{});
}
EvalMask NativeMaskStoreOp::getEvalMask() {
  return *getEvalMaskOfGlobal(getMask());
}
LogicalResult NativeMaskStoreOp::verify() {
  return verifyMaskWord(*this, getMask());
}
LogicalResult
NativeMaskStoreOp::verifySymbolUses(SymbolTableCollection &tables) {
  return verifyMaskUse(*this, getMaskAttr(), getStaticWord(), tables);
}
SuccessorOperands NativeSuspendDelayOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendDelayOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
SuccessorOperands NativeSuspendChangeOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendChangeOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
SuccessorOperands NativeSuspendEdgeOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendEdgeOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
SuccessorOperands NativeSuspendEdgeIffOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendEdgeIffOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
SuccessorOperands NativeSuspendLevelOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendLevelOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
SuccessorOperands NativeSuspendAnyOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendAnyOp::verify() {
  if (getEdges().empty() || getEdges().size() > getNumOperands())
    return emitOpError("edge inventory exceeds the watched operand prefix");
  for (int32_t edge : getEdges())
    if (!sim::symbolizeEdgeKind(edge))
      return emitOpError("invalid edge kind");
  for (Value handle : getWatched())
    if (!handle.getType().isInteger(64))
      return emitOpError("watched handles must be i64");
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
Operation::operand_range NativeSuspendAnyOp::getWatched() {
  return getValues().take_front(
      std::min<size_t>(getEdges().size(), getNumOperands()));
}
Operation::operand_range NativeSuspendAnyOp::getContinuationOperands() {
  return getValues().drop_front(
      std::min<size_t>(getEdges().size(), getNumOperands()));
}
MutableOperandRange NativeSuspendAnyOp::getContinuationOperandsMutable() {
  unsigned watchedCount = std::min<size_t>(getEdges().size(), getNumOperands());
  return MutableOperandRange(getOperation(), watchedCount,
                             getNumOperands() - watchedCount);
}
SuccessorOperands
NativeSuspendClockSetOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendClockSetOp::verify() {
  if (getEdges().empty() || getEdges().size() > 64 ||
      getEdges().size() > getNumOperands() ||
      getConditionCountAttr().getValue().isNegative() ||
      getConditionCount() > getNumOperands() - getEdges().size() ||
      getConditionIndices().size() != getEdges().size())
    return emitOpError("invalid clock and condition inventory");
  for (int32_t index : getConditionIndices())
    if (index < -1 ||
        (index >= 0 && static_cast<uint32_t>(index) >= getConditionCount()))
      return emitOpError("condition index exceeds the condition inventory");
  for (Value handle :
       getValues().take_front(getEdges().size() + getConditionCount()))
    if (!handle.getType().isInteger(64))
      return emitOpError("clock handles must be i64");
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
Operation::operand_range NativeSuspendClockSetOp::getPrimaries() {
  size_t count = std::min<size_t>(getEdges().size(), getNumOperands());
  return getValues().take_front(count);
}
Operation::operand_range NativeSuspendClockSetOp::getConditions() {
  size_t primaryCount = std::min<size_t>(getEdges().size(), getNumOperands());
  size_t count = getConditionCountAttr().getValue().isNegative()
                     ? 0
                     : std::min<uint64_t>(getConditionCount(),
                                          getNumOperands() - primaryCount);
  return getValues().slice(primaryCount, count);
}
Operation::operand_range NativeSuspendClockSetOp::getContinuationOperands() {
  size_t primaryCount = std::min<size_t>(getEdges().size(), getNumOperands());
  size_t conditionCount =
      getConditionCountAttr().getValue().isNegative()
          ? 0
          : std::min<uint64_t>(getConditionCount(),
                               getNumOperands() - primaryCount);
  return getValues().drop_front(primaryCount + conditionCount);
}
MutableOperandRange NativeSuspendClockSetOp::getContinuationOperandsMutable() {
  size_t primaryCount = std::min<size_t>(getEdges().size(), getNumOperands());
  size_t conditionCount =
      getConditionCountAttr().getValue().isNegative()
          ? 0
          : std::min<uint64_t>(getConditionCount(),
                               getNumOperands() - primaryCount);
  size_t begin = primaryCount + conditionCount;
  return MutableOperandRange(getOperation(), begin, getNumOperands() - begin);
}
SuccessorOperands NativeSuspendEventOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendEventOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
SuccessorOperands
NativeSuspendEventOrderOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendEventOrderOp::verify() {
  if (getEventCountAttr().getValue().isNegative() || getEventCount() == 0 ||
      getEventCount() > getNumOperands())
    return emitOpError("event count exceeds the operand inventory");
  for (Value handle : getEvents())
    if (!handle.getType().isInteger(64))
      return emitOpError("event handles must be i64");
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
Operation::operand_range NativeSuspendEventOrderOp::getEvents() {
  return getValues().take_front(
      std::min<size_t>(getEventCount(), getNumOperands()));
}
Operation::operand_range NativeSuspendEventOrderOp::getContinuationOperands() {
  return getValues().drop_front(
      std::min<size_t>(getEventCount(), getNumOperands()));
}
MutableOperandRange
NativeSuspendEventOrderOp::getContinuationOperandsMutable() {
  unsigned eventCount = std::min<size_t>(getEventCount(), getNumOperands());
  return MutableOperandRange(getOperation(), eventCount,
                             getNumOperands() - eventCount);
}
SuccessorOperands NativeSuspendMailboxOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendMailboxOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
SuccessorOperands
NativeSuspendSemaphoreOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendSemaphoreOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
SuccessorOperands NativeSuspendObserveOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendObserveOp::verify() {
  auto planes = get<Field::NativeInitialPlaneCounts>(*this);
  auto conditionBegin = get<Field::NativeConditionOperandBegin>(*this);
  auto continuationBegin = get<Field::NativeContinuationOperandBegin>(*this);
  if (getEdges().empty() || !planes ||
      static_cast<size_t>(planes.size()) != getEdges().size() ||
      !conditionBegin || !continuationBegin ||
      getConditionCountAttr().getValue().isNegative() ||
      getConditionIndices().size() != getEdges().size())
    return emitOpError("requires a complete physical observer inventory");
  uint64_t expected = getEdges().size();
  for (int32_t count : planes.asArrayRef()) {
    if (count < 1 || count > 2)
      return emitOpError("observer initial value requires one or two planes");
    expected += count;
  }
  if (conditionBegin.getValue().isNegative() ||
      continuationBegin.getValue().isNegative() ||
      conditionBegin.getValue().getZExtValue() != expected ||
      continuationBegin.getValue().getZExtValue() !=
          expected + getConditionCount() ||
      expected + getConditionCount() > getNumOperands())
    return emitOpError(
        "observer segments do not match the physical operand inventory");
  for (int32_t index : getConditionIndices())
    if (index < -1 ||
        (index >= 0 && static_cast<uint32_t>(index) >= getConditionCount()))
      return emitOpError("condition index exceeds the observer inventory");
  for (Value value : getPrimaries())
    if (!value.getDefiningOp<NativeObserverOp>())
      return emitOpError("primary must be a schedule observer");
  for (Value value : getConditions())
    if (!value.getDefiningOp<NativeObserverOp>())
      return emitOpError("condition must be a schedule observer");
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
Operation::operand_range NativeSuspendObserveOp::getPrimaries() {
  size_t count = std::min<size_t>(getEdges().size(), getNumOperands());
  return getValues().take_front(count);
}
Operation::operand_range NativeSuspendObserveOp::getInitialValues() {
  size_t primaryCount = std::min<size_t>(getEdges().size(), getNumOperands());
  auto end = get<Field::NativeConditionOperandBegin>(*this);
  size_t limit =
      end ? std::min<uint64_t>(end.getValue().getZExtValue(), getNumOperands())
          : primaryCount;
  return getValues().slice(primaryCount,
                           limit >= primaryCount ? limit - primaryCount : 0);
}
namespace {
size_t observerSegmentBegin(Operation *operation, Field field) {
  auto value = get<IntegerAttr>(operation, field);
  return value && !value.getValue().isNegative()
             ? std::min<uint64_t>(value.getValue().getZExtValue(),
                                  operation->getNumOperands())
             : 0;
}
} // namespace
Operation::operand_range NativeSuspendObserveOp::getConditions() {
  size_t begin =
      observerSegmentBegin(*this, Field::NativeConditionOperandBegin);
  size_t count =
      getConditionCountAttr().getValue().isNegative()
          ? 0
          : std::min<uint64_t>(getConditionCount(), getNumOperands() - begin);
  return getValues().slice(begin, count);
}
Operation::operand_range NativeSuspendObserveOp::getContinuationOperands() {
  return getValues().drop_front(
      observerSegmentBegin(*this, Field::NativeContinuationOperandBegin));
}
MutableOperandRange NativeSuspendObserveOp::getContinuationOperandsMutable() {
  size_t begin =
      observerSegmentBegin(*this, Field::NativeContinuationOperandBegin);
  return MutableOperandRange(getOperation(), begin, getNumOperands() - begin);
}
SuccessorOperands NativeSuspendForeverOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendForeverOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
SuccessorOperands NativeSuspendAwaitOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendAwaitOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
SuccessorOperands NativeSuspendJoinOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendJoinOp::verify() {
  if (getProcessCountAttr().getValue().isNegative() ||
      getProcessCount() > getNumOperands())
    return emitOpError("process count exceeds the operand inventory");
  for (Value handle : getProcesses())
    if (!handle.getType().isInteger(64))
      return emitOpError("process handles must be i64");
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
Operation::operand_range NativeSuspendJoinOp::getProcesses() {
  size_t count = getProcessCountAttr().getValue().isNegative()
                     ? 0
                     : std::min<uint64_t>(getProcessCount(), getNumOperands());
  return getValues().take_front(count);
}
Operation::operand_range NativeSuspendJoinOp::getContinuationOperands() {
  size_t count = getProcessCountAttr().getValue().isNegative()
                     ? 0
                     : std::min<uint64_t>(getProcessCount(), getNumOperands());
  return getValues().drop_front(count);
}
MutableOperandRange NativeSuspendJoinOp::getContinuationOperandsMutable() {
  unsigned count =
      getProcessCountAttr().getValue().isNegative()
          ? 0
          : std::min<uint64_t>(getProcessCount(), getNumOperands());
  return MutableOperandRange(getOperation(), count, getNumOperands() - count);
}
SuccessorOperands
NativeSuspendChildrenOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeSuspendChildrenOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion())
    return emitOpError("continuation must remain in the same native region");
  if (getContinuationOperands().getTypes() !=
      getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation arguments must match their physical operand types");
  return success();
}
LogicalResult NativeSpawnOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto callee = symbols.lookupNearestSymbolFrom<FunctionOpInterface>(
      *this, getCalleeAttr());
  if (!callee)
    return emitOpError("requires a defined native process callee");
  if (getOperandTypes() != callee.getArgumentTypes())
    return emitOpError("captures must match the prepared callee signature");
  return success();
}
LogicalResult NativeSpawnOp::verify() { return success(); }
} // namespace talos::schedule

namespace talos::schedule {
SuccessorOperands NativeProcessControlOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeProcessControlOp::verify() {
  if (getContinuation()->getParent() != (*this)->getParentRegion() ||
      getContinuationOperands().getTypes() !=
          getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation must match the native region and operand types");
  return success();
}
SuccessorOperands
NativeControlBoundaryOp::getSuccessorOperands(unsigned index) {
  assert(index < 2 && "control boundary has two successors");
  return index == 0 ? SuccessorOperands(getResumeOperandsMutable())
                    : SuccessorOperands(MutableOperandRange(
                          getOperation(), getNumOperands(), 0));
}
LogicalResult NativeControlBoundaryOp::verify() {
  auto function = getOperation()->getParentOfType<sim::SimFuncOp>();
  if (!function)
    return emitOpError("must be nested in simulation.func");
  if (function.getEntryKind() == sim::EntryKind::Function ||
      function.getEntryKind() == sim::EntryKind::Observer)
    return emitOpError("requires a suspendable process entry");
  if (getResume() == getBody())
    return emitOpError("resume and body successors must be distinct");
  if (getResume()->getParent() != &function.getBody() ||
      getBody()->getParent() != &function.getBody())
    return emitOpError("successors must be blocks in the same function");
  if (getResume() == &function.getBody().front() ||
      getBody() == &function.getBody().front())
    return emitOpError("successors must not target the entry block");
  if (getResumeOperands().getTypes() != getResume()->getArgumentTypes())
    return emitOpError(
        "resume operand types must match resume block arguments");
  if (!getBody()->getArguments().empty())
    return emitOpError("body successor must not have block arguments");
  return success();
}
SuccessorOperands NativeTaskCallOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeTaskCallOp::verify() {
  if (getArgumentCountAttr().getValue().isNegative() ||
      getArgumentCount() > getValues().size())
    return emitOpError("argument count exceeds the native operand inventory");
  if (getContinuation()->getParent() != (*this)->getParentRegion() ||
      getContinuationOperands().getTypes() !=
          getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation must match the native region and operand types");
  return success();
}
Operation::operand_range NativeTaskCallOp::getArguments() {
  size_t count = getArgumentCountAttr().getValue().isNegative()
                     ? 0
                     : std::min<uint64_t>(getArgumentCount(), getNumOperands());
  return getValues().take_front(count);
}
Operation::operand_range NativeTaskCallOp::getContinuationOperands() {
  size_t count = getArgumentCountAttr().getValue().isNegative()
                     ? 0
                     : std::min<uint64_t>(getArgumentCount(), getNumOperands());
  return getValues().drop_front(count);
}
MutableOperandRange NativeTaskCallOp::getContinuationOperandsMutable() {
  unsigned count =
      getArgumentCountAttr().getValue().isNegative()
          ? 0
          : std::min<uint64_t>(getArgumentCount(), getNumOperands());
  return MutableOperandRange(getOperation(), count, getNumOperands() - count);
}
LogicalResult
NativeTaskCallOp::verifySymbolUses(SymbolTableCollection &symbolTable) {
  auto callee = symbolTable.lookupNearestSymbolFrom<sim::SimFuncOp>(
      getOperation(), getCalleeAttr());
  if (!callee || callee.getEntryKind() != sim::EntryKind::Task)
    return emitOpError("callee must name a sibling task entry");
  if (getArguments().getTypes() != callee.getFunctionType().getInputs())
    return emitOpError("argument types must match the task signature");
  if (!callee.getFunctionType().getResults().empty())
    return emitOpError("task entry must not return SSA results");
  return success();
}
SuccessorOperands
NativeClassVirtualTaskCallOp::getSuccessorOperands(unsigned index) {
  assert(index == 0);
  return SuccessorOperands(getContinuationOperandsMutable());
}
LogicalResult NativeClassVirtualTaskCallOp::verify() {
  if (getArgumentCountAttr().getValue().isNegative() ||
      getArgumentCount() > getValues().size())
    return emitOpError("argument count exceeds the native operand inventory");
  if (getContinuation()->getParent() != (*this)->getParentRegion() ||
      getContinuationOperands().getTypes() !=
          getContinuation()->getArgumentTypes())
    return emitOpError(
        "continuation must match the native region and operand types");
  return success();
}
Operation::operand_range NativeClassVirtualTaskCallOp::getArguments() {
  size_t count =
      getArgumentCountAttr().getValue().isNegative()
          ? 0
          : std::min<uint64_t>(getArgumentCount(), getValues().size());
  return getValues().take_front(count);
}
Operation::operand_range
NativeClassVirtualTaskCallOp::getContinuationOperands() {
  return getValues().drop_front(getArguments().size());
}
MutableOperandRange
NativeClassVirtualTaskCallOp::getContinuationOperandsMutable() {
  unsigned count =
      getArgumentCountAttr().getValue().isNegative()
          ? 0
          : std::min<uint64_t>(getArgumentCount(), getValues().size());
  return MutableOperandRange(getOperation(), 1 + count,
                             getValues().size() - count);
}
LogicalResult NativeClassVirtualTaskCallOp::verifySymbolUses(
    SymbolTableCollection &symbolTable) {
  auto method = symbolTable.lookupNearestSymbolFrom<NativeMethodOp>(
      getOperation(), getMethodAttr());
  if (!method || !method.getIsVirtual() || !method.getIsTask() ||
      !method.getSlotAttr() || *method.getSlot() != getSlot() ||
      !method.getSignatureIdAttr() ||
      *method.getSignatureId() != getSignatureId())
    return emitOpError("method must name a compatible virtual task slot");
  return success();
}
} // namespace talos::schedule

namespace talos::schedule {
LogicalResult
NativeExecuteOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto callee = symbols.lookupNearestSymbolFrom<FunctionOpInterface>(
      *this, getCalleeAttr());
  if (!callee)
    return emitOpError("requires a defined scheduled function");
  auto nativeType = [&](Type type) -> Type {
    if (isa<sim::ContextType>(type))
      return LLVM::LLVMPointerType::get(getContext());
    if (isa<sim::TimeType>(type))
      return IntegerType::get(getContext(), 64);
    return type;
  };
  SmallVector<Type> inputs, results;
  for (Type type : callee.getArgumentTypes())
    inputs.push_back(nativeType(type));
  for (Type type : callee.getResultTypes())
    results.push_back(nativeType(type));
  if (getStatusResult() && results.empty())
    results.push_back(IntegerType::get(getContext(), 32));
  if (getOperandTypes() != TypeRange(inputs) ||
      getResultTypes() != TypeRange(results))
    return emitOpError(
        "operands and results must match the planned native body ABI");
  return success();
}
} // namespace talos::schedule

namespace talos::schedule {
LogicalResult
NativeSynchronousClassCallOp::verifySymbolUses(SymbolTableCollection &symbols) {
  Operation *declaration =
      symbols.lookupNearestSymbolFrom(*this, getMethodAttr());
  auto method = dyn_cast_if_present<sim::SimClassMethodDeclOp>(declaration);
  auto nativeMethod = dyn_cast_if_present<NativeMethodOp>(declaration);
  bool isTask =
      method ? method.getIsTask() : nativeMethod && nativeMethod.getIsTask();
  bool isVirtual = method ? method.getIsVirtual()
                          : nativeMethod && nativeMethod.getIsVirtual();
  if (!isTask || !isVirtual)
    return emitOpError("requires a virtual task method declaration");
  auto slot = method ? method.getSlot() : nativeMethod.getSlot();
  auto signature =
      method ? method.getSignatureId() : nativeMethod.getSignatureId();
  if (!slot || !signature || *slot != getSlot() ||
      *signature != getSignatureId())
    return emitOpError("must match the declared task slot and signature");
  auto type = dyn_cast<FunctionType>(method ? method.getFunctionType()
                                            : nativeMethod.getFunctionType());
  if (!type || type.getNumInputs() < 2 || type.getNumResults() ||
      getArguments().getTypes() != TypeRange(type.getInputs().drop_front(2)) ||
      !isa<sim::ClassHandleType>(getReceiver().getType()))
    return emitOpError("must match the declared task argument types");
  return success();
}
LogicalResult NativeMethodOp::verify() {
  if (!isa<FunctionType>(getFunctionType()))
    return emitOpError("requires a semantic function signature");
  if (getImplementationAttr() &&
      (!getNativeTypeAttr() ||
       !isa<FunctionType>(getNativeTypeAttr().getValue())))
    return emitOpError("requires a prepared native function signature");
  return success();
}
LogicalResult NativeMethodOp::verifySymbolUses(SymbolTableCollection &symbols) {
  if (!symbols.lookupNearestSymbolFrom<sim::SimClassDeclOp>(*this,
                                                            getOwnerAttr()))
    return emitOpError("requires a declared class owner");
  if (getImplementationAttr()) {
    auto callee = symbols.lookupNearestSymbolFrom<FunctionOpInterface>(
        *this, getImplementationAttr());
    if (!callee || callee.getFunctionType() != getNativeTypeAttr().getValue())
      return emitOpError(
          "implementation must match the prepared native signature");
  }
  return success();
}
LogicalResult NativeObserverOp::verify() {
  auto id = get<Field::NativeObserverId>(*this);
  auto width = get<Field::NativeObserverWidth>(*this);
  auto fourState = get<Field::NativeObserverFourState>(*this);
  auto kinds = get<Field::NativeDependencyKinds>(*this);
  auto widths = get<Field::NativeDependencyWidths>(*this);
  auto indices = get<Field::NativeDependencyCaptureIndices>(*this);
  if (!id || !width || width.getValue().isNegative() ||
      width.getValue().isZero() || !fourState || !kinds || !widths || !indices)
    return emitOpError(
        "requires typed observer identity, result, and dependency metadata");
  if (getCaptureCount() <= getNumOperands() &&
      (static_cast<uint64_t>(kinds.size()) !=
           getNumOperands() - getCaptureCount() ||
       widths.size() != kinds.size() || indices.size() != kinds.size()))
    return emitOpError(
        "dependency metadata must match the dependency operands");
  if (getCaptureCountAttr().getValue().isNegative() ||
      getCaptureCount() > getNumOperands())
    return emitOpError("capture count exceeds the operand inventory");
  return success();
}
} // namespace talos::schedule

namespace talos::schedule {
uint32_t getNativeWaitEntryCount(Operation *operation) {
  return TypeSwitch<Operation *, uint32_t>(operation)
      .Case<NativeSuspendChangeOp, NativeSuspendLevelOp, NativeSuspendEdgeOp,
            NativeSuspendEventOp, NativeSuspendMailboxOp,
            NativeSuspendSemaphoreOp, NativeSuspendAwaitOp>(
          [](auto) { return 1; })
      .Case<NativeSuspendEdgeIffOp>([](auto) { return 2; })
      .Case<NativeSuspendAnyOp>(
          [](auto op) { return static_cast<uint32_t>(op.getWatched().size()); })
      .Case<NativeSuspendClockSetOp>([](auto op) {
        return static_cast<uint32_t>(op.getPrimaries().size() +
                                     op.getConditions().size());
      })
      .Case<NativeSuspendEventOrderOp>(
          [](auto op) { return static_cast<uint32_t>(op.getEvents().size()); })
      .Case<NativeSuspendJoinOp>([](auto op) {
        return static_cast<uint32_t>(op.getProcesses().size());
      })
      .Default([](Operation *) { return 0; });
}

} // namespace talos::schedule

namespace talos::schedule {
LogicalResult NativeScratchOp::verify() {
  if (getSizeAttr().getValue().isNegative())
    return emitOpError("scratch byte count must be nonnegative");
  for (Operation *user : getResult().getUsers()) {
    if (!isa<runtime::RTFileReadOp, runtime::RTFileReadMemTokenOp,
             runtime::RTPackedFromBytesOp>(user) ||
        user->getParentRegion() != (*this)->getParentRegion())
      return emitOpError(
          "scratch consumers must remain in the native activation region");
  }
  return success();
}
LogicalResult NativeGCCollectOp::verify() {
  if (getPeriodicClock().has_value() != getPeriod().has_value())
    return emitOpError("a periodic collection point needs both its clock and "
                       "its period");
  if (getPeriod() && *getPeriod() == 0)
    return emitOpError("a periodic clock has a positive period");
  if ((getPosedge() || getEdge()) && !getPeriodicClock())
    return emitOpError("only a periodic collection point follows an edge");
  return success();
}

} // namespace talos::schedule
