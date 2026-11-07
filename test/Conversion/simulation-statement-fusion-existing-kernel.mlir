// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{component-sections=true grow-acyclic=false},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=PRESERVE
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{component-sections=true},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=SLICE

// Existing kernel publications form a false owner cycle with @response. A
// publication DAG exists only if the kernel is split. The no-growth repair
// policy preserves its shared computation and source order as one publication
// member, so conservatively retains both executors (IEEE 1800-2023 4.3/4.6).
// Ordinary planning demonstrates that the same source is otherwise sliceable.
// PRESERVE-LABEL: simulation.func @root(
// PRESERVE: simulation.spawn @existing_kernel
// PRESERVE-NEXT: {{.*}}simulation.spawn @response
// PRESERVE-NEXT: simulation.return
// PRESERVE-NOT: simulation.spawn @__talos_region_kernel_
// PRESERVE-LABEL: simulation.func private @existing_kernel(
// PRESERVE: %[[SHARED:.*]] = simulation.ref.load
// PRESERVE: arith.addi %[[SHARED]],
// PRESERVE: simulation.ref.store %[[SHARED]] to
// SLICE-LABEL: simulation.func @root(
// SLICE: simulation.spawn @__talos_region_kernel_0_0
// SLICE-NEXT: simulation.return

!r = !simulation.ref<i8>
module {
  simulation.design @existing_kernel_cycle {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "existing_kernel"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "response"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "existing_second_owner"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @existing_kernel(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @response(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @existing_kernel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64, schedule.native.region_body, schedule.eval.source_owners = [#schedule.source_owner<codeUnit = 1 : i64, continuation = 1 : i32>, #schedule.source_owner<codeUnit = 3 : i64, continuation = 2 : i32>]} {
      %input = simulation.context.storage %ctx[0] : !r
      %address = simulation.context.storage %ctx[1] : !r
      %response = simulation.context.storage %ctx[2] : !r
      %output = simulation.context.storage %ctx[3] : !r
      cf.br ^body
    ^body:
      %shared = simulation.ref.load %input : !r -> i8
      %value = simulation.ref.load %response : !r -> i8
      %sum = arith.addi %shared, %value : i8
      simulation.ref.store %sum to %output : i8, !r
      simulation.ref.store %shared to %address : i8, !r
      simulation.suspend.any %input, %response edges [0, 0] to ^body : !r, !r
    }
    simulation.func @response(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !r
      %response = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %value = simulation.ref.load %address : !r -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %value, %one : i8
      simulation.ref.store %next to %response : i8, !r
      simulation.suspend.change %address to ^body : !r
    }
  }
}
