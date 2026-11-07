//===- ClockSnapshot.h - Event-time qualification of pending actors -----===//
#ifndef TALOS_UPF_CLOCKSNAPSHOT_H
#define TALOS_UPF_CLOCKSNAPSHOT_H
#include "ControlValue.h"
#include <functional>
#include <memory>
namespace talos::upf_detail {
struct FrozenClock {
  Descriptor epoch, valid;
};
struct ClockSnapshotOptions {
  sim::SimFuncOp root;
  std::function<Descriptor(Location, StringRef, Type)> storage;
  std::function<sim::SimFuncOp(Location, StringRef, ArrayRef<Type>,
                               sim::EntryKind)>
      function;
};
// One history and arming bit per original event control, with independent
// domain and retention qualification channels. No activation body is sampled.
class ClockSnapshots {
public:
  explicit ClockSnapshots(ClockSnapshotOptions options);
  ~ClockSnapshots();
  FailureOr<FrozenClock>
  freeze(sim::SimFuncOp writer, StringRef name, Descriptor epoch,
         llvm::function_ref<Value(OpBuilder &, Location, Value)> eligible);
  LogicalResult finalize();

private:
  struct Impl;
  std::unique_ptr<Impl> impl;
};
Value clockEdge(OpBuilder &b, Location loc, Value before, Value after,
                sim::EdgeKind kind);
} // namespace talos::upf_detail
#endif
