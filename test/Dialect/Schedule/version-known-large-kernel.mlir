// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-unroll-loops,schedule-version-known-activations{minimum-benefit=1})' -o /dev/null 2>&1 | FileCheck %s
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 0 : i64}"},test-talos-unroll-loops,schedule-version-known-activations{minimum-benefit=1})' -o /dev/null 2>&1 | FileCheck %s --allow-empty --check-prefix=UNLIMITED

// A clocked kernel above the inline budget fuses many independent processes, so
// one X/Z among all their inputs would send every member to its four-state body.
// Its source therefore gets known copies of its member runs, even with a
// whole-body two-state variant (IEEE 1800-2023 6.3.1). They are cut small, and
// bounded: only half the segments get a copy, the variant being a copy already.
// CHECK: talos known activation: __talos_clocked_0_1_0.__talos_eval_body_0 segments=3/7 
// A source with a variant keeps its one body otherwise: so does a small kernel,
// and so does any other large function.
// CHECK-NOT: talos known activation: __talos_clocked_0_2_0
// CHECK-NOT: talos known activation: large_function

// Without an inline budget nothing counts as large.
// UNLIMITED-NOT: talos known activation

!c = !simulation.context
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
module attributes {native.optimization_level = 3 : i32, native.debug_timing, schedule.native.max_inline_ops = 64 : i64} {
  simulation.design @large_kernel {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !l8 design
    simulation.storage.decl 1 in 0 : !l8 design
    simulation.code_unit.decl 1 in 0 function hierarchy "top.kernel"
    simulation.code_unit.decl 2 in 0 function hierarchy "top.small"
    simulation.code_unit.decl 3 in 0 function hierarchy "top.other"
    simulation.code_unit.decl 4 in 0 function hierarchy "top.variant"
    simulation.func @two_state_body(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      simulation.return
    }
    simulation.func @__talos_clocked_0_1_0.__talos_eval_body_0(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64, schedule.eval.two_state_variant = @two_state_body} {
      %a = simulation.context.storage %ctx[0] : !r8
      %b = simulation.context.storage %ctx[1] : !r8
      %lower = arith.constant 0 : index
      %upper = arith.constant 200 : index
      %step = arith.constant 1 : index
      scf.for %i = %lower to %upper step %step {
        %x = simulation.ref.load %a : !r8 -> !l8
        %y = simulation.logic.binary add %x, %x : !l8
        %z = simulation.logic.binary and %y, %x : !l8
        simulation.ref.store %z to %b : !l8, !r8
      }
      simulation.return
    }
    simulation.func @__talos_clocked_0_2_0.__talos_eval_body_0(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64, schedule.eval.two_state_variant = @two_state_body} {
      %a = simulation.context.storage %ctx[0] : !r8
      %x = simulation.ref.load %a : !r8 -> !l8
      %y = simulation.logic.binary add %x, %x : !l8
      simulation.ref.store %y to %a : !l8, !r8
      simulation.return
    }
    simulation.func @large_function(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64, schedule.eval.two_state_variant = @two_state_body} {
      %a = simulation.context.storage %ctx[0] : !r8
      %b = simulation.context.storage %ctx[1] : !r8
      %lower = arith.constant 0 : index
      %upper = arith.constant 200 : index
      %step = arith.constant 1 : index
      scf.for %i = %lower to %upper step %step {
        %x = simulation.ref.load %a : !r8 -> !l8
        %y = simulation.logic.binary add %x, %x : !l8
        %z = simulation.logic.binary and %y, %x : !l8
        simulation.ref.store %z to %b : !l8, !r8
      }
      simulation.return
    }
  }
}
