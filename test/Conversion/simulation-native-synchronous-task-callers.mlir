// RUN: talos-opt %S/simulation-bytecode-native-tasks.mlir --encode-talos-sim-to-bytecode=vpi=off --convert-talos-sim-processes-to-llvm-coroutines > %t.llvm
// RUN: FileCheck %s --check-prefix=CHAIN < %t.llvm
// RUN: FileCheck %s --check-prefix=CALLER < %t.llvm
// RUN: talos-opt %S/simulation-bytecode-native-tasks.mlir --encode-talos-sim-to-bytecode=vpi=off --convert-talos-sim-processes-to-llvm-coroutines --mlir-disable-threading --mlir-print-ir-after=prepare-native-managed-roots --mlir-print-ir-module-scope -o /dev/null 2>&1 | FileCheck %s --check-prefix=BOUNDARY
// RUN: talos-opt %s --encode-talos-sim-to-bytecode=vpi=off --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=FALLBACK --implicit-check-not=@derived_run.__talos_synchronous

// IEEE 1800-2023 8.6/8.20/8.26, 13.3 and 13.5.2: original native
// activations call non-suspending tasks synchronously. Their canonical task
// sites/frames remain available for bytecode fallback and observation.
// The shared input includes direct, virtual, interface and static calls with
// sparse continuation IDs, raw reference arguments and four-state values.

// CHAIN-LABEL: llvm.func @chain.__talos_coro_ramp(
// CHAIN-SAME: continuations = [0, 71, 72, 73]
// CHAIN-NOT: llvm.call @base_step.__talos_activate
// CHAIN: llvm.call @base_step.__talos_synchronous
// CHAIN: llvm.getelementptr {{.*}}[0, 21]
// CHAIN: llvm.call %{{.*}} : !llvm.ptr, (!llvm.ptr, i64, i64, i9, i9) -> i32
// CHAIN: llvm.getelementptr {{.*}}[0, 21]
// CHAIN: llvm.call %{{.*}} : !llvm.ptr, (!llvm.ptr, i64, i64, i9, i9) -> i32
// CHAIN-NOT: llvm.call @talos_rt_v1_method_task_activate
// CHAIN-NOT: llvm.call @talos_rt_v1_interface_method_task_activate
// CHAIN: {{^  [}]}}

// CALLER-LABEL: llvm.func @caller.__talos_coro_ramp(
// CALLER-SAME: continuations = [0, 103, 127, 211, 251]
// CALLER-NOT: llvm.call @chain.__talos_activate
// CALLER: llvm.call @chain.__talos_synchronous
// CALLER-NOT: llvm.call @static_task.__talos_activate
// CALLER: llvm.call @static_task.__talos_synchronous
// CALLER: llvm.getelementptr {{.*}}[0, 21]
// CALLER: llvm.call %{{.*}} : !llvm.ptr, (!llvm.ptr, i64, i64, i9, i9) -> i32
// CALLER-NOT: llvm.call @talos_rt_v1_interface_method_task_activate
// CALLER: llvm.call @blocked.__talos_activate
// CALLER: {{^  [}]}}

// The frame snapshot still points at the original task terminators. Insert
// the call before their native root-pop/continuation transfer, then retain
// each terminator with its stable continuation ID and successor values.
// BOUNDARY-LABEL: simulation.func @chain(
// BOUNDARY: simulation.call @base_step.__talos_synchronous
// BOUNDARY: simulation.task.call @base_step
// BOUNDARY-SAME: native.synchronous_task_call
// BOUNDARY-SAME: id = 71
// BOUNDARY: schedule.class.synchronous_call {{.*}}[@Base_step]
// BOUNDARY: simulation.class.virtual_task_call {{.*}}[@Base_step]
// BOUNDARY-SAME: native.synchronous_task_call
// BOUNDARY-SAME: id = 72
// BOUNDARY: schedule.class.synchronous_call {{.*}}[@Runner_step]
// BOUNDARY: simulation.class.virtual_task_call {{.*}}[@Runner_step]
// BOUNDARY-SAME: native.synchronous_task_call
// BOUNDARY-SAME: id = 73

// An exact base call can be synchronous even when a derived override delays.
// A call through that virtual family must retain activation dispatch.
module attributes {
  llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @mixed_family {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 3 in 0 task hierarchy "Base.run"
    simulation.code_unit.decl 4 in 0 task hierarchy "Derived.run"
    simulation.class.decl @Base id 1 {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.decl @Derived id 2 extends @Base {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.method @Base_run of @Base slot 0 signature_id 17 implemented_by @base_run :
        (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = true
    }
    simulation.class.method @Derived_run of @Derived slot 0 signature_id 17 implemented_by @derived_run :
        (!simulation.context, !simulation.class_handle<@Derived>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = true
    }
    simulation.func @base_run(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 3 : i64, entry_kind = 12 : i32} {
      simulation.return
    }
    simulation.func @derived_run(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Derived> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 4 : i64, entry_kind = 12 : i32} {
      %one = simulation.time.constant 1
      simulation.suspend.delay %one to ^done
    ^done:
      simulation.return
    }
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 1 : i32} {
      %actual = simulation.class.alloc %ctx : !simulation.context -> !simulation.class_handle<@Derived>
      %object = simulation.class.cast %actual : !simulation.class_handle<@Derived> to !simulation.class_handle<@Base>
      simulation.task.call @base_run(%ctx, %object, %object) arguments 2 to ^virtual : !simulation.context, !simulation.class_handle<@Base>, !simulation.class_handle<@Base>
    ^virtual(%next: !simulation.class_handle<@Base>):
      simulation.class.virtual_task_call %next[@Base_run] slot 0 signature_id 17 () arguments 0 to ^done : (!simulation.class_handle<@Base>) -> ()
    ^done:
      simulation.return
    }
    simulation.func @__talos_root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 0 : i32} {
      %process = simulation.spawn @caller(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
  }
}

// FALLBACK-LABEL: llvm.func @caller.__talos_coro_ramp(
// FALLBACK: llvm.call @base_run.__talos_synchronous
// FALLBACK-NOT: llvm.getelementptr {{.*}}[0, 21]
// FALLBACK: llvm.call @talos_rt_v1_method_task_activate
// FALLBACK: {{^  [}]}}
