// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-sccp,simulation.func(canonicalize,cse),talos-sim-eliminate-dead-boundaries))' | FileCheck %s
// Equal by-value arguments include both packed planes. Different unknown
// masks of the same value plane must still reach the callee (1800-2023 13.5.1).
!logic = !simulation.logic<320>
!packed = !simulation.packed_array<319 : 0 x !simulation.logic<1>>
!ref = !simulation.ref<!logic>
module {
  simulation.design @wide_arguments {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !logic design
    simulation.code_unit.decl 1 in 0 function hierarchy "same"
    simulation.code_unit.decl 2 in 0 function hierarchy "mixed"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32} {
      %a = simulation.logic.constant 37 : i320, 4 : i320 : !logic
      %b = simulation.logic.constant 37 : i320, 8 : i320 : !logic
      %aa = simulation.packed.unflatten %a : (!logic) -> !packed
      %bb = simulation.packed.unflatten %b : (!logic) -> !packed
      simulation.call @same(%ctx, %aa) : (!simulation.context, !packed) -> ()
      simulation.call @mixed(%ctx, %aa) : (!simulation.context, !packed) -> ()
      simulation.call @same(%ctx, %aa) : (!simulation.context, !packed) -> ()
      simulation.call @mixed(%ctx, %bb) : (!simulation.context, !packed) -> ()
      simulation.return
    }
    simulation.func private @same(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
                                  %config: !packed {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %bits = simulation.packed.flatten %config : (!packed) -> !logic
      %state = simulation.context.storage %ctx[0] : !ref
      simulation.ref.store %bits to %state : !logic, !ref
      simulation.return
    }
    simulation.func private @mixed(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
                                   %config: !packed {simulation.capture_kind = 1 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %bits = simulation.packed.flatten %config : (!packed) -> !logic
      %state = simulation.context.storage %ctx[0] : !ref
      simulation.ref.store %bits to %state : !logic, !ref
      simulation.return
    }
  }
}
// CHECK-LABEL: simulation.func @root
// CHECK: simulation.call @same(%arg0)
// CHECK: simulation.call @mixed(%arg0, %
// CHECK-LABEL: simulation.func private @same(
// CHECK: simulation.logic.constant 37 : i320, 4 : i320
// CHECK-LABEL: simulation.func private @mixed(
// CHECK: simulation.packed.flatten %arg1
