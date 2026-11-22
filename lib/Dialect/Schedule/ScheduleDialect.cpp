#include "talos/Dialect/Schedule/ScheduleDialect.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "mlir/Transforms/InliningUtils.h"
#include "talos/Dialect/Schedule/ScheduleAttrs.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;

#include "talos/Dialect/Schedule/ScheduleDialect.cpp.inc"
#include "talos/Dialect/Schedule/ScheduleEnums.cpp.inc"
namespace talos::schedule {
static FailureOr<SmallVector<uint64_t>> parseCoveragePoints(AsmParser &parser) {
  SmallVector<uint64_t> points;
  if (failed(parser.parseCommaSeparatedList(AsmParser::Delimiter::Square, [&] {
        uint64_t point;
        if (failed(parser.parseInteger(point)))
          return failure();
        points.push_back(point);
        return success();
      })))
    return failure();
  return points;
}
} // namespace talos::schedule
#define GET_ATTRDEF_CLASSES
#include "talos/Dialect/Schedule/ScheduleAttrs.cpp.inc"
namespace talos::schedule {
namespace {
struct ReadyInlinerInterface final : DialectInlinerInterface {
  using DialectInlinerInterface::DialectInlinerInterface;
  bool isLegalToInline(Operation *op, Region *, bool, IRMapping &) const final {
    // Cloning preserves ordered accesses to the same pending set. Regions
    // are formed after body inlining; other schedule actions retain their
    // existing callable/activation restrictions.
    // State-plane, NBA accumulator, NBA index, ready-set word and mask word
    // accesses are plain memory accesses; an NBA stage, a handle-addressed
    // access and a handle-addressed transition inline like the runtime calls
    // they stand for.
    return isa<NativeReadyReadOp, NativeReadyUpdateOp, NativeReadyCommitOp,
               NativeReadyMergeOp, NativeReadyWordLoadOp,
               NativeReadyWordStoreOp, NativeMaskLoadOp, NativeMaskStoreOp,
               NativeStateAddressOp, NativeStateWindowAddressOp,
               NativeStateLoadOp, NativeStateStoreOp,
               NativeNBAAccumulatorAddressOp, NativeNBAAccumulatorLoadOp,
               NativeNBAAccumulatorStoreOp, NativeNBAIndexLoadOp,
               NativeNBAIndexStoreOp, NativeNBAStageOp, NativeStateLoadHandleOp,
               NativeStateLoadHandleBytesOp, NativeStateStoreHandleOp,
               NativeStateStoreHandleBytesOp, NativeStateFrameStoreOp,
               NativeStateLoadAutomaticOp, NativeHandleTransitionOp,
               NativeHandleTransitionBytesOp>(op);
  }
};
} // namespace
Operation *ScheduleDialect::materializeConstant(OpBuilder &builder,
                                               Attribute value, Type type,
                                               Location loc) {
  // A canonical plane's address is a constant; a contribution plane's is not.
  auto plane = dyn_cast<StatePlaneAttr>(value);
  if (plane && isCanonicalStatePlane(plane.getValue()) &&
      type == LLVM::LLVMPointerType::get(builder.getContext()))
    return NativeStateAddressOp::create(builder, loc, plane.getValue());
  // A handle guard folds to the invalid handle, an i64 constant.
  auto integer = dyn_cast<IntegerAttr>(value);
  if (integer && type.isSignlessInteger(64) && integer.getType() == type)
    return arith::ConstantOp::create(builder, loc, type, integer);
  return nullptr;
}

// The typed fields that replaced name tests and untyped markers have their
// payload and belong on one kind of operation: a function's roles, a fixed
// NBA slot global's field, a module's VPI write profile. Passes read them
// through typed accessors, which would take a misplaced or mistyped field for
// an absent one. Other fields are not checked here.
LogicalResult
ScheduleDialect::verifyOperationAttribute(Operation *operation,
                                          NamedAttribute attribute) {
  std::optional<Field> field = symbolizeField(attribute.getName().strref());
  if (!field)
    return success();
  Attribute value = attribute.getValue();
  auto error = [&] {
    return operation->emitOpError("attribute '")
           << attribute.getName().strref() << "' ";
  };
  switch (*field) {
  case Field::EvalRole:
    if (!isa<EvalRoleAttr>(value))
      return error() << "has the wrong payload kind";
    if (!isa<FunctionOpInterface>(operation))
      return error() << "belongs on a function";
    return success();
  case Field::NbaSlot:
    if (!isa<NBASlotAttr>(value))
      return error() << "has the wrong payload kind";
    if (!isa<LLVM::GlobalOp>(operation))
      return error() << "belongs on an llvm.mlir.global";
    return success();
  case Field::EvalWritableVpi:
    if (!isa<UnitAttr>(value))
      return error() << "has the wrong payload kind";
    if (!isa<ModuleOp>(operation))
      return error() << "belongs on a module";
    return success();
  default:
    return success();
  }
}

void ScheduleDialect::initialize() {
  addInterfaces<ReadyInlinerInterface>();
  addOperations<
#define GET_OP_LIST
#include "talos/Dialect/Schedule/ScheduleOps.cpp.inc"
      >();
  addAttributes<
#define GET_ATTRDEF_LIST
#include "talos/Dialect/Schedule/ScheduleAttrs.cpp.inc"
      >();
}
} // namespace talos::schedule
