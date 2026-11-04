// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(prepare-native-schedule-inputs,schedule-plan-native-state)' | FileCheck %s

// IEEE 1800-2023 21.2.3 and 21.7: a $monitor and the value change dump tasks
// act in the Postponed region of a time slot (4.4.2.9). Only a design that
// contains one asks the generated periodic loop for end-of-slot hooks.

// CHECK-LABEL: module
// CHECK-SAME: schedule.eval.postponed_observers
module attributes {llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8", llvm.target_triple = "aarch64-unknown-linux-gnu"} {
  simulation.design @monitor {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "monitor.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "monitor.child"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 0 : i32} {
      %child = simulation.spawn @child(%ctx) : !simulation.context -> !simulation.process
      simulation.monitor.register %child
      simulation.return
    }
    simulation.func @child(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 1 : i32} {
      simulation.return
    }
  }
}

// -----

// CHECK-LABEL: module
// CHECK-SAME: schedule.eval.postponed_observers
module attributes {llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8", llvm.target_triple = "aarch64-unknown-linux-gnu"} {
  simulation.design @dump {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "dump.root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 0 : i32} {
      simulation.dump.flush %ctx : (!simulation.context) -> ()
      simulation.return
    }
  }
}

// -----

// CHECK-LABEL: module
// CHECK-NOT: schedule.eval.postponed_observers
// CHECK: simulation.design @plain
module attributes {llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8", llvm.target_triple = "aarch64-unknown-linux-gnu"} {
  simulation.design @plain {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "plain.root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 0 : i32} {
      simulation.return
    }
  }
}
