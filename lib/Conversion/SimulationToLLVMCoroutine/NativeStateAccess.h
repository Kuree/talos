//===- NativeStateAccess.h - Native state accesses --------------*- C++ -*-===//
//
// Shared queries over native memory accesses, for the passes that read or
// rewrite them. A state plane is accessed only through the typed state-plane
// operations of the schedule dialect; every pointer into a plane is a plane's
// base or a window's address. Other memory is accessed through LLVM loads,
// stores, copies and fills whose addresses derive from a global or a local
// allocation through byte GEPs.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_CONVERSION_SIMULATIONTOLLVM_NATIVE_STATE_ACCESS_H
#define TALOS_CONVERSION_SIMULATIONTOLLVM_NATIVE_STATE_ACCESS_H

#include "talos/Dialect/Schedule/ScheduleDialect.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

#include <optional>

namespace talos::detail {

/// The global an address root names: the plane global of a typed plane
/// pointer, or the global of an llvm.mlir.addressof. An LLVM address of a
/// state plane, or of a contribution plane's binding, names none: native
/// code accesses no plane through it, and a pointer of unknown origin may
/// alias anything.
mlir::FlatSymbolRefAttr getAddressedGlobal(mlir::Operation *root);
inline mlir::FlatSymbolRefAttr getAddressedGlobal(mlir::Value root) {
  mlir::Operation *definition = root.getDefiningOp();
  return definition ? getAddressedGlobal(definition) : nullptr;
}

/// The state plane `pointer` points into, through byte GEPs of a plane's base
/// or window address. (Native finalization rejects such GEPs; consumers
/// before it still see the plane.)
std::optional<schedule::StatePlane> getStatePlaneRoot(mlir::Value pointer);

/// The constant byte offset of `pointer` from its root, when every step to
/// it is a byte GEP by a constant; for a window address, from its plane.
std::optional<uint64_t> getConstantByteOffset(mlir::Value pointer);

/// Where a native memory operation's address points: the root of an LLVM
/// address, the state plane or global it derives from and the constant
/// offset, with the window, written bits and group owner its producer
/// declared.
struct NativeAddress {
  /// The LLVM address; null for a typed state access.
  mlir::Value pointer;
  /// The root of an LLVM address after its GEPs.
  mlir::Value root;
  /// The canonical state plane of a typed access or of a typed plane
  /// pointer. A contribution plane is memory apart from design state; its
  /// accesses describe its binding global instead.
  std::optional<schedule::StatePlane> plane;
  /// The global the address derives from, a state plane's or any other;
  /// empty when the address derives from no global's address. For a
  /// contribution plane it is the pointer global that binds the plane, and
  /// `offset` indexes the bound plane, not the binding.
  llvm::StringRef global;
  /// The constant byte offset, when it is static: from the plane for a
  /// typed access or a window address, from the root otherwise.
  std::optional<uint64_t> offset;
  /// The physical byte window [begin, end) the producer declared, if any.
  mlir::DenseI64ArrayAttr window;
  /// The bits [begin, width] a dynamic write may change, if declared.
  mlir::DenseI64ArrayAttr writtenBits;
  /// The group member the access belongs to, if recorded.
  mlir::IntegerAttr owner;

  bool isTyped() const { return !pointer; }
  /// Whether the address is a local allocation's.
  bool isLocal() const;
};

/// A load or store as the native passes that inventory memory see it: a
/// typed state access, or an LLVM load or store whose address may derive
/// from a global or a local allocation through GEPs.
struct NativeMemoryAccess : NativeAddress {
  mlir::Operation *operation = nullptr;
  /// The type read or written.
  mlir::Type type;
  /// The value written; null for a read.
  mlir::Value stored;
  /// Neither volatile nor atomic.
  bool plain = true;

  bool isWrite() const { return static_cast<bool>(stored); }
};

/// The access `operation` performs, if it is a load or a store of either
/// form.
std::optional<NativeMemoryAccess> getNativeMemoryAccess(mlir::Operation *operation);

/// Where `operation`, an LLVM memory operation such as a load, store, copy or
/// fill, accesses memory through `pointer`.
NativeAddress describeNativeAddress(mlir::Operation *operation,
                                    mlir::Value pointer);

/// The state plane an address lies in, if any.
inline std::optional<schedule::StatePlane>
getStatePlaneOfAccess(const NativeAddress &address) {
  return address.plane;
}

/// Whether `operation` is a load or store, typed or LLVM.
inline bool isNativeMemoryAccess(mlir::Operation *operation) {
  return mlir::isa<mlir::LLVM::LoadOp, mlir::LLVM::StoreOp,
                   schedule::NativeStateLoadOp, schedule::NativeStateStoreOp>(
      operation);
}
/// Whether `operation` is a store, typed or LLVM.
inline bool isNativeMemoryStore(mlir::Operation *operation) {
  return mlir::isa<mlir::LLVM::StoreOp, schedule::NativeStateStoreOp>(
      operation);
}

/// A state plane's address as a producer takes it: the plane's typed base in
/// a function, llvm.mlir.addressof in a global's initializer.
mlir::Value createStatePlaneAddress(mlir::OpBuilder &builder,
                                    mlir::Location location,
                                    schedule::StatePlane plane);
/// The window a state plane's base or a window address points to: its plane,
/// its dynamic byte offset (null when static) and its static byte offset.
struct StateWindow {
  schedule::StatePlane plane;
  mlir::Value dynamicOffset;
  uint64_t staticOffset;
};
std::optional<StateWindow> getStateWindow(mlir::Value pointer);
/// Whether `pointer` is a state plane's base or the address of one of its
/// windows, the only pointers into a plane.
inline bool isTypedStatePointer(mlir::Value pointer) {
  return getStateWindow(pointer).has_value();
}
/// Producers address memory that may lie in a state plane relative to a
/// base, `dynamicBytes` (an i64, or null) plus `staticBytes` past it. Past a
/// typed state-plane pointer the address is a window address and the access
/// a typed state access; elsewhere they are byte GEPs and LLVM accesses. No
/// address computation or LLVM access ever reaches into a plane.
mlir::Value createAddressAt(mlir::OpBuilder &builder, mlir::Location location,
                            mlir::Value base, mlir::Value dynamicBytes,
                            uint64_t staticBytes);
mlir::Value createLoadAt(mlir::OpBuilder &builder, mlir::Location location,
                         mlir::Type type, mlir::Value base,
                         mlir::Value dynamicBytes, uint64_t staticBytes,
                         unsigned alignment);
mlir::Operation *createStoreAt(mlir::OpBuilder &builder,
                               mlir::Location location, mlir::Value value,
                               mlir::Value base, mlir::Value dynamicBytes,
                               uint64_t staticBytes, unsigned alignment);

/// What producers record about a load or store: a typed state access takes
/// it as a property, an LLVM access of other memory as a tag.
/// The group member that owns the access.
void setNativeMemoryOwner(mlir::Operation *operation, mlir::IntegerAttr owner);
/// The physical byte window [begin, end) the access lies in.
void setNativeAccessWindow(mlir::Operation *operation,
                           mlir::DenseI64ArrayAttr window);
/// The bits [begin, width] a dynamic store may change.
void setNativeAccessWrittenBits(mlir::Operation *operation,
                                mlir::DenseI64ArrayAttr bits);
/// The access is a per-site NBA latch destination.
void setNativeLatchDestination(mlir::Operation *operation);
/// The store's writer reports its roots to the unknown summary itself.
void setNativeSummaryReported(mlir::Operation *operation);

/// Whether `operation` writes or reads a per-site NBA latch destination,
/// which the fast two-state NBA commit keeps in both planes.
bool isNativeLatchDestination(mlir::Operation *operation);
void clearNativeLatchDestination(mlir::Operation *operation);

} // namespace talos::detail

#endif
