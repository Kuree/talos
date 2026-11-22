// RUN: talos-opt %s --test-talos-lower-native-handle-transitions | FileCheck %s
// RUN: talos-opt %s --test-talos-lower-native-handle-transitions='entry=owned actor=7' | FileCheck %s --check-prefix=OWNED
// RUN: talos-opt %s --test-talos-lower-native-handle-transitions='entry=projected actor=9' | FileCheck %s --check-prefix=PROJECTED

// Once AOT planning has read the eval bodies' handle-addressed transitions,
// each one the plan does not publish itself becomes the runtime's signal
// transition on snapshots of its planes (IEEE 1800-2023 4.3, 9.4.2): the
// buffers of the `_bytes` form, or entry-block temporaries holding the planes
// of the value form, live only around the call. A plane without X/Z bits
// (6.3.1) passes no unknown snapshot, the null pointer. The call carries no
// schedule facts.
// A wide publication that AOT planning keeps whole instead calls the
// runtime's owned or projected entry from the actor that executes it, its
// slot an i32 before the handle; the snapshots are the same.
module {
  llvm.func @talos_rt_v1_scheduler_signal_transition(!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
  llvm.func @talos_rt_v1_scheduler_wide_transition_owned(!llvm.ptr, i32, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)
  llvm.func @talos_rt_v1_scheduler_wide_transition_projected(!llvm.ptr, i32, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr)

  // OWNED-LABEL: llvm.func @publish(
  // OWNED-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[OLD:.*]]: !llvm.ptr, %[[OLD_UNKNOWN:.*]]: !llvm.ptr, %[[NEW:.*]]: !llvm.ptr, %[[NEW_UNKNOWN:.*]]: !llvm.ptr)
  // OWNED-NEXT: %[[ACTOR:.*]] = llvm.mlir.constant(7 : i32) : i32
  // OWNED-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(72 : i64) : i64
  // OWNED-NEXT: llvm.call @talos_rt_v1_scheduler_wide_transition_owned(%[[CONTEXT]], %[[ACTOR]], %[[HANDLE]], %[[WIDTH]], %[[OLD]], %[[OLD_UNKNOWN]], %[[NEW]], %[[NEW_UNKNOWN]]) : (!llvm.ptr, i32, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> (){{$}}
  // OWNED-NEXT: %[[ACTOR:.*]] = llvm.mlir.constant(7 : i32) : i32
  // OWNED-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(130 : i64) : i64
  // OWNED-NEXT: %[[NONE:.*]] = llvm.mlir.zero : !llvm.ptr
  // OWNED-NEXT: %[[NO_NEW_UNKNOWN:.*]] = llvm.mlir.zero : !llvm.ptr
  // OWNED-NEXT: llvm.call @talos_rt_v1_scheduler_wide_transition_owned(%[[CONTEXT]], %[[ACTOR]], %[[HANDLE]], %[[WIDTH]], %[[OLD]], %[[NONE]], %[[NEW]], %[[NO_NEW_UNKNOWN]]) : (!llvm.ptr, i32, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> (){{$}}
  // OWNED-NEXT: llvm.return

  // PROJECTED-LABEL: llvm.func @publish(
  // PROJECTED-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[OLD:.*]]: !llvm.ptr, %[[OLD_UNKNOWN:.*]]: !llvm.ptr, %[[NEW:.*]]: !llvm.ptr, %[[NEW_UNKNOWN:.*]]: !llvm.ptr)
  // PROJECTED-NEXT: %[[ACTOR:.*]] = llvm.mlir.constant(9 : i32) : i32
  // PROJECTED-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(72 : i64) : i64
  // PROJECTED-NEXT: llvm.call @talos_rt_v1_scheduler_wide_transition_projected(%[[CONTEXT]], %[[ACTOR]], %[[HANDLE]], %[[WIDTH]], %[[OLD]], %[[OLD_UNKNOWN]], %[[NEW]], %[[NEW_UNKNOWN]]) : (!llvm.ptr, i32, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> (){{$}}
  // PROJECTED-NEXT: %[[ACTOR:.*]] = llvm.mlir.constant(9 : i32) : i32
  // PROJECTED-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(130 : i64) : i64
  // PROJECTED-NEXT: %[[NONE:.*]] = llvm.mlir.zero : !llvm.ptr
  // PROJECTED-NEXT: %[[NO_NEW_UNKNOWN:.*]] = llvm.mlir.zero : !llvm.ptr
  // PROJECTED-NEXT: llvm.call @talos_rt_v1_scheduler_wide_transition_projected(%[[CONTEXT]], %[[ACTOR]], %[[HANDLE]], %[[WIDTH]], %[[OLD]], %[[NONE]], %[[NEW]], %[[NO_NEW_UNKNOWN]]) : (!llvm.ptr, i32, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> (){{$}}
  // PROJECTED-NEXT: llvm.return

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

  // OWNED-LABEL: llvm.func @publish_values(
  // OWNED-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[OLD:.*]]: i72, %[[OLD_UNKNOWN:.*]]: i72, %[[NEW:.*]]: i72)
  // OWNED-COUNT-3: llvm.alloca %{{.*}} x i72
  // OWNED: %[[ACTOR:.*]] = llvm.mlir.constant(7 : i32) : i32
  // OWNED-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(72 : i64) : i64
  // OWNED-NEXT: llvm.intr.lifetime.start %[[OLD_SLOT:[^ ]*]] :
  // OWNED-NEXT: llvm.store %[[OLD]], %[[OLD_SLOT]] {alignment = 1 : i64} : i72, !llvm.ptr
  // OWNED-NEXT: llvm.intr.lifetime.start %[[OLD_UNKNOWN_SLOT:[^ ]*]] :
  // OWNED-NEXT: llvm.store %[[OLD_UNKNOWN]], %[[OLD_UNKNOWN_SLOT]] {alignment = 1 : i64} : i72, !llvm.ptr
  // OWNED-NEXT: llvm.intr.lifetime.start %[[NEW_SLOT:[^ ]*]] :
  // OWNED-NEXT: llvm.store %[[NEW]], %[[NEW_SLOT]] {alignment = 1 : i64} : i72, !llvm.ptr
  // OWNED-NEXT: %[[NO_NEW_UNKNOWN:.*]] = llvm.mlir.zero : !llvm.ptr
  // OWNED-NEXT: llvm.call @talos_rt_v1_scheduler_wide_transition_owned(%[[CONTEXT]], %[[ACTOR]], %[[HANDLE]], %[[WIDTH]], %[[OLD_SLOT]], %[[OLD_UNKNOWN_SLOT]], %[[NEW_SLOT]], %[[NO_NEW_UNKNOWN]]) : (!llvm.ptr, i32, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> (){{$}}
  // OWNED-NEXT: llvm.intr.lifetime.end %[[OLD_SLOT]] :
  // OWNED-NEXT: llvm.intr.lifetime.end %[[OLD_UNKNOWN_SLOT]] :
  // OWNED-NEXT: llvm.intr.lifetime.end %[[NEW_SLOT]] :
  // OWNED-NEXT: llvm.return

  // PROJECTED-LABEL: llvm.func @publish_values(
  // PROJECTED-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %{{.*}}: i72, %{{.*}}: i72, %{{.*}}: i72)
  // PROJECTED: %[[ACTOR:.*]] = llvm.mlir.constant(9 : i32) : i32
  // PROJECTED-NEXT: %[[WIDTH:.*]] = llvm.mlir.constant(72 : i64) : i64
  // PROJECTED: llvm.call @talos_rt_v1_scheduler_wide_transition_projected(%[[CONTEXT]], %[[ACTOR]], %[[HANDLE]], %[[WIDTH]], %{{.*}}) : (!llvm.ptr, i32, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> (){{$}}
  // PROJECTED-NEXT: llvm.intr.lifetime.end
  llvm.func @publish_values(%context: !llvm.ptr, %handle: i64, %old: i72, %old_unknown: i72, %new: i72) {
    schedule.transition.handle %context, %handle from %old unknown %old_unknown to %new nba_equivalent {source_owner = #schedule.source_owner<codeUnit = 3 : i64, continuation = 1 : i64>} : i72
    llvm.return
  }
}
