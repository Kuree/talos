// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.native 2> %t.fresh
// RUN: FileCheck %s --check-prefix=FRESH < %t.fresh && FileCheck %s --check-prefix=STORES < %t.native && FileCheck %s --check-prefix=PRIVATE < %t.native
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.published set={callee=@initialize}},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o /dev/null 2>&1 | FileCheck %s --check-prefix=ESCAPED

// Only the first write to flags is overwritten without a read. The first
// write to count is read into saved. An object stored into a design variable
// before a second call makes the receiver observable (1800-2023 8.7).
// FRESH: talos fresh constructor stores: elided=1
// FRESH: talos private class fields: allocations=1 methods=1 accesses=8
// A 17-bit property uses three bytes per plane. Only the value plane
// starts at the four-byte alignment of the property.
// PRIVATE: llvm.call @initialize.__talos_private_receiver(
// PRIVATE: llvm.load %[[FIELD:[0-9]+]] {alignment = 4 : i64} : !llvm.ptr -> i17
// PRIVATE-NEXT: %[[X:[0-9]+]] = llvm.getelementptr %[[FIELD]][3]
// PRIVATE-NEXT: llvm.load %[[X]] {alignment = 1 : i64} : !llvm.ptr -> i17
// PRIVATE-LABEL: llvm.func @initialize.__talos_private_receiver(
// PRIVATE-NOT: llvm.call @talos_rt_v1_object_
// PRIVATE: llvm.cond_br
// PRIVATE: llvm.load {{.*}} : !llvm.ptr -> i8
// PRIVATE: llvm.store %{{[0-9]+}}, %[[VALUE:[0-9]+]] {alignment = 4 : i64} : i17, !llvm.ptr
// PRIVATE-NEXT: %[[UNKNOWN:.*]] = llvm.getelementptr %[[VALUE]][3]
// PRIVATE-NEXT: llvm.store %{{.*}}, %[[UNKNOWN]] {alignment = 1 : i64} : i17, !llvm.ptr
// PRIVATE-NOT: llvm.call @talos_rt_v1_object_
// PRIVATE: llvm.return
// STORES-LABEL: llvm.func @initialize(
// STORES-NOT: llvm.call @talos_rt_v1_object_write_planes
// STORES: llvm.call @talos_rt_v1_object_write(
// STORES: llvm.call @talos_rt_v1_object_read(
// STORES: llvm.call @talos_rt_v1_object_write(
// STORES: llvm.call @talos_rt_v1_object_write(
// STORES: llvm.call @talos_rt_v1_object_write_planes(
// STORES-NOT: llvm.call @talos_rt_v1_object_write
// STORES: llvm.return
// ESCAPED: talos fresh constructor stores: elided=0

!obj = !simulation.class_handle<@item>
!flags = !simulation.logic<17>
!fr = !simulation.managed_ref<!flags, @item>
!ir = !simulation.managed_ref<i8, @item>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", native.closed_executable, native.debug_timing} {
  simulation.design @constructors {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !obj design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "drive"
    simulation.code_unit.decl 3 in 0 function hierarchy "item.new"
    simulation.code_unit.decl 4 in 0 function hierarchy "noop"
    simulation.class.decl @item id 1 {is_abstract = false, is_final = true, is_interface = false}
    simulation.class.field @flags of @item at 0 : !flags {is_static = false, is_weak = false}
    simulation.class.field @count of @item at 1 : i8 {is_static = false, is_weak = false}
    simulation.class.field @saved of @item at 2 : i8 {is_static = false, is_weak = false}
    simulation.class.method @new_item of @item implemented_by @initialize : (!simulation.context, !obj) -> () {is_final = false, is_pure = false, is_static = false, is_task = false, is_virtual = false}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %actor = simulation.spawn @drive(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @drive(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %a = simulation.class.alloc %ctx : !simulation.context -> !obj
      simulation.call @initialize(%ctx, %a) : (!simulation.context, !obj) -> ()
      %published = simulation.context.storage %ctx[0] : !simulation.ref<!obj>
      %b = simulation.class.alloc %ctx : !simulation.context -> !obj
      simulation.ref.store %b to %published : !obj, !simulation.ref<!obj>
      simulation.call @noop(%ctx, %b) {test.published} : (!simulation.context, !obj) -> ()
      %f = simulation.class.field_ref %a[@flags] : !obj -> !fr
      %c = simulation.class.field_ref %a[@count] : !obj -> !ir
      %s = simulation.class.field_ref %a[@saved] : !obj -> !ir
      %flags = simulation.managed.load %f : !fr -> !flags
      %count = simulation.managed.load %c : !ir -> i8
      %saved = simulation.managed.load %s : !ir -> i8
      %fmt = simulation.bytes.constant "flags=%b count=%0d saved=%0d"
      %fd = arith.constant 1 : i32
      simulation.display %ctx to %fd(%fmt, %flags, %count, %saved) newline = true radix = <decimal> flags = [0, 0, 0, 0] : !simulation.bytes, !flags, i8, i8
      %ok = arith.constant 0 : i32
      simulation.finish %ctx, %ok
      simulation.return
    }
    simulation.func private @initialize(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !obj {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64, simulation.class_method = @new_item} {
      %f = simulation.class.field_ref %this[@flags] : !obj -> !fr
      %c = simulation.class.field_ref %this[@count] : !obj -> !ir
      %s = simulation.class.field_ref %this[@saved] : !obj -> !ir
      %zero = simulation.logic.constant 0 : i17, 0 : i17 : !flags
      %new = simulation.logic.constant 9 : i17, 2 : i17 : !flags
      %one = arith.constant 1 : i8
      %two = arith.constant 2 : i8
      simulation.managed.store %zero to %f : !flags, !fr
      simulation.managed.store %one to %c : i8, !ir
      %prior = simulation.managed.load %c : !ir -> i8
      simulation.managed.store %two to %c : i8, !ir
      simulation.managed.store %prior to %s : i8, !ir
      simulation.managed.store %new to %f : !flags, !fr
      simulation.return
    }
    simulation.func private @noop(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %this: !obj {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      simulation.return
    }
  }
}
