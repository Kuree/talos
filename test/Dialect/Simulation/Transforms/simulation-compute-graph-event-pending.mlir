// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s

// A process.event_pending query reads the latched occurrence of the process
// it names: a value change of what that process waits on, or a named event
// (IEEE 1800-2023 9.4.2). Process objects come from spawns (9.7), so a handle
// that is a spawn result, directly or through captures every spawn site fills
// with one, reads exactly the target's wait inputs. A disable iff revoker
// (16.12) thus reads the disable condition, not every resource. Any other
// handle, such as self() or a capture some spawn site fills otherwise, may
// name any process and keeps an unknown read.

!r = !simulation.ref<i1>
module {
  // The scheduler consumes fragment effects. A querier summarized before its
  // target by name order still reads the target's completed summary.
  // CHECK: function = @aquery, block = 0,
  // CHECK-SAME: effects = [#schedule.effect<effect = read, resource = storage, target = descriptor, descriptor = 1,
  // CHECK-SAME: #schedule.effect<effect = read, resource = storage, target = descriptor, descriptor = 4,
  // CHECK: function = @revoke, block = 0,
  // CHECK-SAME: effects = [#schedule.effect<effect = read, resource = storage, target = descriptor, descriptor = 0,
  // CHECK-SAME: #schedule.effect<effect = read, resource = storage, target = descriptor, descriptor = 3,
  simulation.design @pending {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 initial hierarchy "test.pending.cancel"
    simulation.code_unit.decl 2 in 0 initial hierarchy "test.pending.revoke"
    simulation.code_unit.decl 3 in 0 initial hierarchy "test.pending.local"
    simulation.code_unit.decl 4 in 0 initial hierarchy "test.pending.self"
    simulation.code_unit.decl 5 in 0 initial hierarchy "test.pending.mixed"
    simulation.code_unit.decl 6 in 0 initial hierarchy "test.pending.other"
    simulation.code_unit.decl 7 in 0 observer hierarchy "test.pending.disabled"
    simulation.code_unit.decl 8 in 0 initial hierarchy "test.pending.aquery"
    simulation.code_unit.decl 9 in 0 initial hierarchy "test.pending.zwait"
    simulation.code_unit.decl 10 in 0 function hierarchy "test.pending.zread"
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.storage.decl 4 in 0 : i1 design

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32} {
      %disable = simulation.context.storage %ctx[0] : !r
      %state = simulation.context.storage %ctx[1] : !r
      %cancel = simulation.spawn @cancel(%ctx, %disable, %state) : !simulation.context, !r, !r -> !simulation.process
      %other = simulation.spawn @other(%ctx) : !simulation.context -> !simulation.process
      %revoke = simulation.spawn @revoke(%ctx, %cancel) : !simulation.context, !simulation.process -> !simulation.process
      %revoke2 = simulation.spawn @revoke(%ctx, %other) : !simulation.context, !simulation.process -> !simulation.process
      %local = simulation.spawn @local(%ctx, %disable, %state) : !simulation.context, !r, !r -> !simulation.process
      %self = simulation.spawn @self(%ctx) : !simulation.context -> !simulation.process
      %null = simulation.process.null
      %mixed = simulation.spawn @mixed(%ctx, %cancel) : !simulation.context, !simulation.process -> !simulation.process
      %mixed2 = simulation.spawn @mixed(%ctx, %null) : !simulation.context, !simulation.process -> !simulation.process
      %zwait = simulation.spawn @zwait(%ctx) : !simulation.context -> !simulation.process
      %aquery = simulation.spawn @aquery(%ctx, %zwait) : !simulation.context, !simulation.process -> !simulation.process
      simulation.return
    }

    simulation.func private @disabled(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %disable: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) -> i1
        attributes {entry_kind = 14 : i32, code_unit_id = 7 : i64} {
      %value = simulation.ref.load %disable : !r -> i1
      simulation.return %value : i1
    }

    // The disable iff canceller shape: it waits on an observer of the
    // descriptor-captured disable condition (storage 0) and clears attempt
    // state through a formal capture. Only its wait inputs are read.
    simulation.func @cancel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %disable: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64},
        %state: !r {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      %zero = arith.constant false
      cf.br ^wait(%zero : i1)
    ^wait(%previous: i1):
      %observer = simulation.observer.bind @disabled values(%disable : !r) captures 1 : !simulation.observer<i1>
      simulation.suspend.observe %observer, %previous conditions 0 edges [1] indices [-1] to ^body : !simulation.observer<i1>, i1
    ^body:
      simulation.ref.store %zero to %state : i1, !r
      cf.br ^wait(%zero : i1)
    }

    // A second target waits on storage 3.
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %watched = simulation.context.storage %ctx[3] : !r
      cf.br ^wait
    ^wait:
      simulation.suspend.change %watched to ^wait : !r
    }

    // CHECK-LABEL: simulation.func @aquery
    // CHECK-SAME: effect_summary = [#schedule.effect<effect = read, resource = storage, target = descriptor, descriptor = 1,
    // CHECK-NOT: resource = unknown
    // CHECK-SAME: effect = read, resource = storage, target = descriptor, descriptor = 4,
    // CHECK-NOT: resource = unknown
    // CHECK-SAME: effect = write, resource = storage, target = descriptor, descriptor = 2,
    simulation.func @aquery(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %target: !simulation.process {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 8 : i64} {
      %epoch = simulation.context.storage %ctx[2] : !r
      %pending = simulation.process.event_pending %target
      simulation.ref.store %pending to %epoch : i1, !r
      simulation.return
    }

    // The target reads storage 4 only through a call, so the querier sees it
    // only after the target's summary is complete.
    simulation.func @zwait(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 9 : i64} {
      %watched = simulation.context.storage %ctx[1] : !r
      cf.br ^wait
    ^wait:
      %value = simulation.call @zread(%ctx) : (!simulation.context) -> i1
      simulation.suspend.change %watched to ^wait : !r
    }
    simulation.func @zread(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i1
        attributes {entry_kind = 8 : i32, code_unit_id = 10 : i64} {
      %source = simulation.context.storage %ctx[4] : !r
      %value = simulation.ref.load %source : !r -> i1
      simulation.return %value : i1
    }

    // Both spawn sites pass spawn results, so the query reads the union of
    // both targets' wait inputs, and neither target's formal state write.
    // CHECK-LABEL: simulation.func @revoke
    // CHECK-SAME: effect_summary = [#schedule.effect<effect = read, resource = storage, target = descriptor, descriptor = 0,
    // CHECK-NOT: resource = unknown
    // CHECK-SAME: effect = read, resource = storage, target = descriptor, descriptor = 3,
    // CHECK-NOT: resource = unknown
    // CHECK-SAME: effect = write, resource = storage, target = descriptor, descriptor = 2,
    simulation.func @revoke(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %target: !simulation.process {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %epoch = simulation.context.storage %ctx[2] : !r
      %pending = simulation.process.event_pending %target
      simulation.ref.store %pending to %epoch : i1, !r
      simulation.return
    }

    // CHECK-LABEL: simulation.func @local
    // CHECK-SAME: effect_summary = [#schedule.effect<effect = read, resource = storage, target = descriptor, descriptor = 0,
    // CHECK-NOT: resource = unknown
    // CHECK-SAME: effect = write, resource = storage, target = descriptor, descriptor = 2,
    simulation.func @local(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %disable: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64},
        %state: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64})
        attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %epoch = simulation.context.storage %ctx[2] : !r
      %target = simulation.spawn @cancel(%ctx, %disable, %state) : !simulation.context, !r, !r -> !simulation.process
      %pending = simulation.process.event_pending %target
      simulation.ref.store %pending to %epoch : i1, !r
      simulation.return
    }

    // CHECK-LABEL: simulation.func @self
    // CHECK-SAME: effect_summary = [#schedule.effect<effect = read, resource = unknown
    simulation.func @self(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %epoch = simulation.context.storage %ctx[2] : !r
      %target = simulation.process.current
      %pending = simulation.process.event_pending %target
      simulation.ref.store %pending to %epoch : i1, !r
      simulation.return
    }

    // One spawn site passes a handle that is not a spawn result.
    // CHECK-LABEL: simulation.func @mixed
    // CHECK-SAME: effect_summary = [#schedule.effect<effect = read, resource = unknown
    simulation.func @mixed(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %target: !simulation.process {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %epoch = simulation.context.storage %ctx[2] : !r
      %pending = simulation.process.event_pending %target
      simulation.ref.store %pending to %epoch : i1, !r
      simulation.return
    }
  }
}
