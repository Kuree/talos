// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines --mlir-print-ir-after=prepare-native-fragments -o %t.mlir 2> %t.fragments
// RUN: FileCheck %s --check-prefix=TYPED < %t.fragments
// RUN: FileCheck %s --check-prefix=CALL --implicit-check-not=schedule.transition.handle < %t.mlir

// A store through a stable handle publishes its transition through the
// runtime (IEEE 1800-2023 4.3, 9.4.2): as a typed handle-addressed transition
// until AOT planning has read it, then as the runtime's signal transition. A
// scalar store publishes its planes as values, which only the runtime call
// passes through temporaries; a value wider than a word publishes the byte
// buffers its store already holds. A two-state value has no X/Z bits (6.3.1)
// and no unknown planes.
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @transitions {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "transitions.scalar"
    simulation.code_unit.decl 2 in 0 function hierarchy "transitions.bulk"
    simulation.code_unit.decl 3 in 0 function hierarchy "transitions.two_state"
    simulation.code_unit.decl 4 in 0 function hierarchy "transitions.held"

    // TYPED-LABEL: simulation.func @scalar(
    // TYPED-SAME: %[[HANDLE:[^:]*]]: i64 {{.*}}, %[[VALUE:[^:]*]]: i8 {{.*}}, %[[UNKNOWN:[^:]*]]: i8
    // TYPED-NOT: lifetime.start
    // TYPED: %[[OLD:.*]] = schedule.state.load_handle @__talos_state_value[%[[HANDLE]]]
    // TYPED-NEXT: %[[OLD_UNKNOWN:.*]] = schedule.state.load_handle @__talos_state_unknown[%[[HANDLE]]]
    // TYPED: %[[NEW:.*]] = schedule.state.load_handle @__talos_state_value[%[[HANDLE]]]
    // TYPED-NEXT: %[[NEW_UNKNOWN:.*]] = schedule.state.load_handle @__talos_state_unknown[%[[HANDLE]]]
    // TYPED-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
    // TYPED-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]]
    // TYPED-NEXT: schedule.transition.handle %[[CONTEXT]], %[[HANDLE]] from %[[OLD]] unknown %[[OLD_UNKNOWN]] to %[[NEW]] unknown %[[NEW_UNKNOWN]] {source_owner = #schedule.source_owner<codeUnit = 1 : i64, continuation = 0 : i64>} : i8
    // TYPED-NOT: lifetime.start
    // TYPED-NOT: llvm.call @talos_rt_v1_scheduler_signal_transition
    // TYPED: simulation.return
    simulation.func @scalar(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %ref: !simulation.ref<!simulation.logic<8>> {simulation.capture_kind = 1 : i32},
        %value: !simulation.logic<8> {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      simulation.ref.store %value to %ref {schedule.eval.source_owner = #schedule.source_owner<codeUnit = 1 : i64, continuation = 0 : i64>} : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      simulation.return
    }

    // TYPED-LABEL: simulation.func @two_state(
    // TYPED-SAME: %[[HANDLE:[^:]*]]: i64
    // TYPED: schedule.transition.handle %{{[^,]*}}, %[[HANDLE]] from %{{[^ ]*}} to %{{[^ ]*}} : i8
    // TYPED: simulation.return
    simulation.func @two_state(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %ref: !simulation.ref<i8> {simulation.capture_kind = 1 : i32},
        %value: i8 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      simulation.ref.store %value to %ref : i8, !simulation.ref<i8>
      simulation.return
    }

    // A clocked kernel's direct store is NBA-equivalent: its transition
    // carries `nba_equivalent`, so AOT planning holds its wakes until the
    // updates of its NBA region are complete (IEEE 1800-2023 4.5, 4.7).
    // TYPED-LABEL: simulation.func @held(
    // TYPED-SAME: %[[HANDLE:[^:]*]]: i64 {{.*}}, %[[VALUE:[^:]*]]: i72 {{.*}}, %[[UNKNOWN:[^:]*]]: i72
    // TYPED: %[[OLD:.*]] = schedule.state.load_handle @__talos_state_value[%[[HANDLE]]]
    // TYPED-NEXT: %[[OLD_UNKNOWN:.*]] = schedule.state.load_handle @__talos_state_unknown[%[[HANDLE]]]
    // TYPED: %[[NEW:.*]] = schedule.state.load_handle @__talos_state_value[%[[HANDLE]]]
    // TYPED-NEXT: %[[NEW_UNKNOWN:.*]] = schedule.state.load_handle @__talos_state_unknown[%[[HANDLE]]]
    // TYPED: schedule.transition.handle %{{[^,]*}}, %[[HANDLE]] from %[[OLD]] unknown %[[OLD_UNKNOWN]] to %[[NEW]] unknown %[[NEW_UNKNOWN]] nba_equivalent : i72
    // TYPED: simulation.return
    simulation.func @held(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %ref: !simulation.ref<!simulation.logic<72>> {simulation.capture_kind = 1 : i32},
        %value: !simulation.logic<72> {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      simulation.ref.store %value to %ref {schedule.eval.nba_equivalent_store} : !simulation.logic<72>, !simulation.ref<!simulation.logic<72>>
      simulation.return
    }

    // TYPED-LABEL: simulation.func @bulk(
    // TYPED-SAME: %[[SOURCE:[^:]*]]: i64 {{.*}}, %[[DESTINATION:[^:]*]]: i64
    // TYPED: schedule.state.load_handle_bytes @__talos_state_value[%[[DESTINATION]]] into %[[OLD:[^ ]*]]
    // TYPED-NEXT: schedule.state.load_handle_bytes @__talos_state_unknown[%[[DESTINATION]]] into %[[OLD_UNKNOWN:[^ ]*]]
    // TYPED: schedule.state.load_handle_bytes @__talos_state_value[%[[DESTINATION]]] into %[[NEW:[^ ]*]]
    // TYPED-NEXT: schedule.state.load_handle_bytes @__talos_state_unknown[%[[DESTINATION]]] into %[[NEW_UNKNOWN:[^ ]*]]
    // TYPED-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
    // TYPED-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]]
    // TYPED-NEXT: schedule.transition.handle_bytes %[[CONTEXT]], %[[DESTINATION]] from %[[OLD]] unknown %[[OLD_UNKNOWN]] to %[[NEW]] unknown %[[NEW_UNKNOWN]] {width = 65 : i64}
    // TYPED-NOT: llvm.call @talos_rt_v1_scheduler_signal_transition
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

// CALL-LABEL: llvm.func @scalar(
// CALL-SAME: %{{[^:]*}}: !llvm.ptr, %[[HANDLE:[^:]*]]: i64
// CALL: llvm.call @talos_rt_v1_scheduler_signal_transition(%{{.*}}, %[[HANDLE]], %{{[^,]*}}, %[[OLD:[^,]*]], %[[OLD_UNKNOWN:[^,]*]], %[[NEW:[^,]*]], %[[NEW_UNKNOWN:[^)]*]])
// CALL-NEXT: llvm.intr.lifetime.end %[[OLD]]
// CALL-NEXT: llvm.intr.lifetime.end %[[OLD_UNKNOWN]]
// CALL-NEXT: llvm.intr.lifetime.end %[[NEW]]
// CALL-NEXT: llvm.intr.lifetime.end %[[NEW_UNKNOWN]]
// CALL-LABEL: llvm.func @two_state(
// CALL: %[[NO_OLD_UNKNOWN:.*]] = llvm.mlir.zero : !llvm.ptr
// CALL: %[[NO_NEW_UNKNOWN:.*]] = llvm.mlir.zero : !llvm.ptr
// CALL-NEXT: llvm.call @talos_rt_v1_scheduler_signal_transition(%{{[^,]*}}, %{{[^,]*}}, %{{[^,]*}}, %{{[^,]*}}, %[[NO_OLD_UNKNOWN]], %{{[^,]*}}, %[[NO_NEW_UNKNOWN]])
// CALL-LABEL: llvm.func @held(
// CALL-SAME: %{{[^:]*}}: !llvm.ptr, %[[HANDLE:[^:]*]]: i64
// CALL: llvm.call @talos_rt_v1_scheduler_signal_transition(%{{[^,]*}}, %[[HANDLE]], %{{.*}}) : (!llvm.ptr, i64, i64, !llvm.ptr, !llvm.ptr, !llvm.ptr, !llvm.ptr) -> (){{$}}
// CALL-LABEL: llvm.func @bulk(
// CALL-SAME: %{{[^:]*}}: !llvm.ptr, %{{[^:]*}}: i64, %[[DESTINATION:[^:]*]]: i64
// CALL: llvm.call @talos_rt_v1_scheduler_signal_transition(%{{.*}}, %[[DESTINATION]], %{{[^,]*}}, %{{[^,]*}}, %{{[^,]*}}, %{{[^,]*}}, %{{[^)]*}})
