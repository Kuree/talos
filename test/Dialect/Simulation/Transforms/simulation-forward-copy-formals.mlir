// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' > %t.threaded
// RUN: FileCheck %s < %t.threaded
// RUN: talos-opt %s -split-input-file -mlir-disable-threading --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' > %t.serial
// RUN: diff -u %t.serial %t.threaded

// Closed call sites can bound helper formals without weakening the handling
// of design-root actuals, source transients, or genuinely opaque references.
// A private direct-call helper observes only a proven local allocation. Its formal must not pin unrelated design storage.
// CHECK-LABEL: simulation.design @closed_function_local_actual
// CHECK-NOT: simulation.spawn @copy(
// CHECK-NOT: simulation.func private @copy(
// CHECK: simulation.func private @reader(
// CHECK: simulation.func private @caller(
// CHECK: simulation.call @helper(
// CHECK: simulation.func private @helper(
!c = !simulation.context
!l = !simulation.logic<4>
!r = !simulation.ref<!l>
module {
  simulation.design @closed_function_local_actual {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 5 in 0 function hierarchy "helper"
    simulation.storage.decl 0 in 0 : !l design
    simulation.storage.decl 1 in 0 : !l design
    simulation.storage.decl 2 in 0 : !l design
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !r
      %n = simulation.context.storage %ctx[1] : !r
      %d = simulation.context.storage %ctx[2] : !r
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !c, !r, !r -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !c, !r, !r -> !simulation.process
      %caller = simulation.spawn @caller(%ctx) : !c -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !r -> !l
      simulation.ref.store %v to %dst : !l, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func private @reader(%ctx: !c {simulation.capture_kind = 0 : i32}, %in: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> !l
      simulation.ref.store %v to %out : !l, !r
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func private @caller(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !l
      %actual = simulation.ref.alloc %zero : !l -> !r
      simulation.call @helper(%ctx, %actual) : (!c, !r) -> ()
      simulation.return
    }
    simulation.func private @helper(%ctx: !c {simulation.capture_kind = 0 : i32}, %formal: !r {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %v = simulation.ref.load %formal : !r -> !l
      simulation.ref.store %v to %formal : !l, !r
      simulation.return
    }
  }
}

// -----

// A private task's output reference is likewise covered by its exact caller and cannot escape its local actual.
// CHECK-LABEL: simulation.design @closed_task_local_actual
// CHECK-NOT: simulation.spawn @copy(
// CHECK-NOT: simulation.func private @copy(
// CHECK: simulation.func private @reader(
// CHECK: simulation.func private @caller(
// CHECK: simulation.task.call @helper(
// CHECK: simulation.func private @helper(
!c = !simulation.context
!l = !simulation.logic<4>
!r = !simulation.ref<!l>
module {
  simulation.design @closed_task_local_actual {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 5 in 0 task hierarchy "helper"
    simulation.storage.decl 0 in 0 : !l design
    simulation.storage.decl 1 in 0 : !l design
    simulation.storage.decl 2 in 0 : !l design
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !r
      %n = simulation.context.storage %ctx[1] : !r
      %d = simulation.context.storage %ctx[2] : !r
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !c, !r, !r -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !c, !r, !r -> !simulation.process
      %caller = simulation.spawn @caller(%ctx) : !c -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !r -> !l
      simulation.ref.store %v to %dst : !l, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func private @reader(%ctx: !c {simulation.capture_kind = 0 : i32}, %in: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> !l
      simulation.ref.store %v to %out : !l, !r
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func private @caller(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !l
      %actual = simulation.ref.alloc %zero : !l -> !r
      simulation.task.call @helper(%ctx, %actual) arguments 2 to ^done : !c, !r
    ^done:
      simulation.return
    }
    simulation.func private @helper(%ctx: !c {simulation.capture_kind = 0 : i32}, %formal: !r {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 12 : i32, code_unit_id = 5 : i64} {
      %v = simulation.ref.load %formal : !r -> !l
      simulation.ref.store %v to %formal : !l, !r
      simulation.return
    }
  }
}

// -----

// The caller still observes and may write its design-root actual. Keep that sink, while forwarding an unrelated sink.
// CHECK-LABEL: simulation.design @closed_function_design_actual
// CHECK: simulation.spawn @copy(
// CHECK-NOT: simulation.spawn @copy_other(
// CHECK: simulation.func private @copy(
// CHECK-NOT: simulation.func private @copy_other(
// CHECK: simulation.func private @reader_other(
// CHECK: simulation.func private @caller(
// CHECK: simulation.call @helper(
!c = !simulation.context
!l = !simulation.logic<4>
!r = !simulation.ref<!l>
module {
  simulation.design @closed_function_design_actual {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 5 in 0 function hierarchy "helper"
    simulation.code_unit.decl 6 in 0 continuous hierarchy "copy_other"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "reader_other"
    simulation.storage.decl 0 in 0 : !l design
    simulation.storage.decl 1 in 0 : !l design
    simulation.storage.decl 2 in 0 : !l design
    simulation.storage.decl 3 in 0 : !l design
    simulation.storage.decl 4 in 0 : !l design
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !r
      %n = simulation.context.storage %ctx[1] : !r
      %d = simulation.context.storage %ctx[2] : !r
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !c, !r, !r -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !c, !r, !r -> !simulation.process
      %other = simulation.context.storage %ctx[3] : !r
      %other_out = simulation.context.storage %ctx[4] : !r
      %p2 = simulation.spawn @copy_other(%ctx, %s, %other) : !c, !r, !r -> !simulation.process
      %p3 = simulation.spawn @reader_other(%ctx, %other, %other_out) : !c, !r, !r -> !simulation.process
      %caller = simulation.spawn @caller(%ctx, %n) : !c, !r -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !r -> !l
      simulation.ref.store %v to %dst : !l, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func private @reader(%ctx: !c {simulation.capture_kind = 0 : i32}, %in: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> !l
      simulation.ref.store %v to %out : !l, !r
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func private @copy_other(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 6 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !r -> !l
      simulation.ref.store %v to %dst : !l, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func private @reader_other(%ctx: !c {simulation.capture_kind = 0 : i32}, %in: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %out: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 7 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> !l
      simulation.ref.store %v to %out : !l, !r
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func private @caller(%ctx: !c {simulation.capture_kind = 0 : i32}, %actual: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      simulation.call @helper(%ctx, %actual) : (!c, !r) -> ()
      simulation.return
    }
    simulation.func private @helper(%ctx: !c {simulation.capture_kind = 0 : i32}, %formal: !r {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %v = simulation.ref.load %formal : !r -> !l
      simulation.ref.store %v to %formal : !l, !r
      simulation.return
    }
  }
}

// -----

// A public helper may receive other design roots from an external caller, so its formal retains the global fallback.
// CHECK-LABEL: simulation.design @public_formal_keeps_storage
// CHECK: simulation.spawn @copy(
// CHECK: simulation.func private @copy(
// CHECK: simulation.func @helper(
!c = !simulation.context
!l = !simulation.logic<4>
!r = !simulation.ref<!l>
module {
  simulation.design @public_formal_keeps_storage {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 5 in 0 function hierarchy "helper"
    simulation.storage.decl 0 in 0 : !l design
    simulation.storage.decl 1 in 0 : !l design
    simulation.storage.decl 2 in 0 : !l design
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !r
      %n = simulation.context.storage %ctx[1] : !r
      %d = simulation.context.storage %ctx[2] : !r
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !c, !r, !r -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !c, !r, !r -> !simulation.process
      %caller = simulation.spawn @caller(%ctx) : !c -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !r -> !l
      simulation.ref.store %v to %dst : !l, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func private @reader(%ctx: !c {simulation.capture_kind = 0 : i32}, %in: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> !l
      simulation.ref.store %v to %out : !l, !r
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func private @caller(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !l
      %actual = simulation.ref.alloc %zero : !l -> !r
      simulation.call @helper(%ctx, %actual) : (!c, !r) -> ()
      simulation.return
    }
    simulation.func @helper(%ctx: !c {simulation.capture_kind = 0 : i32}, %formal: !r {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %v = simulation.ref.load %formal : !r -> !l
      simulation.ref.store %v to %formal : !l, !r
      simulation.return
    }
  }
}

// -----

// A separate noncall symbol reference can expose this helper outside its inventoried calls.
// CHECK-LABEL: simulation.design @noncall_formal_keeps_storage
// CHECK: simulation.spawn @copy(
// CHECK: simulation.func private @copy(
// CHECK: simulation.func private @helper(
!c = !simulation.context
!l = !simulation.logic<4>
!r = !simulation.ref<!l>
module {
  simulation.design @noncall_formal_keeps_storage {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 5 in 0 function hierarchy "helper"
    simulation.storage.decl 0 in 0 : !l design
    simulation.storage.decl 1 in 0 : !l design
    simulation.storage.decl 2 in 0 : !l design
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64, test.address_taken = @helper} {
      %s = simulation.context.storage %ctx[0] : !r
      %n = simulation.context.storage %ctx[1] : !r
      %d = simulation.context.storage %ctx[2] : !r
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !c, !r, !r -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !c, !r, !r -> !simulation.process
      %caller = simulation.spawn @caller(%ctx) : !c -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !r -> !l
      simulation.ref.store %v to %dst : !l, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func private @reader(%ctx: !c {simulation.capture_kind = 0 : i32}, %in: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> !l
      simulation.ref.store %v to %out : !l, !r
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func private @caller(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !l
      %actual = simulation.ref.alloc %zero : !l -> !r
      simulation.call @helper(%ctx, %actual) : (!c, !r) -> ()
      simulation.return
    }
    simulation.func private @helper(%ctx: !c {simulation.capture_kind = 0 : i32}, %formal: !r {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %v = simulation.ref.load %formal : !r -> !l
      simulation.ref.store %v to %formal : !l, !r
      simulation.return
    }
  }
}

// -----

// An additional symbol reference on the direct call is not part of its canonical callee and can expose the helper.
// CHECK-LABEL: simulation.design @call_attribute_keeps_storage
// CHECK: simulation.spawn @copy(
// CHECK: simulation.func private @copy(
// CHECK: simulation.func private @helper(
!c = !simulation.context
!l = !simulation.logic<4>
!r = !simulation.ref<!l>
module {
  simulation.design @call_attribute_keeps_storage {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 5 in 0 function hierarchy "helper"
    simulation.storage.decl 0 in 0 : !l design
    simulation.storage.decl 1 in 0 : !l design
    simulation.storage.decl 2 in 0 : !l design
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !r
      %n = simulation.context.storage %ctx[1] : !r
      %d = simulation.context.storage %ctx[2] : !r
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !c, !r, !r -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !c, !r, !r -> !simulation.process
      %caller = simulation.spawn @caller(%ctx) : !c -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !r -> !l
      simulation.ref.store %v to %dst : !l, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func private @reader(%ctx: !c {simulation.capture_kind = 0 : i32}, %in: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> !l
      simulation.ref.store %v to %out : !l, !r
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func private @caller(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !l
      %actual = simulation.ref.alloc %zero : !l -> !r
      simulation.call @helper(%ctx, %actual) {test.address_taken = @helper} : (!c, !r) -> ()
      simulation.return
    }
    simulation.func private @helper(%ctx: !c {simulation.capture_kind = 0 : i32}, %formal: !r {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %v = simulation.ref.load %formal : !r -> !l
      simulation.ref.store %v to %formal : !l, !r
      simulation.return
    }
  }
}

// -----

// Delegation must preserve the caller's unknown write shape: a helper can publish source transients that the copy hides.
// CHECK-LABEL: simulation.design @source_formal_writer_keeps_edge_copy
// CHECK: simulation.spawn @copy(
// CHECK: simulation.func private @copy(
// CHECK: simulation.func private @reader(
// CHECK: simulation.suspend.any {{.*}} edges [1]
// CHECK: simulation.func private @caller(
// CHECK: simulation.call @helper(
// CHECK: simulation.func private @helper(
!c = !simulation.context
!l = !simulation.logic<4>
!r = !simulation.ref<!l>
module {
  simulation.design @source_formal_writer_keeps_edge_copy {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 5 in 0 function hierarchy "helper"
    simulation.storage.decl 0 in 0 : !l design
    simulation.storage.decl 1 in 0 : !l design
    simulation.storage.decl 2 in 0 : !l design
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !r
      %n = simulation.context.storage %ctx[1] : !r
      %d = simulation.context.storage %ctx[2] : !r
      %one = simulation.logic.constant 1 : i4, 0 : i4 : !l
      simulation.ref.store %one to %s : !l, !r
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !c, !r, !r -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !c, !r, !r -> !simulation.process
      %caller = simulation.spawn @caller(%ctx, %s) : !c, !r -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !r -> !l
      simulation.ref.store %v to %dst : !l, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func private @reader(%ctx: !c {simulation.capture_kind = 0 : i32}, %in: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %in edges [1] to ^body : !r
    ^body:
      %v = simulation.ref.load %in : !r -> !l
      simulation.ref.store %v to %out : !l, !r
      cf.br ^wait
    }
    simulation.func private @caller(%ctx: !c {simulation.capture_kind = 0 : i32}, %actual: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %delay = simulation.time.constant 1
      simulation.suspend.delay %delay to ^write
    ^write:
      simulation.call @helper(%ctx, %actual) : (!c, !r) -> ()
      simulation.return
    }
    simulation.func private @helper(%ctx: !c {simulation.capture_kind = 0 : i32}, %formal: !r {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !l
      %one = simulation.logic.constant 1 : i4, 0 : i4 : !l
      simulation.ref.store %zero to %formal : !l, !r
      simulation.ref.store %one to %formal : !l, !r
      simulation.return
    }
  }
}

// -----

// A closed formal and an opaque factory can meet at one reference PHI. Delegating the formal must retain the factory fallback.
// CHECK-LABEL: simulation.design @mixed_formal_and_factory_keeps_storage
// CHECK: simulation.spawn @copy(
// CHECK: simulation.func private @copy(
// CHECK: simulation.func private @helper(
!c = !simulation.context
!l = !simulation.logic<4>
!r = !simulation.ref<!l>
module {
  simulation.design @mixed_formal_and_factory_keeps_storage {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 5 in 0 function hierarchy "helper"
    simulation.storage.decl 0 in 0 : !l design
    simulation.storage.decl 1 in 0 : !l design
    simulation.storage.decl 2 in 0 : !l design
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !r
      %n = simulation.context.storage %ctx[1] : !r
      %d = simulation.context.storage %ctx[2] : !r
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !c, !r, !r -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !c, !r, !r -> !simulation.process
      %caller = simulation.spawn @caller(%ctx) : !c -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !r -> !l
      simulation.ref.store %v to %dst : !l, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func private @reader(%ctx: !c {simulation.capture_kind = 0 : i32}, %in: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> !l
      simulation.ref.store %v to %out : !l, !r
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func private @caller(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !l
      %actual = simulation.ref.alloc %zero : !l -> !r
      %choose = arith.constant true
      simulation.call @helper(%ctx, %actual, %choose) : (!c, !r, i1) -> ()
      simulation.return
    }
    simulation.func private @helper(%ctx: !c {simulation.capture_kind = 0 : i32}, %formal: !r {simulation.capture_kind = 1 : i32}, %choose: i1 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %opaque = func.call @factory(%ctx) : (!c) -> !r
      cf.cond_br %choose, ^from_formal, ^from_opaque
    ^from_formal:
      cf.br ^merge(%formal : !r)
    ^from_opaque:
      cf.br ^merge(%opaque : !r)
    ^merge(%picked: !r):
      %v = simulation.ref.load %picked : !r -> !l
      simulation.ref.store %v to %picked : !l, !r
      simulation.return
    }
    func.func private @factory(!c) -> !r
  }
}


// -----

// A func.func caller is outside the simulation-function inventory. Its call
// cannot delegate the helper formal, even alongside a covered local caller.
// CHECK-LABEL: simulation.design @hybrid_caller_keeps_storage
// CHECK: simulation.spawn @copy(
// CHECK: simulation.func private @copy(
// CHECK: simulation.func private @helper(
// CHECK: func.func @outside(
// CHECK: simulation.call @helper(
!c = !simulation.context
!l = !simulation.logic<4>
!r = !simulation.ref<!l>
module {
  simulation.design @hybrid_caller_keeps_storage {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 5 in 0 function hierarchy "helper"
    simulation.storage.decl 0 in 0 : !l design
    simulation.storage.decl 1 in 0 : !l design
    simulation.storage.decl 2 in 0 : !l design
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !r
      %n = simulation.context.storage %ctx[1] : !r
      %d = simulation.context.storage %ctx[2] : !r
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !c, !r, !r -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !c, !r, !r -> !simulation.process
      %caller = simulation.spawn @caller(%ctx) : !c -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !r -> !l
      simulation.ref.store %v to %dst : !l, !r
      simulation.suspend.change %src to ^body : !r
    }
    simulation.func private @reader(%ctx: !c {simulation.capture_kind = 0 : i32}, %in: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !r -> !l
      simulation.ref.store %v to %out : !l, !r
      simulation.suspend.change %in to ^body : !r
    }
    simulation.func private @caller(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !l
      %actual = simulation.ref.alloc %zero : !l -> !r
      simulation.call @helper(%ctx, %actual) : (!c, !r) -> ()
      simulation.return
    }
    simulation.func private @helper(%ctx: !c {simulation.capture_kind = 0 : i32}, %formal: !r {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64} {
      %v = simulation.ref.load %formal : !r -> !l
      simulation.ref.store %v to %formal : !l, !r
      simulation.return
    }
    func.func @outside(%ctx: !c) {
      %in = simulation.context.storage %ctx[1] : !r
      simulation.call @helper(%ctx, %in) : (!c, !r) -> ()
      return
    }
  }
}
