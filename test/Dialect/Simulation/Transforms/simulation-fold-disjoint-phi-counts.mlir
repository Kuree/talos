// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-fold-small-domains)))' | FileCheck %s

// IEEE 1800-2023 12.4.2/12.5.3: a grouped Boolean predicate counts as one
// item. Every incoming phi edge must justify its true value; loop-carried
// predicates and unsupported predecessors retain runtime checking.

// -----

module {
  simulation.design @grouped_short_circuit {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "grouped_short_circuit"
    // CHECK-LABEL: simulation.func @grouped_short_circuit
    // CHECK-NOT: arith.constant 99
    // CHECK: simulation.return
    simulation.func @grouped_short_circuit(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i4 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %zero = arith.constant 0 : i4
      %v1 = arith.constant 1 : i4
      %v2 = arith.constant 2 : i4
      %true = arith.constant true
      %false = arith.constant false
      %p0 = arith.cmpi eq, %x, %zero : i4
      %p1 = arith.cmpi eq, %x, %v1 : i4
      %p2 = arith.cmpi eq, %x, %v2 : i4
      %e0 = arith.extui %p0 : i1 to i32
      cf.cond_br %p1, ^join(%true : i1), ^next
    ^next:
      cf.cond_br %p2, ^join(%true : i1), ^join(%false : i1)
    ^join(%group: i1):
      %increment = arith.addi %e0, %one : i32
      %count = arith.select %group, %increment, %e0 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @grouped_or_is_one_item {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "grouped_or_is_one_item"
    // CHECK-LABEL: simulation.func @grouped_or_is_one_item
    // CHECK-NOT: arith.constant 99
    // CHECK: simulation.return
    simulation.func @grouped_or_is_one_item(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %zero = arith.constant 0 : i20
      %v1 = arith.constant 1 : i20
      %v2 = arith.constant 2 : i20
      %true = arith.constant true
      %false = arith.constant false
      %p0 = arith.cmpi eq, %x, %zero : i20
      %p1 = arith.cmpi eq, %x, %v1 : i20
      %p2 = arith.cmpi eq, %x, %v2 : i20
      %e0 = arith.extui %p0 : i1 to i32
      %group = arith.ori %p1, %p1 : i1
      %increment = arith.addi %e0, %one : i32
      %count = arith.select %group, %increment, %e0 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @forwarded_predicates {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "forwarded_predicates"
    // CHECK-LABEL: simulation.func @forwarded_predicates
    // CHECK-NOT: arith.constant 99
    // CHECK: simulation.return
    simulation.func @forwarded_predicates(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}, %choose: i1 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %zero = arith.constant 0 : i20
      %v1 = arith.constant 1 : i20
      %v2 = arith.constant 2 : i20
      %true = arith.constant true
      %false = arith.constant false
      %p0 = arith.cmpi eq, %x, %zero : i20
      %p1 = arith.cmpi eq, %x, %v1 : i20
      %p2 = arith.cmpi eq, %x, %v2 : i20
      %e0 = arith.extui %p0 : i1 to i32
      cf.cond_br %choose, ^left, ^right
    ^left:
      cf.br ^join(%p1 : i1)
    ^right:
      cf.br ^join(%p2 : i1)
    ^join(%group: i1):
      %increment = arith.addi %e0, %one : i32
      %count = arith.select %group, %increment, %e0 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @false_edge_of_ne {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "false_edge_of_ne"
    // CHECK-LABEL: simulation.func @false_edge_of_ne
    // CHECK-NOT: arith.constant 99
    // CHECK: simulation.return
    simulation.func @false_edge_of_ne(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %zero = arith.constant 0 : i20
      %v1 = arith.constant 1 : i20
      %v2 = arith.constant 2 : i20
      %true = arith.constant true
      %false = arith.constant false
      %p0 = arith.cmpi eq, %x, %zero : i20
      %p1 = arith.cmpi eq, %x, %v1 : i20
      %p2 = arith.cmpi eq, %x, %v2 : i20
      %e0 = arith.extui %p0 : i1 to i32
      %not1 = arith.cmpi ne, %x, %v1 : i20
      cf.cond_br %not1, ^join(%false : i1), ^join(%true : i1)
    ^join(%group: i1):
      %increment = arith.addi %e0, %one : i32
      %count = arith.select %group, %increment, %e0 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @false_edge_of_eq {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "false_edge_of_eq"
    // CHECK-LABEL: simulation.func @false_edge_of_eq
    // CHECK: %[[MULTI:.*]] = arith.cmpi sgt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @false_edge_of_eq(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %zero = arith.constant 0 : i20
      %v1 = arith.constant 1 : i20
      %v2 = arith.constant 2 : i20
      %true = arith.constant true
      %false = arith.constant false
      %p0 = arith.cmpi eq, %x, %zero : i20
      %p1 = arith.cmpi eq, %x, %v1 : i20
      %p2 = arith.cmpi eq, %x, %v2 : i20
      %e0 = arith.extui %p0 : i1 to i32
      cf.cond_br %p1, ^join(%false : i1), ^join(%true : i1)
    ^join(%group: i1):
      %increment = arith.addi %e0, %one : i32
      %count = arith.select %group, %increment, %e0 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @unconditional_true_predecessor {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "unconditional_true_predecessor"
    // CHECK-LABEL: simulation.func @unconditional_true_predecessor
    // CHECK: %[[MULTI:.*]] = arith.cmpi sgt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @unconditional_true_predecessor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}, %choose: i1 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %zero = arith.constant 0 : i20
      %v1 = arith.constant 1 : i20
      %v2 = arith.constant 2 : i20
      %true = arith.constant true
      %false = arith.constant false
      %p0 = arith.cmpi eq, %x, %zero : i20
      %p1 = arith.cmpi eq, %x, %v1 : i20
      %p2 = arith.cmpi eq, %x, %v2 : i20
      %e0 = arith.extui %p0 : i1 to i32
      cf.cond_br %choose, ^known, ^unknown
    ^known:
      cf.cond_br %p1, ^join(%true : i1), ^join(%false : i1)
    ^unknown:
      cf.br ^join(%true : i1)
    ^join(%group: i1):
      %increment = arith.addi %e0, %one : i32
      %count = arith.select %group, %increment, %e0 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @shared_group_is_counted_twice {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "shared_group_is_counted_twice"
    // CHECK-LABEL: simulation.func @shared_group_is_counted_twice
    // CHECK: %[[MULTI:.*]] = arith.cmpi sgt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @shared_group_is_counted_twice(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %zero = arith.constant 0 : i20
      %v1 = arith.constant 1 : i20
      %v2 = arith.constant 2 : i20
      %true = arith.constant true
      %false = arith.constant false
      %p0 = arith.cmpi eq, %x, %zero : i20
      %p1 = arith.cmpi eq, %x, %v1 : i20
      %p2 = arith.cmpi eq, %x, %v2 : i20
      %e0 = arith.extui %p0 : i1 to i32
      %group = arith.ori %p1, %p2 : i1
      %e = arith.extui %group : i1 to i32
      %count = arith.addi %e, %e : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^done
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}

// -----

module {
  simulation.design @loop_carried_predicate {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 function hierarchy "loop_carried_predicate"
    // CHECK-LABEL: simulation.func @loop_carried_predicate
    // CHECK: %[[MULTI:.*]] = arith.cmpi sgt
    // CHECK: cf.cond_br %[[MULTI]]
    simulation.func @loop_carried_predicate(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: i20 {simulation.capture_kind = 1 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %one = arith.constant 1 : i32
      %zero = arith.constant 0 : i20
      %v1 = arith.constant 1 : i20
      %false = arith.constant false
      cf.br ^loop(%x, %false : i20, i1)
    ^loop(%current: i20, %group: i1):
      %p0 = arith.cmpi eq, %current, %zero : i20
      %e0 = arith.extui %p0 : i1 to i32
      %increment = arith.addi %e0, %one : i32
      %count = arith.select %group, %increment, %e0 : i32
      %multi = arith.cmpi sgt, %count, %one : i32
      cf.cond_br %multi, ^report, ^advance
    ^advance:
      %was1 = arith.cmpi eq, %current, %v1 : i20
      cf.br ^loop(%zero, %was1 : i20, i1)
    ^report:
      %bad = arith.constant 99 : i32
      simulation.return %bad : i32
    ^done:
      simulation.return %count : i32
    }
  }
}
