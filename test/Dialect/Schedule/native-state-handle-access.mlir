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

  // Each access has the unknown memory effects of the runtime call it stands
  // for: two identical reads are not merged, and an access whose buffer
  // nobody reads stays.
  // KEEP-LABEL: llvm.func @keep(
  // KEEP-COUNT-2: schedule.state.load_handle @__talos_state_value
  // KEEP: schedule.state.store_handle
  // KEEP: llvm.return
  llvm.func @keep(%handle: i64, %buffer: !llvm.ptr, %changed: !llvm.ptr) {
    schedule.state.load_handle @__talos_state_value[%handle] into %buffer {state_bits = 128 : i64, width = 8 : i64}
    schedule.state.load_handle @__talos_state_value[%handle] into %buffer {state_bits = 128 : i64, width = 8 : i64}
    schedule.state.store_handle %buffer, @__talos_state_value[%handle] changed %changed {state_bits = 128 : i64, width = 8 : i64}
    llvm.return
  }
}
