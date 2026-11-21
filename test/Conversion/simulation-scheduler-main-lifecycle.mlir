// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines -o %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: talos-opt %t.mlir --test-talos-lower-startup-lifecycle=modules=libone.so,libtwo.so | FileCheck %s --check-prefix=LOWER

// The driver asks for state synchronization, initial driver resolution and
// VPI. The generated main runs the startup steps right before the root
// process spawns, and the VPI end-of-simulation callbacks before the last
// status report, whose status they may replace (IEEE 1800-2023 36.9.1,
// 36.10.2, 38.36.3).
// CHECK-LABEL: llvm.func @main
// CHECK: schedule.lifecycle.start state_bits 8 state_sync resolve_initial_drivers vpi
// CHECK-NEXT: llvm.call @__talos_root.__talos_spawn(%[[CONTEXT:[0-9]+]])
// CHECK: %[[STATUS:.*]] = llvm.call @talos_rt_v1_scheduler_run
// CHECK: %[[FINAL:.*]] = schedule.lifecycle.finish %[[CONTEXT]], %[[STATUS]]
// CHECK-NEXT: llvm.call @talos_rt_v1_scheduler_report_status(%[[CONTEXT]], %[[FINAL]])
// CHECK-NEXT: schedule.lifecycle.shutdown %[[CONTEXT]]
// CHECK-NEXT: llvm.call @talos_rt_v1_context_destroy(%[[CONTEXT]])
// CHECK-NEXT: llvm.return %[[FINAL]]

// The startup library names follow every other symbol, in load order; the
// runtime entries the module does not declare yet follow them.
// LOWER-NOT: native.startup
// LOWER-LABEL: llvm.func @main
// LOWER: llvm.call @talos_rt_v1_context_configure_argv
// LOWER: llvm.store
// LOWER-NEXT: %[[CURRENT:.*]] = llvm.mlir.addressof @__talos_current_context
// LOWER-NEXT: %[[CONTEXT:.*]] = llvm.load %[[CURRENT]] {alignment = 8 : i64}
// LOWER: %[[SYNCED:.*]] = llvm.call @talos_rt_v1_native_state_sync(%[[CONTEXT]], %{{.*}}, %{{.*}}, %{{.*}})
// LOWER-NEXT: llvm.call @talos_rt_v1_scheduler_fail(%[[CONTEXT]], %[[SYNCED]])
// LOWER-NEXT: %[[RESOLVED:.*]] = llvm.call @talos_rt_v1_scheduler_resolve_initial_drivers(%[[CONTEXT]])
// LOWER-NEXT: llvm.call @talos_rt_v1_scheduler_fail(%[[CONTEXT]], %[[RESOLVED]])
// LOWER: %[[NAMES:.*]] = llvm.getelementptr inbounds %{{.*}}[0, 0]
// LOWER: %[[COUNT:.*]] = llvm.mlir.constant(2 : i64)
// LOWER-NEXT: %[[STARTED:.*]] = llvm.call @talos_rt_v1_vpi_startup(%[[CONTEXT]], %[[NAMES]], %[[COUNT]])
// LOWER-NEXT: llvm.call @talos_rt_v1_scheduler_fail(%[[CONTEXT]], %[[STARTED]])
// LOWER-NEXT: %[[COMPILED:.*]] = llvm.call @talos_rt_v1_vpi_end_compile(%[[CONTEXT]])
// LOWER-NEXT: llvm.call @talos_rt_v1_scheduler_fail(%[[CONTEXT]], %[[COMPILED]])
// LOWER-NEXT: %[[SIMULATING:.*]] = llvm.call @talos_rt_v1_vpi_start_simulation(%[[CONTEXT]])
// LOWER-NEXT: llvm.call @talos_rt_v1_scheduler_fail(%[[CONTEXT]], %[[SIMULATING]])
// LOWER-NEXT: llvm.call @__talos_root.__talos_spawn
// LOWER: %[[STATUS:.*]] = llvm.call @talos_rt_v1_scheduler_run
// LOWER: %[[ENDED:.*]] = llvm.call @talos_rt_v1_vpi_end_simulation
// LOWER-NEXT: %[[ZERO:.*]] = llvm.mlir.constant(0 : i32)
// LOWER-NEXT: %[[FAILED:.*]] = llvm.icmp "ne" %[[STATUS]], %[[ZERO]]
// LOWER-NEXT: %[[FINAL:.*]] = llvm.select %[[FAILED]], %[[STATUS]], %[[ENDED]]
// LOWER-NEXT: llvm.call @talos_rt_v1_scheduler_report_status(%{{.*}}, %[[FINAL]])
// LOWER-NEXT: llvm.call @talos_rt_v1_vpi_shutdown
// LOWER-NEXT: llvm.call @talos_rt_v1_context_destroy
// LOWER-NEXT: llvm.return %[[FINAL]]
// LOWER: llvm.mlir.global private unnamed_addr constant @__talos_vpi_module_0("libone.so\00")
// LOWER-NEXT: llvm.mlir.global private unnamed_addr constant @__talos_vpi_module_1("libtwo.so\00")
// LOWER-NEXT: llvm.mlir.global private constant @__talos_vpi_startup_modules()
// LOWER: llvm.func @talos_rt_v1_scheduler_resolve_initial_drivers(!llvm.ptr) -> i32
// LOWER-NEXT: llvm.func @talos_rt_v1_vpi_startup(!llvm.ptr, !llvm.ptr, i64) -> i32
// LOWER-NEXT: llvm.func @talos_rt_v1_vpi_end_compile(!llvm.ptr) -> i32
// LOWER-NEXT: llvm.func @talos_rt_v1_vpi_start_simulation(!llvm.ptr) -> i32
// LOWER-NEXT: llvm.func @talos_rt_v1_vpi_end_simulation(!llvm.ptr) -> i32
// LOWER-NEXT: llvm.func @talos_rt_v1_vpi_shutdown(!llvm.ptr)
// LOWER-NOT: schedule.lifecycle

module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu",
  native.startup_state_sync,
  native.startup_resolve_initial_drivers,
  native.startup_vpi
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
