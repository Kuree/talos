//===- NativeStateAccess.cpp - Native state access queries ----------------===//
//
// Shared queries over native memory accesses: typed state-plane operations
// and the LLVM loads, stores, copies and fills of other memory.
//
//===----------------------------------------------------------------------===//

#include "NativeStateAccess.h"
#include "SimulationToLLVMCoroutinePrivate.h"
#include "talos/Dialect/Schedule/ScheduleFields.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/FunctionInterfaces.h"

using namespace mlir;

namespace talos {
namespace detail {
FlatSymbolRefAttr getAddressedGlobal(Operation *root) {
  if (auto address = dyn_cast<LLVM::AddressOfOp>(root))
    return schedule::getStatePlaneOfGlobal(address.getGlobalName())
               ? nullptr
               : address.getGlobalNameAttr();
  if (auto address = dyn_cast<schedule::NativeStateAddressOp>(root))
    return address.getGlobalAttr();
  if (auto window = dyn_cast<schedule::NativeStateWindowAddressOp>(root))
    return window.getGlobalAttr();
  return nullptr;
}

std::optional<schedule::StatePlane> getStatePlaneRoot(Value pointer) {
  while (auto gep = pointer.getDefiningOp<LLVM::GEPOp>())
    pointer = gep.getBase();
  if (auto address = pointer.getDefiningOp<schedule::NativeStateAddressOp>())
    return address.getPlane();
  if (auto window =
          pointer.getDefiningOp<schedule::NativeStateWindowAddressOp>())
    return window.getPlane();
  return std::nullopt;
}

std::optional<uint64_t> getConstantByteOffset(Value pointer) {
  uint64_t bytes = 0;
  while (auto gep = pointer.getDefiningOp<LLVM::GEPOp>()) {
    if (!gep.getElemType().isInteger(8) || gep.getIndices().size() != 1)
      return std::nullopt;
    APInt constant;
    auto index = gep.getIndices()[0];
    if (auto integer = dyn_cast<IntegerAttr>(index))
      constant = integer.getValue();
    else if (!matchPattern(cast<Value>(index), m_ConstantInt(&constant)))
      return std::nullopt;
    if (constant.isNegative() || constant.getActiveBits() > 64 ||
        constant.getZExtValue() > UINT64_MAX - bytes)
      return std::nullopt;
    bytes += constant.getZExtValue();
    pointer = gep.getBase();
  }
  // A window address starts at its own offset into the plane.
  if (auto window =
          pointer.getDefiningOp<schedule::NativeStateWindowAddressOp>()) {
    std::optional<uint64_t> start = window.getConstantOffset();
    if (!start || *start > UINT64_MAX - bytes)
      return std::nullopt;
    bytes += *start;
  }
  return bytes;
}

bool NativeAddress::isLocal() const {
  return root && root.getDefiningOp<LLVM::AllocaOp>();
}

std::optional<NativeMemoryAccess> getNativeMemoryAccess(Operation *operation) {
  NativeMemoryAccess access;
  access.operation = operation;
  if (auto load = dyn_cast<schedule::NativeStateLoadOp>(operation)) {
    access.type = load.getType();
    access.plane = load.getPlane();
    access.global = load.getGlobal();
    access.offset = load.getConstantOffset();
    access.window = load.getWindowAttr();
    access.owner = load.getOwnerAttr();
    return access;
  }
  if (auto store = dyn_cast<schedule::NativeStateStoreOp>(operation)) {
    access.type = store.getValue().getType();
    access.stored = store.getValue();
    access.plane = store.getPlane();
    access.global = store.getGlobal();
    access.offset = store.getConstantOffset();
    access.window = store.getWindowAttr();
    access.writtenBits = store.getWrittenBitsAttr();
    access.owner = store.getOwnerAttr();
    return access;
  }
  if (auto load = dyn_cast<LLVM::LoadOp>(operation)) {
    static_cast<NativeAddress &>(access) =
        describeNativeAddress(operation, load.getAddr());
    access.type = load.getType();
    access.plain = !load.getVolatile_() &&
                   load.getOrdering() == LLVM::AtomicOrdering::not_atomic;
    return access;
  }
  if (auto store = dyn_cast<LLVM::StoreOp>(operation)) {
    static_cast<NativeAddress &>(access) =
        describeNativeAddress(operation, store.getAddr());
    access.type = store.getValue().getType();
    access.stored = store.getValue();
    access.plain = !store.getVolatile_() &&
                   store.getOrdering() == LLVM::AtomicOrdering::not_atomic;
    return access;
  }
  return std::nullopt;
}

NativeAddress describeNativeAddress(Operation *operation, Value pointer) {
  NativeAddress access;
  access.pointer = pointer;
  access.root = pointer;
  while (auto gep = access.root.getDefiningOp<LLVM::GEPOp>())
    access.root = gep.getBase();
  if (FlatSymbolRefAttr global = getAddressedGlobal(access.root))
    access.global = global.getValue();
  access.plane = getStatePlaneRoot(access.root);
  access.offset = getConstantByteOffset(pointer);
  access.window = schedule::get<schedule::Field::EvalStateAccessBytes>(operation);
  access.writtenBits =
      schedule::get<schedule::Field::EvalUnknownWriteRange>(operation);
  access.owner = schedule::get<schedule::Field::EvalGroupOwner>(operation);
  return access;
}

bool isNativeLatchDestination(Operation *operation) {
  if (auto load = dyn_cast<schedule::NativeStateLoadOp>(operation))
    return load.getLatchDestination();
  if (auto store = dyn_cast<schedule::NativeStateStoreOp>(operation))
    return store.getLatchDestination();
  return schedule::has<schedule::Field::EvalPreserveNbaUnknown>(operation);
}

void clearNativeLatchDestination(Operation *operation) {
  if (auto load = dyn_cast<schedule::NativeStateLoadOp>(operation))
    load.setLatchDestination(false);
  else if (auto store = dyn_cast<schedule::NativeStateStoreOp>(operation))
    store.setLatchDestination(false);
  else
    schedule::remove<schedule::Field::EvalPreserveNbaUnknown>(operation);
}

Value createStatePlaneAddress(OpBuilder &builder, Location location,
                              schedule::StatePlane plane) {
  // Typed state operations live in functions; a global's initializer takes
  // a plane's address as a constant.
  Block *block = builder.getInsertionBlock();
  Operation *parent = block ? block->getParentOp() : nullptr;
  if (parent && (isa<FunctionOpInterface>(parent) ||
                 parent->getParentOfType<FunctionOpInterface>()))
    return schedule::NativeStateAddressOp::create(builder, location, plane);
  return LLVM::AddressOfOp::create(
      builder, location, LLVM::LLVMPointerType::get(builder.getContext()),
      schedule::getStatePlaneGlobalName(plane));
}

std::optional<StateWindow> getStateWindow(Value pointer) {
  if (auto base = pointer.getDefiningOp<schedule::NativeStateAddressOp>())
    return StateWindow{base.getPlane(), Value(), 0};
  if (auto window =
          pointer.getDefiningOp<schedule::NativeStateWindowAddressOp>())
    return StateWindow{window.getPlane(), window.getDynamicOffset(),
                       window.getStaticOffset()};
  return std::nullopt;
}

namespace {
/// The window `dynamicBytes` plus `staticBytes` past a typed window.
StateWindow offsetWindow(OpBuilder &builder, Location location,
                         StateWindow window, Value dynamicBytes,
                         uint64_t staticBytes) {
  if (dynamicBytes)
    window.dynamicOffset =
        window.dynamicOffset
            ? LLVM::AddOp::create(builder, location, window.dynamicOffset,
                                  dynamicBytes)
                  .getResult()
            : dynamicBytes;
  assert(window.staticOffset <= UINT64_MAX - staticBytes &&
         "state window offset overflows");
  window.staticOffset += staticBytes;
  return window;
}
} // namespace

Value createAddressAt(OpBuilder &builder, Location location, Value base,
                      Value dynamicBytes, uint64_t staticBytes) {
  if (std::optional<StateWindow> typed = getStateWindow(base)) {
    if (!dynamicBytes && !staticBytes)
      return base;
    StateWindow window =
        offsetWindow(builder, location, *typed, dynamicBytes, staticBytes);
    return schedule::NativeStateWindowAddressOp::create(
        builder, location, window.plane, window.dynamicOffset,
        window.staticOffset);
  }
  Value address = base;
  if (dynamicBytes)
    address = LLVM::GEPOp::create(
        builder, location, LLVM::LLVMPointerType::get(builder.getContext()),
        builder.getI8Type(), address, ValueRange{dynamicBytes});
  if (staticBytes)
    address = byteGEP(builder, location, address, staticBytes);
  return address;
}

Value createLoadAt(OpBuilder &builder, Location location, Type type, Value base,
                   Value dynamicBytes, uint64_t staticBytes,
                   unsigned alignment) {
  if (std::optional<StateWindow> typed = getStateWindow(base)) {
    assert(llvm::isPowerOf2_64(alignment) && "typed access needs an alignment");
    StateWindow window =
        offsetWindow(builder, location, *typed, dynamicBytes, staticBytes);
    return schedule::NativeStateLoadOp::create(
        builder, location, type, window.plane, window.dynamicOffset,
        window.staticOffset, alignment);
  }
  return LLVM::LoadOp::create(
      builder, location, type,
      createAddressAt(builder, location, base, dynamicBytes, staticBytes),
      alignment);
}

Operation *createStoreAt(OpBuilder &builder, Location location, Value value,
                         Value base, Value dynamicBytes, uint64_t staticBytes,
                         unsigned alignment) {
  if (std::optional<StateWindow> typed = getStateWindow(base)) {
    assert(llvm::isPowerOf2_64(alignment) && "typed access needs an alignment");
    StateWindow window =
        offsetWindow(builder, location, *typed, dynamicBytes, staticBytes);
    return schedule::NativeStateStoreOp::create(
        builder, location, value, window.plane, window.dynamicOffset,
        window.staticOffset, alignment);
  }
  return LLVM::StoreOp::create(
      builder, location, value,
      createAddressAt(builder, location, base, dynamicBytes, staticBytes),
      alignment);
}

Value createGlobalAddress(OpBuilder &builder, Location location,
                          StringRef global) {
  if (auto plane = schedule::getStatePlaneOfGlobal(global))
    return createStatePlaneAddress(builder, location, *plane);
  return LLVM::AddressOfOp::create(
      builder, location, LLVM::LLVMPointerType::get(builder.getContext()),
      global);
}

void setNativeAccessWindow(Operation *operation, DenseI64ArrayAttr window) {
  assert(schedule::isValidStateWindow(window.asArrayRef()) &&
         "malformed state access window");
  if (auto load = dyn_cast<schedule::NativeStateLoadOp>(operation))
    load.setWindowAttr(window);
  else if (auto store = dyn_cast<schedule::NativeStateStoreOp>(operation))
    store.setWindowAttr(window);
  else
    schedule::set<schedule::Field::EvalStateAccessBytes>(operation, window);
}

void setNativeAccessWrittenBits(Operation *operation, DenseI64ArrayAttr bits) {
  assert(schedule::isValidStateWrittenBits(bits.asArrayRef()) &&
         "malformed written bits");
  if (auto store = dyn_cast<schedule::NativeStateStoreOp>(operation))
    store.setWrittenBitsAttr(bits);
  else
    schedule::set<schedule::Field::EvalUnknownWriteRange>(operation, bits);
}

void setNativeLatchDestination(Operation *operation) {
  if (auto load = dyn_cast<schedule::NativeStateLoadOp>(operation))
    load.setLatchDestination(true);
  else if (auto store = dyn_cast<schedule::NativeStateStoreOp>(operation))
    store.setLatchDestination(true);
  else
    schedule::set<schedule::Field::EvalPreserveNbaUnknown>(
        operation, UnitAttr::get(operation->getContext()));
}

void setNativeSummaryReported(Operation *operation) {
  if (auto store = dyn_cast<schedule::NativeStateStoreOp>(operation))
    store.setSummaryReported(true);
  else
    schedule::set<schedule::Field::EvalUnknownSummaryReported>(
        operation, UnitAttr::get(operation->getContext()));
}

void setNativeMemoryOwner(Operation *operation, IntegerAttr owner) {
  if (auto load = dyn_cast<schedule::NativeStateLoadOp>(operation))
    load.setOwnerAttr(owner);
  else if (auto store = dyn_cast<schedule::NativeStateStoreOp>(operation))
    store.setOwnerAttr(owner);
  else
    schedule::set<schedule::Field::EvalGroupOwner>(operation, owner);
}
} // namespace detail
} // namespace talos
