// RUN: talos-opt %s --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s

// A function made from another's code keeps its origin roles (here
// clocked_kernel, fused_kernel and eval_body): the ramp, requirements and
// execute wrappers of a process, and the activation helpers of a task.
// spawn_helper describes only the function that spawns a process, so only
// each __talos_spawn helper has it, whatever its source has.

// CHECK-LABEL: llvm.func @suspending.__talos_coro_ramp(
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<clocked_kernel>}
// CHECK-LABEL: llvm.func @suspending.__talos_native_requirements(
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<clocked_kernel>}
// CHECK-LABEL: llvm.func @suspending.__talos_native_execute(
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<clocked_kernel>}
// CHECK-LABEL: llvm.func @suspending.__talos_spawn(
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<clocked_kernel|spawn_helper>}
// CHECK-LABEL: llvm.func @plain.__talos_native_execute(
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<fused_kernel>}
// CHECK-LABEL: llvm.func @plain.__talos_spawn(
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<fused_kernel|spawn_helper>}
// CHECK-LABEL: llvm.func @task.__talos_native_execute(
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<eval_body>}
// CHECK-LABEL: llvm.func internal @task.__talos_activate_checked(
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<eval_body>}
// CHECK-LABEL: llvm.func @task.__talos_activate(
// CHECK-SAME: schedule.eval.role = #schedule.eval_role<eval_body>}
module attributes {llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  simulation.design @roles {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 initial hierarchy "roles.suspending"
    simulation.code_unit.decl 2 in 0 initial hierarchy "roles.plain"
    simulation.code_unit.decl 3 in 0 task hierarchy "roles.task"
    simulation.func @suspending(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 1 : i32, schedule.eval.role = #schedule.eval_role<clocked_kernel|spawn_helper>} {
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^resume
    ^resume:
      simulation.return
    }
    simulation.func @plain(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 1 : i32, schedule.eval.role = #schedule.eval_role<fused_kernel|spawn_helper>} {
      simulation.return
    }
    simulation.func @task(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 3 : i64, entry_kind = 12 : i32, schedule.eval.role = #schedule.eval_role<eval_body|spawn_helper>} {
      simulation.return
    }
  }
}
