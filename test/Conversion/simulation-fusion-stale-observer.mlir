// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements,talos-sim-materialize-compute-fusion))' | FileCheck %s --check-prefix=FUSE
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements),test-talos-edit-attributes{has=test.observe set={id = 3 : i64}},simulation.design(talos-sim-materialize-compute-fusion))' | FileCheck %s --check-prefix=KEEP --implicit-check-not=__talos_region_kernel_ --implicit-check-not=compute_graph --implicit-check-not=effect_summary
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements),test-talos-edit-attributes{has=test.write set={id = 1 : i64}},simulation.design(talos-sim-materialize-compute-fusion))' | FileCheck %s --check-prefix=KEEP --implicit-check-not=__talos_region_kernel_ --implicit-check-not=compute_graph --implicit-check-not=effect_summary
// The unchanged plan is valid. Editing ONLY an outside actor's watch or
// writer invalidates its observation/exclusivity proof even though none of
// the member bodies or requested fragment IDs changed.
// FUSE: simulation.spawn @__talos_region_kernel_
// KEEP: simulation.spawn @producer_and_consumer
// KEEP: simulation.spawn @transform
// KEEP: simulation.spawn @observer
module {
  simulation.design @observed_transitions {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer_and_consumer"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "transform"
    simulation.code_unit.decl 3 in 0 always hierarchy "observer"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @producer_and_consumer(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @transform(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @observer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @producer_and_consumer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %address = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %bank_address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %bank_result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      simulation.ref.store %a to %bank_address : i8, !simulation.ref<i8>
      %zero = arith.constant 0 : i8
      simulation.ref.store %zero to %result : i8, !simulation.ref<i8>
      %r = simulation.ref.load %bank_result : !simulation.ref<i8> -> i8
      simulation.ref.store %r to %result : i8, !simulation.ref<i8>
      simulation.suspend.any %address, %bank_result edges [0, 0] to ^body : !simulation.ref<i8>, !simulation.ref<i8>
    }
    simulation.func @transform(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %address = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      cf.br ^body
    ^body:
      %a = simulation.ref.load %address : !simulation.ref<i8> -> i8
      simulation.ref.store %a to %result : i8, !simulation.ref<i8>
      simulation.suspend.change %address to ^body : !simulation.ref<i8>
    }
    simulation.func @observer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      %address = simulation.context.storage %ctx[0] {test.observe} : !simulation.ref<i8>
      %result = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      %writeDestination = simulation.context.storage %ctx[0] {test.write} : !simulation.ref<i8>
      %zero = arith.constant 0 : i8
      simulation.ref.store %zero to %writeDestination : i8, !simulation.ref<i8>
      cf.br ^wait
    ^wait:
      simulation.suspend.change %address to ^wait : !simulation.ref<i8>
    }
  }
}
