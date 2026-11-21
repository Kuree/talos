// RUN: not talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines -o /dev/null 2>&1 | FileCheck %s

// A predeclared runtime entry must have its catalog prototype; lowering does
// not reuse a declaration of another type.
// CHECK: error: 'llvm.func' op runtime symbol @talos_rt_v1_scheduler_fail is predeclared with an incompatible type

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  llvm.func @talos_rt_v1_scheduler_fail(i64)
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
