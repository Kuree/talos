// RUN: talos-opt %s -mlir-disable-threading --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{native.closed_executable}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' --mlir-print-ir-after=prepare-native-managed-roots --mlir-print-ir-module-scope -o /dev/null 2>&1 | FileCheck %s
// RUN: talos-opt %s -mlir-disable-threading --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' --mlir-print-ir-after=prepare-native-managed-roots --mlir-print-ir-module-scope -o /dev/null 2>&1 | FileCheck %s --check-prefix=OPEN

// The first storage word belongs to one startup process. A second process
// also uses the other, so both of its accesses stay with the ordinary heap.
// CHECK-LABEL: simulation.func private @writer(
// CHECK: simulation.queue.push_back {{.*}} {native.private_queue}
// CHECK: simulation.queue.pop {{.*}} {native.private_queue}
// CHECK: simulation.queue.push_back %{{[^ ]+}} into %{{[^ ]+}} :
// CHECK-LABEL: simulation.func private @reader(
// CHECK: simulation.container.size %{{[^ ]+}} :
// OPEN-LABEL: simulation.func private @writer(
// OPEN-NOT: native.private_queue
// OPEN-LABEL: simulation.func private @reader(
// OPEN-NOT: native.private_queue
// OPEN: simulation.return

!c = !simulation.context
!q = !simulation.queue<i8, 0>
!r = !simulation.ref<!q>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128"} {
  simulation.design @storage_owners {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !q design
    simulation.storage.decl 1 in 0 : !q design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "writer"
    simulation.code_unit.decl 3 in 0 initial hierarchy "reader"
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.spawn @writer(%ctx) : !c -> !simulation.process
      %b = simulation.spawn @reader(%ctx) : !c -> !simulation.process
      simulation.return
    }
    simulation.func private @writer(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %a = simulation.context.storage %ctx[0] : !r
      %b = simulation.context.storage %ctx[1] : !r
      %z = arith.constant 0 : i64
      %byte = arith.constant 42 : i8
      %one = simulation.container.create %z {alignment = 1 : i64, bit_width = 8 : i64, bound = -1 : i64, container_kind = #simulation.container_kind<queue>, element_flags = #simulation.element_flags<none>, element_kind = #simulation.element_kind<bits>, trace_kinds = array<i32>, trace_offsets = array<i64>, type_id = 17 : i64, value_size = 1 : i64} : (i64) -> !q
      simulation.ref.store %one to %a : !q, !r
      %private = simulation.ref.load %a : !r -> !q
      simulation.queue.push_back %byte into %private : !q, i8
      %saved = simulation.queue.pop %private[%z] : !q -> i8
      %two = simulation.container.create %z {alignment = 1 : i64, bit_width = 8 : i64, bound = -1 : i64, container_kind = #simulation.container_kind<queue>, element_flags = #simulation.element_flags<none>, element_kind = #simulation.element_kind<bits>, trace_kinds = array<i32>, trace_offsets = array<i64>, type_id = 17 : i64, value_size = 1 : i64} : (i64) -> !q
      simulation.ref.store %two to %b : !q, !r
      %shared = simulation.ref.load %b : !r -> !q
      simulation.queue.push_back %saved into %shared {native.private_queue} : !q, i8
      simulation.return
    }
    simulation.func private @reader(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %b = simulation.context.storage %ctx[1] : !r
      %q = simulation.ref.load %b : !r -> !q
      %size = simulation.container.size %q : (!q) -> i64
      %fd = arith.constant 1 : i32
      simulation.display %ctx to %fd (%size) newline = true radix = <decimal> flags = [0] : i64
      simulation.return
    }
  }
}
