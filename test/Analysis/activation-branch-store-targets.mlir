// RUN: talos-opt %s '--test-talos-activation-regions=inputs=true reaching-values=true' -o %t.analyzed 2>&1 | FileCheck %s
// RUN: talos-opt %s -o %t.original
// RUN: diff %t.original %t.analyzed

// Two branches store the same value to different variables. Activation
// preparation must keep each store on its own branch: merging the blocks
// would store through a selected reference, which has no static target and
// forces whole-root live-ins instead of per-lane reaching values.
module {
  simulation.design @branch_store_targets {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    // CHECK-LABEL: regions @branch_targets valid=1
    // CHECK: values valid=1
    // CHECK-NEXT: value-input s0[0,1) s1[0,8){{$}}
    simulation.code_unit.decl 1 in 0 always_comb hierarchy "branch_targets"
    simulation.func @branch_targets(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 1 : i64} {
      %select = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %input = simulation.context.storage %ctx[1] : !simulation.ref<i8>
      %left = simulation.context.storage %ctx[2] : !simulation.ref<i8>
      %right = simulation.context.storage %ctx[3] : !simulation.ref<i8>
      %zero = arith.constant 0 : i8
      cf.br ^body
    ^body:
      simulation.ref.store %zero to %left : i8, !simulation.ref<i8>
      simulation.ref.store %zero to %right : i8, !simulation.ref<i8>
      %c = simulation.ref.load %select : !simulation.ref<i1> -> i1
      %v = simulation.ref.load %input : !simulation.ref<i8> -> i8
      cf.cond_br %c, ^to_left, ^to_right
    ^to_left:
      simulation.ref.store %v to %left : i8, !simulation.ref<i8>
      cf.br ^wait
    ^to_right:
      simulation.ref.store %v to %right : i8, !simulation.ref<i8>
      cf.br ^wait
    ^wait:
      simulation.suspend.any %select, %input edges [0, 0] to ^body : !simulation.ref<i1>, !simulation.ref<i8>
    }
  }
}
