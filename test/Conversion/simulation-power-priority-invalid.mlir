// RUN: not talos-opt %s --split-input-file --encode-talos-sim-to-bytecode='vpi=off' -o /dev/null 2>&1 | FileCheck %s
// RUN: not talos-opt %s --split-input-file --convert-talos-sim-processes-to-llvm-coroutines -o /dev/null 2>&1 | FileCheck %s
// IEEE 1801-2018 9.7.3: reserved RTC/power occurrence observers must be
// detached internal Active actors. Native and bytecode validate the same roles.

// CHECK: error: {{.*}}priority signal resume is reserved for internal concurrent cancellation or abort observers, or Active power observers
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  simulation.design @missing_internal {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 fork hierarchy "top.actor"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @actor(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @actor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 2 : i64, home_region = 2 : i32, simulation.power_monitor, schedule.detached_controls, schedule.priority_signal_resume} {
      simulation.return
    }
  }
}

// -----

// CHECK: error: {{.*}}priority signal resume is reserved for internal concurrent cancellation or abort observers, or Active power observers
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  simulation.design @wrong_region {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 fork hierarchy "top.actor"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @actor(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @actor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 2 : i64, home_region = 10 : i32, internal, simulation.power_monitor, schedule.detached_controls, schedule.priority_signal_resume} {
      simulation.return
    }
  }
}

// -----

// CHECK: error: {{.*}}priority signal resume is reserved for internal concurrent cancellation or abort observers, or Active power observers
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  simulation.design @mixed_roles {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 fork hierarchy "top.actor"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @actor(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @actor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 2 : i64, home_region = 2 : i32, internal, simulation.power_monitor, schedule.concurrent_cancel, schedule.detached_controls, schedule.priority_signal_resume} {
      simulation.return
    }
  }
}

// -----

// CHECK: error: {{.*}}priority signal resume is reserved for internal concurrent cancellation or abort observers, or Active power observers
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  simulation.design @missing_detached {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 fork hierarchy "top.actor"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @actor(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @actor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 2 : i64, home_region = 2 : i32, internal, simulation.power_monitor, schedule.priority_signal_resume} {
      simulation.return
    }
  }
}
