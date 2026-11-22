// RUN: talos-opt %s | talos-opt | FileCheck %s
// RUN: talos-opt %s --mlir-print-op-generic | talos-opt | FileCheck %s
// RUN: talos-opt %s --emit-bytecode | talos-opt | FileCheck %s
// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(cse,canonicalize))' | FileCheck %s --check-prefix=KEEP

// A store through a stable handle publishes its transition from its old and
// new planes (IEEE 1800-2023 4.3, 9.4.2), as values or as snapshot buffers; a
// plane without X/Z bits (6.3.1) has no unknown plane. Both forms round-trip
// through custom and generic syntax and bytecode, which keep the operand
// segments, the source owner and `nba_equivalent` in properties.
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
    // CHECK: schedule.transition.handle %[[CONTEXT]], %[[HANDLE]] from %[[OLD]] to %[[NEW]] unknown %[[NEW_UNKNOWN]] : i72
    schedule.transition.handle %context, %handle from %old to %new unknown %new_unknown : i72
    // CHECK: schedule.transition.handle %[[CONTEXT]], %[[HANDLE]] from %[[OLD]] unknown %[[OLD_UNKNOWN]] to %[[NEW]] nba_equivalent : i72
    schedule.transition.handle %context, %handle from %old unknown %old_unknown to %new nba_equivalent : i72
    llvm.return
  }

  // A transition has the unknown memory effects of the runtime call it stands
  // for: two identical transitions are two publications, neither merged nor
  // dropped.
  // KEEP-LABEL: llvm.func @keep(
  // KEEP-COUNT-2: schedule.transition.handle %
  // KEEP-COUNT-2: schedule.transition.handle_bytes %
  // KEEP-NEXT: llvm.return
  llvm.func @keep(%context: !llvm.ptr, %handle: i64, %value: i72, %snapshot: !llvm.ptr) {
    schedule.transition.handle %context, %handle from %value to %value : i72
    schedule.transition.handle %context, %handle from %value to %value : i72
    schedule.transition.handle_bytes %context, %handle from %snapshot to %snapshot {width = 72 : i64}
    schedule.transition.handle_bytes %context, %handle from %snapshot to %snapshot {width = 72 : i64}
    llvm.return
  }
}
