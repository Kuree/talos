// RUN: talos-opt %s | talos-opt | FileCheck %s --check-prefix=ROUND
// RUN: talos-opt %s --mlir-print-op-generic | talos-opt | FileCheck %s --check-prefix=ROUND
// RUN: talos-opt %s --emit-bytecode | talos-opt | FileCheck %s --check-prefix=ROUND
// RUN: talos-opt %s --pass-pipeline='builtin.module(llvm.func(cse,canonicalize))' | FileCheck %s --check-prefix=KEEP

module {
  llvm.mlir.global internal @__talos_state_value(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>
  llvm.mlir.global internal @__talos_state_unknown(dense<0> : tensor<16xi8>) : !llvm.array<16 x i8>

  // Accesses of the state a stable handle names round-trip through custom and
  // generic syntax and bytecode, a store with and without `continuous`.
  // ROUND-LABEL: llvm.func @round(
  // ROUND-SAME: %[[HANDLE:.*]]: i64, %[[BUFFER:.*]]: !llvm.ptr, %[[CHANGED:.*]]: !llvm.ptr)
  // ROUND: schedule.state.load_handle @__talos_state_unknown[%[[HANDLE]]] into %[[BUFFER]] {state_bits = 128 : i64, width = 7 : i64}
  // ROUND: schedule.state.store_handle %[[BUFFER]], @__talos_state_value[%[[HANDLE]]] changed %[[CHANGED]] {state_bits = 128 : i64, width = 200 : i64}
  // ROUND: schedule.state.store_handle %[[BUFFER]], @__talos_state_unknown[%[[HANDLE]]] changed %[[CHANGED]] continuous {state_bits = 128 : i64, width = 1 : i64}
  llvm.func @round(%handle: i64, %buffer: !llvm.ptr, %changed: !llvm.ptr) {
    schedule.state.load_handle @__talos_state_unknown[%handle] into %buffer {state_bits = 128 : i64, width = 7 : i64}
    schedule.state.store_handle %buffer, @__talos_state_value[%handle] changed %changed {state_bits = 128 : i64, width = 200 : i64}
    schedule.state.store_handle %buffer, @__talos_state_unknown[%handle] changed %changed continuous {state_bits = 128 : i64, width = 1 : i64}
    llvm.return
  }

  // A frame store writes at most 64 bits, with the X/Z bits of a four-state
  // destination when it has any; a DPI export thunk reads an automatic
  // variable for a context and gets the runtime status.
  // ROUND-LABEL: llvm.func @frame(
  // ROUND-SAME: %[[HANDLE:.*]]: i64, %[[VALUE:.*]]: i7, %[[UNKNOWN:.*]]: i7, %[[CONTEXT:.*]]: !llvm.ptr, %[[BUFFER:.*]]: !llvm.ptr)
  // ROUND: schedule.state.frame_store %[[VALUE]], %[[UNKNOWN]] to %[[HANDLE]] four_state continuous {state_bits = 128 : i64} : i7, i7
  // ROUND: schedule.state.frame_store %[[VALUE]] to %[[HANDLE]] four_state {state_bits = 128 : i64} : i7
  // ROUND: schedule.state.frame_store %[[VALUE]] to %[[HANDLE]] {state_bits = 128 : i64} : i7
  // ROUND: %{{.*}} = schedule.state.load_automatic %[[CONTEXT]], %[[HANDLE]] into %[[BUFFER]] unknown {width = 65 : i64}
  llvm.func @frame(%handle: i64, %value: i7, %unknown: i7, %context: !llvm.ptr, %buffer: !llvm.ptr) -> i32 {
    schedule.state.frame_store %value, %unknown to %handle four_state continuous {state_bits = 128 : i64} : i7, i7
    schedule.state.frame_store %value to %handle four_state {state_bits = 128 : i64} : i7
    schedule.state.frame_store %value to %handle {state_bits = 128 : i64} : i7
    %status = schedule.state.load_automatic %context, %handle into %buffer unknown {width = 65 : i64}
    llvm.return %status : i32
  }

  // Each access has the unknown memory effects of the runtime call it stands
  // for: two identical accesses are not merged, and an access whose buffer
  // or status nobody reads stays.
  // KEEP-LABEL: llvm.func @keep(
  // KEEP-COUNT-2: schedule.state.load_handle @__talos_state_value
  // KEEP: schedule.state.store_handle
  // KEEP-COUNT-2: schedule.state.frame_store
  // KEEP-COUNT-2: schedule.state.load_automatic
  // KEEP: llvm.return
  llvm.func @keep(%handle: i64, %buffer: !llvm.ptr, %changed: !llvm.ptr, %value: i8, %context: !llvm.ptr) {
    schedule.state.load_handle @__talos_state_value[%handle] into %buffer {state_bits = 128 : i64, width = 8 : i64}
    schedule.state.load_handle @__talos_state_value[%handle] into %buffer {state_bits = 128 : i64, width = 8 : i64}
    schedule.state.store_handle %buffer, @__talos_state_value[%handle] changed %changed {state_bits = 128 : i64, width = 8 : i64}
    schedule.state.frame_store %value to %handle {state_bits = 128 : i64} : i8
    schedule.state.frame_store %value to %handle {state_bits = 128 : i64} : i8
    %unused = schedule.state.load_automatic %context, %handle into %buffer {width = 8 : i64}
    %again = schedule.state.load_automatic %context, %handle into %buffer {width = 8 : i64}
    llvm.return
  }
}
