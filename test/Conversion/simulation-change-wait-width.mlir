// RUN: talos-opt %s --pass-pipeline='builtin.module(prepare-native-schedule-inputs,schedule-plan-native-state,prepare-native-process-frames,schedule-plan-native-actors,schedule-specialize-native-captures,convert-simulation-to-native-schedule,prepare-native-managed-roots,schedule-mark-clean-native-nba,schedule-specialize-native-eval,schedule-annotate-compact-nba,prepare-native-fragments)' --verify-each | FileCheck %s
// IEEE 1800-2023 9.4.2: Change watches the entire value; only directed
// edges scalarize to the LSB. The separate iff condition keeps its own width.
// CHECK: schedule.suspend.edge change
// CHECK-SAME: native.wait_widths = array<i32: 65>
// CHECK: schedule.suspend.edge_iff change
// CHECK-SAME: native.wait_widths = array<i32: 65, 2>
// CHECK: schedule.suspend.edge posedge
// CHECK-SAME: native.wait_widths = array<i32: 1>
// CHECK: schedule.suspend.edge_iff negedge
// CHECK-SAME: native.wait_widths = array<i32: 1, 2>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu"} {
  simulation.design @widths {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 initial hierarchy "test.widths"
    simulation.func @widths(
        %ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %clock: !simulation.ref<!simulation.logic<65>> {simulation.capture_kind = 1 : i32},
        %condition: !simulation.ref<!simulation.logic<2>> {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 1 : i64} {
      simulation.suspend.edge change %clock to ^iff : !simulation.ref<!simulation.logic<65>>
    ^iff:
      simulation.suspend.edge_iff change %clock iff %condition to ^positive : !simulation.ref<!simulation.logic<65>>, !simulation.ref<!simulation.logic<2>>
    ^positive:
      simulation.suspend.edge posedge %clock to ^negative : !simulation.ref<!simulation.logic<65>>
    ^negative:
      simulation.suspend.edge_iff negedge %clock iff %condition to ^end : !simulation.ref<!simulation.logic<65>>, !simulation.ref<!simulation.logic<2>>
    ^end:
      simulation.return
    }
  }
}
