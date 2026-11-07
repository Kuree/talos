// RUN: talos-opt %s --test-talos-local-unknown -o /dev/null 2>&1 | FileCheck %s
// IEEE 1800-2023 6.6.1: a lone strong contribution equals its net bits.
// Its old unknown plane may be left untouched only if it and the new payload
// are known. Dense may-write facts include publications even with no later
// reads. A known write clears X/Z (4.6(a)); only later known writes can elide
// that clear without an entry check. Undriven holes stay Z (6.7.1).
!c = !simulation.context
!l8 = !simulation.logic<8>
!l32 = !simulation.logic<32>
!net = !simulation.net<!l32>
!driver = !simulation.driver<!l32>
!d8 = !simulation.driver<!l8>
module {
  simulation.design @net_stores {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !l32 design
    simulation.driver.decl 0 in 0 drives 0 : !l32 design {driven_low = 24 : i64, driven_width = 8 : i64}
    simulation.code_unit.decl 1 in 0 function hierarchy "write_only_known"
    simulation.code_unit.decl 2 in 0 function hierarchy "clear"
    simulation.code_unit.decl 3 in 0 function hierarchy "conditional_x"
    simulation.code_unit.decl 4 in 0 function hierarchy "deferred_known"
    simulation.code_unit.decl 5 in 0 function hierarchy "deferred_x"
    // CHECK-LABEL: local-unknown @write_only_known
    // CHECK-NEXT: net-gate 0[24+:8]
    // CHECK-NEXT: store entry: known
    simulation.func @write_only_known(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d = simulation.context.driver %ctx[0] : !driver
      %hi = simulation.driver.extract %d from 24 : !driver -> !d8
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      simulation.driver.drive %hi = %one {test.store = "entry"} : !d8, !l8
      simulation.return
    }
    // CHECK-LABEL: local-unknown @clear
    // CHECK-NEXT: store x: four-state
    // CHECK-NEXT: store clear: four-state
    // CHECK-NEXT: store after_clear: known
    simulation.func @clear(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %d = simulation.context.driver %ctx[0] : !driver
      %hi = simulation.driver.extract %d from 24 : !driver -> !d8
      %x = simulation.logic.constant 0 : i8, -1 : i8 : !l8
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      simulation.driver.drive %hi = %x {test.store = "x"} : !d8, !l8
      simulation.driver.drive %hi = %one {test.store = "clear"} : !d8, !l8
      simulation.driver.drive %hi = %one {test.store = "after_clear"} : !d8, !l8
      simulation.return
    }
    // No read follows either branch's writer. Query liveness must still
    // preserve the possible X before the first known publication.
    // CHECK-LABEL: local-unknown @conditional_x
    // CHECK-NEXT: store branch_x: four-state
    // CHECK-NEXT: store join_clear: four-state
    // CHECK-NEXT: store after_join: known
    simulation.func @conditional_x(%ctx: !c {simulation.capture_kind = 0 : i32}, %take: i1 {simulation.capture_kind = 2 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      %d = simulation.context.driver %ctx[0] : !driver
      %hi = simulation.driver.extract %d from 24 : !driver -> !d8
      %x = simulation.logic.constant 0 : i8, -1 : i8 : !l8
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      cf.cond_br %take, ^change, ^join
    ^change:
      simulation.driver.drive %hi = %x {test.store = "branch_x"} : !d8, !l8
      cf.br ^join
    ^join:
      simulation.driver.drive %hi = %one {test.store = "join_clear"} : !d8, !l8
      simulation.driver.drive %hi = %one {test.store = "after_join"} : !d8, !l8
      simulation.return
    }
    // CHECK-LABEL: local-unknown @deferred_known
    // CHECK-NEXT: read deferred_known: written
    // CHECK-NEXT: store deferred_known_defer: four-state
    // CHECK-NEXT: store deferred_known_publish: four-state
    simulation.func @deferred_known(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %d = simulation.context.driver %ctx[0] : !driver
      %wide = simulation.logic.constant 0 : i32, 0 : i32 : !l32
      simulation.driver.drive %d = %wide {schedule.defer_net_resolution, test.store = "deferred_known_defer"} : !driver, !l32
      %n = simulation.context.net %ctx[0] : !net
      %v = simulation.net.read %n {test.read = "deferred_known"} : !net -> !l32
      %r = simulation.logic.extract %v from 24 : !l32 -> !l8
      %hi = simulation.driver.extract %d from 24 : !driver -> !d8
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      simulation.driver.drive %hi = %one {test.store = "deferred_known_publish"} : !d8, !l8
      simulation.return %r : !l8
    }
    // CHECK-LABEL: local-unknown @deferred_x
    // CHECK-NEXT: read deferred_x: written
    // CHECK-NEXT: store deferred_x_defer: four-state
    // CHECK-NEXT: store deferred_x_publish: four-state
    simulation.func @deferred_x(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %d = simulation.context.driver %ctx[0] : !driver
      %wide = simulation.logic.constant 0 : i32, -1 : i32 : !l32
      simulation.driver.drive %d = %wide {schedule.defer_net_resolution, test.store = "deferred_x_defer"} : !driver, !l32
      %n = simulation.context.net %ctx[0] : !net
      %v = simulation.net.read %n {test.read = "deferred_x"} : !net -> !l32
      %r = simulation.logic.extract %v from 24 : !l32 -> !l8
      %hi = simulation.driver.extract %d from 24 : !driver -> !d8
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      simulation.driver.drive %hi = %one {test.store = "deferred_x_publish"} : !d8, !l8
      simulation.return %r : !l8
    }
  }
}
