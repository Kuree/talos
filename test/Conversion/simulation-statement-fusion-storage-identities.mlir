// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{grow-acyclic=false},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-build-compute-graph,talos-sim-verify-compute-graph,test-talos-repeatable-activations))' -o %t 2> %t.trace
// RUN: FileCheck %s --check-prefix=FUSED < %t
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace

// IEEE 1800-2023 4.3/4.6: source-ordered publications may be fused, but
// merging the two conditional stores through a reference phi hides their
// different storage roots. One unknown writer would revoke every native
// repeatability proof, including @independent. Keep concrete handles until
// scheduling is frozen; LLVM can merge the native blocks afterward.
// FUSED-LABEL: simulation.func @root(
// FUSED-DAG: simulation.spawn @__talos_region_kernel_0_0
// FUSED-DAG: simulation.spawn @independent
// FUSED: simulation.return
// TRACE: repeatable @independent = 1

!r = !simulation.ref<i8>
module {
  simulation.design @storage_identities {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i1 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "response"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "independent"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %p = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %r = simulation.spawn @response(%ctx) : !simulation.context -> !simulation.process
      %i = simulation.spawn @independent(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      %address = simulation.context.storage %ctx[1] : !r
      %response = simulation.context.storage %ctx[2] : !r
      %a = simulation.context.storage %ctx[3] : !r
      %b = simulation.context.storage %ctx[4] : !r
      %flag = simulation.context.storage %ctx[5] : !simulation.ref<i1>
      cf.br ^body
    ^body:
      %old = simulation.ref.load %response : !r -> i8
      simulation.ref.store %old to %a : i8, !r
      simulation.ref.store %old to %b : i8, !r
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %address : i8, !r
      %select = simulation.ref.load %flag : !simulation.ref<i1> -> i1
      cf.cond_br %select, ^left, ^right
    ^left:
      simulation.ref.store %value to %a : i8, !r
      cf.br ^wait
    ^right:
      simulation.ref.store %value to %b : i8, !r
      cf.br ^wait
    ^wait:
      simulation.suspend.any %input, %response, %flag edges [0, 0, 0] to ^body : !r, !r, !simulation.ref<i1>
    }
    simulation.func @response(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !r
      %response = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %address : !r -> i8
      simulation.ref.store %value to %response : i8, !r
      simulation.suspend.change %address to ^body : !r
    }
    simulation.func @independent(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %input = simulation.context.storage %ctx[0] : !r
      %output = simulation.context.storage %ctx[6] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %input : !r -> i8
      simulation.ref.store %value to %output : i8, !r
      simulation.suspend.change %input to ^body : !r
    }
  }
}
