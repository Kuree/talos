// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=ALL < %t.mlir

// Lowering declares every runtime entry from its catalog row: the row's
// prototype and its native.runtime_entry. Each declaration goes to the start
// of the module, so the module lists them in reverse order of first
// declaration; the eager runtime ABI list comes first, in its own order.
// CHECK: llvm.func @talos_rt_v1_scheduler_run_aot(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_run_aot>}
// CHECK-NEXT: llvm.func @talos_rt_v1_scheduler_install_aot(!llvm.ptr, !llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_install_aot>}
// CHECK-NEXT: llvm.func @talos_rt_v1_scheduler_report_status(!llvm.ptr, i32) attributes {native.runtime_entry = #native.runtime_entry<scheduler_report_status>}
// CHECK-NEXT: llvm.func @talos_rt_v1_scheduler_run(!llvm.ptr) -> i32 attributes {native.runtime_entry = #native.runtime_entry<scheduler_run>}
// CHECK: llvm.func @talos_rt_v1_scheduler_signal_transition(
// CHECK-NEXT: llvm.func @talos_rt_v1_scheduler_signal(!llvm.ptr, i64, i64, i32) attributes {native.runtime_entry = #native.runtime_entry<scheduler_signal>}
// CHECK-NEXT: llvm.func @talos_rt_v1_strength_resolve_kind(i16, i16, i32) -> i16 attributes {native.runtime_entry = #native.runtime_entry<strength_resolve_kind>}
// CHECK-NEXT: llvm.func @talos_rt_v1_strength_resolve(i16, i16) -> i16 attributes {native.runtime_entry = #native.runtime_entry<strength_resolve>}
// CHECK-NOT: llvm.func @talos_rt_

// No declaration lacks its entry, and none of these entries is cold.
// ALL-NOT: llvm.func @talos_rt_{{[a-z0-9_]+}}({{[^)]*}}){{( -> [^ ]+)?$}}
// ALL-NOT: passthrough = ["cold"]

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @design attributes {
    compute_graph = #schedule.graph<
      version = 1, vpi = full, workers = 1,
      nodes = [#schedule.fragment<id = 0, function = @__talos_root, block = 0, region = active, action = terminate, tier = native, cost = 1, lane = 0, twoState = true, effects = []>],
      edges = [],
      regions = [
        #schedule.region<kind = active, groups = [#schedule.group<fragments = [0], schedule = acyclic, feedback = []>]>,
        #schedule.region<kind = nba, groups = []>,
        #schedule.region<kind = observed, groups = []>,
        #schedule.region<kind = reactive, groups = []>,
        #schedule.region<kind = postponed, groups = []>
      ]>,
    time_precision_fs = 1000000 : i64
  } {
    simulation.scope.decl 0 hierarchy "\\$root " debug "$root" {
      dpi_precision_femtoseconds = 1000000 : i64,
      dpi_unit_femtoseconds = 1000000 : i64
    }
    simulation.code_unit.decl 832639515527371617 in 0 root_initializer hierarchy "__talos_root" debug "root initializer"
    simulation.func @__talos_root(%arg0: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {
      code_unit_id = 832639515527371617 : i64,
      domain = 0 : i32,
      effect_summary = [],
      entry_kind = 0 : i32,
      fragment_abi = #schedule.fragment_abi<version = 1, fragments = [0]>,
      home_region = 2 : i32
    } {
      simulation.return
    }
  }
}
