// RUN: talos-opt %s --test-talos-activation-regions='slice-order=true reaching-values=true' -o /dev/null 2>&1 | FileCheck %s

// producer and independent start ready. Finishing producer unblocks its
// consumer, which should get the forwarded value before independent runs.
// CHECK: slice graph: acyclic
// CHECK-NEXT: slice order: @producer @consumer @independent{{$}}

!c = !simulation.context
!r = !simulation.ref<i8>
module {
  simulation.design @order {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "producer"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "independent"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "consumer"
    simulation.func @producer(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      cf.br ^body
    ^body:
      %src = simulation.context.storage %ctx[0] : !r
      %dst = simulation.context.storage %ctx[1] : !r
      %v = simulation.ref.load %src : !r -> i8
      simulation.ref.store %v to %dst : i8, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func @independent(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %src = simulation.context.storage %ctx[0] : !r
      %dst = simulation.context.storage %ctx[2] : !r
      %v = simulation.ref.load %src : !r -> i8
      simulation.ref.store %v to %dst : i8, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func @consumer(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %src = simulation.context.storage %ctx[1] : !r
      %dst = simulation.context.storage %ctx[3] : !r
      %v = simulation.ref.load %src : !r -> i8
      simulation.ref.store %v to %dst : i8, !r
      simulation.suspend.change %src to ^body : !r
    }
  }
}
