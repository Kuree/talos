// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements,talos-sim-materialize-compute-fusion))' | FileCheck %s --check-prefix=OWNER
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements))' | FileCheck %s --check-prefix=PLAN

// Every design has an `initial` sink reading the roots only the processes
// under test write.

// @sel loads the whole 3-bit way_id and uses bit 2; @mux writes bit 1 of it
// from @sel's output. Physical load ranges make that a cycle; the lane
// publication of @sel's store reads way_id[2,3) only, so the pair is a DAG
// and runs once in data order: @sel, then @mux.
// CHECK-LABEL: simulation.design @lane_reads
// CHECK: simulation.spawn @sink
// CHECK: simulation.spawn @__talos_region_kernel_0_0
// CHECK-NOT: simulation.spawn
// CHECK-LABEL: simulation.func private @__talos_region_kernel_0_0
// CHECK: ^bb1:
// CHECK: %[[WAY:.*]] = simulation.ref.load {{.*}} : !simulation.ref<!simulation.logic<3>>
// CHECK: %[[SEL:.*]] = simulation.logic.extract %[[WAY]] from 2
// CHECK: simulation.ref.store %[[SEL]] to
// CHECK: simulation.ref.store {{.*}} to %{{.*}} : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
// PLAN-LABEL: simulation.design @lane_reads
// PLAN: #schedule.fusion<id = 0, fragments = [{{[0-9]+, [0-9]+}}], interleaved = true, dataflow = true>
module {
  simulation.design @lane_reads {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<3> design
    simulation.storage.decl 1 in 0 : !simulation.logic<1> design
    simulation.storage.decl 2 in 0 : !simulation.logic<2> design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "sel"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "mux"
    simulation.code_unit.decl 3 in 0 initial hierarchy "sink"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %s = simulation.spawn @sink(%ctx) : !simulation.context -> !simulation.process
      %a = simulation.spawn @sel(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @mux(%ctx) : !simulation.context -> !simulation.process
      simulation.return
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

// -----

// OWNER-LABEL: simulation.design @identity_lanes
// OWNER: simulation.func private @__talos_region_kernel_0_0
// OWNER-COUNT-3: simulation.ref.store {{.*}}schedule.eval.source_owner = #schedule.source_owner<codeUnit = 1 : i64, continuation = 77 : i32>
// @copy publishes one identity lane out[0,4) <- in[0,4). @reader uses out[0]
// to compute flag and @writer stores flag into in[3]: a cycle through the
// whole copy, but not lane by lane. The copy is split at bits 1 and 3 into
// partial stores, ordered copy[0,1), reader, writer, copy[3,4).
// CHECK-LABEL: simulation.design @identity_lanes
// CHECK: simulation.spawn @sink
// CHECK: simulation.spawn @__talos_region_kernel_0_0
// CHECK-NOT: simulation.spawn
// CHECK-LABEL: simulation.func private @__talos_region_kernel_0_0
// CHECK: ^bb1:
// CHECK-DAG: simulation.ref.extract %{{.*}} from 0 : !simulation.ref<!simulation.logic<4>> -> !simulation.ref<!simulation.logic<1>>
// CHECK-DAG: simulation.ref.extract %{{.*}} from 1 : !simulation.ref<!simulation.logic<4>> -> !simulation.ref<!simulation.logic<2>>
// CHECK-DAG: simulation.ref.extract %{{.*}} from 3 : !simulation.ref<!simulation.logic<4>> -> !simulation.ref<!simulation.logic<1>>
// CHECK: simulation.suspend.any
#copy_owner = #schedule.source_owner<codeUnit = 1 : i64, continuation = 77 : i32>
module {
  simulation.design @identity_lanes {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<1> design
    simulation.storage.decl 3 in 0 : !simulation.logic<1> design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "copy"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "writer"
    simulation.code_unit.decl 4 in 0 initial hierarchy "sink"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %s = simulation.spawn @sink(%ctx) : !simulation.context -> !simulation.process
      %a = simulation.spawn @copy(%ctx) : !simulation.context -> !simulation.process
      %b = simulation.spawn @reader(%ctx) : !simulation.context -> !simulation.process
      %c = simulation.spawn @writer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @sink(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %out = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %v = simulation.ref.load %out : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.return
    }
    simulation.func @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64, schedule.eval.source_owners = [#copy_owner]} {
      %in = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %out = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in {schedule.eval.source_owner = #copy_owner} : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out {schedule.eval.source_owner = #copy_owner} : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %out = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %flag = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<1>>
      %mode = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<1>>
      %bit0 = simulation.ref.extract %out from 0 : !simulation.ref<!simulation.logic<4>> -> !simulation.ref<!simulation.logic<1>>
      cf.br ^body
    ^body:
      %b = simulation.ref.load %bit0 : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %m = simulation.ref.load %mode : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %f = simulation.logic.binary and %b, %m : !simulation.logic<1>
      simulation.ref.store %f to %flag : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      simulation.suspend.any %bit0, %mode edges [0, 0] to ^body : !simulation.ref<!simulation.logic<1>>, !simulation.ref<!simulation.logic<1>>
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %in = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %flag = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<1>>
      %bit3 = simulation.ref.extract %in from 3 : !simulation.ref<!simulation.logic<4>> -> !simulation.ref<!simulation.logic<1>>
      cf.br ^body
    ^body:
      %f = simulation.ref.load %flag : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      simulation.ref.store %f to %bit3 : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
      simulation.suspend.change %flag to ^body : !simulation.ref<!simulation.logic<1>>
    }
  }
}
