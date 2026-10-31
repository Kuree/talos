// RUN: talos-opt %s -o %t.mlir --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph),test-talos-native-aot-analysis)' 2>&1 | FileCheck %s
// IEEE 1801-2018 6.50/9.7: the closed generated clock loop does not yet
// publish cohort transitions. Retain native coroutines under the shared
// scheduler, instead of admitting an ordering query to a stale closed plan.
// CHECK: native-aot eligible=false fully=false
// CHECK-NEXT: reason scheduler cohort requires runtime calendar ordering
module {
  simulation.design @cohort_requires_runtime {
    simulation.scope.decl 0 hierarchy "top"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "top.root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "top.initial"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @initial(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @initial(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %cohort = simulation.scheduler.cohort %ctx
      %fmt = simulation.bytes.constant "%0d"
      %stdout = arith.constant 1 : i32
      simulation.display %ctx to %stdout(%fmt, %cohort) newline = true radix = <decimal> flags = [0,0] : !simulation.bytes, i64
      simulation.return
    }
  }
}
