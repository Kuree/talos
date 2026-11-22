// RUN: talos-opt %s --test-talos-lower-native-handle-transitions | FileCheck %s

// Once AOT planning has read the eval bodies' handle-addressed transitions,
// each one the plan does not publish itself becomes the runtime's signal
// transition on snapshots of its planes (IEEE 1800-2023 4.3, 9.4.2): the
// buffers of the `_bytes` form, or entry-block temporaries holding the planes
// of the value form, live only around the call. A plane without X/Z bits
// (6.3.1) passes no unknown snapshot, the null pointer. The call carries no
// schedule facts.
module {
  llvm.func @talos_rt_v1_scheduler_signal_transition(!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)

  // CHECK-LABEL: llvm.func @publish(
  // CHECK-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[OLD:.*]]: !llvm.ptr, %[[OLD_UNKNOWN:.*]]: !llvm.ptr, %[[NEW:.*]]: !llvm.ptr, %[[NEW_UNKNOWN:.*]]: !llvm.ptr)
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(72 : i64) : i64
  // CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_signal_transition(%[[CONTEXT]], %[[HANDLE]], %[[WIDTH]], %[[OLD]], %[[OLD_UNKNOWN]], %[[NEW]], %[[NEW_UNKNOWN]]) : (!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> (){{$}}
  // CHECK-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(130 : i64) : i64
  // CHECK-NEXT: %[[NONE:.*]] = llvm.mlir.zero : !llvm.ptr
  // CHECK-NEXT: %[[NO_NEW_UNKNOWN:.*]] = llvm.mlir.zero : !llvm.ptr
  // CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_signal_transition(%[[CONTEXT]], %[[HANDLE]], %[[WIDTH]], %[[OLD]], %[[NONE]], %[[NEW]], %[[NO_NEW_UNKNOWN]]) : (!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> (){{$}}
  // CHECK-NEXT: llvm.return
  llvm.func @publish(%context: !llvm.ptr, %handle: i64, %old: !llvm.ptr, %old_unknown: !llvm.ptr, %new: !llvm.ptr, %new_unknown: !llvm.ptr) {
    schedule.transition.handle_bytes %context, %handle from %old unknown %old_unknown to %new unknown %new_unknown nba_equivalent {source_owner = #schedule.source_owner<codeUnit = 3 : i64, continuation = 1 : i64>, width = 72 : i64}
    schedule.transition.handle_bytes %context, %handle from %old to %new {width = 130 : i64}
    llvm.return
  }

  // CHECK-LABEL: llvm.func @publish_values(
  // CHECK-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[OLD:.*]]: i72, %[[OLD_UNKNOWN:.*]]: i72, %[[NEW:.*]]: i72)
  // CHECK-COUNT-3: llvm.alloca %{{.*}} x i72
  // CHECK: %[[WIDTH:.*]] = llvm.mlir.constant(72 : i64) : i64
  // CHECK-NEXT: llvm.intr.lifetime.start %[[OLD_SLOT:[^ ]*]] :
  // CHECK-NEXT: llvm.store %[[OLD]], %[[OLD_SLOT]] {alignment = 1 : i64} : i72, !llvm.ptr
  // CHECK-NEXT: llvm.intr.lifetime.start %[[OLD_UNKNOWN_SLOT:[^ ]*]] :
  // CHECK-NEXT: llvm.store %[[OLD_UNKNOWN]], %[[OLD_UNKNOWN_SLOT]] {alignment = 1 : i64} : i72, !llvm.ptr
  // CHECK-NEXT: llvm.intr.lifetime.start %[[NEW_SLOT:[^ ]*]] :
  // CHECK-NEXT: llvm.store %[[NEW]], %[[NEW_SLOT]] {alignment = 1 : i64} : i72, !llvm.ptr
  // CHECK-NEXT: %[[NO_NEW_UNKNOWN:.*]] = llvm.mlir.zero : !llvm.ptr
  // CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_signal_transition(%[[CONTEXT]], %[[HANDLE]], %[[WIDTH]], %[[OLD_SLOT]], %[[OLD_UNKNOWN_SLOT]], %[[NEW_SLOT]], %[[NO_NEW_UNKNOWN]]) : (!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> (){{$}}
  // CHECK-NEXT: llvm.intr.lifetime.end %[[OLD_SLOT]]
  // CHECK-NEXT: llvm.intr.lifetime.end %[[OLD_UNKNOWN_SLOT]]
  // CHECK-NEXT: llvm.intr.lifetime.end %[[NEW_SLOT]]
  // CHECK-NEXT: llvm.return
  llvm.func @publish_values(%context: !llvm.ptr, %handle: i64, %old: i72, %old_unknown: i72, %new: i72) {
    schedule.transition.handle %context, %handle from %old unknown %old_unknown to %new nba_equivalent {source_owner = #schedule.source_owner<codeUnit = 3 : i64, continuation = 1 : i64>} : i72
    llvm.return
  }
}
