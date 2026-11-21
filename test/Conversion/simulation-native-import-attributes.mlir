// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines --mlir-print-ir-after=prepare-native-fragments -o /dev/null 2>&1 | FileCheck %s

// Native code inside a design imports the module's declaration of each runtime
// entry it uses as an exact copy: the runtime entry, `cold` and every other
// function attribute stay what flattening later finds at module scope. The
// attributes here stand in for the catalog's cold diagnostics and the sampled
// plane's memory effects.
// CHECK-LABEL: simulation.design @imports
// CHECK: llvm.func @talos_rt_v1_native_state_load_plane(!llvm.ptr, !llvm.ptr, i64, i64, i64, i32, i32, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<native_state_load_plane>, no_unwind, passthrough = ["cold"]}
// CHECK-LABEL: simulation.func @read(
// CHECK: schedule.state.load_handle @__talos_state_value
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  llvm.func @talos_rt_v1_native_state_load_plane(!llvm.ptr, !llvm.ptr, i64, i64, i64, i32, i32, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<native_state_load_plane>, no_unwind, passthrough = ["cold"]}
  simulation.design @imports {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "imports.read"
    simulation.func @read(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %ref: !simulation.ref<i8> {simulation.capture_kind = 1 : i32})
        -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %loaded = simulation.ref.load %ref : !simulation.ref<i8> -> i8
      simulation.return %loaded : i8
    }
  }
}
