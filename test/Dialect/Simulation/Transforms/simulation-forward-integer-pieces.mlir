// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' -o %t.threaded
// RUN: FileCheck %s < %t.threaded
// RUN: talos-opt %s --split-input-file --mlir-disable-threading --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' -o %t.serial
// RUN: diff %t.serial %t.threaded

// IEEE 1800-2023 6.6.1/11.4.12: a complete disjoint strong partition is
// the concatenation of its source pieces, for plain integers and packed
// two-state aggregates too. This does not relax startup, transient, waveform,
// source-event or observer proofs. Incomplete/overlapping partitions remain.
// CHECK-LABEL: simulation.design @partitioned_i4
// CHECK-NOT: simulation.spawn @low
// CHECK-NOT: simulation.spawn @high
// CHECK: simulation.func private @reader(
// CHECK: arith.shli
// CHECK: arith.ori
// CHECK: simulation.suspend.any
// CHECK-NOT: simulation.func private @low
// CHECK-NOT: simulation.func private @high
module {
  simulation.design @partitioned_i4 {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "low"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "high"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 5 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : i2 design
    simulation.storage.decl 1 in 0 : i4 design
    simulation.storage.decl 2 in 0 : i2 design
    simulation.net.decl 0 in 0 : i4 design
    simulation.driver.decl 0 in 0 drives 0 : i4 design {driven_low = 0 : i64, driven_width = 2 : i64}
    simulation.driver.decl 1 in 0 drives 0 : i4 design {driven_low = 2 : i64, driven_width = 2 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %b = simulation.context.storage %ctx[2] : !simulation.ref<i2>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<i4>
      %n = simulation.context.net %ctx[0] : !simulation.net<i4>
      %d0 = simulation.context.driver %ctx[0] : !simulation.driver<i4>
      %d1 = simulation.context.driver %ctx[1] : !simulation.driver<i4>
      %p0 = simulation.spawn @low(%ctx, %a, %d0) : !simulation.context, !simulation.ref<i2>, !simulation.driver<i4> -> !simulation.process
      %p1 = simulation.spawn @high(%ctx, %b, %d1) : !simulation.context, !simulation.ref<i2>, !simulation.driver<i4> -> !simulation.process
      %p2 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<i4>, !simulation.ref<i4> -> !simulation.process
      %p3 = simulation.spawn @writer(%ctx, %a, %b) : !simulation.context, !simulation.ref<i2>, !simulation.ref<i2> -> !simulation.process
      simulation.return
    }
    simulation.func private @low(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<i4> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<i2> -> i2
      %part = simulation.driver.extract %drv from 0 : !simulation.driver<i4> -> !simulation.driver<i2>
      simulation.driver.drive %part = %v : !simulation.driver<i2>, i2
      simulation.suspend.change %src to ^body : !simulation.ref<i2>
    }
    simulation.func private @high(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %drv: !simulation.driver<i4> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<i2> -> i2
      %part = simulation.driver.extract %drv from 2 : !simulation.driver<i4> -> !simulation.driver<i2>
      simulation.driver.drive %part = %v : !simulation.driver<i2>, i2
      simulation.suspend.change %src to ^body : !simulation.ref<i2>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<i4> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<i4> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<i4> -> i4
      simulation.ref.store %v to %out : i4, !simulation.ref<i4>
      simulation.suspend.change %in to ^body {schedule.procedural_event_wait} : !simulation.net<i4>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %b: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %c = arith.constant 1 : i2
      simulation.ref.store %c to %a : i2, !simulation.ref<i2>
      simulation.ref.store %c to %b : i2, !simulation.ref<i2>
      simulation.return
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @partitioned_packed_i4
// CHECK-NOT: simulation.spawn @low
// CHECK-NOT: simulation.spawn @high
// CHECK: simulation.func private @reader(
// CHECK: arith.shli
// CHECK: arith.ori
// CHECK: simulation.suspend.any
// CHECK-NOT: simulation.func private @low
// CHECK-NOT: simulation.func private @high
!p2 = !simulation.packed_array<1 : 0 x i1>
!p4 = !simulation.packed_array<3 : 0 x i1>
module {
  simulation.design @partitioned_packed_i4 {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "low"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "high"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 5 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !p2 design
    simulation.storage.decl 1 in 0 : !p4 design
    simulation.storage.decl 2 in 0 : !p2 design
    simulation.net.decl 0 in 0 : !p4 design
    simulation.driver.decl 0 in 0 drives 0 : !p4 design {driven_low = 0 : i64, driven_width = 2 : i64}
    simulation.driver.decl 1 in 0 drives 0 : !p4 design {driven_low = 2 : i64, driven_width = 2 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<!p2>
      %b = simulation.context.storage %ctx[2] : !simulation.ref<!p2>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!p4>
      %n = simulation.context.net %ctx[0] : !simulation.net<!p4>
      %d0 = simulation.context.driver %ctx[0] : !simulation.driver<!p4>
      %d1 = simulation.context.driver %ctx[1] : !simulation.driver<!p4>
      %p0 = simulation.spawn @low(%ctx, %a, %d0) : !simulation.context, !simulation.ref<!p2>, !simulation.driver<!p4> -> !simulation.process
      %p1 = simulation.spawn @high(%ctx, %b, %d1) : !simulation.context, !simulation.ref<!p2>, !simulation.driver<!p4> -> !simulation.process
      %p2 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!p4>, !simulation.ref<!p4> -> !simulation.process
      %p3 = simulation.spawn @writer(%ctx, %a, %b) : !simulation.context, !simulation.ref<!p2>, !simulation.ref<!p2> -> !simulation.process
      simulation.return
    }
    simulation.func private @low(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!p2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!p4> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!p2> -> !p2
      %part = simulation.driver.extract %drv from 0 : !simulation.driver<!p4> -> !simulation.driver<!p2>
      simulation.driver.drive %part = %v : !simulation.driver<!p2>, !p2
      simulation.suspend.change %src to ^body : !simulation.ref<!p2>
    }
    simulation.func private @high(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!p2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %drv: !simulation.driver<!p4> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!p2> -> !p2
      %part = simulation.driver.extract %drv from 2 : !simulation.driver<!p4> -> !simulation.driver<!p2>
      simulation.driver.drive %part = %v : !simulation.driver<!p2>, !p2
      simulation.suspend.change %src to ^body : !simulation.ref<!p2>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!p4> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!p4> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<!p4> -> !p4
      simulation.ref.store %v to %out : !p4, !simulation.ref<!p4>
      simulation.suspend.change %in to ^body {schedule.procedural_event_wait} : !simulation.net<!p4>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.ref<!p2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %b: !simulation.ref<!p2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %bits = arith.constant 1 : i2
      %c = simulation.packed.unflatten %bits : (i2) -> !p2
      simulation.ref.store %c to %a : !p2, !simulation.ref<!p2>
      simulation.ref.store %c to %b : !p2, !simulation.ref<!p2>
      simulation.return
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @gap_i4
// CHECK: simulation.spawn @low
// CHECK: simulation.spawn @high
// CHECK: simulation.func private @low(
// CHECK: simulation.func private @high(
module {
  simulation.design @gap_i4 {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "low"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "high"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 5 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : i2 design
    simulation.storage.decl 1 in 0 : i4 design
    simulation.storage.decl 2 in 0 : i2 design
    simulation.net.decl 0 in 0 : i4 design
    simulation.driver.decl 0 in 0 drives 0 : i4 design {driven_low = 0 : i64, driven_width = 2 : i64}
    simulation.driver.decl 1 in 0 drives 0 : i4 design {driven_low = 3 : i64, driven_width = 1 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %b = simulation.context.storage %ctx[2] : !simulation.ref<i2>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<i4>
      %n = simulation.context.net %ctx[0] : !simulation.net<i4>
      %d0 = simulation.context.driver %ctx[0] : !simulation.driver<i4>
      %d1 = simulation.context.driver %ctx[1] : !simulation.driver<i4>
      %p0 = simulation.spawn @low(%ctx, %a, %d0) : !simulation.context, !simulation.ref<i2>, !simulation.driver<i4> -> !simulation.process
      %p1 = simulation.spawn @high(%ctx, %b, %d1) : !simulation.context, !simulation.ref<i2>, !simulation.driver<i4> -> !simulation.process
      %p2 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<i4>, !simulation.ref<i4> -> !simulation.process
      %p3 = simulation.spawn @writer(%ctx, %a, %b) : !simulation.context, !simulation.ref<i2>, !simulation.ref<i2> -> !simulation.process
      simulation.return
    }
    simulation.func private @low(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<i4> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<i2> -> i2
      %part = simulation.driver.extract %drv from 0 : !simulation.driver<i4> -> !simulation.driver<i2>
      simulation.driver.drive %part = %v : !simulation.driver<i2>, i2
      simulation.suspend.change %src to ^body : !simulation.ref<i2>
    }
    simulation.func private @high(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %drv: !simulation.driver<i4> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<i2> -> i2
      %piece = arith.trunci %v : i2 to i1
      %part = simulation.driver.extract %drv from 3 : !simulation.driver<i4> -> !simulation.driver<i1>
      simulation.driver.drive %part = %piece : !simulation.driver<i1>, i1
      simulation.suspend.change %src to ^body : !simulation.ref<i2>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<i4> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<i4> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<i4> -> i4
      simulation.ref.store %v to %out : i4, !simulation.ref<i4>
      simulation.suspend.change %in to ^body {schedule.procedural_event_wait} : !simulation.net<i4>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %b: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %c = arith.constant 1 : i2
      simulation.ref.store %c to %a : i2, !simulation.ref<i2>
      simulation.ref.store %c to %b : i2, !simulation.ref<i2>
      simulation.return
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @overlap_i4
// CHECK: simulation.spawn @low
// CHECK: simulation.spawn @high
// CHECK: simulation.func private @low(
// CHECK: simulation.func private @high(
module {
  simulation.design @overlap_i4 {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "low"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "high"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 5 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : i2 design
    simulation.storage.decl 1 in 0 : i4 design
    simulation.storage.decl 2 in 0 : i2 design
    simulation.net.decl 0 in 0 : i4 design
    simulation.driver.decl 0 in 0 drives 0 : i4 design {driven_low = 0 : i64, driven_width = 2 : i64}
    simulation.driver.decl 1 in 0 drives 0 : i4 design {driven_low = 1 : i64, driven_width = 3 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %b = simulation.context.storage %ctx[2] : !simulation.ref<i2>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<i4>
      %n = simulation.context.net %ctx[0] : !simulation.net<i4>
      %d0 = simulation.context.driver %ctx[0] : !simulation.driver<i4>
      %d1 = simulation.context.driver %ctx[1] : !simulation.driver<i4>
      %p0 = simulation.spawn @low(%ctx, %a, %d0) : !simulation.context, !simulation.ref<i2>, !simulation.driver<i4> -> !simulation.process
      %p1 = simulation.spawn @high(%ctx, %b, %d1) : !simulation.context, !simulation.ref<i2>, !simulation.driver<i4> -> !simulation.process
      %p2 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<i4>, !simulation.ref<i4> -> !simulation.process
      %p3 = simulation.spawn @writer(%ctx, %a, %b) : !simulation.context, !simulation.ref<i2>, !simulation.ref<i2> -> !simulation.process
      simulation.return
    }
    simulation.func private @low(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<i4> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<i2> -> i2
      %part = simulation.driver.extract %drv from 0 : !simulation.driver<i4> -> !simulation.driver<i2>
      simulation.driver.drive %part = %v : !simulation.driver<i2>, i2
      simulation.suspend.change %src to ^body : !simulation.ref<i2>
    }
    simulation.func private @high(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %drv: !simulation.driver<i4> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<i2> -> i2
      %piece = arith.extui %v : i2 to i3
      %part = simulation.driver.extract %drv from 1 : !simulation.driver<i4> -> !simulation.driver<i3>
      simulation.driver.drive %part = %piece : !simulation.driver<i3>, i3
      simulation.suspend.change %src to ^body : !simulation.ref<i2>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<i4> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<i4> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<i4> -> i4
      simulation.ref.store %v to %out : i4, !simulation.ref<i4>
      simulation.suspend.change %in to ^body {schedule.procedural_event_wait} : !simulation.net<i4>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %b: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %c = arith.constant 1 : i2
      simulation.ref.store %c to %a : i2, !simulation.ref<i2>
      simulation.ref.store %c to %b : i2, !simulation.ref<i2>
      simulation.return
    }
  }
}
