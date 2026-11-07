// RUN: talos-opt %s --test-talos-local-unknown -o /dev/null 2>&1 | FileCheck %s

// IEEE 1800-2023 6.7.1: undriven packed positions stay Z. Only the high
// element is observed (7.4.1), so its guard must not include the Z holes.
// The same sparse value / dense write solve must preserve an explicit X
// write and distinguish writes on every path from writes on one path.
!c = !simulation.context
!l8 = !simulation.logic<8>
!array = !simulation.packed_array<3 : 0 x !l8>
!net = !simulation.net<!array>
!driver = !simulation.driver<!array>
module {
  simulation.design @net_ranges {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !array design
    simulation.driver.decl 0 in 0 drives 0 : !array design {driven_low = 0 : i64, driven_width = 8 : i64}
    simulation.driver.decl 1 in 0 drives 0 : !array design {driven_low = 24 : i64, driven_width = 8 : i64}
    simulation.net.decl 1 in 0 : !simulation.packed_struct<[#simulation.field<name = "a", type = !l8, ordinal = 0, packedOffset = 8>, #simulation.field<name = "b", type = !l8, ordinal = 1, packedOffset = 0>]> design
    simulation.net.decl 2 in 0 : !simulation.packed_array<0 : 3 x !l8> design
    simulation.code_unit.decl 6 in 0 function hierarchy "record"
    simulation.code_unit.decl 7 in 0 function hierarchy "ascending"
    simulation.code_unit.decl 1 in 0 function hierarchy "holes"
    simulation.code_unit.decl 2 in 0 function hierarchy "written"
    simulation.code_unit.decl 3 in 0 function hierarchy "conditional"
    simulation.code_unit.decl 4 in 0 function hierarchy "mixed"
    simulation.code_unit.decl 5 in 0 function hierarchy "snapshot"
    // CHECK-LABEL: local-unknown @holes
    // CHECK-NEXT: net-gate 0[24+:8]
    // CHECK-NEXT: read holes: gated
    simulation.func @holes(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %n = simulation.context.net %ctx[0] : !net
      %v = simulation.net.read %n {test.read = "holes"} : !net -> !array
      %r = simulation.aggregate.extract %v[0] : (!array) -> !l8
      simulation.return %r : !l8
    }
    // An unconditional known drive removes the read's entry obligation;
    // eliding the drive's unknown-plane store still needs its old bits known.
    // CHECK-LABEL: local-unknown @written
    // CHECK-NEXT: net-gate 0[24+:8]
    // CHECK-NEXT: read written: gated
    // CHECK-NEXT: store written: known
    simulation.func @written(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %d = simulation.context.driver %ctx[1] : !driver
      %hi = simulation.driver.extract %d from 24 : !driver -> !simulation.driver<!l8>
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      simulation.driver.drive %hi = %one {test.store = "written"} : !simulation.driver<!l8>, !l8
      %n = simulation.context.net %ctx[0] : !net
      %v = simulation.net.read %n {test.read = "written"} : !net -> !array
      %r = simulation.aggregate.extract %v[0] : (!array) -> !l8
      simulation.return %r : !l8
    }
    // One path cannot discharge the entry obligation of the other.
    // CHECK-LABEL: local-unknown @conditional
    // CHECK-NEXT: net-gate 0[24+:8]
    // CHECK-NEXT: read conditional: gated
    simulation.func @conditional(%ctx: !c {simulation.capture_kind = 0 : i32}, %take: i1 {simulation.capture_kind = 2 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64} {
      cf.cond_br %take, ^write, ^join
    ^write:
      %d = simulation.context.driver %ctx[1] : !driver
      %hi = simulation.driver.extract %d from 24 : !driver -> !simulation.driver<!l8>
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      simulation.driver.drive %hi = %one : !simulation.driver<!l8>, !l8
      cf.br ^join
    ^join:
      %n = simulation.context.net %ctx[0] : !net
      %v = simulation.net.read %n {test.read = "conditional"} : !net -> !array
      %r = simulation.aggregate.extract %v[0] : (!array) -> !l8
      simulation.return %r : !l8
    }
    // An X write to low bits cannot erase the high bits' entry guard.
    // Low remains four-state; only the high element can use the guard.
    // CHECK-LABEL: local-unknown @mixed
    // CHECK-NEXT: net-gate 0[24+:8]
    // CHECK-NEXT: read mixed: written
    simulation.func @mixed(%ctx: !c {simulation.capture_kind = 0 : i32}) -> (!l8, !l8)
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %d = simulation.context.driver %ctx[0] : !driver
      %lo = simulation.driver.extract %d from 0 : !driver -> !simulation.driver<!l8>
      %x = simulation.logic.constant 0 : i8, -1 : i8 : !l8
      simulation.driver.drive %lo = %x : !simulation.driver<!l8>, !l8
      %n = simulation.context.net %ctx[0] : !net
      %v = simulation.net.read %n {test.read = "mixed"} : !net -> !array
      %hi = simulation.aggregate.extract %v[0] : (!array) -> !l8
      %low = simulation.aggregate.extract %v[3] : (!array) -> !l8
      simulation.return %hi, %low : !l8, !l8
    }
    // Keep the original snapshot: a later X drive cannot change the value
    // read before it (4.6(a)); the second read observes that X.
    // CHECK-LABEL: local-unknown @snapshot
    // CHECK-NEXT: net-gate 0[24+:8]
    // CHECK-NEXT: read before: gated
    // CHECK-NEXT: read after: written
    simulation.func @snapshot(%ctx: !c {simulation.capture_kind = 0 : i32}) -> (!l8, !l8)
        attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %n = simulation.context.net %ctx[0] : !net
      %before = simulation.net.read %n {test.read = "before"} : !net -> !array
      %d = simulation.context.driver %ctx[1] : !driver
      %hi = simulation.driver.extract %d from 24 : !driver -> !simulation.driver<!l8>
      %x = simulation.logic.constant 0 : i8, -1 : i8 : !l8
      simulation.driver.drive %hi = %x : !simulation.driver<!l8>, !l8
      %after = simulation.net.read %n {test.read = "after"} : !net -> !array
      %a = simulation.aggregate.extract %before[0] : (!array) -> !l8
      %b = simulation.aggregate.extract %after[0] : (!array) -> !l8
      simulation.return %a, %b : !l8, !l8
    }
    // Packed struct offsets and round-trip views preserve the demanded field.
    // CHECK-LABEL: local-unknown @record
    // CHECK-NEXT: net-gate 1[0+:8]
    // CHECK-NEXT: read record: gated
    simulation.func @record(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64} {
      %n = simulation.context.net %ctx[1] : !simulation.net<!simulation.packed_struct<[#simulation.field<name = "a", type = !l8, ordinal = 0, packedOffset = 8>, #simulation.field<name = "b", type = !l8, ordinal = 1, packedOffset = 0>]>>
      %v = simulation.net.read %n {test.read = "record"} : !simulation.net<!simulation.packed_struct<[#simulation.field<name = "a", type = !l8, ordinal = 0, packedOffset = 8>, #simulation.field<name = "b", type = !l8, ordinal = 1, packedOffset = 0>]>> -> !simulation.packed_struct<[#simulation.field<name = "a", type = !l8, ordinal = 0, packedOffset = 8>, #simulation.field<name = "b", type = !l8, ordinal = 1, packedOffset = 0>]>
      %flat = simulation.packed.flatten %v : (!simulation.packed_struct<[#simulation.field<name = "a", type = !l8, ordinal = 0, packedOffset = 8>, #simulation.field<name = "b", type = !l8, ordinal = 1, packedOffset = 0>]>) -> !simulation.logic<16>
      %again = simulation.packed.unflatten %flat : (!simulation.logic<16>) -> !simulation.packed_struct<[#simulation.field<name = "a", type = !l8, ordinal = 0, packedOffset = 8>, #simulation.field<name = "b", type = !l8, ordinal = 1, packedOffset = 0>]>
      %r = simulation.aggregate.extract %again[1] : (!simulation.packed_struct<[#simulation.field<name = "a", type = !l8, ordinal = 0, packedOffset = 8>, #simulation.field<name = "b", type = !l8, ordinal = 1, packedOffset = 0>]>) -> !l8
      simulation.return %r : !l8
    }
    // An ascending declaration's last ordinal is its low packed element.
    // CHECK-LABEL: local-unknown @ascending
    // CHECK-NEXT: net-gate 2[0+:8]
    // CHECK-NEXT: read ascending: gated
    simulation.func @ascending(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 7 : i64} {
      %n = simulation.context.net %ctx[2] : !simulation.net<!simulation.packed_array<0 : 3 x !l8>>
      %v = simulation.net.read %n {test.read = "ascending"} : !simulation.net<!simulation.packed_array<0 : 3 x !l8>> -> !simulation.packed_array<0 : 3 x !l8>
      %r = simulation.aggregate.extract %v[3] : (!simulation.packed_array<0 : 3 x !l8>) -> !l8
      simulation.return %r : !l8
    }
  }
}
