// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s

// IEEE 1800-2023 4.9.4/9.4.2: an NBA scheduled by an event-controlled body
// commits after the body has returned to its event control. It can wake the
// same process. Suppressing a blocking self-write must preserve that path.
// CHECK: #schedule.nba_commit<id = [[COMMIT:[0-9]+]]
// CHECK-SAME: #schedule.edge<source = 2, target = [[COMMIT]], kind = nba_stage,
// CHECK-SAME: #schedule.edge<source = [[COMMIT]], target = 1, kind = nba_activate,
// CHECK-LABEL: simulation.func @loop(
// CHECK: simulation.suspend.change
// CHECK-SAME: schedule.procedural_event_wait, schedule.repeating_always_wait
// CHECK: simulation.nba.enqueue

!ref = !simulation.ref<!simulation.logic<1>>
module {
  simulation.design @event_wait_nba {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<1> design
    simulation.code_unit.decl 1 in 0 always hierarchy "top.loop"

    simulation.func @loop(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %a: !ref {simulation.capture_kind = 3 : i32,
                  simulation.descriptor_id = 0 : i64})
        attributes {entry_kind = 3 : i32, code_unit_id = 1 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %a to ^body
          {schedule.procedural_event_wait, schedule.repeating_always_wait} : !ref
    ^body:
      %one = simulation.logic.constant 1 : i1, 0 : i1 : !simulation.logic<1>
      simulation.nba.enqueue %one to %a : (!simulation.logic<1>, !ref) -> ()
      cf.br ^wait
    }
  }
}
