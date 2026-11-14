//===- NativeStateAccess.h - Typed native state accesses ---------*- C++ -*-===//
//
// Shared queries over native state accesses, for the passes that read or
// rewrite them: the typed state-plane operations of the schedule dialect, and
// the LLVM loads and stores that remain beside them.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_CONVERSION_SIMULATIONTOLLVM_NATIVE_STATE_ACCESS_H
#define TALOS_CONVERSION_SIMULATIONTOLLVM_NATIVE_STATE_ACCESS_H

#include "talos/Dialect/Schedule/ScheduleDialect.h"
#include "talos/Dialect/Schedule/ScheduleOps.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"

#include <optional>

namespace talos::detail {

/// The global an address root names: an llvm.mlir.addressof, or the plane
/// global of a schedule.state.address.
mlir::FlatSymbolRefAttr getAddressedGlobal(mlir::Operation *root);
inline mlir::FlatSymbolRefAttr getAddressedGlobal(mlir::Value root) {
  mlir::Operation *definition = root.getDefiningOp();
  return definition ? getAddressedGlobal(definition) : nullptr;
}

/// The state plane whose base `pointer` is derived from through GEPs, if any.
std::optional<schedule::StatePlane> getStatePlaneRoot(mlir::Value pointer);

/// The constant byte offset of `pointer` from its root, when every step to
/// it is a byte GEP by a constant.
std::optional<uint64_t> getConstantByteOffset(mlir::Value pointer);

/// Where a native memory operation's address points: the root of an LLVM
/// address, the global it derives from and the constant offset, with the
/// window, written bits and group owner its producer declared.
struct NativeAddress {
  /// The LLVM address; null for a typed state access.
  mlir::Value pointer;
  /// The root of an LLVM address after its GEPs.
  mlir::Value root;
  /// The global the address derives from, a state plane or any other; empty
  /// when the address derives from no global's address.
  llvm::StringRef global;
  /// The constant byte offset from the root, when it is static.
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
/// from a global through GEPs. During the migration to typed producers both
/// forms reach these passes; each sees one description of either.
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
  return schedule::getStatePlaneOfGlobal(address.global);
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
/// The address of a global named at run time of the producer, which may be
/// a state plane: createStatePlaneAddress for a plane, llvm.mlir.addressof
/// otherwise.
mlir::Value createGlobalAddress(mlir::OpBuilder &builder,
                                mlir::Location location,
                                llvm::StringRef global);

/// What producers record about a load or store of either form: a typed
/// access takes it as a property, an LLVM one as the tag raising maps to it.
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
