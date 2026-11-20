// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-inline{opt-level=3 tiny-cost=0 specialization-cost=100 caller-growth-constant=100 design-growth-constant=100}))' | FileCheck %s
//
// A caller with a nonconstant scalar argument can probe the cold exit when
// its callee is inlined. Preserve the condition and its terminating action.
module {
  simulation.design @conditional_exit {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "check"
    simulation.code_unit.decl 2 in 0 function hierarchy "caller"
    simulation.func private @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %invalid: i1 {simulation.capture_kind = 1 : i32}) -> i1 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      cf.cond_br %invalid, ^error, ^ok
    ^error:
      %status = arith.constant 1 : i32
      simulation.fatal %ctx, %status
      simulation.return %invalid : i1
    ^ok:
      simulation.return %invalid : i1
    }
    simulation.func @caller(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %runtime: i1 {simulation.capture_kind = 1 : i32}) -> i1 attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %value = simulation.call @check(%ctx, %runtime) : (!simulation.context, i1) -> i1
      simulation.return %value : i1
    }
  }
}
// CHECK-LABEL: simulation.func @caller(
// CHECK: cf.cond_br %arg1
// CHECK: simulation.fatal
// CHECK-NOT: simulation.call
// CHECK: simulation.return
