// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines --mlir-print-ir-after=prepare-native-fragments -o %t.mlir 2> %t.fragments
// RUN: FileCheck %s --check-prefix=TYPED < %t.fragments
// RUN: FileCheck %s --check-prefix=CALL < %t.mlir

// A reference argument holds a stable handle, so native lowering accesses its
// state through the runtime: as typed handle-addressed accesses until AOT
// planning has read them, then as the runtime calls. A scalar access moves its
// plane as an SSA value, which only the runtime call passes through a
// temporary; a value wider than a word moves it through a byte buffer. A store
// reports whether it changed the state (IEEE 1800-2023 9.4.2); a continuous
// store's contribution is kept for a release (10.6.2).
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @handles {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "handles.scalar"
    simulation.code_unit.decl 2 in 0 function hierarchy "handles.bulk"

    // TYPED-LABEL: simulation.func @scalar(
    // TYPED-SAME: %[[CTX:[^:]*]]: !simulation.context {{.*}}, %[[HANDLE:[^:]*]]: i64 {{.*}}, %[[VALUE:[^:]*]]: i8 {{.*}}, %[[UNKNOWN:[^:]*]]: i8
    // TYPED-NOT: lifetime.start
    // TYPED: %[[LOADED:.*]] = schedule.state.load_handle @__talos_state_value[%[[HANDLE]]] {state_bits = 8 : i64} : i8
    // TYPED-NEXT: %[[LOADED_UNKNOWN:.*]] = schedule.state.load_handle @__talos_state_unknown[%[[HANDLE]]] {state_bits = 8 : i64} : i8
    // TYPED-NOT: lifetime.start
    // TYPED: %[[CHANGED:.*]] = schedule.state.store_handle %[[VALUE]], @__talos_state_value[%[[HANDLE]]] continuous {state_bits = 8 : i64} : i8
    // TYPED-NEXT: arith.select %[[CHANGED]], %[[VALUE]],
    // TYPED-NEXT: schedule.state.store_handle %[[UNKNOWN]], @__talos_state_unknown[%[[HANDLE]]] continuous {state_bits = 8 : i64} : i8
    // TYPED-NOT: llvm.call @talos_rt_v1_native_state_{{load|store}}
    // TYPED: simulation.return %[[LOADED]], %[[LOADED_UNKNOWN]]
    simulation.func @scalar(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %ref: !simulation.ref<!simulation.logic<8>> {simulation.capture_kind = 1 : i32},
        %value: !simulation.logic<8> {simulation.capture_kind = 2 : i32})
        -> !simulation.logic<8>
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %loaded = simulation.ref.load %ref : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.ref.store %value to %ref {simulation.continuous_store} : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return %loaded : !simulation.logic<8>
    }

    // TYPED-LABEL: simulation.func @bulk(
    // TYPED-SAME: %[[SOURCE:[^:]*]]: i64 {{.*}}, %[[DESTINATION:[^:]*]]: i64
    // TYPED: schedule.state.load_handle_bytes @__talos_state_value[%[[SOURCE]]] into %[[VALUE:[^ ]*]] {state_bits = 8 : i64, width = 65 : i64}
    // TYPED-NEXT: schedule.state.load_handle_bytes @__talos_state_unknown[%[[SOURCE]]] into %[[UNKNOWN:[^ ]*]] {state_bits = 8 : i64, width = 65 : i64}
    // TYPED: schedule.state.store_handle_bytes %[[VALUE]], @__talos_state_value[%[[DESTINATION]]] changed %[[CHANGED:[^ ]*]] {state_bits = 8 : i64, width = 65 : i64}
    // TYPED-NEXT: schedule.state.store_handle_bytes %[[UNKNOWN]], @__talos_state_unknown[%[[DESTINATION]]] changed %[[CHANGED]] {state_bits = 8 : i64, width = 65 : i64}
    // TYPED-NOT: llvm.call @talos_rt_v1_native_state_{{load|store}}
    // TYPED: simulation.return
    simulation.func @bulk(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %source: !simulation.ref<!simulation.logic<65>> {simulation.capture_kind = 1 : i32},
        %destination: !simulation.ref<!simulation.logic<65>> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %value = simulation.ref.load %source : !simulation.ref<!simulation.logic<65>> -> !simulation.logic<65>
      simulation.ref.store %value to %destination : !simulation.logic<65>, !simulation.ref<!simulation.logic<65>>
      simulation.return
    }
  }
}

// CALL-NOT: schedule.state.load_handle
// CALL-NOT: schedule.state.store_handle
// CALL-LABEL: llvm.func @scalar(
// CALL: llvm.intr.lifetime.start %[[OUT:.*]] : !llvm.ptr
// CALL: llvm.call @talos_rt_v1_native_state_load_plane({{.*}}, %[[OUT]])
// CALL-NEXT: llvm.load %[[OUT]] {alignment = 1 : i64} : !llvm.ptr -> i8
// CALL-NEXT: llvm.intr.lifetime.end %[[OUT]]
// CALL: llvm.call @talos_rt_v1_native_state_store_continuous_plane(
// CALL-LABEL: llvm.func @bulk(
// CALL: llvm.call @talos_rt_v1_native_state_load_plane(
// CALL: llvm.call @talos_rt_v1_native_state_store_plane(
