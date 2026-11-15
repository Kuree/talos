// RUN: talos-opt %s --canonicalize | FileCheck %s

// IEEE 1800-2023 7.2.1: packed members occupy their declared bit positions.
// Reading a two-state member converts X/Z to zero; four-state members retain
// both planes. Unrelated unknown bits must not prevent a constant field fold.
!cfg = !simulation.packed_struct<[
  #simulation.field<name = "high", type = !simulation.logic<4>, ordinal = 0, packedOffset = 36>,
  #simulation.field<name = "depth", type = i32, ordinal = 1, packedOffset = 4>,
  #simulation.field<name = "low", type = !simulation.logic<4>, ordinal = 2, packedOffset = 0>
]>
!logic_record = !simulation.packed_struct<[
  #simulation.field<name = "logic", type = !simulation.logic<4>, ordinal = 0, packedOffset = 4>,
  #simulation.field<name = "bits", type = i4, ordinal = 1, packedOffset = 0>
]>
!words = !simulation.packed_struct<[
  #simulation.field<name = "high", type = i32, ordinal = 0, packedOffset = 32>,
  #simulation.field<name = "low", type = i32, ordinal = 1, packedOffset = 0>
]>
!array = !simulation.packed_array<2 : 5 x !simulation.logic<4>>
!nested = !simulation.packed_struct<[
  #simulation.field<name = "array", type = !array, ordinal = 0, packedOffset = 8>,
  #simulation.field<name = "low", type = i8, ordinal = 1, packedOffset = 0>
]>

// CHECK-LABEL: func.func @known_field
// CHECK-NEXT: %[[EIGHT:.*]] = arith.constant 8 : i32
// CHECK-NEXT: return %[[EIGHT]] : i32
func.func @known_field() -> i32 {
  %bits = simulation.logic.constant 128 : i40, 0 : i40 : !simulation.logic<40>
  %cfg = simulation.packed.unflatten %bits : (!simulation.logic<40>) -> !cfg
  %depth = simulation.aggregate.extract %cfg[1] : (!cfg) -> i32
  return %depth : i32
}

// CHECK-LABEL: func.func @unknown_neighbors
// CHECK-NEXT: %[[EIGHT:.*]] = arith.constant 8 : i32
// CHECK-NEXT: return %[[EIGHT]] : i32
func.func @unknown_neighbors() -> i32 {
  %bits = simulation.logic.constant 128 : i40, 1030792151055 : i40 : !simulation.logic<40>
  %cfg = simulation.packed.unflatten %bits : (!simulation.logic<40>) -> !cfg
  %depth = simulation.aggregate.extract %cfg[1] : (!cfg) -> i32
  return %depth : i32
}

// CHECK-LABEL: func.func @two_state_member
// CHECK-NEXT: %[[ZERO:.*]] = arith.constant 0 : i4
// CHECK-NEXT: return %[[ZERO]] : i4
func.func @two_state_member() -> i4 {
  %bits = simulation.logic.constant 173 : i8, 15 : i8 : !simulation.logic<8>
  %record = simulation.packed.unflatten %bits : (!simulation.logic<8>) -> !logic_record
  %member = simulation.aggregate.extract %record[1] : (!logic_record) -> i4
  return %member : i4
}

// CHECK-LABEL: func.func @four_state_member
// CHECK-NEXT: %[[LOGIC:.*]] = simulation.logic.constant -6 : i4, 5 : i4
// CHECK-NEXT: return %[[LOGIC]] : !simulation.logic<4>
func.func @four_state_member() -> !simulation.logic<4> {
  %bits = simulation.logic.constant 173 : i8, 83 : i8 : !simulation.logic<8>
  %record = simulation.packed.unflatten %bits : (!simulation.logic<8>) -> !logic_record
  %member = simulation.aggregate.extract %record[0] : (!logic_record) -> !simulation.logic<4>
  return %member : !simulation.logic<4>
}

// CHECK-LABEL: func.func @two_state_packed_source
// CHECK-NEXT: %[[EIGHT:.*]] = arith.constant 8 : i32
// CHECK-NEXT: return %[[EIGHT]] : i32
func.func @two_state_packed_source() -> i32 {
  %bits = arith.constant 34359738368 : i64
  %record = simulation.packed.unflatten %bits : (i64) -> !words
  %member = simulation.aggregate.extract %record[0] : (!words) -> i32
  return %member : i32
}

// CHECK-LABEL: func.func @nested_ascending_array
// CHECK-NEXT: %[[TEN:.*]] = simulation.logic.constant -6 : i4, 0 : i4
// CHECK-NEXT: return %[[TEN]] : !simulation.logic<4>
func.func @nested_ascending_array() -> !simulation.logic<4> {
  %bits = simulation.logic.constant 655360 : i24, 0 : i24 : !simulation.logic<24>
  %record = simulation.packed.unflatten %bits : (!simulation.logic<24>) -> !nested
  %array = simulation.aggregate.extract %record[0] : (!nested) -> !array
  %member = simulation.aggregate.extract %array[1] : (!array) -> !simulation.logic<4>
  return %member : !simulation.logic<4>
}

// CHECK-LABEL: func.func @dynamic_source
// CHECK: simulation.packed.unflatten %arg0
// CHECK: simulation.aggregate.extract
func.func @dynamic_source(%bits: !simulation.logic<40>) -> i32 {
  %cfg = simulation.packed.unflatten %bits : (!simulation.logic<40>) -> !cfg
  %depth = simulation.aggregate.extract %cfg[1] : (!cfg) -> i32
  return %depth : i32
}
