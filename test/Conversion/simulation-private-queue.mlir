// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.mlir
// RUN: FileCheck %s < %t.mlir

// One property can only contain fresh scalar queues. A different property
// of the same private receiver can also take an external argument at a CFG
// join. Its operations retain the managed ABI (1800-2023 7.10.3, 8.12).
// CHECK-LABEL: llvm.func @fill.__talos_private_receiver(
// CHECK: llvm.call @__talos_private_queue_append_1_two
// CHECK: llvm.call @__talos_private_queue_read_1_two
// CHECK: llvm.call @talos_rt_v1_queue_push(
// CHECK: llvm.return

!c = !simulation.context
!obj = !simulation.class_handle<@item>
!q = !simulation.queue<i8, 0>
!field = !simulation.managed_ref<!q, @item>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", native.closed_executable} {
  simulation.design @private_queues {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "drive"
    simulation.code_unit.decl 3 in 0 function hierarchy "item.fill"
    simulation.class.decl @item id 1 {is_abstract = false, is_final = true, is_interface = false}
    simulation.class.field @own of @item at 0 : !q {is_static = false, is_weak = false}
    simulation.class.field @mixed of @item at 1 : !q {is_static = false, is_weak = false}
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %actor = simulation.spawn @drive(%ctx) : !c -> !simulation.process
      simulation.return
    }
    simulation.func private @drive(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %which = simulation.ref.load %r : !simulation.ref<i1> -> i1
      %zero = arith.constant 0 : i64
      %outer = simulation.container.create %zero {alignment = 1 : i64, bit_width = 8 : i64, bound = -1 : i64, container_kind = #simulation.container_kind<queue>, element_flags = #simulation.element_flags<none>, element_kind = #simulation.element_kind<bits>, trace_kinds = array<i32>, trace_offsets = array<i64>, type_id = 17 : i64, value_size = 1 : i64} : (i64) -> !q
      %o = simulation.class.alloc %ctx : !c -> !obj
      %v = simulation.call @fill(%ctx, %o, %outer, %which) : (!c, !obj, !q, i1) -> i8
      %fd = arith.constant 1 : i32
      simulation.display %ctx to %fd (%v) newline = true radix = <decimal> flags = [0] : i8
      simulation.return
    }
    simulation.func private @fill(%ctx: !c {simulation.capture_kind = 0 : i32}, %this: !obj {simulation.capture_kind = 1 : i32}, %foreign: !q {simulation.capture_kind = 1 : i32}, %which: i1 {simulation.capture_kind = 1 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %f = simulation.class.field_ref %this[@own] : !obj -> !field
      %g = simulation.class.field_ref %this[@mixed] : !obj -> !field
      %zero = arith.constant 0 : i64
      %byte = arith.constant 57 : i8
      %queue = simulation.container.create %zero {alignment = 1 : i64, bit_width = 8 : i64, bound = -1 : i64, container_kind = #simulation.container_kind<queue>, element_flags = #simulation.element_flags<none>, element_kind = #simulation.element_kind<bits>, trace_kinds = array<i32>, trace_offsets = array<i64>, type_id = 17 : i64, value_size = 1 : i64} : (i64) -> !q
      simulation.managed.store %queue to %f : !q, !field
      %owned = simulation.managed.load %f : !field -> !q
      simulation.queue.push_back %byte into %owned : !q, i8
      %value = simulation.container.read %owned, %zero : (!q, i64) -> i8
      cf.cond_br %which, ^fresh, ^join(%foreign : !q)
    ^fresh:
      %other = simulation.container.create %zero {alignment = 1 : i64, bit_width = 8 : i64, bound = -1 : i64, container_kind = #simulation.container_kind<queue>, element_flags = #simulation.element_flags<none>, element_kind = #simulation.element_kind<bits>, trace_kinds = array<i32>, trace_offsets = array<i64>, type_id = 17 : i64, value_size = 1 : i64} : (i64) -> !q
      cf.br ^join(%other : !q)
    ^join(%selected: !q):
      simulation.managed.store %selected to %g : !q, !field
      %maybeShared = simulation.managed.load %g : !field -> !q
      simulation.queue.push_back %value into %maybeShared : !q, i8
      simulation.return %value : i8
    }
  }
}
