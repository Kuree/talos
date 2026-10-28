// RUN: talos-opt %s -split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' | FileCheck %s

// Shapes the readers of a single-driver net take over (IEEE 1800-2023 10.3.2,
// 6.6.1): views and waits on slices, partitioned nets, chains of copies,
// display items, and writers whose activations publish each bit once. The
// blocked counterparts are in simulation-forward-copy-processes-blockers.mlir.
// `assign y = a[2:1]; always @(posedge y)`: an edge on a vector is detected on
// its least significant bit (IEEE 1800-2023 9.4.2), which is a[1].
// CHECK-LABEL: simulation.design @edge_on_slice
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader({{.*}}, %[[A:.*]]: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
// CHECK: %[[BIT:.*]] = simulation.ref.extract %[[A]] from 1 : !simulation.ref<!simulation.logic<4>> -> !simulation.ref<!simulation.logic<1>>
// CHECK-NEXT: simulation.suspend.edge posedge %[[BIT]]
// CHECK-NOT: simulation.func private @copy
module {
  simulation.design @edge_on_slice {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<2> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<2> design {driven_low = 0 : i64, driven_width = 2 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<2>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<2>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<2>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<2>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!simulation.logic<2>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      %s = simulation.logic.extract %v from 1 : !simulation.logic<4> -> !simulation.logic<2>
      simulation.driver.drive %drv = %s : !simulation.driver<!simulation.logic<2>>, !simulation.logic<2>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<2>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %in to ^body : !simulation.net<!simulation.logic<2>>
    ^body:
      simulation.ref.store %five to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      cf.br ^wait
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// `assign y[1:0] = a; assign y[3:2] = b;`: per-bit resolution makes a strong
// partition a set of independent copies (6.6.1); the reader reads {b, a}
// and waits on both, keeping its wait's discardable attributes.
// CHECK-LABEL: simulation.design @partitioned
// CHECK-NOT: simulation.spawn @low
// CHECK-NOT: simulation.spawn @high
// CHECK: simulation.func private @reader({{.*}}, %[[B:.*]]: !simulation.ref<!simulation.logic<2>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %[[A:.*]]: !simulation.ref<!simulation.logic<2>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
// CHECK: %[[VB:.*]] = simulation.ref.load %[[B]]
// CHECK: %[[VA:.*]] = simulation.ref.load %[[A]]
// CHECK: simulation.logic.concat %[[VB]], %[[VA]] : (!simulation.logic<2>, !simulation.logic<2>) -> !simulation.logic<4>
// CHECK: simulation.suspend.any %[[A]], %[[B]] edges [0, 0] to ^{{.*}} {schedule.procedural_event_wait}
// CHECK-NOT: simulation.func private @low
// CHECK-NOT: simulation.func private @high
module {
  simulation.design @partitioned {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "low"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "high"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 5 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<2> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.storage.decl 2 in 0 : !simulation.logic<2> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 2 : i64}
    simulation.driver.decl 1 in 0 drives 0 : !simulation.logic<4> design {driven_low = 2 : i64, driven_width = 2 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<2>>
      %b = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<2>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %d0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %d1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @low(%ctx, %a, %d0) : !simulation.context, !simulation.ref<!simulation.logic<2>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @high(%ctx, %b, %d1) : !simulation.context, !simulation.ref<!simulation.logic<2>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p3 = simulation.spawn @writer(%ctx, %a, %b) : !simulation.context, !simulation.ref<!simulation.logic<2>>, !simulation.ref<!simulation.logic<2>> -> !simulation.process
      simulation.return
    }
    simulation.func private @low(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<2>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
      %part = simulation.driver.extract %drv from 0 : !simulation.driver<!simulation.logic<4>> -> !simulation.driver<!simulation.logic<2>>
      simulation.driver.drive %part = %v : !simulation.driver<!simulation.logic<2>>, !simulation.logic<2>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<2>>
    }
    simulation.func private @high(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<2>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<2>> -> !simulation.logic<2>
      %part = simulation.driver.extract %drv from 2 : !simulation.driver<!simulation.logic<4>> -> !simulation.driver<!simulation.logic<2>>
      simulation.driver.drive %part = %v : !simulation.driver<!simulation.logic<2>>, !simulation.logic<2>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<2>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body {schedule.procedural_event_wait} : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.ref<!simulation.logic<2>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %b: !simulation.ref<!simulation.logic<2>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %c = simulation.logic.constant 1 : i2, 0 : i2 : !simulation.logic<2>
      simulation.ref.store %c to %a : !simulation.logic<2>, !simulation.ref<!simulation.logic<2>>
      simulation.ref.store %c to %b : !simulation.logic<2>, !simulation.ref<!simulation.logic<2>>
      simulation.return
    }
  }
}

// -----

// `assign y = s; assign z = y;`: leaves first. The first round forwards s
// into the second copy, the next round forwards that copy into the reader.
// CHECK-LABEL: simulation.design @chain
// CHECK-NOT: simulation.spawn @first
// CHECK-NOT: simulation.spawn @second
// CHECK: simulation.func private @reader({{.*}}, %[[S:.*]]: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
// CHECK: simulation.ref.load %[[S]]
// CHECK: simulation.suspend.change %[[S]]
// CHECK-NOT: simulation.func private @first
// CHECK-NOT: simulation.func private @second
module {
  simulation.design @chain {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "first"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "second"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 5 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.net.decl 1 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.driver.decl 1 in 0 drives 1 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %y = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %z = simulation.context.net %ctx[1] : !simulation.net<!simulation.logic<4>>
      %d0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %d1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @first(%ctx, %s, %d0) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @second(%ctx, %y, %d1) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @reader(%ctx, %z, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p3 = simulation.spawn @writer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      simulation.return
    }
    simulation.func private @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.driver.drive %drv = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %src : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.driver.drive %drv = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
      simulation.suspend.change %src to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// A net item carries its handle for strength formats (21.2.1.5). Without one,
// the item prints the forwarded value: the handle and the net flag go.
// CHECK-LABEL: simulation.design @display
// CHECK: simulation.func private @reader({{.*}}, %[[S:.*]]: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
// CHECK: %[[V:.*]] = simulation.ref.load %[[S]]
// CHECK: simulation.display %{{.*}} to %{{.*}}(%{{.*}}, %[[V]]) newline = true radix = <binary> flags = [0, 0] : !simulation.bytes, !simulation.logic<4>{{$}}
module {
  simulation.design @display {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 initial hierarchy "reader"
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
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %fd = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "y=%b"
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
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

// A port reflection (for extended VCD) and the identity of a net collapsed
// onto this one name the net only for VPI and waveform dumps, which are absent.
// CHECK-LABEL: simulation.design @reflected
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader({{.*}}, %[[S:.*]]: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
// CHECK: simulation.ref.load %[[S]]
module {
  simulation.design @reflected {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.port.decl 0 in 0 source 0 net = true at 0 : !simulation.logic<4> input ordinal 0 hierarchy "top.y"
    simulation.vpi_net_identity.decl 0 backed_by 0 in 0 : !simulation.logic<4> hierarchy "top.inner.y" debug "y" {vpi_type = #simulation.vpi_type<kind = logic, isSigned = false, isFourState = true, range = [3, 0], children = [], childNames = []>}
    simulation.vpi_relation.decl <kind = net_identity, id = 0 : i64> selector 126 handle ordinal 0 to <kind = net, id = 0 : i64>
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}

// -----

// `s = 0; #1 s = 5;`: a delay always ends the activation (9.4.1), so each
// store publishes on its own activation.
// CHECK-LABEL: simulation.design @delayed_stores
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK-NOT: simulation.func private @copy
module {
  simulation.design @delayed_stores {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 always hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %delay = simulation.time.constant 1
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      simulation.ref.store %zero to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      %again = simulation.time.constant 1
      simulation.suspend.delay %again to ^set
    ^set:
      simulation.ref.store %five to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      cf.br ^wait
    }
  }
}

// -----

// One nonblocking write per activation publishes once per step (10.4.2).
// CHECK-LABEL: simulation.design @nonblocking_writer
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK-NOT: simulation.func private @copy
module {
  simulation.design @nonblocking_writer {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 always hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %delay = simulation.time.constant 1
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      simulation.nba.enqueue %five to %out : (!simulation.logic<4>, !simulation.ref<!simulation.logic<4>>) -> ()
      cf.br ^wait
    }
  }
}

// -----

// `if (c) s = 0; else s = 5;`: the stores never share an activation.
// CHECK-LABEL: simulation.design @exclusive_stores
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader
// CHECK-NOT: simulation.func private @copy
module {
  simulation.design @exclusive_stores {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "reader"
    simulation.code_unit.decl 4 in 0 always hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.storage.decl 2 in 0 : !simulation.logic<1> design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %sel = simulation.context.storage %ctx[2] : !simulation.ref<!simulation.logic<1>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
      %p2 = simulation.spawn @writer(%ctx, %s, %sel) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.ref<!simulation.logic<1>> -> !simulation.process
      simulation.return
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %drv: !simulation.driver<!simulation.logic<4>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %src : !simulation.ref<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.driver.drive %drv = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
      simulation.suspend.change %src to ^body : !simulation.ref<!simulation.logic<4>>
    }
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.suspend.change %in to ^body : !simulation.net<!simulation.logic<4>>
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !simulation.ref<!simulation.logic<1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      %zero = simulation.logic.constant 0 : i4, 0 : i4 : !simulation.logic<4>
      %five = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      %delay = simulation.time.constant 1
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      %c = simulation.ref.load %sel : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %b = simulation.logic.is_true %c : !simulation.logic<1>
      cf.cond_br %b, ^zero, ^five
    ^zero:
      simulation.ref.store %zero to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      cf.br ^wait
    ^five:
      simulation.ref.store %five to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      cf.br ^wait
    }
  }
}

// -----

// A program reader of an Active writer runs after every Active copy (4.5).
// CHECK-LABEL: simulation.design @program_reader
// CHECK-NOT: simulation.spawn @copy
// CHECK: simulation.func private @reader({{.*}}, %[[S:.*]]: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64})
// CHECK: simulation.ref.load %[[S]]
module {
  simulation.design @program_reader {
    simulation.scope.decl 0
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "copy"
    simulation.code_unit.decl 3 in 0 initial hierarchy "reader"
    simulation.code_unit.decl 4 in 0 initial hierarchy "writer"
    simulation.storage.decl 0 in 0 : !simulation.logic<4> design
    simulation.storage.decl 1 in 0 : !simulation.logic<4> design
    simulation.net.decl 0 in 0 : !simulation.logic<4> design
    simulation.driver.decl 0 in 0 drives 0 : !simulation.logic<4> design {driven_low = 0 : i64, driven_width = 4 : i64}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
      %d = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<4>>
      %n = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<4>>
      %drv = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.logic<4>>
      %p0 = simulation.spawn @copy(%ctx, %s, %drv) : !simulation.context, !simulation.ref<!simulation.logic<4>>, !simulation.driver<!simulation.logic<4>> -> !simulation.process
      %p1 = simulation.spawn @reader(%ctx, %n, %d) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.ref<!simulation.logic<4>> -> !simulation.process
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
    simulation.func private @reader(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64, domain = 1 : i32, home_region = 10 : i32} {
      %v = simulation.net.read %in : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
      simulation.ref.store %v to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %out: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
      simulation.ref.store %c to %out : !simulation.logic<4>, !simulation.ref<!simulation.logic<4>>
      simulation.return
    }
  }
}
