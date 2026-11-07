// RUN: talos-opt %s --test-talos-local-unknown='minimum-read-work=1' -o /dev/null 2>&1 | FileCheck %s
// A payload forwarded unchanged into an NBA can be X indefinitely. Retaining
// its exact plane must allow an independent guarded arithmetic cone in the
// same fused body. Excluding a premise changes profitability, not semantics:
// sparse value facts still carry the payload's possible X/Z to every use.
// LRM 6.3.1, 10.4.2: retain the exact captured NBA payload.
!c = !simulation.context
!l8 = !simulation.logic<8>
!r8 = !simulation.ref<!l8>
module {
  simulation.design @forwarded_payload {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !l8 design
    simulation.storage.decl 1 in 0 : !l8 design
    simulation.storage.decl 2 in 0 : !l8 design
    simulation.code_unit.decl 1 in 0 function hierarchy "forwarded_payload"
    // CHECK-LABEL: local-unknown @forwarded_payload
    // CHECK-SAME: gate: 0
    // CHECK-NEXT: read arithmetic: gated
    // CHECK-NEXT: read payload: unresolved
    simulation.func @forwarded_payload(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %source = simulation.context.storage %ctx[0] : !r8
      %payload = simulation.context.storage %ctx[1] : !r8
      %out = simulation.context.storage %ctx[2] : !r8
      %value = simulation.ref.load %source {test.read = "arithmetic"} : !r8 -> !l8
      %data = simulation.ref.load %payload {test.read = "payload"} : !r8 -> !l8
      simulation.nba.enqueue %data to %out : (!l8, !r8) -> ()
      %p0 = simulation.logic.binary mul %value, %value : !l8
      %p1 = simulation.logic.binary mul %p0, %value : !l8
      %p2 = simulation.logic.binary mul %p1, %value : !l8
      %p3 = simulation.logic.binary mul %p2, %value : !l8
      %p4 = simulation.logic.binary mul %p3, %value : !l8
      %p5 = simulation.logic.binary mul %p4, %value : !l8
      %p6 = simulation.logic.binary mul %p5, %value : !l8
      %p7 = simulation.logic.binary mul %p6, %value : !l8
      %p8 = simulation.logic.binary mul %p7, %value : !l8
      %p9 = simulation.logic.binary mul %p8, %value : !l8
      %p10 = simulation.logic.binary mul %p9, %value : !l8
      %p11 = simulation.logic.binary mul %p10, %value : !l8
      %p12 = simulation.logic.binary mul %p11, %value : !l8
      %p13 = simulation.logic.binary mul %p12, %value : !l8
      %p14 = simulation.logic.binary mul %p13, %value : !l8
      %p15 = simulation.logic.binary mul %p14, %value : !l8
      simulation.return %p15 : !l8
    }
  }
}
