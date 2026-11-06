// RUN: talos-opt %s --encode-talos-sim-to-bytecode=vpi=off --convert-talos-sim-processes-to-llvm-coroutines | FileCheck %s

// A recursive synchronous task uses target-sized descriptor/table pointers.
// The task activation entry and the synchronous entry have distinct fields.
module attributes {
  llvm.data_layout = "e-p:32:32-i64:64-i32:32-i16:16-i8:8",
  llvm.target_triple = "wasm32-unknown-unknown"
} {
  simulation.design @tasks {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 task hierarchy "Base.run"
    simulation.code_unit.decl 2 in 0 initial hierarchy "caller"
    simulation.class.decl @Base id 1 {is_abstract = false, is_final = false, is_interface = false}
    simulation.class.method @method of @Base slot 0 signature_id 17 implemented_by @run :
      (!simulation.context, !simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>) -> () {
      is_final = false, is_pure = false, is_static = false, is_task = true, is_virtual = true
    }
    simulation.func @run(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}, %ref: !simulation.ref<i9> {simulation.capture_kind = 2 : i32}, %value: !simulation.logic<9> {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 1 : i64, entry_kind = 12 : i32} {
      simulation.class.virtual_task_call %this[@method] slot 0 signature_id 17 (%ref, %value) arguments 2 to ^done :
        (!simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>) -> ()
    ^done:
      simulation.return
    }
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !simulation.class_handle<@Base> {simulation.capture_kind = 1 : i32}, %ref: !simulation.ref<i9> {simulation.capture_kind = 2 : i32}, %value: !simulation.logic<9> {simulation.capture_kind = 2 : i32})
        attributes {code_unit_id = 2 : i64, entry_kind = 1 : i32} {
      simulation.class.virtual_task_call %this[@method] slot 0 signature_id 17 (%ref, %value) arguments 2 to ^done :
        (!simulation.class_handle<@Base>, !simulation.ref<i9>, !simulation.logic<9>) -> ()
    ^done:
      simulation.return
    }
  }
}

// CHECK: llvm.func internal @method.__talos_typed_entry(
// CHECK: llvm.call @run.__talos_synchronous
// CHECK-LABEL: llvm.mlir.global internal constant @Base.__talos_methods()
// CHECK-SAME: !llvm.array<1 x struct<(i64, i32, i32, ptr, ptr, i64, ptr)>>
// CHECK: llvm.mlir.addressof @method.__talos_native_thunk
// CHECK: llvm.insertvalue {{.*}}[3]
// CHECK: llvm.mlir.addressof @method.__talos_native_sync_thunk
// CHECK: llvm.insertvalue {{.*}}[6]
// CHECK-LABEL: llvm.func @run.__talos_synchronous(
// CHECK-SAME: -> i32
// CHECK: llvm.load {{.*}} {alignment = 4 : i64} : !llvm.ptr -> !llvm.ptr
// CHECK: llvm.getelementptr {{.*}}[0, 21]
// CHECK: llvm.load {{.*}} {alignment = 4 : i64} : !llvm.ptr -> !llvm.ptr
// CHECK: llvm.call %{{.*}} : !llvm.ptr, (!llvm.ptr, i64, i64, i9, i9) -> i32
