// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s

// A spawned process shares its spawner's variables (IEEE 1800-2023 6.21,
// 9.3.2) and a reference shares its actual's representation (13.5.2), so an
// entry capture refers to exactly the actuals its spawn sites pass. A write
// through it updates those roots only, and a write to a spawner's automatic
// local, which no hierarchical reference can name (6.21), updates no design
// root; neither may alias every root the way an unresolved formal does.
// Reads keep their formal: a private value still carries its producer's
// influence. A staged update keeps its formal for its site identity. A
// capture some other entry can supply stays unresolved.

!r = !simulation.ref<i1>
module {
  // The scheduler consumes the same rewrite on fragment effects.
  // CHECK: function = @design, block = 0,
  // CHECK-SAME: effects = [#schedule.effect<effect = write, resource = storage, target = descriptor, descriptor = 0, formal = 0, low = 0, width = 1, dynamic = false, deferred = false, trigger = none>, #schedule.effect<effect = write, resource = storage, target = descriptor, descriptor = 1, formal = 0, low = 0, width = 1, dynamic = false, deferred = false, trigger = none>]
  // CHECK: function = @private, block = 0,
  // CHECK-SAME: effects = [#schedule.effect<effect = read, resource = storage, target = formal, descriptor = 0, formal = 1, low = 0, width = 1, dynamic = false, deferred = false, trigger = none>, #schedule.effect<effect = nba, resource = storage, target = formal, descriptor = 0, formal = 1, low = 0, width = 1, dynamic = false, deferred = false, trigger = none>]
  simulation.design @captures {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 fork hierarchy "test.captures.private"
    simulation.code_unit.decl 2 in 0 fork hierarchy "test.captures.relay"
    simulation.code_unit.decl 3 in 0 fork hierarchy "test.captures.forwarded"
    simulation.code_unit.decl 4 in 0 fork hierarchy "test.captures.design"
    simulation.code_unit.decl 5 in 0 function hierarchy "test.captures.helper"
    simulation.code_unit.decl 6 in 0 fork hierarchy "test.captures.called"
    simulation.code_unit.decl 7 in 0 fork hierarchy "test.captures.notify"
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i1 design

    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32} {
      %a = simulation.context.storage %ctx[0] : !r
      %b = simulation.context.storage %ctx[1] : !r
      %zero = arith.constant false
      %local = simulation.ref.alloc %zero : i1 -> !r
      %p0 = simulation.spawn @private(%ctx, %local) : !simulation.context, !r -> !simulation.process
      %p1 = simulation.spawn @relay(%ctx, %local) : !simulation.context, !r -> !simulation.process
      %p2 = simulation.spawn @design(%ctx, %a) : !simulation.context, !r -> !simulation.process
      %p3 = simulation.spawn @design(%ctx, %b) : !simulation.context, !r -> !simulation.process
      %p4 = simulation.spawn @design(%ctx, %local) : !simulation.context, !r -> !simulation.process
      %event = simulation.context.event %ctx[0] : !simulation.event
      %p5 = simulation.spawn @notify(%ctx, %event) : !simulation.context, !simulation.event -> !simulation.process
      simulation.call @helper(%ctx, %a) : (!simulation.context, !r) -> ()
      simulation.return
    }

    // CHECK-LABEL: simulation.func @private
    // CHECK-SAME: effect_summary = [#schedule.effect<effect = read, resource = storage, target = formal, descriptor = 0, formal = 1, low = 0, width = 1, dynamic = false, deferred = false, trigger = none>, #schedule.effect<effect = nba, resource = storage, target = formal, descriptor = 0, formal = 1, low = 0, width = 1, dynamic = false, deferred = false, trigger = none>]
    simulation.func @private(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !r {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 1 : i64} {
      %old = simulation.ref.load %state : !r -> i1
      %true = arith.constant true
      %new = arith.xori %old, %true : i1
      simulation.ref.store %new to %state : i1, !r
      simulation.nba.enqueue %new to %state : (i1, !r) -> ()
      simulation.return
    }

    simulation.func @relay(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !r {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 2 : i64} {
      %p = simulation.spawn @forwarded(%ctx, %state) : !simulation.context, !r -> !simulation.process
      simulation.return
    }

    // A capture forwarded by another spawn resolves through both.
    // CHECK-LABEL: simulation.func @forwarded
    // CHECK-SAME: effect_summary = []
    simulation.func @forwarded(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !r {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 3 : i64} {
      %false = arith.constant false
      simulation.ref.store %false to %state : i1, !r
      simulation.return
    }

    // Spawn sites pass two roots and a local, so the write updates exactly the
    // two roots.
    // CHECK-LABEL: simulation.func @design
    // CHECK-SAME: effect_summary = [#schedule.effect<effect = write, resource = storage, target = descriptor, descriptor = 0, formal = 0, low = 0, width = 1, dynamic = false, deferred = false, trigger = none>, #schedule.effect<effect = write, resource = storage, target = descriptor, descriptor = 1, formal = 0, low = 0, width = 1, dynamic = false, deferred = false, trigger = none>]
    simulation.func @design(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %target: !r {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64} {
      %false = arith.constant false
      simulation.ref.store %false to %target : i1, !r
      simulation.return
    }

    // An immediate trigger through a capture triggers its actual event.
    // CHECK-LABEL: simulation.func @notify
    // CHECK-SAME: effect_summary = [#schedule.effect<effect = trigger, resource = event, target = descriptor, descriptor = 0, formal = 0, low = 0, width = 64, dynamic = false, deferred = false, trigger = none>]
    simulation.func @notify(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %event: !simulation.event {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 7 : i64} {
      simulation.event.trigger %event nonblocking = false
      simulation.return
    }

    simulation.func @helper(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %target: !r {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %p = simulation.spawn @called(%ctx, %target) : !simulation.context, !r -> !simulation.process
      simulation.return
    }

    // The spawner's formal comes from a call, which any caller may supply.
    // CHECK-LABEL: simulation.func @called
    // CHECK-SAME: effect_summary = [#schedule.effect<effect = write, resource = storage, target = formal, descriptor = 0, formal = 1,
    simulation.func @called(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %target: !r {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 13 : i32, code_unit_id = 6 : i64} {
      %false = arith.constant false
      simulation.ref.store %false to %target : i1, !r
      simulation.return
    }
  }
}
