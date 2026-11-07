// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{grow-acyclic=false},talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o %t.sim.mlir
// RUN: FileCheck %s --check-prefix=FALLBACK --implicit-check-not='__talos_region_kernel_' < %t.sim.mlir
// RUN: talos-opt %s --test-talos-activation-regions='functions=a_implicit,b_implicit,a_explicit,b_explicit components=true reaching-values=true idempotence=true' -o /dev/null 2>&1 | FileCheck %s --check-prefix=GRAPH
// RUN: talos-opt %t.sim.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe && %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// IEEE 1800-2023 4.6(a)/10.4.1: source A captures q BEFORE publishing
// request. At time2, changing d=a=1 must capture q=1 while enable is still1;
// only that request publication permits B to lower enable. A publication-only
// DAG would place request -> B -> A's capture and incorrectly leave q=0.
// Fixed-input idempotence holds for both implicit and explicit self-holds,
// but does not authorize that reordering. Keep each held-state owner whole.
// FALLBACK-DAG: simulation.spawn @a_implicit
// FALLBACK-DAG: simulation.spawn @b_implicit
// FALLBACK-DAG: simulation.spawn @a_explicit
// FALLBACK-DAG: simulation.spawn @b_explicit
// GRAPH: regions @a_implicit valid=1
// GRAPH-NEXT: idempotent=1
// GRAPH: regions @a_explicit valid=1
// GRAPH-NEXT: idempotent=1
// GRAPH: slice components: valid nodes=4 components=2 cyclic=2 events=4
// OUTPUT: {{^}}held order 1 1{{$}}

!r = !simulation.ref<i1>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @retained_source_order {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.storage.decl 5 in 0 : i1 design
    simulation.storage.decl 6 in 0 : i1 design
    simulation.storage.decl 7 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "a_implicit"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "b_implicit"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "a_explicit"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "b_explicit"
    simulation.code_unit.decl 5 in 0 initial hierarchy "drive"
    simulation.code_unit.decl 6 in 0 initial hierarchy "check"
    simulation.code_unit.decl 9 in 0 root_initializer hierarchy "root"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 9 : i64} {
      %p0 = simulation.spawn @a_implicit(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @b_implicit(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @a_explicit(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @b_explicit(%ctx) : !simulation.context -> !simulation.process
      %p4 = simulation.spawn @drive(%ctx) : !simulation.context -> !simulation.process
      %p5 = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @a_implicit(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !r
      %d = simulation.context.storage %ctx[1] : !r
      %enable = simulation.context.storage %ctx[2] : !r
      %q = simulation.context.storage %ctx[3] : !r
      %request = simulation.context.storage %ctx[4] : !r
      cf.br ^body
    ^body:
      %e = simulation.ref.load %enable : !r -> i1
      cf.cond_br %e, ^capture, ^publish
    ^capture:
      %value = simulation.ref.load %d : !r -> i1
      simulation.ref.store %value to %q : i1, !r
      cf.br ^publish
    ^publish:
      %requestValue = simulation.ref.load %a : !r -> i1
      simulation.ref.store %requestValue to %request : i1, !r
      simulation.suspend.any %a, %d, %enable edges [0, 0, 0] to ^body : !r, !r, !r
    }
    simulation.func @b_implicit(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %request = simulation.context.storage %ctx[4] : !r
      %enable = simulation.context.storage %ctx[2] : !r
      %one = arith.constant true
      cf.br ^body
    ^body:
      %r = simulation.ref.load %request : !r -> i1
      %e = arith.xori %r, %one : i1
      simulation.ref.store %e to %enable : i1, !r
      simulation.suspend.change %request to ^body : !r
    }
    simulation.func @a_explicit(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !r
      %d = simulation.context.storage %ctx[1] : !r
      %enable = simulation.context.storage %ctx[5] : !r
      %q = simulation.context.storage %ctx[6] : !r
      %request = simulation.context.storage %ctx[7] : !r
      cf.br ^body
    ^body:
      %old = simulation.ref.load %q : !r -> i1
      %e = simulation.ref.load %enable : !r -> i1
      cf.cond_br %e, ^capture, ^hold
    ^capture:
      %value = simulation.ref.load %d : !r -> i1
      cf.br ^chosen(%value : i1)
    ^hold:
      cf.br ^chosen(%old : i1)
    ^chosen(%next : i1):
      simulation.ref.store %next to %q : i1, !r
      cf.br ^publish
    ^publish:
      %requestValue = simulation.ref.load %a : !r -> i1
      simulation.ref.store %requestValue to %request : i1, !r
      simulation.suspend.any %a, %d, %enable edges [0, 0, 0] to ^body : !r, !r, !r
    }
    simulation.func @b_explicit(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %request = simulation.context.storage %ctx[7] : !r
      %enable = simulation.context.storage %ctx[5] : !r
      %one = arith.constant true
      cf.br ^body
    ^body:
      %r = simulation.ref.load %request : !r -> i1
      %e = arith.xori %r, %one : i1
      simulation.ref.store %e to %enable : i1, !r
      simulation.suspend.change %request to ^body : !r
    }
    simulation.func @drive(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %a = simulation.context.storage %ctx[0] : !r
      %d = simulation.context.storage %ctx[1] : !r
      %one = arith.constant true
      %two = simulation.time.constant 2
      simulation.suspend.delay %two to ^change
    ^change:
      simulation.ref.store %one to %d : i1, !r
      simulation.ref.store %one to %a : i1, !r
      simulation.return
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %q = simulation.context.storage %ctx[3] : !r
      %qe = simulation.context.storage %ctx[6] : !r
      %three = simulation.time.constant 3
      %format = simulation.bytes.constant "held order %0d %0d"
      %stdout = arith.constant -2147483647 : i32
      simulation.suspend.delay %three to ^sample
    ^sample:
      %value = simulation.ref.load %q : !r -> i1
      %explicit = simulation.ref.load %qe : !r -> i1
      simulation.display %ctx to %stdout(%format, %value, %explicit) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i1, i1
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}
