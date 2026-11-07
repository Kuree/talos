//===- OrdinaryWrites.h - Caller-aware procedural power writes ----------===//

#ifndef TALOS_UPF_ORDINARYWRITES_H
#define TALOS_UPF_ORDINARYWRITES_H

#include "ClockSnapshot.h"
#include "Retention.h"
#include "llvm/ADT/DenseSet.h"
#include <functional>

namespace talos::upf_detail {
// Final physical ownership and exact published policy, after retention has
// split its normal/output state. Generated policy stores are not producers.
struct WriteDomain {
  std::string name;
  Descriptor epoch;
  llvm::DenseSet<uint64_t> ordinary, retained;
  llvm::DenseSet<Operation *> actors;
  SmallVector<Descriptor> dependencies;
  bool exact = false, immutable = false;
  std::function<Value(OpBuilder &, Location, Value)> normal;
};
struct OrdinaryWriteOptions {
  sim::SimDesignOp design;
  sim::SimFuncOp root;
  ArrayRef<sim::SimFuncOp> functions;
  const llvm::DenseSet<uint64_t> &originalStorage;
  ArrayRef<WriteDomain> domains;
  ArrayRef<RetentionWrite> retainedWrites;
  ClockSnapshots &clocks;
  std::function<Descriptor(Location, StringRef, Type)> storage;
  std::function<sim::SimFuncOp(Location, StringRef, ArrayRef<Type>,
                               sim::EntryKind)>
      function;
};

// Instrument original procedural statements once, retaining both the caller's
// execution provenance and the destination root's independent power policy.
LogicalResult lowerOrdinaryUPFWrites(const OrdinaryWriteOptions &options);
} // namespace talos::upf_detail
#endif
