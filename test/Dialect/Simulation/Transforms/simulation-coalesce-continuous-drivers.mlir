// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-coalesce-continuous-drivers{vpi=off},simulation.func(canonicalize)))' | FileCheck %s
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-coalesce-continuous-drivers{vpi=full},simulation.func(canonicalize)))' | FileCheck %s --check-prefix=FULL

// Two generate-loop assignments `o[i] = |{d[1][i], d[0][i]}` (IEEE 1800-2023
// 27.4, 10.3.2) drive the two bits of `o`. They become one process with one
// driver of both bits (6.6.1: one strong contribution per bit). The lanes
// transpose into word operations: `o = d[0] | d[1]` (11.4.9).
// CHECK-LABEL: simulation.design @or_lanes
// CHECK: simulation.driver.decl 0 in 0 drives 1 : !simulation.packed_array<1 : 0 x i1> design {driven_low = 0 : i64, driven_width = 2 : i64}
// CHECK-NOT: simulation.driver.decl
// CHECK: simulation.func @root
// CHECK: simulation.spawn @bit0.coalesced(
// CHECK-NOT: simulation.spawn
// CHECK-LABEL: simulation.func private @bit0.coalesced(
// CHECK-SAME: %[[D:[^:]*]]: !simulation.net<!simulation.packed_array<3 : 0 x i1>>
// CHECK-SAME: %[[O:[^:]*]]: !simulation.driver<!simulation.packed_array<1 : 0 x i1>>
// CHECK-NOT: arith.extui
// CHECK: %[[LOV:.*]] = simulation.net.extract %[[D]] from 0 : {{.*}} -> !simulation.net<i2>
// CHECK: %[[LO:.*]] = simulation.net.read %[[LOV]]
// CHECK: %[[HIV:.*]] = simulation.net.extract %[[D]] from 2 : {{.*}} -> !simulation.net<i2>
// CHECK: %[[HI:.*]] = simulation.net.read %[[HIV]]
// CHECK: %[[OR:.*]] = arith.ori %[[LO]], %[[HI]] : i2
// CHECK: %[[OV:.*]] = simulation.driver.extract %[[O]] from 0 : {{.*}} -> !simulation.driver<i2>
// CHECK: simulation.driver.drive %[[OV]] = %[[OR]] : !simulation.driver<i2>, i2
// CHECK: simulation.suspend.any %[[D]] edges [0] to
// CHECK-NOT: simulation.func private @bit1
// FULL-LABEL: simulation.design @or_lanes
// FULL: simulation.spawn @bit0.coalesced(
// FULL-NOT: simulation.spawn
simulation.design @or_lanes {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.net.decl 0 in 0 : !simulation.packed_array<3 : 0 x i1> design
  simulation.net.decl 1 in 0 : !simulation.packed_array<1 : 0 x i1> design
  simulation.driver.decl 0 in 0 drives 1 : !simulation.packed_array<1 : 0 x i1> design {driven_low = 0 : i64, driven_width = 1 : i64}
  simulation.driver.decl 1 in 0 drives 1 : !simulation.packed_array<1 : 0 x i1> design {driven_low = 1 : i64, driven_width = 1 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %d0 = simulation.context.net %ctx[0] : !simulation.net<!simulation.packed_array<3 : 0 x i1>>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<1 : 0 x i1>>
    %p0 = simulation.spawn @bit0(%ctx, %d0, %o0) : !simulation.context, !simulation.net<!simulation.packed_array<3 : 0 x i1>>, !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.process
    %d1 = simulation.context.net %ctx[0] : !simulation.net<!simulation.packed_array<3 : 0 x i1>>
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<1 : 0 x i1>>
    %p1 = simulation.spawn @bit1(%ctx, %d1, %o1) : !simulation.context, !simulation.net<!simulation.packed_array<3 : 0 x i1>>, !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !simulation.net<!simulation.packed_array<3 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^body
  ^body:
    %v0 = simulation.net.extract %d from 0 : !simulation.net<!simulation.packed_array<3 : 0 x i1>> -> !simulation.net<i1>
    %b0 = simulation.net.read %v0 : !simulation.net<i1> -> i1
    %v1 = simulation.net.extract %d from 2 : !simulation.net<!simulation.packed_array<3 : 0 x i1>> -> !simulation.net<i1>
    %b1 = simulation.net.read %v1 : !simulation.net<i1> -> i1
    %z0 = arith.extui %b0 : i1 to i2
    %z1 = arith.extui %b1 : i1 to i2
    %one = arith.constant 1 : i2
    %s1 = arith.shli %z1, %one : i2
    %g = arith.ori %s1, %z0 : i2
    %zero = arith.constant 0 : i2
    %r = arith.cmpi ne, %g, %zero : i2
    %t = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %t = %r : !simulation.driver<i1>, i1
    simulation.suspend.any %v0, %v1 edges [0, 0] to ^body : !simulation.net<i1>, !simulation.net<i1>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !simulation.net<!simulation.packed_array<3 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^body
  ^body:
    %v0 = simulation.net.extract %d from 1 : !simulation.net<!simulation.packed_array<3 : 0 x i1>> -> !simulation.net<i1>
    %b0 = simulation.net.read %v0 : !simulation.net<i1> -> i1
    %v1 = simulation.net.extract %d from 3 : !simulation.net<!simulation.packed_array<3 : 0 x i1>> -> !simulation.net<i1>
    %b1 = simulation.net.read %v1 : !simulation.net<i1> -> i1
    %z0 = arith.extui %b0 : i1 to i2
    %z1 = arith.extui %b1 : i1 to i2
    %one = arith.constant 1 : i2
    %s1 = arith.shli %z1, %one : i2
    %g = arith.ori %s1, %z0 : i2
    %zero = arith.constant 0 : i2
    %r = arith.cmpi ne, %g, %zero : i2
    %t = simulation.driver.extract %o from 1 : !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %t = %r : !simulation.driver<i1>, i1
    simulation.suspend.any %v0, %v1 edges [0, 0] to ^body : !simulation.net<i1>, !simulation.net<i1>
  }
}

// -----

// The same lanes in four-state: a reduction of a concatenation is the
// bitwise operation of its bits with the same X/Z tables (11.4.9, 11.4.8).
// CHECK-LABEL: simulation.design @or_lanes_logic
// FULL-LABEL: simulation.design @or_lanes_logic
// CHECK: simulation.func private @bit0.coalesced(
// CHECK-NOT: simulation.logic.reduction
// CHECK: %[[LO:.*]] = simulation.net.read {{.*}} -> !simulation.logic<2>
// CHECK: %[[HI:.*]] = simulation.net.read {{.*}} -> !simulation.logic<2>
// CHECK: %[[OR:.*]] = simulation.logic.binary or %[[LO]], %[[HI]] : !simulation.logic<2>
// CHECK: simulation.driver.drive %{{.*}} = %[[OR]] : !simulation.driver<!simulation.logic<2>>, !simulation.logic<2>
simulation.design @or_lanes_logic {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.net.decl 0 in 0 : !simulation.packed_array<3 : 0 x !simulation.logic<1>> design
  simulation.net.decl 1 in 0 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design
  simulation.driver.decl 0 in 0 drives 1 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design {driven_low = 0 : i64, driven_width = 1 : i64}
  simulation.driver.decl 1 in 0 drives 1 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design {driven_low = 1 : i64, driven_width = 1 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %d = simulation.context.net %ctx[0] : !simulation.net<!simulation.packed_array<3 : 0 x !simulation.logic<1>>>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %p0 = simulation.spawn @bit0(%ctx, %d, %o0) : !simulation.context, !simulation.net<!simulation.packed_array<3 : 0 x !simulation.logic<1>>>, !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.process
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %p1 = simulation.spawn @bit1(%ctx, %d, %o1) : !simulation.context, !simulation.net<!simulation.packed_array<3 : 0 x !simulation.logic<1>>>, !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !simulation.net<!simulation.packed_array<3 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^body
  ^body:
    %v0 = simulation.net.extract %d from 0 : !simulation.net<!simulation.packed_array<3 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %b0 = simulation.net.read %v0 : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    %v1 = simulation.net.extract %d from 2 : !simulation.net<!simulation.packed_array<3 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %b1 = simulation.net.read %v1 : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    %g = simulation.logic.concat %b1, %b0 : (!simulation.logic<1>, !simulation.logic<1>) -> !simulation.logic<2>
    %r = simulation.logic.reduction or %g : !simulation.logic<2> -> !simulation.logic<1>
    %t = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.driver<!simulation.logic<1>>
    simulation.driver.drive %t = %r : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
    simulation.suspend.any %v0, %v1 edges [0, 0] to ^body : !simulation.net<!simulation.logic<1>>, !simulation.net<!simulation.logic<1>>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !simulation.net<!simulation.packed_array<3 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^body
  ^body:
    %v0 = simulation.net.extract %d from 1 : !simulation.net<!simulation.packed_array<3 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %b0 = simulation.net.read %v0 : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    %v1 = simulation.net.extract %d from 3 : !simulation.net<!simulation.packed_array<3 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %b1 = simulation.net.read %v1 : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    %g = simulation.logic.concat %b1, %b0 : (!simulation.logic<1>, !simulation.logic<1>) -> !simulation.logic<2>
    %r = simulation.logic.reduction or %g : !simulation.logic<2> -> !simulation.logic<1>
    %t = simulation.driver.extract %o from 1 : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.driver<!simulation.logic<1>>
    simulation.driver.drive %t = %r : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
    simulation.suspend.any %v0, %v1 edges [0, 0] to ^body : !simulation.net<!simulation.logic<1>>, !simulation.net<!simulation.logic<1>>
  }
}

// -----

// Row t[1] = t[0] ^ y reads the row another member drives. Running the
// members back to back is an allowed Active order (4.7), so the merged
// process uses row 0's value and does not wait on its own net. A deposit
// (38.34) or force (10.6.2) on row 0 would be visible to row 1, so with VPI
// mutation the reader keeps its process and nothing merges.
// CHECK-LABEL: simulation.design @rows
// CHECK: simulation.func private @row0.coalesced(
// CHECK-SAME: %[[X:[^:]*]]: !simulation.net<i4>
// CHECK-SAME: %[[Y:[^:]*]]: !simulation.net<i4>
// CHECK: %[[XV:.*]] = simulation.net.read %[[X]]
// CHECK: %[[YV:.*]] = simulation.net.read %[[Y]]
// CHECK: arith.xori %[[XV]], %[[YV]] : i4
// CHECK: simulation.driver.drive %{{.*}} : !simulation.driver<i8>, i8
// CHECK: simulation.suspend.any %[[X]], %[[Y]] edges [0, 0] to
// FULL-LABEL: simulation.design @rows
// FULL-DAG: simulation.spawn @row0(
// FULL-DAG: simulation.spawn @row1(
// FULL-NOT: coalesced
simulation.design @rows {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "row0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "row1"
  simulation.net.decl 0 in 0 : !simulation.packed_array<7 : 0 x i1> design
  simulation.net.decl 1 in 0 : i4 design
  simulation.net.decl 2 in 0 : i4 design
  simulation.driver.decl 0 in 0 drives 0 : !simulation.packed_array<7 : 0 x i1> design {driven_low = 0 : i64, driven_width = 4 : i64}
  simulation.driver.decl 1 in 0 drives 0 : !simulation.packed_array<7 : 0 x i1> design {driven_low = 4 : i64, driven_width = 4 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %t = simulation.context.net %ctx[0] : !simulation.net<!simulation.packed_array<7 : 0 x i1>>
    %x = simulation.context.net %ctx[1] : !simulation.net<i4>
    %y = simulation.context.net %ctx[2] : !simulation.net<i4>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<7 : 0 x i1>>
    %p0 = simulation.spawn @row0(%ctx, %x, %o0) : !simulation.context, !simulation.net<i4>, !simulation.driver<!simulation.packed_array<7 : 0 x i1>> -> !simulation.process
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<7 : 0 x i1>>
    %p1 = simulation.spawn @row1(%ctx, %t, %y, %o1) : !simulation.context, !simulation.net<!simulation.packed_array<7 : 0 x i1>>, !simulation.net<i4>, !simulation.driver<!simulation.packed_array<7 : 0 x i1>> -> !simulation.process
    simulation.return
  }
  simulation.func private @row0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: !simulation.net<i4> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %o: !simulation.driver<!simulation.packed_array<7 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.read %x : !simulation.net<i4> -> i4
    %d = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<7 : 0 x i1>> -> !simulation.driver<i4>
    simulation.driver.drive %d = %v : !simulation.driver<i4>, i4
    simulation.suspend.change %x to ^body : !simulation.net<i4>
  }
  simulation.func private @row1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %t: !simulation.net<!simulation.packed_array<7 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %y: !simulation.net<i4> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}, %o: !simulation.driver<!simulation.packed_array<7 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^body
  ^body:
    %r0 = simulation.net.extract %t from 0 : !simulation.net<!simulation.packed_array<7 : 0 x i1>> -> !simulation.net<i4>
    %a = simulation.net.read %r0 : !simulation.net<i4> -> i4
    %b = simulation.net.read %y : !simulation.net<i4> -> i4
    %v = arith.xori %a, %b : i4
    %d = simulation.driver.extract %o from 4 : !simulation.driver<!simulation.packed_array<7 : 0 x i1>> -> !simulation.driver<i4>
    simulation.driver.drive %d = %v : !simulation.driver<i4>, i4
    simulation.suspend.any %r0, %y edges [0, 0] to ^body : !simulation.net<i4>, !simulation.net<i4>
  }
}

// -----

// A driver with another handle (a power-domain monitor that corrupts the
// contribution, IEEE 1801-2018 9.5.3) keeps its process. The two remaining
// adjacent drivers merge, and driver IDs stay dense: driver 3 becomes 2.
// CHECK-LABEL: simulation.design @handles
// FULL-LABEL: simulation.design @handles
// FULL: simulation.spawn @bit1.coalesced(
// CHECK: simulation.driver.decl 0 in 0 drives 0 : {{.*}} {driven_low = 0 : i64, driven_width = 1 : i64}
// CHECK: simulation.driver.decl 1 in 0 drives 0 : {{.*}} {driven_low = 1 : i64, driven_width = 2 : i64}
// CHECK: simulation.driver.decl 2 in 0 drives 1 :
// CHECK-NOT: simulation.driver.decl
// CHECK: simulation.func @root
// CHECK-DAG: simulation.spawn @bit0(
// CHECK-DAG: simulation.spawn @bit1.coalesced(
// CHECK-DAG: %[[OTHER:.*]] = simulation.context.driver %{{.*}}[2] : !simulation.driver<i1>
// CHECK-DAG: simulation.spawn @other(%{{.*}}, %[[OTHER]])
// CHECK: simulation.func private @bit1.coalesced(
// CHECK: simulation.driver.extract %{{.*}} from 1 : {{.*}} -> !simulation.driver<i2>
// CHECK: simulation.func private @other({{.*}}: !simulation.driver<i1> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 2 : i64})
// CHECK: simulation.func private @monitor
// CHECK: simulation.context.driver %{{.*}}[0]
simulation.design @handles {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.code_unit.decl 4 in 0 continuous hierarchy "bit2"
  simulation.code_unit.decl 5 in 0 continuous hierarchy "other"
  simulation.code_unit.decl 6 in 0 always hierarchy "monitor"
  simulation.net.decl 0 in 0 : !simulation.packed_array<2 : 0 x i1> design
  simulation.net.decl 1 in 0 : i1 design
  simulation.net.decl 2 in 0 : i1 design
  simulation.driver.decl 0 in 0 drives 0 : !simulation.packed_array<2 : 0 x i1> design {driven_low = 0 : i64, driven_width = 1 : i64}
  simulation.driver.decl 1 in 0 drives 0 : !simulation.packed_array<2 : 0 x i1> design {driven_low = 1 : i64, driven_width = 1 : i64}
  simulation.driver.decl 2 in 0 drives 0 : !simulation.packed_array<2 : 0 x i1> design {driven_low = 2 : i64, driven_width = 1 : i64}
  simulation.driver.decl 3 in 0 drives 1 : i1 design {driven_low = 0 : i64, driven_width = 1 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %a = simulation.context.net %ctx[2] : !simulation.net<i1>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<2 : 0 x i1>>
    %p0 = simulation.spawn @bit0(%ctx, %a, %o0) : !simulation.context, !simulation.net<i1>, !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.process
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<2 : 0 x i1>>
    %p1 = simulation.spawn @bit1(%ctx, %a, %o1) : !simulation.context, !simulation.net<i1>, !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.process
    %o2 = simulation.context.driver %ctx[2] : !simulation.driver<!simulation.packed_array<2 : 0 x i1>>
    %p2 = simulation.spawn @bit2(%ctx, %a, %o2) : !simulation.context, !simulation.net<i1>, !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.process
    %o3 = simulation.context.driver %ctx[3] : !simulation.driver<i1>
    %p3 = simulation.spawn @other(%ctx, %a, %o3) : !simulation.context, !simulation.net<i1>, !simulation.driver<i1> -> !simulation.process
    %p4 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}, %o: !simulation.driver<!simulation.packed_array<2 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.read %a : !simulation.net<i1> -> i1
    %d = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %d = %v : !simulation.driver<i1>, i1
    simulation.suspend.change %a to ^body : !simulation.net<i1>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}, %o: !simulation.driver<!simulation.packed_array<2 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.read %a : !simulation.net<i1> -> i1
    %d = simulation.driver.extract %o from 1 : !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %d = %v : !simulation.driver<i1>, i1
    simulation.suspend.change %a to ^body : !simulation.net<i1>
  }
  simulation.func private @bit2(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}, %o: !simulation.driver<!simulation.packed_array<2 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.read %a : !simulation.net<i1> -> i1
    %n = arith.constant true
    %w = arith.xori %v, %n : i1
    %d = simulation.driver.extract %o from 2 : !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %d = %w : !simulation.driver<i1>, i1
    simulation.suspend.change %a to ^body : !simulation.net<i1>
  }
  simulation.func private @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}, %o: !simulation.driver<i1> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.read %a : !simulation.net<i1> -> i1
    simulation.driver.drive %o = %v : !simulation.driver<i1>, i1
    simulation.suspend.change %a to ^body : !simulation.net<i1>
  }
  simulation.func private @monitor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 3 : i32, code_unit_id = 6 : i64} {
    %o = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<2 : 0 x i1>>
    %f = arith.constant false
    %d = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %d = %f : !simulation.driver<i1>, i1
    simulation.return
  }
}

// -----

// `o` is port-collapsed with the parent's `p` (IEEE 1800-2023 23.3.3.7);
// each bit still has one contribution in the collapsed net, so bits 0 and 1
// merge. Bit 2 reads `p`, a collapsed alias of bits the run drives, which
// the forwarding does not track by net, so it keeps its own process.
// CHECK-LABEL: simulation.design @collapsed
// CHECK: simulation.driver.decl 0 in 0 drives 1 : {{.*}} {driven_low = 0 : i64, driven_width = 2 : i64}
// CHECK: simulation.driver.decl 1 in 0 drives 1 : {{.*}} {driven_low = 2 : i64, driven_width = 1 : i64}
// CHECK-NOT: simulation.driver.decl
// CHECK-DAG: simulation.spawn @bit0.coalesced(
// CHECK-DAG: simulation.spawn @bit2(
// FULL-LABEL: simulation.design @collapsed
// FULL: simulation.spawn @bit0.coalesced(
simulation.design @collapsed {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.code_unit.decl 4 in 0 continuous hierarchy "bit2"
  simulation.net.decl 0 in 0 : i1 design
  simulation.net.decl 1 in 0 : !simulation.packed_array<2 : 0 x i1> design
  simulation.net.decl 2 in 0 : !simulation.packed_array<2 : 0 x i1> design
  simulation.net.connect.decl 0 in 0 1[0] to 2[0] width 3 reversed = false rhs_dominates = true
  simulation.driver.decl 0 in 0 drives 1 : !simulation.packed_array<2 : 0 x i1> design {driven_low = 0 : i64, driven_width = 1 : i64}
  simulation.driver.decl 1 in 0 drives 1 : !simulation.packed_array<2 : 0 x i1> design {driven_low = 1 : i64, driven_width = 1 : i64}
  simulation.driver.decl 2 in 0 drives 1 : !simulation.packed_array<2 : 0 x i1> design {driven_low = 2 : i64, driven_width = 1 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %a = simulation.context.net %ctx[0] : !simulation.net<i1>
    %p = simulation.context.net %ctx[2] : !simulation.net<!simulation.packed_array<2 : 0 x i1>>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<2 : 0 x i1>>
    %p0 = simulation.spawn @bit0(%ctx, %a, %o0) : !simulation.context, !simulation.net<i1>, !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.process
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<2 : 0 x i1>>
    %p1 = simulation.spawn @bit1(%ctx, %a, %o1) : !simulation.context, !simulation.net<i1>, !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.process
    %o2 = simulation.context.driver %ctx[2] : !simulation.driver<!simulation.packed_array<2 : 0 x i1>>
    %p2 = simulation.spawn @bit2(%ctx, %p, %o2) : !simulation.context, !simulation.net<!simulation.packed_array<2 : 0 x i1>>, !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %o: !simulation.driver<!simulation.packed_array<2 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.read %a : !simulation.net<i1> -> i1
    %d = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %d = %v : !simulation.driver<i1>, i1
    simulation.suspend.change %a to ^body : !simulation.net<i1>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %o: !simulation.driver<!simulation.packed_array<2 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.read %a : !simulation.net<i1> -> i1
    %n = arith.constant true
    %w = arith.xori %v, %n : i1
    %d = simulation.driver.extract %o from 1 : !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %d = %w : !simulation.driver<i1>, i1
    simulation.suspend.change %a to ^body : !simulation.net<i1>
  }
  simulation.func private @bit2(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %p: !simulation.net<!simulation.packed_array<2 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}, %o: !simulation.driver<!simulation.packed_array<2 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
    cf.br ^body
  ^body:
    %r = simulation.net.extract %p from 0 : !simulation.net<!simulation.packed_array<2 : 0 x i1>> -> !simulation.net<i1>
    %v = simulation.net.read %r : !simulation.net<i1> -> i1
    %d = simulation.driver.extract %o from 2 : !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %d = %v : !simulation.driver<i1>, i1
    simulation.suspend.change %r to ^body : !simulation.net<i1>
  }
}

// -----

// Argument bindings name arguments by index. The merged process drops bit0's
// dead capture %u, so its bindings move down by one, bit1's read of %e is a
// new capture, and bindings of uncaptured arguments (%u, bit1's driver) go.
// bit1 reads net 1 through its own handle, which merges into bit0's capture:
// its binding of that argument (under another path) would bind it twice and
// is dropped, as is its second provider of the shared constant `top.w`.
// CHECK-LABEL: simulation.design @bindings
// CHECK: simulation.func private @bit0.coalesced(%{{[^:]*}}: !simulation.context {{[^%]*}}, %{{[^:]*}}: !simulation.net<i1> {{[^%]*}}, %{{[^:]*}}: !simulation.driver<!simulation.packed_array<1 : 0 x i1>> {{[^%]*}}, %{{[^:]*}}: !simulation.net<i1> {{[^%]*}})
// CHECK-SAME: simulation.bindings = [#simulation.argument_binding<path = "top.d", argument = 1, kind = direct, copyOut = false>, #simulation.argument_binding<path = "top.o", argument = 2, kind = lvalue_only, copyOut = false>, #simulation.constant_binding<path = "top.w", {{.*}} : !simulation.logic<32>>, #simulation.argument_binding<path = "top.e", argument = 3, kind = direct, copyOut = false>]
simulation.design @bindings {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.net.decl 0 in 0 : i1 design
  simulation.net.decl 1 in 0 : i1 design
  simulation.net.decl 2 in 0 : i1 design
  simulation.net.decl 3 in 0 : !simulation.packed_array<1 : 0 x i1> design
  simulation.driver.decl 0 in 0 drives 3 : !simulation.packed_array<1 : 0 x i1> design {driven_low = 0 : i64, driven_width = 1 : i64}
  simulation.driver.decl 1 in 0 drives 3 : !simulation.packed_array<1 : 0 x i1> design {driven_low = 1 : i64, driven_width = 1 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %u = simulation.context.net %ctx[0] : !simulation.net<i1>
    %d = simulation.context.net %ctx[1] : !simulation.net<i1>
    %e = simulation.context.net %ctx[2] : !simulation.net<i1>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<1 : 0 x i1>>
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<1 : 0 x i1>>
    %p0 = simulation.spawn @bit0(%ctx, %u, %d, %o0) : !simulation.context, !simulation.net<i1>, !simulation.net<i1>, !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.process
    %d1 = simulation.context.net %ctx[1] : !simulation.net<i1>
    %p1 = simulation.spawn @bit1(%ctx, %d1, %e, %o1) : !simulation.context, !simulation.net<i1>, !simulation.net<i1>, !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %u: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %d: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64, simulation.bindings = [#simulation.argument_binding<path = "top.u", argument = 1, kind = direct, copyOut = false>, #simulation.argument_binding<path = "top.d", argument = 2, kind = direct, copyOut = false>, #simulation.argument_binding<path = "top.o", argument = 3, kind = lvalue_only, copyOut = false>, #simulation.constant_binding<path = "top.w", value = #simulation.frozen_constant<value = [8 : i32, 0 : i32], isSigned = true> : !simulation.logic<32>>]} {
    cf.br ^body
  ^body:
    %b = simulation.net.read %d : !simulation.net<i1> -> i1
    %t = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %t = %b : !simulation.driver<i1>, i1
    simulation.suspend.any %d edges [0] to ^body : !simulation.net<i1>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %e: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64, simulation.bindings = [#simulation.argument_binding<path = "top.d_alias", argument = 1, kind = direct, copyOut = false>, #simulation.argument_binding<path = "top.e", argument = 2, kind = direct, copyOut = false>, #simulation.argument_binding<path = "top.o", argument = 3, kind = lvalue_only, copyOut = false>, #simulation.constant_binding<path = "top.w", value = #simulation.frozen_constant<value = [8 : i32, 0 : i32], isSigned = true> : !simulation.logic<32>>]} {
    cf.br ^body
  ^body:
    %a = simulation.net.read %d : !simulation.net<i1> -> i1
    %c = simulation.net.read %e : !simulation.net<i1> -> i1
    %b = arith.andi %a, %c : i1
    %t = simulation.driver.extract %o from 1 : !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %t = %b : !simulation.driver<i1>, i1
    simulation.suspend.any %d, %e edges [0, 0] to ^body : !simulation.net<i1>, !simulation.net<i1>
  }
}
