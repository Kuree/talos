// RUN: talos-opt %s | talos-opt | FileCheck %s

// A store through a stable handle publishes its transition from its old and
// new planes (IEEE 1800-2023 4.3, 9.4.2), as values or as snapshot buffers; a
// plane without X/Z bits (6.3.1) has no unknown plane.
module {
  // CHECK-LABEL: llvm.func @publish(
  // CHECK-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[OLD:.*]]: !llvm.ptr, %[[OLD_UNKNOWN:.*]]: !llvm.ptr, %[[NEW:.*]]: !llvm.ptr, %[[NEW_UNKNOWN:.*]]: !llvm.ptr)
  llvm.func @publish(%context: !llvm.ptr, %handle: i64, %old: !llvm.ptr, %old_unknown: !llvm.ptr, %new: !llvm.ptr, %new_unknown: !llvm.ptr) {
    // CHECK: schedule.transition.handle_bytes %[[CONTEXT]], %[[HANDLE]] from %[[OLD]] unknown %[[OLD_UNKNOWN]] to %[[NEW]] unknown %[[NEW_UNKNOWN]] nba_equivalent {source_owner = #schedule.source_owner<codeUnit = 3 : i64, continuation = 1 : i64>, width = 72 : i64}
    schedule.transition.handle_bytes %context, %handle from %old unknown %old_unknown to %new unknown %new_unknown nba_equivalent {source_owner = #schedule.source_owner<codeUnit = 3 : i64, continuation = 1 : i64>, width = 72 : i64}
    // CHECK: schedule.transition.handle_bytes %[[CONTEXT]], %[[HANDLE]] from %[[OLD]] to %[[NEW]] {width = 130 : i64}
    schedule.transition.handle_bytes %context, %handle from %old to %new {width = 130 : i64}
    // CHECK: schedule.transition.handle_bytes %[[CONTEXT]], %[[HANDLE]] from %[[OLD]] to %[[NEW]] unknown %[[NEW_UNKNOWN]] {width = 65 : i64}
    schedule.transition.handle_bytes %context, %handle from %old to %new unknown %new_unknown {width = 65 : i64}
    // CHECK: schedule.transition.handle_bytes %[[CONTEXT]], %[[HANDLE]] from %[[OLD]] unknown %[[OLD_UNKNOWN]] to %[[NEW]] {width = 8 : i64}
    schedule.transition.handle_bytes %context, %handle from %old unknown %old_unknown to %new {width = 8 : i64}
    llvm.return
  }

  // CHECK-LABEL: llvm.func @publish_values(
  // CHECK-SAME: %[[CONTEXT:.*]]: !llvm.ptr, %[[HANDLE:.*]]: i64, %[[OLD:.*]]: i72, %[[OLD_UNKNOWN:.*]]: i72, %[[NEW:.*]]: i72, %[[NEW_UNKNOWN:.*]]: i72)
  llvm.func @publish_values(%context: !llvm.ptr, %handle: i64, %old: i72, %old_unknown: i72, %new: i72, %new_unknown: i72) {
    // CHECK: schedule.transition.handle %[[CONTEXT]], %[[HANDLE]] from %[[OLD]] unknown %[[OLD_UNKNOWN]] to %[[NEW]] unknown %[[NEW_UNKNOWN]] nba_equivalent {source_owner = #schedule.source_owner<codeUnit = 3 : i64, continuation = 1 : i64>} : i72
    schedule.transition.handle %context, %handle from %old unknown %old_unknown to %new unknown %new_unknown nba_equivalent {source_owner = #schedule.source_owner<codeUnit = 3 : i64, continuation = 1 : i64>} : i72
    // CHECK: schedule.transition.handle %[[CONTEXT]], %[[HANDLE]] from %[[OLD]] to %[[NEW]] : i72
    schedule.transition.handle %context, %handle from %old to %new : i72
    llvm.return
  }
}
