// RUN: talos-opt %s --encode-talos-sim-to-bytecode=vpi=off --test-talos-print-bytecode=metadata=true -o /dev/null 2>&1 | FileCheck %s --check-prefix=IMAGE
// RUN: talos-opt %s --encode-talos-sim-to-bytecode=vpi=off --prepare-synchronous-native-tasks --prepare-synchronous-native-tasks | FileCheck %s --check-prefix=BODY
// RUN: talos-opt %s --encode-talos-sim-to-bytecode=vpi=off --convert-talos-sim-processes-to-llvm-coroutines > %t.llvm
// RUN: FileCheck %s --check-prefix=ENTRIES --implicit-check-not=@Derived.__talos_direct_methods < %t.llvm
// RUN: FileCheck %s --check-prefix=LLVM < %t.llvm
// RUN: talos-opt %s --encode-talos-sim-to-bytecode='vpi=off require-bytecode' --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s --check-prefix=BYTECODE

// IEEE 1800-2023 8.6, 8.10, 8.20, 8.26 and 13.3: synchronous class
// tasks preserve automatic lifetime, static/exact binding and dynamic dispatch.
// Every native task retains its original activation and continuation frame.
// Sparse cross-tier continuation IDs become dense ordinals in native plans.
// The source task remains a task; only its native helper uses a function ABI.
module attributes {
  llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @tasks {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 9 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 1 in 0 task hierarchy "Base.step"
    simulation.code_unit.decl 2 in 0 task hierarchy "Derived.step"
    simulation.code_unit.decl 3 in 0 task hierarchy "Base.chain"
    simulation.code_unit.decl 4 in 0 task hierarchy "Base.static_task"
    simulation.code_unit.decl 5 in 0 task hierarchy "Base.sleep"
    simulation.code_unit.decl 6 in 0 task hierarchy "Base.blocked"
    simulation.code_unit.decl 7 in 0 task hierarchy "Base.unused"
    simulation.code_unit.decl 8 in 0 initial hierarchy "top.caller"
    simulation.class.decl @Runner id 1 {is_abstract = true, is_final = false, is_interface = true}
    simulation.class.decl @Base id 2 implements [@Runner] {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.decl @Derived id 3 extends @Base {is_abstract = false, is_final = true, is_interface = false}
    simulation.class.method @Runner_step of @Runner slot 4294967295 signature_id 17 interface_ordinal 0 :
      (!simulation.context, !simulation.class_handle<@Runner>, !simulation.ref<i9>, !simulation.logic<9>) -> () {
      is_final = false, is_pure = true, is_static = false, is_task = true, is_virtual = true
    }
    simulation.class.method @Base_step of @Base slot 0 signature_id 17 implemented_by @base_step :
      (!simulation.context, !simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = true
    }
    simulation.class.method @Derived_step of @Derived slot 0 signature_id 17 implemented_by @derived_step :
      (!simulation.context, !simulation.class_handle<@Derived>, !simulation.ref<i9>, !simulation.logic<9>) -> () {
      is_final = true, is_pure = false, is_static = false, is_task = true, is_virtual = true
    }
    simulation.class.method @Base_chain of @Base implemented_by @chain :
      (!simulation.context, !simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.class.method @Base_static of @Base implemented_by @static_task : (!simulation.context, i9) -> () {
      is_final = false, is_pure = false, is_static = true, is_task = true, is_virtual = false
    }
    simulation.class.method @Base_sleep of @Base implemented_by @sleep : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.class.method @Base_blocked of @Base implemented_by @blocked : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.class.method @Base_unused of @Base implemented_by @unused : (!simulation.context, !simulation.class_handle<@Base>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = false
    }
    simulation.func @base_step(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}, %ref: !simulation.ref<i9> {simulation.capture_kind = 2 : i32}, %value: !simulation.logic<9> {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 12 : i32, native.partition = "methods"} {
      simulation.return
    }
    simulation.func @derived_step(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Derived> {simulation.capture_kind = 1 : i32}, %ref: !simulation.ref<i9> {simulation.capture_kind = 2 : i32}, %value: !simulation.logic<9> {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 12 : i32, native.partition = "methods"} {
      simulation.return
    }
    simulation.func @chain(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}, %ref: !simulation.ref<i9> {simulation.capture_kind = 2 : i32}, %value: !simulation.logic<9> {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 3 : i64, entry_kind = 12 : i32, native.partition = "methods"} {
      simulation.task.call @base_step(%ctx, %this, %ref, %value, %this, %ref, %value) arguments 4 to ^dispatch {site = #schedule.continuation<id = 71>} :
        !simulation.context, !simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>, !simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>
    ^dispatch(%object: !simulation.class_handle<@Base>, %reference: !simulation.ref<i9>, %logic: !simulation.logic<9>):
      simulation.class.virtual_task_call %object[@Base_step] slot 0 signature_id 17 (%reference, %logic, %object, %reference, %logic) arguments 2 to ^interface {site = #schedule.continuation<id = 72>} :
        (!simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>, !simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>) -> ()
    ^interface(%last: !simulation.class_handle<@Base>, %last_ref: !simulation.ref<i9>, %last_logic: !simulation.logic<9>):
      %interface = simulation.class.cast %last : !simulation.class_handle<@Base> to !simulation.class_handle<@Runner>
      simulation.class.virtual_task_call %interface[@Runner_step] slot 4294967295 signature_id 17 (%last_ref, %last_logic) arguments 2 to ^done {site = #schedule.continuation<id = 73>} :
        (!simulation.class_handle<@Runner>, !simulation.ref<i9>, !simulation.logic<9>) -> ()
    ^done:
      simulation.return
    }
    simulation.func @static_task(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %value: i9 {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 4 : i64, entry_kind = 12 : i32} {
      simulation.return
    }
    simulation.func @sleep(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 5 : i64, entry_kind = 12 : i32} {
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^done
    ^done:
      simulation.return
    }
    simulation.func @blocked(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 6 : i64, entry_kind = 12 : i32} {
      simulation.task.call @sleep(%ctx, %this) arguments 2 to ^done : !simulation.context, !simulation.class_handle<@Base>
    ^done:
      simulation.return
    }
    simulation.func @unused(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32})
        attributes {code_unit_id = 7 : i64, entry_kind = 12 : i32} {
      simulation.return
    }
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 8 : i64, entry_kind = 1 : i32} {
      %actual = simulation.class.alloc %ctx : !simulation.context -> !simulation.class_handle<@Derived>
      %object = simulation.class.cast %actual : !simulation.class_handle<@Derived> to !simulation.class_handle<@Base>
      %value = arith.constant 42 : i9
      %logic = simulation.logic.from_bits %value : i9 -> !simulation.logic<9>
      %ref = simulation.ref.alloc %value : i9 -> !simulation.ref<i9>
      simulation.task.call @chain(%ctx, %object, %ref, %logic, %object, %ref, %logic) arguments 4 to ^static {site = #schedule.continuation<id = 103>} :
        !simulation.context, !simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>, !simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>
    ^static(%next: !simulation.class_handle<@Base>, %reference: !simulation.ref<i9>, %continued: !simulation.logic<9>):
      %nine = arith.constant 9 : i9
      simulation.task.call @static_task(%ctx, %nine, %next, %reference, %continued) arguments 2 to ^interface {site = #schedule.continuation<id = 127>} :
        !simulation.context, i9, !simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>
    ^interface(%last: !simulation.class_handle<@Base>, %last_ref: !simulation.ref<i9>, %last_logic: !simulation.logic<9>):
      %interface = simulation.class.cast %last : !simulation.class_handle<@Base> to !simulation.class_handle<@Runner>
      simulation.class.virtual_task_call %interface[@Runner_step] slot 4294967295 signature_id 17 (%last_ref, %last_logic, %last) arguments 2 to ^blocked {site = #schedule.continuation<id = 211>} :
        (!simulation.class_handle<@Runner>, !simulation.ref<i9>, !simulation.logic<9>, !simulation.class_handle<@Base>) -> ()
    ^blocked(%final: !simulation.class_handle<@Base>):
      simulation.task.call @blocked(%ctx, %final) arguments 2 to ^done {site = #schedule.continuation<id = 251>} : !simulation.context, !simulation.class_handle<@Base>
    ^done:
      simulation.return
    }
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 9 : i64, entry_kind = 0 : i32} {
      %process = simulation.spawn @caller(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
  }
}

// IMAGE: opcode=66 flags=0
// IMAGE-NEXT: native method: argument_planes=3 result_planes=0 result_size=0 handle_arguments=1 continuation=1
// IMAGE-NEXT: argument plane=0 {{.*}} native_size=8 result_offset=9
// IMAGE-NEXT: argument plane=1 {{.*}} native_size=2 result_offset=0
// IMAGE-NEXT: argument plane=2 {{.*}} native_size=2 result_offset=0
// IMAGE: opcode=67 flags=0
// IMAGE: opcode=66 flags=0 {{.*}} src0=4294967295
// IMAGE-NEXT: native method: argument_planes=1 result_planes=0 result_size=0 continuation=2
// IMAGE: opcode=68 flags=0
// IMAGE-NEXT: native method: argument_planes=3 result_planes=0 result_size=0 handle_arguments=1 continuation=3
// IMAGE: opcode=40 flags=0

// BODY: simulation.func @base_step(
// BODY-SAME: code_unit_id = 1 : i64
// BODY-SAME: entry_kind = 12 : i32
// BODY-SAME: native.synchronous_task_body = @base_step.__talos_synchronous
// BODY: simulation.func @chain(
// BODY: simulation.task.call @base_step
// BODY: simulation.class.virtual_task_call
// BODY: simulation.func @chain.__talos_synchronous(
// BODY-SAME: entry_kind = 8 : i32
// BODY-SAME: native.partition = "methods"
// BODY-NOT: runtime.bytecode_function
// BODY: simulation.call @base_step.__talos_synchronous
// BODY-NEXT: cf.br
// BODY: schedule.class.synchronous_call {{.*}}[@Base_step]
// BODY-NEXT: cf.br
// BODY: schedule.class.synchronous_call {{.*}}[@Runner_step]
// BODY-NEXT: cf.br
// BODY-NOT: simulation.task.call
// BODY-NOT: @unused.__talos_synchronous
// BODY-NOT: @sleep.__talos_synchronous
// BODY-NOT: @blocked.__talos_synchronous

// ENTRIES-NOT: @Derived.__talos_direct_methods
// ENTRIES-DAG: llvm.func internal @Base_step.__talos_typed_entry(
// ENTRIES-DAG: llvm.func internal @Derived_step.__talos_typed_entry(
// ENTRIES-DAG: llvm.func internal @Base_step.__talos_native_sync_thunk(
// ENTRIES-DAG: llvm.func internal @Derived_step.__talos_native_sync_thunk(
// ENTRIES-DAG: llvm.func internal @Base_chain.__talos_native_sync_thunk(
// ENTRIES-DAG: llvm.func internal @Base_static.__talos_native_sync_thunk(
// ENTRIES-DAG: llvm.func internal @Base_step.__talos_native_thunk(
// ENTRIES-DAG: llvm.func internal @Derived_step.__talos_native_thunk(
// LLVM-LABEL: llvm.func @chain.__talos_synchronous(
// LLVM-SAME: -> i32
// LLVM: llvm.call @talos_rt_v1_native_state_retain
// LLVM: llvm.call @base_step.__talos_synchronous
// LLVM: llvm.getelementptr {{.*}}[0, 21]
// LLVM: llvm.call @talos_rt_v1_native_state_retain
// LLVM: llvm.call %{{.*}} : !llvm.ptr, (!llvm.ptr, i64, i64, i9, i9) -> i32
// LLVM: llvm.getelementptr {{.*}}[0, 21]
// LLVM: llvm.call @talos_rt_v1_native_state_retain
// LLVM: llvm.call %{{.*}} : !llvm.ptr, (!llvm.ptr, i64, i64, i9, i9) -> i32
// LLVM-NOT: llvm.call @talos_rt_v1_method_invoke
// LLVM-NOT: llvm.call @talos_rt_v1_method_task_activate
// LLVM: llvm.func @base_step.__talos_synchronous(
// LLVM-NOT: @unused.__talos_synchronous
// LLVM-NOT: @sleep.__talos_synchronous
// LLVM-NOT: @blocked.__talos_synchronous

// BYTECODE: module attributes
// BYTECODE-NOT: __talos_synchronous
// BYTECODE-NOT: __talos_native_sync_thunk
// BYTECODE-NOT: __talos_typed_entry
