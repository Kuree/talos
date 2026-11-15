// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph))' | FileCheck %s

// IEEE 1800-2023 9.4.2: the outer event control of an always procedure has
// completed while its body runs, so the body's own blocking update does not
// enable that wait again; only an update made while waiting can. No
// self-sensitivity edge connects the body to its own outer wait.
// CHECK-LABEL: simulation.design @repeating_always attributes {compute_graph = #schedule.graph<
// CHECK-SAME: #schedule.fragment<id = [[WAIT:[0-9]+]], function = @process, block = 1
// CHECK-SAME: effect = watch
// CHECK-SAME: #schedule.fragment<id = [[BODY:[0-9]+]], function = @process, block = 2
// CHECK-SAME: effect = write
// CHECK-SAME: edges = [
// CHECK-NOT: kind = sensitivity
// CHECK-SAME: regions =
module {
  simulation.design @repeating_always {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 always hierarchy "top.process"
    simulation.storage.decl 0 in 0 : !simulation.logic<1> design

    simulation.func @process(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %state: !simulation.ref<!simulation.logic<1>> {
          simulation.capture_kind = 3 : i32,
          simulation.descriptor_id = 0 : i64
        }) attributes {entry_kind = 3 : i32, code_unit_id = 1 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %state to ^body {
          schedule.procedural_event_wait,
          schedule.repeating_always_wait
        } : !simulation.ref<!simulation.logic<1>>
    ^body:
      %value = simulation.ref.load %state :
          !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      simulation.ref.store %value to %state : !simulation.logic<1>,
          !simulation.ref<!simulation.logic<1>>
      cf.br ^wait
    }
  }
}
