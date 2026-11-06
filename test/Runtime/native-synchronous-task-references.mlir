// RUN: talos-opt %s --encode-talos-sim-to-bytecode=vpi=off --convert-talos-sim-processes-to-llvm-coroutines --materialize-runtime-byte-globals | talos-translate --mlir-to-llvmir | opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx -I%S/../../runtime/include %t.o %S/Inputs/check-task-reference-release.cpp -Wl,--wrap=talos_rt_v1_native_state_alloc -Wl,--wrap=talos_rt_v1_context_destroy %runtime_link_flags -o %t.exe
// RUN: env TALOS_RT_GC_THRESHOLD=1 %t.exe | FileCheck %s

// Duplicate automatic ref formals each transfer one reference to the helper;
// the continuation keeps its own reference. Collect between the two writes,
// check immediate aliases, then confirm the allocation is gone at shutdown.
// IEEE 1800-2023 8.6, 13.3, 13.5.2.
// CHECK: 13
// CHECK-NEXT: automatic task reference released

module attributes {
  llvm.data_layout = "e-p:64:64-i64:64-i32:32-i16:16-i8:8",
  llvm.target_triple = "x86_64-unknown-linux-gnu"
} {
  simulation.design @task_references {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 3 in 0 task hierarchy "Base.bump"
    simulation.code_unit.decl 4 in 0 task hierarchy "Base.static_bump"
    simulation.class.decl @Runner id 1 {is_abstract = true, is_final = false, is_interface = true}
    simulation.class.decl @Base id 2 implements [@Runner] {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.method @Runner_bump of @Runner slot 4294967295 signature_id 17 interface_ordinal 0 :
        (!simulation.context, !simulation.class_handle<@Runner>, !simulation.ref<i9>, !simulation.ref<i9>) -> () {
      is_final = false, is_pure = true, is_static = false, is_task = true, is_virtual = true
    }
    simulation.class.method @Base_bump of @Base slot 0 signature_id 17 implemented_by @bump :
        (!simulation.context, !simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.ref<i9>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = true
    }
    simulation.class.method @Base_static of @Base implemented_by @static_bump :
        (!simulation.context, !simulation.ref<i9>, !simulation.ref<i9>) -> () {
      is_final = false, is_pure = false, is_static = true, is_task = true, is_virtual = false
    }
    simulation.func @bump(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}, %first: !simulation.ref<i9> {simulation.capture_kind = 2 : i32}, %second: !simulation.ref<i9> {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 3 : i64, entry_kind = 12 : i32} {
      %one = arith.constant 1 : i9
      %a = simulation.ref.load %first : !simulation.ref<i9> -> i9
      %b = arith.addi %a, %one : i9
      simulation.ref.store %b to %first : i9, !simulation.ref<i9>
      simulation.gc.safepoint %ctx : !simulation.context
      %c = simulation.ref.load %second : !simulation.ref<i9> -> i9
      %d = arith.addi %c, %one : i9
      simulation.ref.store %d to %second : i9, !simulation.ref<i9>
      simulation.return
    }
    simulation.func @static_bump(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %first: !simulation.ref<i9> {simulation.capture_kind = 2 : i32}, %second: !simulation.ref<i9> {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 4 : i64, entry_kind = 12 : i32} {
      %one = arith.constant 1 : i9
      %a = simulation.ref.load %first : !simulation.ref<i9> -> i9
      %b = arith.addi %a, %one : i9
      simulation.ref.store %b to %first : i9, !simulation.ref<i9>
      simulation.gc.safepoint %ctx : !simulation.context
      %c = simulation.ref.load %second : !simulation.ref<i9> -> i9
      %d = arith.addi %c, %one : i9
      simulation.ref.store %d to %second : i9, !simulation.ref<i9>
      simulation.return
    }
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 1 : i32} {
      %object = simulation.class.alloc %ctx : !simulation.context -> !simulation.class_handle<@Base>
      %five = arith.constant 5 : i9
      %local = simulation.ref.alloc %five : i9 -> !simulation.ref<i9>
      simulation.task.call @bump(%ctx, %object, %local, %local, %object, %local) arguments 4 to ^virtual {site = #schedule.continuation<id = 101>} :
          !simulation.context, !simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.ref<i9>, !simulation.class_handle<@Base>, !simulation.ref<i9>
    ^virtual(%next: !simulation.class_handle<@Base>, %reference: !simulation.ref<i9>):
      simulation.class.virtual_task_call %next[@Base_bump] slot 0 signature_id 17 (%reference, %reference, %next, %reference) arguments 2 to ^interface {site = #schedule.continuation<id = 103>} :
          (!simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.ref<i9>, !simulation.class_handle<@Base>, !simulation.ref<i9>) -> ()
    ^interface(%last: !simulation.class_handle<@Base>, %last_ref: !simulation.ref<i9>):
      %runner = simulation.class.cast %last : !simulation.class_handle<@Base> to !simulation.class_handle<@Runner>
      simulation.class.virtual_task_call %runner[@Runner_bump] slot 4294967295 signature_id 17 (%last_ref, %last_ref, %last_ref) arguments 2 to ^static {site = #schedule.continuation<id = 107>} :
          (!simulation.class_handle<@Runner>, !simulation.ref<i9>, !simulation.ref<i9>, !simulation.ref<i9>) -> ()
    ^static(%actual: !simulation.ref<i9>):
      simulation.task.call @static_bump(%ctx, %actual, %actual, %actual) arguments 3 to ^done {site = #schedule.continuation<id = 109>} :
          !simulation.context, !simulation.ref<i9>, !simulation.ref<i9>, !simulation.ref<i9>
    ^done(%result: !simulation.ref<i9>):
      %value = simulation.ref.load %result : !simulation.ref<i9> -> i9
      %format = simulation.bytes.constant "%0d"
      %stdout = arith.constant 1 : i32
      simulation.display %ctx to %stdout(%format, %value) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i9
      simulation.return
    }
    simulation.func @__talos_root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 0 : i32} {
      %process = simulation.spawn @caller(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
  }
}
