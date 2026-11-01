// RUN: talos-opt %s -o /dev/null \
// RUN:   --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph),test-talos-native-aot-analysis)' \
// RUN:   2>&1 | FileCheck %s

// IEEE 1800-2023 4.9.5: a switch's control change re-resolves every node the
// switch connects. The runtime owns that topology change, so a generated plan
// must not admit a process that makes it.
// CHECK: native-aot eligible=false fully=false
// CHECK-NEXT: reason switch control requires generic ordering

module {
  simulation.design @pass_control_ineligible {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !simulation.logic<1> design
    simulation.net.decl 1 in 0 : !simulation.logic<1> design
    simulation.net.pass.decl 0 in 0 0[0] to 1[0] width 1 reversed = false {
      controlled = true
    }
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "initial"

    simulation.func @root(
        %ctx: !simulation.context
            {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %initial = simulation.spawn @initial(%ctx) :
          !simulation.context -> !simulation.process
      simulation.return
    }

    simulation.func @initial(
        %ctx: !simulation.context
            {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %one = simulation.logic.constant true, false : !simulation.logic<1>
      simulation.net.pass.control 0 = %one : !simulation.logic<1>
      simulation.return
    }
  }
}
