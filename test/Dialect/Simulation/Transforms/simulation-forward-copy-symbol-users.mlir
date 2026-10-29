// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' > %t.threaded
// RUN: FileCheck %s < %t.threaded
// RUN: talos-opt %s -split-input-file -mlir-disable-threading --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' > %t.serial
// RUN: diff -u %t.serial %t.threaded

// Symbol references are uses, not necessarily calls. An operation can also
// name the same symbol in more than one attribute.
// A reference on another callee's spawn cannot start the copy, and that
// spawn must remain intact.
// CHECK-LABEL: simulation.design @foreign_copy_reference
// CHECK: simulation.spawn @reader({{.*}}) {test.ref = @copy}
// CHECK: simulation.func private @copy
// CHECK: simulation.func private @reader
module {
  simulation.design @foreign_copy_reference {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p1 = simulation.spawn @reader(%ctx, %n, %d) {test.ref = @copy} : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %value = simulation.logic.binary xor %v, %c : !simulation.logic<4>
      simulation.ref.store %value to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<4>>
    }
  }
}

// -----

// Repeated uses on a real copy spawn erase that spawn only once.
// CHECK-LABEL: simulation.design @duplicate_copy_reference
// CHECK-NOT: simulation.spawn @copy(
// CHECK: simulation.func private @reader
// CHECK: simulation.logic.binary xor
// CHECK-NOT: simulation.func private @copy(
module {
  simulation.design @duplicate_copy_reference {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) {test.ref = @copy} : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %value = simulation.logic.binary xor %v, %c : !simulation.logic<4>
      simulation.ref.store %value to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<4>>
    }
  }
}

// -----

// A reader with a non-call reference cannot gain captures at another
// function's spawn. Keep its input materialized and the foreign spawn's ABI.
// CHECK-LABEL: simulation.design @foreign_reader_reference
// CHECK: simulation.spawn @copy(
// CHECK: simulation.spawn @other({{.*}}) {test.ref = @reader} : !simulation.context -> !simulation.process
// CHECK: simulation.func private @copy
// CHECK: simulation.func private @reader
// CHECK: simulation.func private @other
module {
  simulation.design @foreign_reader_reference {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "other"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      %p2 = simulation.spawn @other(%ctx) {test.ref = @reader} : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %value = simulation.logic.binary xor %v, %c : !simulation.logic<4>
      simulation.ref.store %value to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      simulation.return
    }
  }
}

// -----

// A repeated reference to the actual reader still adds each capture once.
// The verifier checks the resulting spawn operands against the callee ABI.
// CHECK-LABEL: simulation.design @duplicate_reader_reference
// CHECK-NOT: simulation.spawn @copy(
// CHECK: simulation.func private @reader
// CHECK: simulation.logic.binary xor
// CHECK-NOT: simulation.func private @copy(
module {
  simulation.design @duplicate_reader_reference {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) {test.ref = @reader} : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %value = simulation.logic.binary xor %v, %c : !simulation.logic<4>
      simulation.ref.store %value to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<4>>
    }
  }
}
