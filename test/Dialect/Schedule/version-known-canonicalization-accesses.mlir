// RUN: talos-opt %s --pass-pipeline='builtin.module(schedule-version-known-activations,schedule-version-known-regions)' -o %t
// RUN: FileCheck %s < %t
// RUN: talos-opt %s --mlir-disable-threading --pass-pipeline='builtin.module(schedule-version-known-activations,schedule-version-known-regions)' -o %t.serial && diff %t %t.serial
// RUN: talos-opt %t --pass-pipeline='builtin.module(schedule-version-known-activations,schedule-version-known-regions)' -o %t.again && diff %t %t.again

// IEEE 1800-2023 4.6/6.3.1/7.2/7.3/7.4.5: a late value cleanup must retain
// each planned snapshot and its path certificate. General aggregate/ref
// canonicalizers can instead create unproved narrow reads and leave the old
// read unused. Keep aggregate, union and indexed-array accesses unchanged.
!word = !simulation.logic<8>
!record = !simulation.unpacked_struct<[#simulation.field<name = "a", type = !word, ordinal = 0, packedOffset = 0>, #simulation.field<name = "b", type = !word, ordinal = 1, packedOffset = 0>]>
!choice = !simulation.unpacked_union<fields = [#simulation.field<name = "a", type = !word, ordinal = 0, packedOffset = 0>, #simulation.field<name = "b", type = !simulation.logic<4>, ordinal = 1, packedOffset = 0>], isTagged = false>
!memory = !simulation.unpacked_array<0 : 7 x !word>
module attributes {native.optimization_level = 3 : i32} {
  simulation.design @preserve_accesses {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !record design
    simulation.storage.decl 1 in 0 : !choice design
    simulation.storage.decl 2 in 0 : !memory design
    simulation.code_unit.decl 1 in 0 function hierarchy "aggregate"
    simulation.code_unit.decl 2 in 0 function hierarchy "union"
    simulation.code_unit.decl 3 in 0 function hierarchy "array"

    // CHECK-LABEL: simulation.func @aggregate(
    // CHECK-NEXT: %[[R:.*]] = simulation.context.storage
    // CHECK-NEXT: %[[V:.*]] = simulation.ref.load %[[R]] {schedule.native.known_read}
    // CHECK-NEXT: %[[E:.*]] = simulation.aggregate.extract %[[V]][0]
    // CHECK-NEXT: simulation.return %[[E]]
    simulation.func @aggregate(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> !word
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64, schedule.native.known_activation} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!record>
      %v = simulation.ref.load %r {schedule.native.known_read} : !simulation.ref<!record> -> !record
      %e = simulation.aggregate.extract %v[0] : (!record) -> !word
      simulation.return %e : !word
    }

    // CHECK-LABEL: simulation.func @union(
    // CHECK-NEXT: %[[R:.*]] = simulation.context.storage
    // CHECK-NEXT: %[[V:.*]] = simulation.ref.load %[[R]] {schedule.native.known_read}
    // CHECK-NEXT: %[[E:.*]] = simulation.union.extract %[[V]][0]
    // CHECK-NEXT: simulation.return %[[E]]
    simulation.func @union(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> !word
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64, schedule.native.known_activation} {
      %r = simulation.context.storage %ctx[1] : !simulation.ref<!choice>
      %v = simulation.ref.load %r {schedule.native.known_read} : !simulation.ref<!choice> -> !choice
      %e = simulation.union.extract %v[0] : (!choice) -> !word
      simulation.return %e : !word
    }

    // CHECK-LABEL: simulation.func @array(
    // CHECK-NEXT: %[[R:.*]] = simulation.context.storage
    // CHECK-NEXT: %[[V:.*]] = simulation.ref.load %[[R]] {schedule.native.known_read}
    // CHECK-NEXT: %[[E:.*]] = simulation.array.extract_dynamic %[[V]][%arg1]
    // CHECK-NEXT: simulation.return %[[E]]
    simulation.func @array(%ctx: !simulation.context {simulation.capture_kind = 0 : i32},
                           %index: i3 {simulation.capture_kind = 2 : i32}) -> !word
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64, schedule.native.known_activation} {
      %r = simulation.context.storage %ctx[2] : !simulation.ref<!memory>
      %v = simulation.ref.load %r {schedule.native.known_read} : !simulation.ref<!memory> -> !memory
      %e = simulation.array.extract_dynamic %v[%index] : (!memory, i3) -> !word
      simulation.return %e : !word
    }
  }
}
