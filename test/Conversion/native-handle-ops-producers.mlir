// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines --mlir-print-ir-after=prepare-native-fragments -o /dev/null 2>&1 | FileCheck %s

// A dynamic selection, of a packed view or an array element, offsets its
// handle and guards the result with the selection's validity: an index is
// invalid when it is out of range or has X/Z bits, and an invalid handle
// selects nothing (IEEE 1800-2023 7.4.5, 11.5.1). A two-bit view of a four-bit input is valid while it overlaps the
// input, from start -1 to 3, so that a partly out-of-range write keeps its
// in-range bits. A selection proved valid in a static state root has no guard;
// its offset carries the proof.
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @selections {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "selections.known"
    simulation.code_unit.decl 2 in 0 function hierarchy "selections.unknown"
    simulation.code_unit.decl 3 in 0 function hierarchy "selections.proved"
    simulation.code_unit.decl 4 in 0 function hierarchy "selections.element"
    simulation.storage.decl 0 in 0 : !simulation.logic<8> design

    // CHECK-LABEL: simulation.func @known(
    // CHECK-SAME: %{{[^:]*}}: !simulation.context {simulation.capture_kind = 0 : i32}, %[[HANDLE:[^:]*]]: i64 {simulation.capture_kind = 2 : i32}, %[[LOW:[^:]*]]: i64 {simulation.capture_kind = 2 : i32})
    // CHECK-NEXT: %[[REPRESENTABLE:.*]] = arith.constant true
    // CHECK-NEXT: %[[FIRST:.*]] = arith.constant -1 : i64
    // CHECK-NEXT: %[[LAST:.*]] = arith.constant 3 : i64
    // CHECK-NEXT: %[[FROM_FIRST:.*]] = arith.cmpi sge, %[[LOW]], %[[FIRST]] : i64
    // CHECK-NEXT: %[[TO_LAST:.*]] = arith.cmpi sle, %[[LOW]], %[[LAST]] : i64
    // CHECK-NEXT: %[[OVERLAPS:.*]] = arith.andi %[[FROM_FIRST]], %[[TO_LAST]] : i1
    // CHECK-NEXT: %[[IN_RANGE:.*]] = arith.andi %[[OVERLAPS]], %[[REPRESENTABLE]] : i1
    // CHECK-NEXT: %[[INVALID:.*]] = arith.constant -1 : i64
    // CHECK-NEXT: %[[LIVE:.*]] = arith.cmpi ne, %[[HANDLE]], %[[INVALID]] : i64
    // CHECK-NEXT: %[[VALID:.*]] = arith.andi %[[IN_RANGE]], %[[LIVE]] : i1
    // CHECK-NEXT: %[[OFFSET:.*]] = schedule.handle.offset %[[HANDLE]], %[[LOW]]{{$}}
    // CHECK-NEXT: %[[SELECTED:.*]] = schedule.handle.guard %[[VALID]], %[[OFFSET]]{{$}}
    // CHECK: schedule.state.store_handle %{{.*}}, @__talos_state_value[%[[SELECTED]]]
    simulation.func @known(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %input: !simulation.ref<!simulation.logic<4>>
            {simulation.capture_kind = 1 : i32},
        %low: i64 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %view = simulation.ref.dyn_extract %input from %low :
          (!simulation.ref<!simulation.logic<4>>, i64) ->
          !simulation.ref<!simulation.logic<2>>
      %value = simulation.logic.constant 1 : i2, 0 : i2 : !simulation.logic<2>
      simulation.ref.store %value to %view :
          !simulation.logic<2>, !simulation.ref<!simulation.logic<2>>
      simulation.return
    }

    // An index with X/Z bits is invalid too.
    // CHECK-LABEL: simulation.func @unknown(
    // CHECK-SAME: %[[HANDLE:[^:]*]]: i64 {simulation.capture_kind = 2 : i32}, %[[LOW:[^:]*]]: i64 {simulation.capture_kind = 2 : i32}, %[[LOW_UNKNOWN:[^:]*]]: i64 {simulation.capture_kind = 2 : i32})
    // CHECK: %[[LIVE:.*]] = arith.cmpi ne, %[[HANDLE]], %{{.*}} : i64
    // CHECK-NEXT: %[[IN_RANGE:.*]] = arith.andi %{{.*}}, %[[LIVE]] : i1
    // CHECK-NEXT: %[[NONE:.*]] = arith.constant 0 : i64
    // CHECK-NEXT: %[[KNOWN:.*]] = arith.cmpi eq, %[[LOW_UNKNOWN]], %[[NONE]] : i64
    // CHECK-NEXT: %[[VALID:.*]] = arith.andi %[[IN_RANGE]], %[[KNOWN]] : i1
    // CHECK-NEXT: %[[OFFSET:.*]] = schedule.handle.offset %[[HANDLE]], %[[LOW]]{{$}}
    // CHECK-NEXT: %[[SELECTED:.*]] = schedule.handle.guard %[[VALID]], %[[OFFSET]]{{$}}
    // CHECK: schedule.state.store_handle %{{.*}}, @__talos_state_value[%[[SELECTED]]]
    simulation.func @unknown(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %input: !simulation.ref<!simulation.logic<4>>
            {simulation.capture_kind = 1 : i32},
        %low: !simulation.logic<64> {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %view = simulation.ref.dyn_extract %input from %low :
          (!simulation.ref<!simulation.logic<4>>, !simulation.logic<64>) ->
          !simulation.ref<!simulation.logic<2>>
      %value = simulation.logic.constant 1 : i2, 0 : i2 : !simulation.logic<2>
      simulation.ref.store %value to %view :
          !simulation.logic<2>, !simulation.ref<!simulation.logic<2>>
      simulation.return
    }

    // A known two-bit index selects within the eight-bit static state object
    // 1: the selection is valid, so its offset is proved in bounds and has no
    // guard.
    // CHECK-LABEL: simulation.func @proved(
    // CHECK-SAME: %[[LOW:[^:]*]]: i64 {simulation.capture_kind = 2 : i32})
    // CHECK-NEXT: %[[ROOT:.*]] = arith.constant 4611686022722355200 : i64
    // CHECK-NEXT: %[[MASK:.*]] = arith.constant 3 : i64
    // CHECK-NEXT: %[[INDEX:.*]] = arith.andi %[[LOW]], %[[MASK]] : i64
    // CHECK-NOT: schedule.handle.guard
    // CHECK: %[[SELECTED:.*]] = schedule.handle.offset %[[ROOT]], %[[INDEX]] in_bounds{{$}}
    // CHECK-NOT: schedule.handle.guard
    // CHECK: schedule.state.store_handle %{{.*}}, @__talos_state_value[%[[SELECTED]]]
    simulation.func @proved(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %low: i64 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %state = simulation.context.storage %ctx[0] :
          !simulation.ref<!simulation.logic<8>>
      %three = arith.constant 3 : i64
      %index = arith.andi %low, %three : i64
      %view = simulation.ref.dyn_extract %state from %index :
          (!simulation.ref<!simulation.logic<8>>, i64) ->
          !simulation.ref<!simulation.logic<2>>
      %value = simulation.logic.constant 1 : i2, 0 : i2 : !simulation.logic<2>
      simulation.ref.store %value to %view :
          !simulation.logic<2>, !simulation.ref<!simulation.logic<2>>
      simulation.return
    }

    // An element of an unpacked array [0:3] of bytes is valid for an index in
    // [0, 3]; its offset is the index times the element's eight bits.
    // CHECK-LABEL: simulation.func @element(
    // CHECK-SAME: %[[HANDLE:[^:]*]]: i64 {simulation.capture_kind = 2 : i32}, %[[INDEX:[^:]*]]: i64 {simulation.capture_kind = 2 : i32})
    // CHECK-NEXT: %[[REPRESENTABLE:.*]] = arith.constant true
    // CHECK-NEXT: %[[LEFT:.*]] = arith.constant 0 : i64
    // CHECK-NEXT: %[[RIGHT:.*]] = arith.constant 3 : i64
    // CHECK-NEXT: %[[FROM_LEFT:.*]] = arith.cmpi sge, %[[INDEX]], %[[LEFT]] : i64
    // CHECK-NEXT: %[[TO_RIGHT:.*]] = arith.cmpi sle, %[[INDEX]], %[[RIGHT]] : i64
    // CHECK-NEXT: %[[IN_ARRAY:.*]] = arith.andi %[[FROM_LEFT]], %[[TO_RIGHT]] : i1
    // CHECK-NEXT: %[[IN_RANGE:.*]] = arith.andi %[[IN_ARRAY]], %[[REPRESENTABLE]] : i1
    // CHECK-NEXT: %[[INVALID:.*]] = arith.constant -1 : i64
    // CHECK-NEXT: %[[LIVE:.*]] = arith.cmpi ne, %[[HANDLE]], %[[INVALID]] : i64
    // CHECK-NEXT: %[[VALID:.*]] = arith.andi %[[IN_RANGE]], %[[LIVE]] : i1
    // CHECK-NEXT: %[[STRIDE:.*]] = arith.constant 8 : i64
    // CHECK-NEXT: %[[BITS:.*]] = arith.muli %[[INDEX]], %[[STRIDE]] : i64
    // CHECK-NEXT: %[[OFFSET:.*]] = schedule.handle.offset %[[HANDLE]], %[[BITS]]{{$}}
    // CHECK-NEXT: %[[SELECTED:.*]] = schedule.handle.guard %[[VALID]], %[[OFFSET]]{{$}}
    // CHECK: schedule.state.store_handle %{{.*}}, @__talos_state_value[%[[SELECTED]]]
    simulation.func @element(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %array: !simulation.ref<!simulation.unpacked_array<0 : 3 x !simulation.logic<8>>>
            {simulation.capture_kind = 1 : i32},
        %index: i64 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %element = simulation.ref.array_element %array[%index] :
          (!simulation.ref<!simulation.unpacked_array<0 : 3 x !simulation.logic<8>>>, i64) ->
          !simulation.ref<!simulation.logic<8>>
      %value = simulation.logic.constant 1 : i8, 0 : i8 : !simulation.logic<8>
      simulation.ref.store %value to %element :
          !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }
  }
}
