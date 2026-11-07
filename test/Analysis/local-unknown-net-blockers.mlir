// RUN: talos-opt %s --split-input-file --test-talos-local-unknown -o /dev/null 2>&1 | FileCheck %s
// LRM 6.3.2, 6.6.1, 6.7.1 and 23.3.3.7: the payload of an overlapping,
// high-Z, delayed or aliased contribution is not by itself the resolved net
// value. Such a write must not discharge an entry proof for a later read.

!c = !simulation.context
!l8 = !simulation.logic<8>
!l32 = !simulation.logic<32>
!array = !simulation.packed_array<3 : 0 x !l8>
module {
  simulation.design @overlap {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !array design
    simulation.driver.decl 0 in 0 drives 0 : !array design {driven_low = 24 : i64, driven_width = 8 : i64}
    simulation.driver.decl 1 in 0 drives 0 : !array design {driven_low = 24 : i64, driven_width = 8 : i64}
    simulation.code_unit.decl 1 in 0 function hierarchy "overlap"
    // CHECK-LABEL: local-unknown @overlap
    // CHECK-NEXT: read overlap: written
    // CHECK-NEXT: store overlap: four-state
    simulation.func @overlap(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d = simulation.context.driver %ctx[0] : !simulation.driver<!array>
      %view = simulation.driver.extract %d from 24 : !simulation.driver<!array> -> !simulation.driver<!l8>
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      simulation.driver.drive %view = %one {test.store = "overlap"} : !simulation.driver<!l8>, !l8
      %n = simulation.context.net %ctx[0] : !simulation.net<!array>
      %v = simulation.net.read %n {test.read = "overlap"} : !simulation.net<!array> -> !array
      %r = simulation.aggregate.extract %v[0] : (!array) -> !l8
      simulation.return %r : !l8
    }
  }
}

// -----
!c = !simulation.context
!l8 = !simulation.logic<8>
!l32 = !simulation.logic<32>
!array = !simulation.packed_array<3 : 0 x !l8>
module {
  simulation.design @high_z {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !array design
    simulation.driver.decl 0 in 0 drives 0 : !array design {driven_low = 24 : i64, driven_width = 8 : i64, strength0 = 0 : i32}
    simulation.code_unit.decl 1 in 0 function hierarchy "high_z"
    // CHECK-LABEL: local-unknown @high_z
    // CHECK-NEXT: read high_z: written
    // CHECK-NEXT: store high_z: four-state
    simulation.func @high_z(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d = simulation.context.driver %ctx[0] : !simulation.driver<!array>
      %view = simulation.driver.extract %d from 24 : !simulation.driver<!array> -> !simulation.driver<!l8>
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      simulation.driver.drive %view = %one {test.store = "high_z"} : !simulation.driver<!l8>, !l8
      %n = simulation.context.net %ctx[0] : !simulation.net<!array>
      %v = simulation.net.read %n {test.read = "high_z"} : !simulation.net<!array> -> !array
      %r = simulation.aggregate.extract %v[0] : (!array) -> !l8
      simulation.return %r : !l8
    }
  }
}

// -----
!c = !simulation.context
!l8 = !simulation.logic<8>
!l32 = !simulation.logic<32>
!array = !simulation.packed_array<3 : 0 x !l8>
module {
  simulation.design @delayed {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !array design {propagation_delays = array<i64: 1, 1, 1>}
    simulation.driver.decl 0 in 0 drives 0 : !array design {driven_low = 24 : i64, driven_width = 8 : i64}
    simulation.code_unit.decl 1 in 0 function hierarchy "delayed"
    // CHECK-LABEL: local-unknown @delayed
    // CHECK-NEXT: read delayed: written
    // CHECK-NEXT: store delayed: four-state
    simulation.func @delayed(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d = simulation.context.driver %ctx[0] : !simulation.driver<!array>
      %view = simulation.driver.extract %d from 24 : !simulation.driver<!array> -> !simulation.driver<!l8>
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      simulation.driver.drive %view = %one {test.store = "delayed"} : !simulation.driver<!l8>, !l8
      %n = simulation.context.net %ctx[0] : !simulation.net<!array>
      %v = simulation.net.read %n {test.read = "delayed"} : !simulation.net<!array> -> !array
      %r = simulation.aggregate.extract %v[0] : (!array) -> !l8
      simulation.return %r : !l8
    }
  }
}

// -----
!c = !simulation.context
!l8 = !simulation.logic<8>
!l32 = !simulation.logic<32>
!array = !simulation.packed_array<3 : 0 x !l8>
module {
  simulation.design @alias {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !array design
    simulation.driver.decl 0 in 0 drives 0 : !array design {driven_low = 24 : i64, driven_width = 8 : i64}
    simulation.net.decl 1 in 0 : !array design
    simulation.net.connect.decl 0 in 0 0[0] to 1[31] width 32 reversed = true rhs_dominates = false
    simulation.code_unit.decl 1 in 0 function hierarchy "alias"
    // CHECK-LABEL: local-unknown @alias
    // CHECK-NEXT: read alias: written
    // CHECK-NEXT: store alias: four-state
    simulation.func @alias(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d = simulation.context.driver %ctx[0] : !simulation.driver<!array>
      %view = simulation.driver.extract %d from 24 : !simulation.driver<!array> -> !simulation.driver<!l8>
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      simulation.driver.drive %view = %one {test.store = "alias"} : !simulation.driver<!l8>, !l8
      %n = simulation.context.net %ctx[1] : !simulation.net<!array>
      %v = simulation.net.read %n {test.read = "alias"} : !simulation.net<!array> -> !array
      %r = simulation.aggregate.extract %v[3] : (!array) -> !l8
      simulation.return %r : !l8
    }
  }
}

// -----
!c = !simulation.context
!l8 = !simulation.logic<8>
!l32 = !simulation.logic<32>
!array = !simulation.packed_array<3 : 0 x !l8>
module {
  simulation.design @clip_known {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !array design
    simulation.driver.decl 0 in 0 drives 0 : !array design {driven_low = 24 : i64, driven_width = 8 : i64}
    simulation.code_unit.decl 1 in 0 function hierarchy "clip_known"
    // CHECK-LABEL: local-unknown @clip_known
    // CHECK-NEXT: read clip_known: gated
    // CHECK-NEXT: store clip_known: four-state
    simulation.func @clip_known(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d = simulation.context.driver %ctx[0] : !simulation.driver<!array>
      %flat = simulation.logic.constant 0 : i32, 255 : i32 : !l32
      %payload = simulation.packed.unflatten %flat : (!l32) -> !array
      simulation.driver.drive %d = %payload {test.store = "clip_known"} : !simulation.driver<!array>, !array
      %n = simulation.context.net %ctx[0] : !simulation.net<!array>
      %v = simulation.net.read %n {test.read = "clip_known"} : !simulation.net<!array> -> !array
      %r = simulation.aggregate.extract %v[0] : (!array) -> !l8
      simulation.return %r : !l8
    }
  }
}

// -----
!c = !simulation.context
!l8 = !simulation.logic<8>
!l32 = !simulation.logic<32>
!array = !simulation.packed_array<3 : 0 x !l8>
module {
  simulation.design @clip_x {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !array design
    simulation.driver.decl 0 in 0 drives 0 : !array design {driven_low = 24 : i64, driven_width = 8 : i64}
    simulation.code_unit.decl 1 in 0 function hierarchy "clip_x"
    // CHECK-LABEL: local-unknown @clip_x
    // CHECK-NEXT: read clip_x: written
    // CHECK-NEXT: store clip_x: four-state
    simulation.func @clip_x(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %d = simulation.context.driver %ctx[0] : !simulation.driver<!array>
      %flat = simulation.logic.constant 0 : i32, 4278190080 : i32 : !l32
      %payload = simulation.packed.unflatten %flat : (!l32) -> !array
      simulation.driver.drive %d = %payload {test.store = "clip_x"} : !simulation.driver<!array>, !array
      %n = simulation.context.net %ctx[0] : !simulation.net<!array>
      %v = simulation.net.read %n {test.read = "clip_x"} : !simulation.net<!array> -> !array
      %r = simulation.aggregate.extract %v[0] : (!array) -> !l8
      simulation.return %r : !l8
    }
  }
}

// -----
!c = !simulation.context
!l8 = !simulation.logic<8>
!l32 = !simulation.logic<32>
!array = !simulation.packed_array<3 : 0 x !l8>
module {
  simulation.design @full_observation {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !array design
    simulation.driver.decl 0 in 0 drives 0 : !array design {driven_low = 24 : i64, driven_width = 8 : i64}
    simulation.code_unit.decl 1 in 0 function hierarchy "full_observation"
    // CHECK-LABEL: local-unknown @full_observation
    // CHECK-NEXT: net-gate 0[0+:32]
    // CHECK-NEXT: read full_observation: gated
    simulation.func @full_observation(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !array
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %n = simulation.context.net %ctx[0] : !simulation.net<!array>
      %v = simulation.net.read %n {test.read = "full_observation"} : !simulation.net<!array> -> !array
      simulation.return %v : !array
    }
  }
}

// -----
!c = !simulation.context
!l8 = !simulation.logic<8>
!l32 = !simulation.logic<32>
!array = !simulation.packed_array<3 : 0 x !l8>
module {
  simulation.design @unpacked {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !simulation.unpacked_array<0 : 1 x !l8> design
    simulation.code_unit.decl 1 in 0 function hierarchy "unpacked"
    // CHECK-LABEL: local-unknown @unpacked
    // CHECK-NEXT: read leaf: unresolved
    simulation.func @unpacked(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %net = simulation.context.net %ctx[0] : !simulation.net<!simulation.unpacked_array<0 : 1 x !l8>>
      %leaf = simulation.net.extract %net from 0 : !simulation.net<!simulation.unpacked_array<0 : 1 x !l8>> -> !simulation.net<!l8>
      %v = simulation.net.read %leaf {test.read = "leaf"} : !simulation.net<!l8> -> !l8
      simulation.return %v : !l8
    }
  }
}
