// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph),test-talos-edit-attributes{op=simulation.design set={schedule.static_body_fusion = [#schedule.fusion<id = 0, fragments = [1, 3, 6], interleaved = true, dataflow = true, atomic = [1]>]}},simulation.design(talos-sim-materialize-compute-fusion))' | FileCheck %s
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph),test-talos-edit-attributes{op=simulation.design set={schedule.static_body_fusion = [#schedule.fusion<id = 0, fragments = [1, 3, 6], interleaved = true, dataflow = true, atomic = [1]>]}},test-talos-edit-attributes{has=test.atomic_store clone},simulation.design(talos-sim-materialize-compute-fusion))' | FileCheck %s --check-prefix=KEEP --implicit-check-not=__talos_region_kernel_
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph),test-talos-edit-attributes{op=simulation.design set={schedule.static_body_fusion = [#schedule.fusion<id = 0, fragments = [1, 3, 6], interleaved = true, dataflow = true, atomic = [1]>]}},test-talos-edit-attributes{has=test.atomic_store clone},simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion))' | FileCheck %s --check-prefix=KEEP --implicit-check-not=__talos_region_kernel_
// This output is observable to toggle coverage, so its owner's source order
// must remain atomic. The other two owners use lane-precise dataflow slicing.
// A later edit adding a publication invalidates the old certificate; the
// materializer must derive the repeated-write and observation facts again.
// CHECK: simulation.spawn @__talos_region_kernel_
// CHECK: simulation.func private @__talos_region_kernel_
// KEEP: simulation.spawn @atomic
// KEEP: simulation.spawn @sel
// KEEP: simulation.spawn @mux
module {
  simulation.design @lane_reads {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<3> design
    simulation.storage.decl 1 in 0 : !simulation.logic<1> design
    simulation.storage.decl 2 in 0 : !simulation.logic<2> design
    simulation.storage.decl 3 in 0 : !simulation.logic<2> design {coverage.toggle_observable}
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "atomic"
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "sel"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "mux"
    simulation.code_unit.decl 3 in 0 initial hierarchy "sink"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %atomic = simulation.spawn @atomic(%ctx) : !simulation.context -> !simulation.process
      %s = simulation.spawn @sink(%ctx) : !simulation.context -> !simulation.process
      %a = simulation.spawn @sel(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @mux(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @atomic(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %in = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<2>>
      %out = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<2>>
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
      simulation.ref.store %v to %out {test.atomic_store} : !simulation.logic<2>, !simulation.ref<!simulation.logic<2>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<2>>
    }
    simulation.func @sink(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %way = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<3>>
      %v = simulation.ref.load %way : !simulation.ref<!simulation.logic<3>> -> !simulation.logic<3>
      simulation.return
    }
    simulation.func @sel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %way = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<3>>
      %sel = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<1>>
      cf.br ^body
    ^body:
      %w = simulation.ref.load %way : !simulation.ref<!simulation.logic<3>> -> !simulation.logic<3>
      %bit = simulation.logic.extract %w from 2 : !simulation.logic<3> -> !simulation.logic<1>
      simulation.ref.store %bit to %sel : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      simulation.suspend.change %way to ^body : !simulation.ref<!simulation.logic<3>>
    }
    simulation.func @mux(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %way = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<3>>
      %sel = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<1>>
      %lru = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<2>>
      %out = simulation.ref.extract %way from 1 : !simulation.ref<!simulation.logic<3>> -> !simulation.ref<!simulation.logic<1>>
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %l = simulation.ref.load %lru : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
      %i = simulation.logic.resize %s signed = false : !simulation.logic<1> -> !simulation.logic<2>
      %picked = simulation.logic.dyn_extract %l from %i : (!simulation.logic<2>, !simulation.logic<2>) -> !simulation.logic<1>
      simulation.ref.store %picked to %out : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      simulation.suspend.any %sel, %lru edges [0, 0] to ^body : !simulation.ref<!simulation.logic<1>>, !simulation.ref<!simulation.logic<2>>
    }
  }
}
