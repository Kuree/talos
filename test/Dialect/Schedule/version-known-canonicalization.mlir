// RUN: talos-opt %s --pass-pipeline='builtin.module(schedule-version-known-activations{minimum-benefit=1},schedule-version-known-regions)' -o %t
// RUN: FileCheck %s < %t
// RUN: talos-opt %s --mlir-disable-threading --pass-pipeline='builtin.module(schedule-version-known-activations{minimum-benefit=1},schedule-version-known-regions)' -o %t.serial && diff %t %t.serial
// RUN: talos-opt %t --pass-pipeline='builtin.module(schedule-version-known-activations{minimum-benefit=1},schedule-version-known-regions)' -o %t.again && diff %t %t.again

// IEEE 1800-2023 6.3.1/6.11.2/11.4: after a guard proves its reads known,
// expose their exact integer views and reuse value canonicalization before
// two-plane lowering. The unproved branch retains four-state arithmetic.
// Keep scheduled blocks, effect order, and memory-backed values intact.
module attributes {native.optimization_level = 3 : i32} {
  simulation.design @canonical_known {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<8> design
    simulation.storage.decl 1 in 0 : !simulation.logic<256> design
    simulation.storage.decl 2 in 0 : !simulation.logic<256> design
    simulation.code_unit.decl 1 in 0 function hierarchy "scalar"
    simulation.code_unit.decl 2 in 0 function hierarchy "memory"
    simulation.code_unit.decl 3 in 0 function hierarchy "snapshot"
    simulation.code_unit.decl 4 in 0 function hierarchy "fully_known"
    // CHECK-LABEL: simulation.func @scalar
    // CHECK: schedule.known.roots
    // CHECK-NEXT: cf.cond_br %{{.*}} weights([1048575, 1]), ^[[COPY:bb[0-9]+]], ^[[BODY:bb[0-9]+]]
    // CHECK: ^[[BODY]]:
    // CHECK: simulation.logic.binary mul
    // CHECK: simulation.return
    // CHECK: ^[[COPY]]:
    // CHECK: %[[VALUE:.*]] = simulation.ref.load %{{.*}} {schedule.native.known_read}
    // CHECK-NEXT: %[[BITS:.*]] = simulation.logic.to_bits %[[VALUE]]
    // CHECK-NOT: simulation.logic.binary
    // CHECK: arith.muli %[[BITS]], %[[BITS]] : i8
    // CHECK-NOT: simulation.logic.binary
    // CHECK: simulation.return
    simulation.func @scalar(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> !simulation.logic<8>
        attributes {entry_kind = 8 : i32, code_unit_id = 1 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<8>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %p0 = simulation.logic.binary mul %x, %x : !simulation.logic<8>
      %p1 = simulation.logic.binary mul %p0, %x : !simulation.logic<8>
      %p2 = simulation.logic.binary mul %p1, %x : !simulation.logic<8>
      %p3 = simulation.logic.binary mul %p2, %x : !simulation.logic<8>
      %p4 = simulation.logic.binary mul %p3, %x : !simulation.logic<8>
      %p5 = simulation.logic.binary mul %p4, %x : !simulation.logic<8>
      %p6 = simulation.logic.binary mul %p5, %x : !simulation.logic<8>
      %p7 = simulation.logic.binary mul %p6, %x : !simulation.logic<8>
      simulation.return %p7 : !simulation.logic<8>
    }
    // CHECK-LABEL: simulation.func @memory
    // CHECK: schedule.known.roots
    // CHECK-NEXT: cf.cond_br %{{.*}}, ^[[MEMCOPY:bb[0-9]+]], ^[[MEMBODY:bb[0-9]+]]
    // CHECK: ^[[MEMBODY]]:
    // CHECK: simulation.ref.load %{{.*}} : !simulation.ref<!simulation.logic<256>>
    // CHECK-NEXT: simulation.ref.store
    // CHECK: simulation.return
    // CHECK: ^[[MEMCOPY]]:
    // CHECK: %[[M:.*]] = simulation.ref.load %{{.*}} {schedule.native.known_read} : !simulation.ref<!simulation.logic<256>>
    // CHECK-NEXT: simulation.ref.store %[[M]] to %{{.*}} {schedule.native.known_store}
    // CHECK-NOT: -> i256
    // CHECK-NOT: i256 ->
    // CHECK: simulation.return
    simulation.func @memory(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> !simulation.logic<8>
        attributes {entry_kind = 8 : i32, code_unit_id = 2 : i64} {
      %scalar = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<8>>
      %x = simulation.ref.load %scalar : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %p0 = simulation.logic.binary mul %x, %x : !simulation.logic<8>
      %p1 = simulation.logic.binary mul %p0, %x : !simulation.logic<8>
      %p2 = simulation.logic.binary mul %p1, %x : !simulation.logic<8>
      %p3 = simulation.logic.binary mul %p2, %x : !simulation.logic<8>
      %p4 = simulation.logic.binary mul %p3, %x : !simulation.logic<8>
      %p5 = simulation.logic.binary mul %p4, %x : !simulation.logic<8>
      %p6 = simulation.logic.binary mul %p5, %x : !simulation.logic<8>
      %p7 = simulation.logic.binary mul %p6, %x : !simulation.logic<8>
      %src = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<256>>
      %dst = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<256>>
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<256>> -> !simulation.logic<256>
      simulation.ref.store %v to %dst : !simulation.logic<256>, !simulation.ref<!simulation.logic<256>>
      simulation.return %p7 : !simulation.logic<8>
    }
    // A fully proved variant must be cleaned even when region analysis
    // finds no further work worth guarding.
    // CHECK-LABEL: simulation.func @fully_known
    // CHECK-NOT: schedule.known.
    // CHECK: simulation.ref.load
    // CHECK: arith.muli
    // CHECK-NOT: simulation.logic.binary
    // CHECK: simulation.return
    simulation.func @fully_known(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> !simulation.logic<8>
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64, schedule.eval.inductive_two_state} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<8>>
      %x = simulation.ref.load %r : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %p0 = simulation.logic.binary mul %x, %x : !simulation.logic<8>
      %p1 = simulation.logic.binary mul %p0, %x : !simulation.logic<8>
      %p2 = simulation.logic.binary mul %p1, %x : !simulation.logic<8>
      %p3 = simulation.logic.binary mul %p2, %x : !simulation.logic<8>
      %p4 = simulation.logic.binary mul %p3, %x : !simulation.logic<8>
      %p5 = simulation.logic.binary mul %p4, %x : !simulation.logic<8>
      %p6 = simulation.logic.binary mul %p5, %x : !simulation.logic<8>
      %p7 = simulation.logic.binary mul %p6, %x : !simulation.logic<8>
      simulation.return %p7 : !simulation.logic<8>
    }
    // A guard on live storage does not describe an older snapshot (4.4.2.1).
    // CHECK-LABEL: simulation.func @snapshot
    // CHECK: %[[S:.*]] = simulation.assert.sampled_read
    // CHECK-NEXT: simulation.return %[[S]]
    simulation.func @snapshot(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> !simulation.logic<8>
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64, schedule.native.known_activation, schedule.eval.inductive_two_state} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<8>>
      %s = simulation.assert.sampled_read %ctx from %r : (!simulation.context, !simulation.ref<!simulation.logic<8>>) -> !simulation.logic<8>
      simulation.return %s : !simulation.logic<8>
    }
  }
}
