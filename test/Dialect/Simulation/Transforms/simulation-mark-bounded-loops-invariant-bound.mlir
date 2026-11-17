// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-mark-bounded-loops)))' | FileCheck %s

// IEEE 1800-2023 12.7.1, 11.6.1: a loop `for (k = 0; k < c.n; k++)` over a
// by-value argument (13.5.1) runs against a bound that is fixed while it
// runs, even when the header recomputes it from the argument. Whatever that
// bound is, an unsigned counter stepping by one reaches it without wrapping,
// so the loop terminates. A bound loaded inside the loop, or carried by it,
// may change on every iteration and proves nothing. A larger step can jump
// past a maximal bound and wrap, so it proves nothing either.
!cfg = !simulation.packed_struct<[#simulation.field<name = "n", type = i32, ordinal = 0, packedOffset = 0>]>
module {
  simulation.design @invariant_bound {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 function hierarchy "argument"
    simulation.code_unit.decl 2 in 0 function hierarchy "loaded"
    simulation.code_unit.decl 3 in 0 function hierarchy "carried"
    simulation.code_unit.decl 4 in 0 function hierarchy "stride"
    simulation.code_unit.decl 5 in 0 function hierarchy "decreasing"

    // CHECK-LABEL: simulation.func @argument
    // CHECK: cf.cond_br %{{.*}}, ^{{.*}}, ^{{.*}} {schedule.bounded_loop_header}
    // CHECK: cf.br ^{{.*}}(%{{.*}} : i32) {schedule.bounded_loop_latch}
    simulation.func @argument(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %c: !cfg {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      cf.br ^head(%zero : i32)
    ^head(%k: i32):
      %bits = simulation.packed.flatten %c : (!cfg) -> i32
      %more = arith.cmpi ult, %k, %bits : i32
      cf.cond_br %more, ^body, ^exit
    ^body:
      %next = arith.addi %k, %one : i32
      cf.br ^head(%next : i32)
    ^exit:
      simulation.return %k : i32
    }

    // CHECK-LABEL: simulation.func @loaded
    // CHECK-NOT: schedule.bounded_loop_
    // CHECK: simulation.return
    simulation.func @loaded(%ctx: !simulation.context {simulation.capture_kind = 0 : i32})
        -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %bound = simulation.context.storage %ctx[0] : !simulation.ref<i32>
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      cf.br ^head(%zero : i32)
    ^head(%k: i32):
      %n = simulation.ref.load %bound : !simulation.ref<i32> -> i32
      %more = arith.cmpi ult, %k, %n : i32
      cf.cond_br %more, ^body, ^exit
    ^body:
      %next = arith.addi %k, %one : i32
      simulation.ref.store %next to %bound : i32, !simulation.ref<i32>
      cf.br ^head(%next : i32)
    ^exit:
      simulation.return %k : i32
    }

    // CHECK-LABEL: simulation.func @carried
    // CHECK-NOT: schedule.bounded_loop_
    // CHECK: simulation.return
    simulation.func @carried(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %start: i32 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      cf.br ^head(%zero, %start : i32, i32)
    ^head(%k: i32, %n: i32):
      %more = arith.cmpi ult, %k, %n : i32
      cf.cond_br %more, ^body, ^exit
    ^body:
      %next = arith.addi %k, %one : i32
      %grown = arith.addi %n, %one : i32
      cf.br ^head(%next, %grown : i32, i32)
    ^exit:
      simulation.return %k : i32
    }
    // CHECK-LABEL: simulation.func @stride
    // CHECK-NOT: schedule.bounded_loop_
    // CHECK: simulation.return
    simulation.func @stride(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %c: !cfg {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %zero = arith.constant 0 : i32
      %two = arith.constant 2 : i32
      cf.br ^head(%zero : i32)
    ^head(%k: i32):
      %bits = simulation.packed.flatten %c : (!cfg) -> i32
      %more = arith.cmpi ult, %k, %bits : i32
      cf.cond_br %more, ^body, ^exit
    ^body:
      %next = arith.addi %k, %two : i32
      cf.br ^head(%next : i32)
    ^exit:
      simulation.return %k : i32
    }

    // CHECK-LABEL: simulation.func @decreasing
    // CHECK: cf.cond_br %{{.*}}, ^{{.*}}, ^{{.*}} {schedule.bounded_loop_header}
    // CHECK: cf.br ^{{.*}}(%{{.*}} : i32) {schedule.bounded_loop_latch}
    simulation.func @decreasing(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
        %c: !cfg {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %start = arith.constant 100 : i32
      %one = arith.constant 1 : i32
      cf.br ^head(%start : i32)
    ^head(%k: i32):
      %bits = simulation.packed.flatten %c : (!cfg) -> i32
      %more = arith.cmpi ugt, %k, %bits : i32
      cf.cond_br %more, ^body, ^exit
    ^body:
      %next = arith.subi %k, %one : i32
      cf.br ^head(%next : i32)
    ^exit:
      simulation.return %k : i32
    }
  }
}
