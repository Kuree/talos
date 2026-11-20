//===- SimulationContextCache.h - Per-context analysis caches ---*- C++ -*-===//
//
// An analysis cache keyed by operation addresses, or validated by a digest of
// the addresses of uniqued attributes and types, is sound only while the
// context owning those objects is alive. A process-wide cache outlives it: a
// later context can reuse the addresses of its operations, attributes and
// types, so a stale entry matches unrelated IR. talos-opt --split-input-file
// runs every split in a fresh context, and macOS's allocator reuses such
// addresses readily. The Simulation dialect therefore keeps one store of
// these caches per context and destroys it with the context.
//
//===----------------------------------------------------------------------===//

#ifndef TALOS_DIALECT_SIMULATION_SIMULATIONCONTEXTCACHE_H
#define TALOS_DIALECT_SIMULATION_SIMULATIONCONTEXTCACHE_H

#include "mlir/IR/MLIRContext.h"

#include "llvm/ADT/STLFunctionalExtras.h"

#include <memory>

namespace talos::sim {

/// Returns the object stored under `key` in `context`'s cache store, creating
/// it with `make` on first use; it lives until `context` is destroyed. Without
/// a loaded Simulation dialect nothing is stored and every call returns a
/// fresh object. Thread-safe.
std::shared_ptr<void>
getOrCreateContextCache(mlir::MLIRContext *context, const void *key,
                        llvm::function_ref<std::shared_ptr<void>()> make);

/// The default-constructed `T` cache of `context`, one per context and type.
template <typename T>
std::shared_ptr<T> getContextCache(mlir::MLIRContext *context) {
  // Mutable, so identical-data folding cannot merge two types' keys.
  static char key;
  return std::static_pointer_cast<T>(getOrCreateContextCache(context, &key, [] {
    return std::static_pointer_cast<void>(std::make_shared<T>());
  }));
}

} // namespace talos::sim

#endif // TALOS_DIALECT_SIMULATION_SIMULATIONCONTEXTCACHE_H
