// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' > %t.threaded
// RUN: FileCheck %s < %t.threaded
// RUN: talos-opt %s -split-input-file -mlir-disable-threading --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' > %t.serial
// RUN: diff -u %t.serial %t.threaded
// RUN: talos-opt %s -split-input-file > %t.original
// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{census=true}))' > %t.census 2> %t.census.log
// RUN: diff -u %t.original %t.census

// Continuous variable assignments retain their defaults before startup and
// keep observations and writers outside the substituted pure computation.
// State-domain conversions belong to the assignment, before a reader's slice.
// Pure short-circuit diamonds preserve the original i1 decision and X/Z value.
// CHECK-LABEL: simulation.design @storage_expression
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK: simulation.logic.binary xor
// CHECK-NOT: simulation.func private @copy
module {
  simulation.design @storage_expression {
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

// CHECK-LABEL: simulation.design @integer_packed_subview
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK: arith.xori
// CHECK: arith.shrui
// CHECK: arith.trunci
// CHECK-NOT: simulation.func private @copy
module {
  simulation.design @integer_packed_subview {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.packed_array<3 : 0 x i1> design
    simulation.storage.decl 1 in 0 : !simulation.packed_array<3 : 0 x i1> design
    simulation.storage.decl 2 in 0 : i2 design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<i2>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.packed_array<3 : 0 x i1>>, !simulation.ref<!simulation.packed_array<3 : 0 x i1>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.packed_array<3 : 0 x i1>>, !simulation.ref<i2> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.packed_array<3 : 0 x i1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.packed_array<3 : 0 x i1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.packed_array<3 : 0 x i1>> -> !simulation.packed_array<3 : 0 x i1>
      %bits = simulation.packed.flatten %v : (!simulation.packed_array<3 : 0 x i1>) -> i4
      %c = arith.constant 5 : i4
      %xor = arith.xori %bits, %c : i4
      %value = simulation.packed.unflatten %xor : (i4) -> !simulation.packed_array<3 : 0 x i1>
      simulation.ref.store %value to %dst : !simulation.packed_array<3 : 0 x i1>, !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.packed_array<3 : 0 x i1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %view = simulation.ref.extract %in from 1 : !simulation.ref<!simulation.packed_array<3 : 0 x i1>> -> !simulation.ref<i2>
      %value = simulation.ref.load %view : !simulation.ref<i2> -> i2
      simulation.ref.store %value to %out : i2, !simulation.ref<i2>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @logic_to_integer
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK: simulation.logic.to_bits
// CHECK: simulation.packed.unflatten
// CHECK-NOT: simulation.func private @copy
module {
  simulation.design @logic_to_integer {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.packed_array<3 : 0 x i1> design
    simulation.storage.decl 2 in 0 : !simulation.packed_array<3 : 0 x i1> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.packed_array<3 : 0 x i1>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.packed_array<3 : 0 x i1>>, !simulation.ref<!simulation.packed_array<3 : 0 x i1>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.packed_array<3 : 0 x i1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %bits = simulation.logic.to_bits %v : !simulation.logic<4> -> i4
      %value = simulation.packed.unflatten %bits : (i4) -> !simulation.packed_array<3 : 0 x i1>
      simulation.ref.store %value to %dst : !simulation.packed_array<3 : 0 x i1>, !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.packed_array<3 : 0 x i1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.packed_array<3 : 0 x i1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %value = simulation.ref.load %in : !simulation.ref<!simulation.packed_array<3 : 0 x i1>> -> !simulation.packed_array<3 : 0 x i1>
      simulation.ref.store %value to %out : !simulation.packed_array<3 : 0 x i1>, !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @integer_to_logic
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK: simulation.logic.from_bits
// CHECK-NOT: simulation.func private @copy
module {
  simulation.design @integer_to_logic {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.packed_array<3 : 0 x i1> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.packed_array<3 : 0 x i1>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.packed_array<3 : 0 x i1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.packed_array<3 : 0 x i1>> -> !simulation.packed_array<3 : 0 x i1>
      %bits = simulation.packed.flatten %v : (!simulation.packed_array<3 : 0 x i1>) -> i4
      %value = simulation.logic.from_bits %bits : i4 -> !simulation.logic<4>
      simulation.ref.store %value to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.packed_array<3 : 0 x i1>>
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

// CHECK-LABEL: simulation.design @initializer_read
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @initializer_read {
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
      %before = simulation.ref.load %n : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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

// CHECK-LABEL: simulation.design @observable_storage
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @observable_storage {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design {observability = 1 : i32}
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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

// CHECK-LABEL: simulation.design @automatic_storage
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @automatic_storage {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> automatic
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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

// CHECK-LABEL: simulation.design @conditional_spawn
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @conditional_spawn {
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
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %condition = arith.constant false
      cf.cond_br %condition, ^start, ^done
    ^start:
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      cf.br ^done
    ^done:
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

// CHECK-LABEL: simulation.design @late_spawn
// CHECK: simulation.spawn @starter
// CHECK: simulation.func private @copy
module {
  simulation.design @late_spawn {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "starter"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p0 = simulation.spawn @starter(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @starter(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^later
    ^later:
      %p2 = simulation.spawn @copy(%ctx, %src, %dst) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      simulation.return
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @other_writer
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @other_writer {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %v = simulation.logic.constant 3 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @forced_storage
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @forced_storage {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %v = simulation.logic.constant 3 : i4, 0 : i4 : !simulation.logic<4>
      simulation.override %out = %v assign false : !simulation.ref<!simulation.logic<4>>, !simulation.logic<4>
      simulation.return
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @ref_call_writer
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @ref_call_writer {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 function hierarchy "touch"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      simulation.call @touch(%ctx, %n) : (!simulation.context, !simulation.ref<!simulation.logic<4>>) -> ()
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @touch(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %ref: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %v = simulation.logic.constant 3 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %v to %ref : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @pure_short_circuit
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK: arith.select
// CHECK-NOT: simulation.func private @copy
module {
  simulation.design @pure_short_circuit {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 3 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %side = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n, %side) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %rhs: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %first = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %condition = simulation.logic.is_true %first : !simulation.logic<4>
      %yes = simulation.logic.constant 15 : i4, 0 : i4 : !simulation.logic<4>
      cf.cond_br %condition, ^join(%yes : !simulation.logic<4>), ^arm
    ^arm:
      %no = simulation.ref.load %rhs : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      cf.br ^join(%no : !simulation.logic<4>)
    ^join(%value: !simulation.logic<4>):
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

// Branches may carry discardable symbol references. Build symbol-user
// inventories after normalization has erased those branches, so the removed
// references neither pin the copy nor leave dangling operation pointers.
// Census must restore these attributes together with the original CFG.
// CHECK-LABEL: simulation.design @branch_symbol_users
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK: arith.select
// CHECK-NOT: simulation.func private @copy
!c = !simulation.context
!l = !simulation.logic<1>
!r = !simulation.ref<!l>
module {
  simulation.design @branch_symbol_users {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !l design
    simulation.storage.decl 1 in 0 : !l design
    simulation.storage.decl 2 in 0 : !l design
    simulation.storage.decl 3 in 0 : !l design
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !r
      %n = simulation.context.storage %ctx[1] : !r
      %d = simulation.context.storage %ctx[2] : !r
      %side = simulation.context.storage %ctx[3] : !r
      %p0 = simulation.spawn @copy(%ctx, %s, %n, %side) : !c, !r, !r, !r -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !c, !r, !r -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %rhs: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %first = simulation.ref.load %src : !r -> !l
      %condition = simulation.logic.is_true %first : !l
      cf.cond_br %condition, ^join(%first : !l), ^arm {test.ref = @copy}
    ^arm:
      %no = simulation.ref.load %rhs : !r -> !l
      cf.br ^join(%no : !l) {test.ref = @copy}
    ^join(%value: !l):
      simulation.ref.store %value to %dst : !l, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func private @reader(%ctx: !c {simulation.capture_kind = 0 : i32}, %in: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %value = simulation.ref.load %in : !r -> !l
      simulation.ref.store %value to %out : !l, !r
      simulation.suspend.change %in to ^body : !r
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @empty_short_circuit_arm
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK: arith.select
// CHECK-NOT: simulation.func private @copy
module {
  simulation.design @empty_short_circuit_arm {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 3 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %side = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n, %side) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %rhs: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %first = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %condition = simulation.logic.is_true %first : !simulation.logic<4>
      %yes = simulation.logic.constant 15 : i4, 0 : i4 : !simulation.logic<4>
      %no = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      cf.cond_br %condition, ^join(%yes : !simulation.logic<4>), ^arm
    ^arm:
      cf.br ^join(%no : !simulation.logic<4>)
    ^join(%value: !simulation.logic<4>):
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

// CHECK-LABEL: simulation.design @effectful_short_circuit
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @effectful_short_circuit {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 3 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %side = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n, %side) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %side: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %first = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %condition = simulation.logic.is_true %first : !simulation.logic<4>
      %yes = simulation.logic.constant 15 : i4, 0 : i4 : !simulation.logic<4>
      cf.cond_br %condition, ^join(%yes : !simulation.logic<4>), ^arm
    ^arm:
      simulation.ref.store %first to %side : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      %no = simulation.ref.load %side : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      cf.br ^join(%no : !simulation.logic<4>)
    ^join(%value: !simulation.logic<4>):
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

// CHECK-LABEL: simulation.design @automatic_short_circuit_read
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @automatic_short_circuit_read {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 3 in 0 : !simulation.logic<4> automatic
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %side = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n, %side) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %rhs: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %first = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %condition = simulation.logic.is_true %first : !simulation.logic<4>
      %yes = simulation.logic.constant 15 : i4, 0 : i4 : !simulation.logic<4>
      cf.cond_br %condition, ^join(%yes : !simulation.logic<4>), ^arm
    ^arm:
      %no = simulation.ref.load %rhs : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      cf.br ^join(%no : !simulation.logic<4>)
    ^join(%value: !simulation.logic<4>):
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

// Final reads may follow the last source write without an Active copy update.
// CHECK-LABEL: simulation.design @final_storage_observer
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @final_storage_observer {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 final hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 2 : i32, code_unit_id = 3 : i64} {
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// A direct net display item is an observer even without a separate net.read.
// CHECK-LABEL: simulation.design @final_net_display
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK: simulation.display {{.*}}flags = [0, 2048]
module {
  simulation.design @final_net_display {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 final hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n) : !simulation.context, !simulation.net<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.driver.drive %drv = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 2 : i32, code_unit_id = 3 : i64} {
      %fd = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "y=%b"
      %v = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      simulation.display %ctx to %fd(%fmt, %v, %in) newline = true radix = <binary> flags = [0, 2048] : !simulation.bytes, !simulation.logic<4>, !simulation.net<!simulation.logic<4>>
      simulation.return
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// A ref.copy reads its packed source without a ref.load. At time 1 the
// assignment has already published f (4.5, 4.9.1, 10.3.2); retain it until
// this source handle can be rewritten.
// CHECK-LABEL: simulation.design @ref_copy_source
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
// CHECK: simulation.func private @reader
// CHECK: simulation.ref.copy

module {
  simulation.design @ref_copy_source {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 initial hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c = simulation.logic.constant 15 : i4, 0 : i4 : !simulation.logic<4>
      %value = simulation.logic.binary or %v, %c : !simulation.logic<4>
      simulation.ref.store %value to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^later
    ^later:
      simulation.ref.copy %in to %out : !simulation.ref<!simulation.logic<4>>
      %value = simulation.ref.load %out : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %fd = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "y=%b"
      simulation.display %ctx to %fd(%fmt, %value) newline = true radix = <binary> flags = [0, 0] : !simulation.bytes, !simulation.logic<4>
      simulation.return
    }
  }
}

// -----

// An unspawned assignment never replaces the variable declaration default
// (6.8, Table 6-7). A vacuous check of zero users is not a startup proof.
// CHECK-LABEL: simulation.design @unspawned_storage_copy
// CHECK: simulation.func private @copy
// CHECK: simulation.func private @reader
// CHECK: simulation.ref.load

module {
  simulation.design @unspawned_storage_copy {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 initial hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c = simulation.logic.constant 15 : i4, 0 : i4 : !simulation.logic<4>
      %value = simulation.logic.binary or %v, %c : !simulation.logic<4>
      simulation.ref.store %value to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^later
    ^later:
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %fd = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "y=%b"
      simulation.display %ctx to %fd(%fmt, %value) newline = true radix = <binary> flags = [0, 0] : !simulation.bytes, !simulation.logic<4>
      simulation.return
    }
  }
}

// -----

// A driver whose assignment never starts leaves the net at z (6.6).
// Require an actual spawn for net copies as well as storage copies.
// CHECK-LABEL: simulation.design @unspawned_net_copy
// CHECK: simulation.func private @copy
// CHECK: simulation.func private @reader
// CHECK: simulation.net.read

module {
  simulation.design @unspawned_net_copy {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 initial hierarchy "reader"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c = simulation.logic.constant 15 : i4, 0 : i4 : !simulation.logic<4>
      %value = simulation.logic.binary or %v, %c : !simulation.logic<4>
      simulation.driver.drive %drv = %value : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^later
    ^later:
      %value = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      %fd = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "y=%b"
      simulation.display %ctx to %fd(%fmt, %value) newline = true radix = <binary> flags = [0, 0] : !simulation.bytes, !simulation.logic<4>
      simulation.return
    }
  }
}

// -----

// A CFG join of two captured roots is an observation of either root.
// Losing its single descriptor must retain the materialized assignment.
// CHECK-LABEL: simulation.design @ambiguous_storage_reader
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @ambiguous_storage_reader {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %choose = arith.constant true
      %p1 = simulation.spawn @reader(%ctx, %n, %d, %choose) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, i1 -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %choose: i1 {simulation.capture_kind = 2 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      cf.cond_br %choose, ^from_sink, ^from_other
    ^from_sink:
      cf.br ^merge(%in : !simulation.ref<!simulation.logic<4>>)
    ^from_other:
      cf.br ^merge(%out : !simulation.ref<!simulation.logic<4>>)
    ^merge(%picked: !simulation.ref<!simulation.logic<4>>):
      %value = simulation.ref.load %picked : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.any %in, %out edges [0, 0] to ^body : !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %a = simulation.logic.constant 10 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %a to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// The contributing roots can be created inside the reader rather than
// appearing in its capture list. Trace the CFG inputs, including views.
// CHECK-LABEL: simulation.design @context_storage_reader
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @context_storage_reader {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %choose = arith.constant true
      %p1 = simulation.spawn @reader(%ctx, %d, %choose) : !simulation.context, !simulation.ref<!simulation.logic<4>>, i1 -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %choose: i1 {simulation.capture_kind = 2 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %sink = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %other = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      cf.br ^body
    ^body:
      cf.cond_br %choose, ^from_sink, ^from_other
    ^from_sink:
      cf.br ^merge(%sink : !simulation.ref<!simulation.logic<4>>)
    ^from_other:
      cf.br ^merge(%other : !simulation.ref<!simulation.logic<4>>)
    ^merge(%picked: !simulation.ref<!simulation.logic<4>>):
      %value = simulation.ref.load %picked : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.any %sink, %other edges [0, 0] to ^body : !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %a = simulation.logic.constant 10 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %a to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// An unresolved arith.select handle has both alternatives as provenance.
// CHECK-LABEL: simulation.design @selected_storage_reader
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @selected_storage_reader {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %choose = arith.constant true
      %p1 = simulation.spawn @reader(%ctx, %n, %d, %choose) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, i1 -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %choose: i1 {simulation.capture_kind = 2 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %other = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      cf.br ^body
    ^body:
      %picked = arith.select %choose, %in, %other : !simulation.ref<!simulation.logic<4>>
      %value = simulation.ref.load %picked : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.any %in, %other edges [0, 0] to ^body : !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>

    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %a = simulation.logic.constant 10 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %a to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// An unbound formal can alias design storage even when no local fact
// names that root. Conservatively retain assignments of the same kind.
// CHECK-LABEL: simulation.design @unbound_storage_reader
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @unbound_storage_reader {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %choose = arith.constant true
      %p1 = simulation.spawn @reader(%ctx, %n, %d, %choose) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, i1 -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 1 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %choose: i1 {simulation.capture_kind = 2 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %other = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      cf.br ^body
    ^body:
      cf.cond_br %choose, ^from_sink, ^from_other
    ^from_sink:
      cf.br ^merge(%in : !simulation.ref<!simulation.logic<4>>)
    ^from_other:
      cf.br ^merge(%other : !simulation.ref<!simulation.logic<4>>)
    ^merge(%picked: !simulation.ref<!simulation.logic<4>>):
      %value = simulation.ref.load %picked : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.any %in, %other edges [0, 0] to ^body : !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %a = simulation.logic.constant 10 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %a to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// An unresolved selection of proven local allocations cannot alias
// design storage and must not disable unrelated copy forwarding.
// CHECK-LABEL: simulation.design @local_selected_reader
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK-NOT: simulation.func private @copy
module {
  simulation.design @local_selected_reader {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %choose = arith.constant true
      %p1 = simulation.spawn @reader(%ctx, %n, %d, %choose) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, i1 -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %choose: i1 {simulation.capture_kind = 2 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %one = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      %a = simulation.ref.alloc %one : !simulation.logic<4> -> !simulation.ref<!simulation.logic<4>>
      %b = simulation.ref.alloc %one : !simulation.logic<4> -> !simulation.ref<!simulation.logic<4>>
      cf.br ^body
    ^body:
      %local = arith.select %choose, %a, %b : !simulation.ref<!simulation.logic<4>>
      %unused = simulation.ref.load %local : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %value to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.ref<!simulation.logic<4>>

    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %a = simulation.logic.constant 10 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %a to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}


// -----

// An unresolved writer of the copy source can publish transients.
// Record possible contributors as unknown-shape writers; pinning only
// assignments to those roots would miss this edge-observing sink.
// CHECK-LABEL: simulation.design @ambiguous_source_writer
// CHECK: simulation.spawn @copy
// CHECK: simulation.func private @copy
module {
  simulation.design @ambiguous_source_writer {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %choose = arith.constant true
      %p1 = simulation.spawn @reader(%ctx, %n, %d, %choose) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, i1 -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s, %d, %choose) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>>, i1 -> !simulation.process

      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %choose: i1 {simulation.capture_kind = 2 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %in edges [1] to ^observe : !simulation.ref<!simulation.logic<4>>
    ^observe:
      %value = simulation.ref.load %in : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %fd = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "y=%b"
      simulation.display %ctx to %fd(%fmt, %value) newline = true radix = <binary> flags = [0, 0] : !simulation.bytes, !simulation.logic<4>
      cf.br ^wait

    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %other: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %choose: i1 {simulation.capture_kind = 2 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %one = simulation.logic.constant 1 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %one to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^choose_target
    ^choose_target:
      cf.cond_br %choose, ^first, ^second
    ^first:
      cf.br ^merge(%out : !simulation.ref<!simulation.logic<4>>)
    ^second:
      cf.br ^merge(%other : !simulation.ref<!simulation.logic<4>>)
    ^merge(%picked: !simulation.ref<!simulation.logic<4>>):
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %zero to %picked : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.ref.store %one to %picked : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return

    }
  }
}

// -----

// The first round forwards copyA and clones its pure xor into reader.
// That xor's discardable symbol reference keeps copyB alive. The next round
// must find the cloned xor as copyB's user after the original xor was erased
// with copyA, and must retain copyB for that non-spawn use.
//
// CHECK-LABEL: simulation.design @cross_round_symbol_users
// CHECK-NOT: simulation.spawn @copyA(
// CHECK: simulation.spawn @copyB(
// CHECK-NOT: simulation.func private @copyA(
// CHECK: simulation.func private @reader(
// CHECK: simulation.logic.binary xor {{.*}} {test.ref = @copyB}
// CHECK: simulation.func private @copyB(
module {
  simulation.design @cross_round_symbol_users {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 continuous hierarchy "copyB"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<4> design
    simulation.storage.decl 3 in 0 : !simulation.logic<4> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<4>>
      %b = simulation.context.storage %ctx[3] : !simulation.ref<!simulation.logic<4>>
      %p0 = simulation.spawn @copyA(%ctx, %s, %n) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process

      %p2 = simulation.spawn @copyB(%ctx, %s, %b) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      simulation.return
    }
    simulation.func private @copyA(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %value = simulation.logic.binary xor %v, %c {test.ref = @copyB} : !simulation.logic<4>
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
    simulation.func private @copyB(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %dst : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
  }
}
