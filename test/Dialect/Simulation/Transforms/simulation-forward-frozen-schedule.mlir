// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{maximum-rounds=0 closed-model=true}))' | FileCheck %s --check-prefix=NORMAL
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=off}))' -o %t.graph
// RUN: talos-opt %t.graph --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{maximum-rounds=0 closed-model=true},talos-sim-verify-compute-graph))' -o %t.after
// RUN: diff %t.graph %t.after

// Even zero copy rounds normalize an unplanned continuous expression's CFG.
// Once scheduling artifacts are frozen, the whole pass must preserve their
// source revision, including the producer's multi-block short-circuit arm.
// IEEE 1800-2023 4.3/10.3.2: preserve the original scheduled evaluations.
// NORMAL-LABEL: simulation.func private @copy(
// NORMAL: arith.select
// NORMAL: simulation.ref.store

module {
  simulation.design @empty_short_circuit_arm {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 3 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %side = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n, %side) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %rhs: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %first = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %condition = simulation.logic.is_true %first : !simulation.logic<4>
      %yes = simulation.logic.constant 15 : i4, 0 : i4 : !simulation.logic<4>
      %no = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      cf.cond_br %condition, ^join(%yes : !simulation.logic<4>), ^arm
    ^arm:
      cf.br ^join(%no : !simulation.logic<4>)
    ^join(%value: !simulation.logic<4>):
      simulation.ref.store %value to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<4>>
    }
  }
}


// -----

// A plan can retain its source graph inside nested attributes after the
// design-level graph was removed. The CFG must still remain unchanged.
// NORMAL-LABEL: simulation.design @embedded_graph
// NORMAL-LABEL: simulation.func private @copy(
// NORMAL: cf.cond_br
// NORMAL-NOT: arith.select
// NORMAL: simulation.ref.store

module {
  simulation.design @embedded_graph attributes {test.plan = {source = #schedule.graph<version = 1, vpi = off, workers = 1, nodes = [], edges = [], regions = [#schedule.region<kind = active, groups = []>, #schedule.region<kind = nba, groups = []>, #schedule.region<kind = observed, groups = []>, #schedule.region<kind = reactive, groups = []>, #schedule.region<kind = postponed, groups = []>]>}} {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 3 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %side = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n, %side) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %rhs: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %first = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %condition = simulation.logic.is_true %first : !simulation.logic<4>
      %yes = simulation.logic.constant 15 : i4, 0 : i4 : !simulation.logic<4>
      %no = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      cf.cond_br %condition, ^join(%yes : !simulation.logic<4>), ^arm
    ^arm:
      cf.br ^join(%no : !simulation.logic<4>)
    ^join(%value: !simulation.logic<4>):
      simulation.ref.store %value to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<4>>
    }
  }
}


// -----

// An empty recorded effect summary is frozen too, even though its array
// contains no individual schedule.effect attribute.
// NORMAL-LABEL: simulation.design @recorded_effects
// NORMAL-LABEL: simulation.func private @copy(
// NORMAL: cf.cond_br
// NORMAL-NOT: arith.select
// NORMAL: simulation.ref.store

module {
  simulation.design @recorded_effects {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 3 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %side = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n, %side) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %rhs: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64, effect_summary = []} {
      cf.br ^body
    ^body:
      %first = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %condition = simulation.logic.is_true %first : !simulation.logic<4>
      %yes = simulation.logic.constant 15 : i4, 0 : i4 : !simulation.logic<4>
      %no = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      cf.cond_br %condition, ^join(%yes : !simulation.logic<4>), ^arm
    ^arm:
      cf.br ^join(%no : !simulation.logic<4>)
    ^join(%value: !simulation.logic<4>):
      simulation.ref.store %value to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<4>>
    }
  }
}


// -----

// Replay checkpoint ownership is on an ancestor module. Its attributes
// must be checked without requiring any metadata on this design's functions.
// NORMAL-LABEL: simulation.design @module_plan
// NORMAL-LABEL: simulation.func private @copy(
// NORMAL: cf.cond_br
// NORMAL-NOT: arith.select
// NORMAL: simulation.ref.store

module attributes {test.plan = {source = #schedule.graph<version = 1, vpi = off, workers = 1, nodes = [], edges = [], regions = [#schedule.region<kind = active, groups = []>, #schedule.region<kind = nba, groups = []>, #schedule.region<kind = observed, groups = []>, #schedule.region<kind = reactive, groups = []>, #schedule.region<kind = postponed, groups = []>]>}} {
  simulation.design @module_plan {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 3 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %side = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n, %side) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %rhs: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %first = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %condition = simulation.logic.is_true %first : !simulation.logic<4>
      %yes = simulation.logic.constant 15 : i4, 0 : i4 : !simulation.logic<4>
      %no = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      cf.cond_br %condition, ^join(%yes : !simulation.logic<4>), ^arm
    ^arm:
      cf.br ^join(%no : !simulation.logic<4>)
    ^join(%value: !simulation.logic<4>):
      simulation.ref.store %value to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<4>>
    }
  }
}
