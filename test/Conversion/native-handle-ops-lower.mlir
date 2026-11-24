// RUN: talos-opt %s --test-talos-lower-native-handle-ops | FileCheck %s

// Once AOT planning has read a selection, an offset becomes the runtime's
// handle offset, and one proved in bounds the plain sum: its offset field
// neither carries nor borrows. A guard becomes a select of the invalid handle
// (IEEE 1800-2023 7.4.5, 11.5.1). The order of the selection is kept.
// Handle operations read and write no state, so first an offset recomputing
// a dominating one takes its handle, offsets by zero and proved chains fold,
// and unused ones go away: none of them reaches the runtime.
module {
  llvm.func @talos_rt_v1_native_handle_offset(i64, i64) -> i64
  llvm.func @use(i64, i64, i64)

  // A guarded handle may be invalid, so an offset of it is not proved in
  // bounds: the runtime offsets it, and keeps the invalid handle.
  // CHECK-LABEL: llvm.func @chain(
  // CHECK-SAME: %[[ROOT:.*]]: i64, %[[INDEX:.*]]: i64, %[[VALID:.*]]: i1)
  // CHECK-NEXT: %[[ELEMENT:.*]] = llvm.call @talos_rt_v1_native_handle_offset(%[[ROOT]], %[[INDEX]]) : (i64, i64) -> i64
  // CHECK-NEXT: %[[INVALID:.*]] = arith.constant -1 : i64
  // CHECK-NEXT: %[[GUARDED:.*]] = arith.select %[[VALID]], %[[ELEMENT]], %[[INVALID]] : i64
  // CHECK-NEXT: %[[FIELD:.*]] = llvm.call @talos_rt_v1_native_handle_offset(%[[GUARDED]], %[[INDEX]]) : (i64, i64) -> i64
  // CHECK-NEXT: llvm.return %[[FIELD]]
  llvm.func @chain(%root: i64, %index: i64, %valid: i1) -> i64 {
    %element = schedule.handle.offset %root, %index
    %guarded = schedule.handle.guard %valid, %element
    %field = schedule.handle.offset %guarded, %index
    llvm.return %field : i64
  }

  // A frame handle's validity compares the handle with the invalid handle; its
  // select takes that same constant.
  // CHECK-LABEL: llvm.func @frame(
  // CHECK-SAME: %[[HANDLE:.*]]: i64, %[[AMOUNT:.*]]: i64)
  // CHECK-NEXT: %[[INVALID:.*]] = llvm.mlir.constant(-1 : i64) : i64
  // CHECK-NEXT: %[[VALID:.*]] = arith.cmpi ne, %[[HANDLE]], %[[INVALID]] : i64
  // CHECK-NEXT: %[[SUM:.*]] = arith.addi %[[HANDLE]], %[[AMOUNT]] : i64
  // CHECK-NEXT: %[[SELECTED:.*]] = arith.select %[[VALID]], %[[SUM]], %[[INVALID]] : i64
  // CHECK-NEXT: llvm.return %[[SELECTED]]
  llvm.func @frame(%handle: i64, %amount: i64) -> i64 {
    %invalid = llvm.mlir.constant(-1 : i64) : i64
    %valid = arith.cmpi ne, %handle, %invalid : i64
    %sum = arith.addi %handle, %amount : i64
    %selected = schedule.handle.guard %valid, %sum
    llvm.return %selected : i64
  }

  // The dominated offset takes the dominating one's handle, proved in bounds
  // or not, while an offset on another path keeps its own call. An offset by
  // zero is its guarded handle, and a proved chain is one sum.
  // CHECK-LABEL: llvm.func @reuse(
  // CHECK-SAME: %[[ROOT:.*]]: i64, %[[INDEX:.*]]: i64, %[[VALID:.*]]: i1, %[[TAKEN:.*]]: i1)
  // CHECK: %[[TWO:.*]] = arith.constant 2 : i64
  // CHECK-NEXT: llvm.cond_br %[[TAKEN]], ^[[THEN:.*]], ^[[ELSE:.*]]
  // CHECK: ^[[THEN]]:
  // CHECK-NEXT: %[[ELEMENT:.*]] = llvm.call @talos_rt_v1_native_handle_offset(%[[ROOT]], %[[INDEX]]) : (i64, i64) -> i64
  // CHECK-NEXT: %[[INVALID:.*]] = arith.constant -1 : i64
  // CHECK-NEXT: %[[GUARDED:.*]] = arith.select %[[VALID]], %[[ELEMENT]], %[[INVALID]] : i64
  // CHECK-NEXT: %[[SUM:.*]] = arith.addi %[[INDEX]], %[[TWO]] : i64
  // CHECK-NEXT: %[[CHAIN:.*]] = llvm.add %[[ROOT]], %[[SUM]] : i64
  // CHECK-NEXT: llvm.call @use(%[[ELEMENT]], %[[GUARDED]], %[[CHAIN]])
  // CHECK: ^[[ELSE]]:
  // CHECK-NEXT: %[[OTHER:.*]] = llvm.call @talos_rt_v1_native_handle_offset(%[[ROOT]], %[[INDEX]]) : (i64, i64) -> i64
  // CHECK-NEXT: llvm.call @use(%[[OTHER]], %[[OTHER]], %[[OTHER]])
  llvm.func @reuse(%root: i64, %index: i64, %valid: i1, %taken: i1) {
    %zero = arith.constant 0 : i64
    %two = arith.constant 2 : i64
    llvm.cond_br %taken, ^then, ^else
  ^then:
    %element = schedule.handle.offset %root, %index
    %guarded = schedule.handle.guard %valid, %element
    %again = schedule.handle.offset %root, %index in_bounds
    %same = schedule.handle.offset %guarded, %zero
    %first = schedule.handle.offset %root, %two in_bounds
    %chain = schedule.handle.offset %first, %index in_bounds
    llvm.call @use(%again, %same, %chain) : (i64, i64, i64) -> ()
    llvm.return
  ^else:
    %other = schedule.handle.offset %root, %index
    llvm.call @use(%other, %other, %other) : (i64, i64, i64) -> ()
    llvm.return
  }

  // An offset not proved in bounds takes the sum of a dominating proved one:
  // that one ran on the same operands, which therefore satisfy its proof. It
  // is not speculatable (native-handle-ops-speculation.mlir), so no rewrite
  // has moved it above the guards its proof depends on.
  // CHECK-LABEL: llvm.func @proved_first(
  // CHECK-SAME: %[[ROOT:.*]]: i64, %[[INDEX:.*]]: i64)
  // CHECK-NEXT: %[[SUM:.*]] = llvm.add %[[ROOT]], %[[INDEX]] : i64
  // CHECK-NEXT: llvm.call @use(%[[SUM]], %[[SUM]], %[[SUM]])
  // CHECK-NEXT: llvm.return
  llvm.func @proved_first(%root: i64, %index: i64) {
    %proved = schedule.handle.offset %root, %index in_bounds
    %unproved = schedule.handle.offset %root, %index
    llvm.call @use(%proved, %unproved, %unproved) : (i64, i64, i64) -> ()
    llvm.return
  }

  // Unused handle operations, and the offsets only they used, go away.
  // CHECK-LABEL: llvm.func @unused(
  // CHECK-NEXT: llvm.return
  llvm.func @unused(%root: i64, %index: i64, %valid: i1) {
    %element = schedule.handle.offset %root, %index
    %guarded = schedule.handle.guard %valid, %element
    %field = schedule.handle.offset %guarded, %index
    %proved = schedule.handle.offset %root, %index in_bounds
    %member = schedule.handle.offset %proved, %index in_bounds
    llvm.return
  }

  // Preserve the tagged object through a dynamic field selection. A second
  // displacement cannot turn an overflowing first selection into a valid one.
  // CHECK-LABEL: llvm.func @tagged_chain(
  // CHECK: llvm.trunc
  // CHECK: arith.cmpi eq
  // CHECK: arith.select
  // CHECK-NOT: llvm.call
  // CHECK: llvm.trunc
  // CHECK: arith.cmpi ne
  // CHECK: arith.select
  // CHECK-NOT: llvm.call
  // CHECK: llvm.return
  llvm.func @tagged_chain(%first: i64, %second: i64) -> i64 {
    %root = arith.constant 4611686027017322496 : i64
    %field = schedule.handle.offset %root, %first
    %nested = schedule.handle.offset %field, %second
    llvm.return %nested : i64
  }
}
