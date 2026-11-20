// RUN: talos-opt %s -o /dev/null --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph),test-talos-native-aot-analysis)' 2>&1 | FileCheck %s

// A partial run order cannot assign ranks to its missing actor.
// CHECK: native-aot eligible=false
// CHECK: reason Active preemption has an invalid source actor

module {
  simulation.design @preemption {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "actor"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      simulation.spawn @actor(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @actor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %zero = simulation.time.constant 0
      simulation.suspend.delay %zero to ^done {resume_region = 2 : i32,
          schedule.active_preemption_after = ["missing"]}
    ^done:
      simulation.return
    }
  }
}
