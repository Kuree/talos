// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{closed-model=true}))' | FileCheck %s
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' | FileCheck %s --check-prefix=OPEN
//
// Each spawned child retains its actual reference (1800-2023 9.3.2, 13.5.2).
// One binding is automatic storage and the other names an observable copy.
// The unrelated continuous assignment can be forwarded in a closed model.
// CHECK-LABEL: simulation.func @root(
// CHECK-NOT: simulation.spawn @copy(
// CHECK: simulation.spawn @observed_copy(
// CHECK-NOT: simulation.func private @copy(
// CHECK: simulation.func private @observed_copy(
// CHECK: simulation.func private @caller(
// CHECK: simulation.ref.alloc
// CHECK: simulation.spawn @child(
// CHECK: simulation.context.storage %{{.*}}[3]
// CHECK: simulation.spawn @child(
// CHECK: simulation.func private @child(
// OPEN-LABEL: simulation.func @root(
// OPEN: simulation.spawn @copy(
// OPEN: simulation.spawn @observed_copy(
!c = !simulation.context
!l = !simulation.logic<4>
!r = !simulation.ref<!l>
module {
  simulation.design @spawned_references {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 5 in 0 fork hierarchy "child"
    simulation.code_unit.decl 6 in 0 continuous hierarchy "observed_copy"
    simulation.storage.decl 3 in 0 : !l design
    simulation.storage.decl 0 in 0 : !l design
    simulation.storage.decl 1 in 0 : !l design
    simulation.storage.decl 2 in 0 : !l design
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !r
      %n = simulation.context.storage %ctx[1] : !r
      %d = simulation.context.storage %ctx[2] : !r
      %p0 = simulation.spawn @copy(%ctx, %s, %n) : !c, !r, !r -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !c, !r, !r -> !simulation.process
      %observed = simulation.context.storage %ctx[3] : !r
      %keep = simulation.spawn @observed_copy(%ctx, %s, %observed) : !c, !r, !r -> !simulation.process
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
    simulation.func private @observed_copy(%ctx: !c {simulation.capture_kind = 0 : i32}, %src: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dst: !r {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 6 : i64} {
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
      %p0 = simulation.spawn @child(%ctx, %actual) : !c, !r -> !simulation.process
      %visible = simulation.context.storage %ctx[3] : !r
      %p1 = simulation.spawn @child(%ctx, %visible) : !c, !r -> !simulation.process
      simulation.return
    }
    simulation.func private @child(%ctx: !c {simulation.capture_kind = 0 : i32}, %formal: !r {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 5 : i64} {
      %v = simulation.ref.load %formal : !r -> !l
      simulation.ref.store %v to %formal : !l, !r
      simulation.return
    }
  }
}

// -----

// One unbounded actual among two spawns can designate the copy. Its read
// and write keep the materialized destination in either compilation mode.
// CHECK-LABEL: simulation.design @opaque_spawn_capture
// CHECK: simulation.spawn @copy(
// CHECK: simulation.func private @copy(
// OPEN-LABEL: simulation.design @opaque_spawn_capture
// OPEN: simulation.spawn @copy(
!c = !simulation.context
!l = !simulation.logic<4>
!r = !simulation.ref<!l>
module {
  simulation.design @opaque_spawn_capture {
    func.func private @factory(!c) -> !r
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "caller"
    simulation.code_unit.decl 5 in 0 fork hierarchy "child"
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
      %p0 = simulation.spawn @child(%ctx, %actual) : !c, !r -> !simulation.process
      %opaque = func.call @factory(%ctx) : (!c) -> !r
      %p1 = simulation.spawn @child(%ctx, %opaque) : !c, !r -> !simulation.process
      simulation.return
    }
    simulation.func private @child(%ctx: !c {simulation.capture_kind = 0 : i32}, %formal: !r {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 5 : i64} {
      %v = simulation.ref.load %formal : !r -> !l
      simulation.ref.store %v to %formal : !l, !r
      simulation.return
    }
  }
}
