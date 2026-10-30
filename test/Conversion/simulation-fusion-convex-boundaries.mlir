// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph),test-talos-edit-attributes{op=simulation.design set={schedule.static_body_fusion = [#schedule.fusion<id = 0, fragments = [1, 5], interleaved = true>]}},simulation.design(talos-sim-materialize-compute-fusion))' | FileCheck %s --implicit-check-not=__talos_region_kernel_
// A -> B -> C crosses an effectful original executor. Even a forged plan
// that requests A and C must fail independent materialization validation.
// CHECK: simulation.spawn @a
// CHECK: simulation.spawn @b
// CHECK: simulation.spawn @c
// CHECK: simulation.func @b
// CHECK: simulation.display
!ctx = !simulation.context
!r = !simulation.ref<i8>
module {
  simulation.design @nonconvex {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "a"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "b"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "c"
    simulation.func @root(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32} {
      %a = simulation.spawn @a(%ctx) : !ctx -> !simulation.process
      %b = simulation.spawn @b(%ctx) : !ctx -> !simulation.process
      %c = simulation.spawn @c(%ctx) : !ctx -> !simulation.process
      simulation.return
    }
    simulation.func @a(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %in = simulation.context.storage %ctx[0] : !r
      %out = simulation.context.storage %ctx[1] : !r
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> i8
      simulation.ref.store %v to %out : i8, !r
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func @b(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %in = simulation.context.storage %ctx[1] : !r
      %out = simulation.context.storage %ctx[2] : !r
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> i8
      simulation.ref.store %v to %out : i8, !r
      %fmt = simulation.bytes.constant "boundary %0d"
      %channel = arith.constant 1 : i32
      simulation.display %ctx to %channel(%fmt, %v) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i8
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func @c(%ctx: !ctx {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %in = simulation.context.storage %ctx[2] : !r
      %out = simulation.context.storage %ctx[3] : !r
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> i8
      simulation.ref.store %v to %out : i8, !r
      simulation.suspend.change %in to ^body : !r
    }
  }
}
