// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-coalesce-continuous-drivers{vpi=off},simulation.func(canonicalize)))' | FileCheck %s

// Two-state lane rules (IEEE 1800-2023 11.4.8, 11.4.9): `o[i] = (d[i] & s) ^
// c[i]` with a shared select bit and per-lane constants becomes one word
// expression: contiguous reads of d, the select bit sign-extended to a
// word (11.4.12.1), and the constant lanes as one constant.
// CHECK-LABEL: simulation.design @bitwise
// CHECK: simulation.func private @bit0.coalesced(
// CHECK-SAME: %[[D:[^:]*]]: !simulation.net<!simulation.packed_array<1 : 0 x i1>>
// CHECK-SAME: %[[S:[^:]*]]: !simulation.net<i1>
// CHECK-DAG: %[[SV:.*]] = simulation.net.read %[[S]]
// CHECK-DAG: %[[DV:.*]] = simulation.net.read {{.*}} -> i2
// CHECK-DAG: %[[SW:.*]] = arith.extsi %[[SV]] : i1 to i2
// CHECK: %[[AND:.*]] = arith.andi %[[DV]], %[[SW]] : i2
// CHECK: %[[X:.*]] = arith.xori %[[AND]], %{{.*}} : i2
// CHECK: simulation.driver.drive %{{.*}} = %[[X]] : !simulation.driver<i2>, i2
simulation.design @bitwise {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.net.decl 0 in 0 : !simulation.packed_array<1 : 0 x i1> design
  simulation.net.decl 1 in 0 : i1 design
  simulation.net.decl 2 in 0 : !simulation.packed_array<1 : 0 x i1> design
  simulation.driver.decl 0 in 0 drives 2 : !simulation.packed_array<1 : 0 x i1> design {driven_low = 0 : i64, driven_width = 1 : i64}
  simulation.driver.decl 1 in 0 drives 2 : !simulation.packed_array<1 : 0 x i1> design {driven_low = 1 : i64, driven_width = 1 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %d = simulation.context.net %ctx[0] : !simulation.net<!simulation.packed_array<1 : 0 x i1>>
    %s = simulation.context.net %ctx[1] : !simulation.net<i1>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<1 : 0 x i1>>
    %p0 = simulation.spawn @bit0(%ctx, %d, %s, %o0) : !simulation.context, !simulation.net<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<i1>, !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.process
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<1 : 0 x i1>>
    %p1 = simulation.spawn @bit1(%ctx, %d, %s, %o1) : !simulation.context, !simulation.net<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<i1>, !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !simulation.net<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %s: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.extract %d from 0 : !simulation.net<!simulation.packed_array<1 : 0 x i1>> -> !simulation.net<i1>
    %b = simulation.net.read %v : !simulation.net<i1> -> i1
    %sv = simulation.net.read %s : !simulation.net<i1> -> i1
    %a = arith.andi %b, %sv : i1
    %c = arith.constant true
    %x = arith.xori %a, %c : i1
    %t = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %t = %x : !simulation.driver<i1>, i1
    simulation.suspend.any %v, %s edges [0, 0] to ^body : !simulation.net<i1>, !simulation.net<i1>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !simulation.net<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %s: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.extract %d from 1 : !simulation.net<!simulation.packed_array<1 : 0 x i1>> -> !simulation.net<i1>
    %b = simulation.net.read %v : !simulation.net<i1> -> i1
    %sv = simulation.net.read %s : !simulation.net<i1> -> i1
    %a = arith.andi %sv, %b : i1
    %c = arith.constant false
    %x = arith.xori %a, %c : i1
    %t = simulation.driver.extract %o from 1 : !simulation.driver<!simulation.packed_array<1 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %t = %x : !simulation.driver<i1>, i1
    simulation.suspend.any %v, %s edges [0, 0] to ^body : !simulation.net<i1>, !simulation.net<i1>
  }
}

// -----

// Four-state lane rules: `o[i] = ~(x[i] ~^ y[i])` with x one read value and
// y read per bit becomes a word extract, read, xnor and not, preserving X/Z
// per bit (11.4.8 Tables 11-14 and 11-15).
// CHECK-LABEL: simulation.design @logic_lanes
// CHECK: simulation.func private @bit0.coalesced(
// CHECK: %[[XV:.*]] = simulation.net.read %{{.*}} -> !simulation.logic<2>
// CHECK: %[[YV:.*]] = simulation.net.read %{{.*}} -> !simulation.logic<2>
// CHECK: %[[XN:.*]] = simulation.logic.binary xnor %[[XV]], %[[YV]] : !simulation.logic<2>
// CHECK: %[[N:.*]] = simulation.logic.unary bit_not %[[XN]] : (!simulation.logic<2>) -> !simulation.logic<2>
// CHECK: simulation.driver.drive %{{.*}} = %[[N]] : !simulation.driver<!simulation.logic<2>>, !simulation.logic<2>
simulation.design @logic_lanes {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.net.decl 0 in 0 : !simulation.logic<2> design
  simulation.net.decl 1 in 0 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design
  simulation.net.decl 2 in 0 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design
  simulation.driver.decl 0 in 0 drives 2 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design {driven_low = 0 : i64, driven_width = 1 : i64}
  simulation.driver.decl 1 in 0 drives 2 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design {driven_low = 1 : i64, driven_width = 1 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %x = simulation.context.net %ctx[0] : !simulation.net<!simulation.logic<2>>
    %y = simulation.context.net %ctx[1] : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %p0 = simulation.spawn @bit0(%ctx, %x, %y, %o0) : !simulation.context, !simulation.net<!simulation.logic<2>>, !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>, !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.process
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %p1 = simulation.spawn @bit1(%ctx, %x, %y, %o1) : !simulation.context, !simulation.net<!simulation.logic<2>>, !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>, !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: !simulation.net<!simulation.logic<2>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %y: !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^body
  ^body:
    %xv = simulation.net.read %x : !simulation.net<!simulation.logic<2>> -> !simulation.logic<2>
    %xb = simulation.logic.extract %xv from 0 : !simulation.logic<2> -> !simulation.logic<1>
    %yv = simulation.net.extract %y from 0 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %yb = simulation.net.read %yv : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    %e = simulation.logic.binary xnor %xb, %yb : !simulation.logic<1>
    %n = simulation.logic.unary bit_not %e : (!simulation.logic<1>) -> !simulation.logic<1>
    %t = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.driver<!simulation.logic<1>>
    simulation.driver.drive %t = %n : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
    simulation.suspend.any %x, %yv edges [0, 0] to ^body : !simulation.net<!simulation.logic<2>>, !simulation.net<!simulation.logic<1>>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: !simulation.net<!simulation.logic<2>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %y: !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^body
  ^body:
    %xv = simulation.net.read %x : !simulation.net<!simulation.logic<2>> -> !simulation.logic<2>
    %xb = simulation.logic.extract %xv from 1 : !simulation.logic<2> -> !simulation.logic<1>
    %yv = simulation.net.extract %y from 1 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %yb = simulation.net.read %yv : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    %e = simulation.logic.binary xnor %xb, %yb : !simulation.logic<1>
    %n = simulation.logic.unary bit_not %e : (!simulation.logic<1>) -> !simulation.logic<1>
    %t = simulation.driver.extract %o from 1 : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.driver<!simulation.logic<1>>
    simulation.driver.drive %t = %n : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
    simulation.suspend.any %x, %yv edges [0, 0] to ^body : !simulation.net<!simulation.logic<2>>, !simulation.net<!simulation.logic<1>>
  }
}

// -----

// A reduction of a single four-state bit turns z into x (11.4.9), which the
// bit alone would not, so these lanes merge but stay scalar.
// CHECK-LABEL: simulation.design @single_bit_reduction
// CHECK: simulation.func private @bit0.coalesced(
// CHECK: simulation.logic.reduction or
// CHECK: simulation.logic.reduction or
// CHECK: simulation.logic.concat
// CHECK: simulation.driver.drive
simulation.design @single_bit_reduction {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.net.decl 0 in 0 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design
  simulation.net.decl 1 in 0 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design
  simulation.driver.decl 0 in 0 drives 1 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design {driven_low = 0 : i64, driven_width = 1 : i64}
  simulation.driver.decl 1 in 0 drives 1 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design {driven_low = 1 : i64, driven_width = 1 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %d = simulation.context.net %ctx[0] : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %p0 = simulation.spawn @bit0(%ctx, %d, %o0) : !simulation.context, !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>, !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.process
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %p1 = simulation.spawn @bit1(%ctx, %d, %o1) : !simulation.context, !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>, !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.extract %d from 0 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %b = simulation.net.read %v : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    %g = simulation.logic.concat %b : (!simulation.logic<1>) -> !simulation.logic<1>
    %r = simulation.logic.reduction or %g : !simulation.logic<1> -> !simulation.logic<1>
    %t = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.driver<!simulation.logic<1>>
    simulation.driver.drive %t = %r : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
    simulation.suspend.change %v to ^body : !simulation.net<!simulation.logic<1>>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %o: !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.extract %d from 1 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %b = simulation.net.read %v : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    %g = simulation.logic.concat %b : (!simulation.logic<1>) -> !simulation.logic<1>
    %r = simulation.logic.reduction or %g : !simulation.logic<1> -> !simulation.logic<1>
    %t = simulation.driver.extract %o from 1 : !simulation.driver<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.driver<!simulation.logic<1>>
    simulation.driver.drive %t = %r : !simulation.driver<!simulation.logic<1>>, !simulation.logic<1>
    simulation.suspend.change %v to ^body : !simulation.net<!simulation.logic<1>>
  }
}

// -----

// `flat[4*i +: 4] = arr[i]` reads elements of an unpacked array, whose
// slices count padded storage bits: the merged process keeps the original
// whole-array watch and element reads instead of packed views of the array.
// CHECK-LABEL: simulation.design @unpacked_source
// CHECK: simulation.func private @row0.coalesced(
// CHECK-SAME: %[[ARR:[^:]*]]: !simulation.ref<!simulation.unpacked_array
// CHECK-NOT: simulation.ref.extract
// CHECK: simulation.ref.subelement %[[ARR]]{{\[\[}}0]]
// CHECK: simulation.ref.subelement %[[ARR]]{{\[\[}}1]]
// CHECK: simulation.suspend.any %[[ARR]] edges [0] to
simulation.design @unpacked_source {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "row0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "row1"
  simulation.storage.decl 0 in 0 : !simulation.unpacked_array<0 : 1 x !simulation.packed_array<3 : 0 x !simulation.logic<1>>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>> design
  simulation.net.decl 0 in 0 : !simulation.packed_array<7 : 0 x !simulation.logic<1>> design
  simulation.driver.decl 0 in 0 drives 0 : !simulation.packed_array<7 : 0 x !simulation.logic<1>> design {driven_low = 0 : i64, driven_width = 4 : i64}
  simulation.driver.decl 1 in 0 drives 0 : !simulation.packed_array<7 : 0 x !simulation.logic<1>> design {driven_low = 4 : i64, driven_width = 4 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %a = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<3 : 0 x !simulation.logic<1>>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<7 : 0 x !simulation.logic<1>>>
    %p0 = simulation.spawn @row0(%ctx, %a, %o0) : !simulation.context, !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<3 : 0 x !simulation.logic<1>>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>, !simulation.driver<!simulation.packed_array<7 : 0 x !simulation.logic<1>>> -> !simulation.process
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<7 : 0 x !simulation.logic<1>>>
    %p1 = simulation.spawn @row1(%ctx, %a, %o1) : !simulation.context, !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<3 : 0 x !simulation.logic<1>>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>, !simulation.driver<!simulation.packed_array<7 : 0 x !simulation.logic<1>>> -> !simulation.process
    simulation.return
  }
  simulation.func private @row0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<3 : 0 x !simulation.logic<1>>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %o: !simulation.driver<!simulation.packed_array<7 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^body
  ^body:
    %e = simulation.ref.subelement %a[[0]] : !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<3 : 0 x !simulation.logic<1>>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>> -> !simulation.ref<!simulation.packed_array<3 : 0 x !simulation.logic<1>>>
    %v = simulation.ref.load %e : !simulation.ref<!simulation.packed_array<3 : 0 x !simulation.logic<1>>> -> !simulation.packed_array<3 : 0 x !simulation.logic<1>>
    %f = simulation.packed.flatten %v : (!simulation.packed_array<3 : 0 x !simulation.logic<1>>) -> !simulation.logic<4>
    %t = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<7 : 0 x !simulation.logic<1>>> -> !simulation.driver<!simulation.logic<4>>
    simulation.driver.drive %t = %f : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
    simulation.suspend.change %a to ^body : !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<3 : 0 x !simulation.logic<1>>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>
  }
  simulation.func private @row1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<3 : 0 x !simulation.logic<1>>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %o: !simulation.driver<!simulation.packed_array<7 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^body
  ^body:
    %e = simulation.ref.subelement %a[[1]] : !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<3 : 0 x !simulation.logic<1>>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>> -> !simulation.ref<!simulation.packed_array<3 : 0 x !simulation.logic<1>>>
    %v = simulation.ref.load %e : !simulation.ref<!simulation.packed_array<3 : 0 x !simulation.logic<1>>> -> !simulation.packed_array<3 : 0 x !simulation.logic<1>>
    %f = simulation.packed.flatten %v : (!simulation.packed_array<3 : 0 x !simulation.logic<1>>) -> !simulation.logic<4>
    %t = simulation.driver.extract %o from 4 : !simulation.driver<!simulation.packed_array<7 : 0 x !simulation.logic<1>>> -> !simulation.driver<!simulation.logic<4>>
    simulation.driver.drive %t = %f : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
    simulation.suspend.change %a to ^body : !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<3 : 0 x !simulation.logic<1>>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>
  }
}

// -----

// With a force in the design (10.6.2) a forced row 0 must be visible to the
// reader of row 0, so `r2 = r0 ^ y` keeps its process; the independent rows
// 0 and 1 still merge.
// CHECK-LABEL: simulation.design @override_blocks_forwarding
// CHECK: simulation.driver.decl 0 in 0 drives 0 : {{.*}} {driven_low = 0 : i64, driven_width = 8 : i64}
// CHECK: simulation.driver.decl 1 in 0 drives 0 : {{.*}} {driven_low = 8 : i64, driven_width = 4 : i64}
// CHECK-DAG: simulation.spawn @r0.coalesced(
// CHECK-DAG: simulation.spawn @r2(
simulation.design @override_blocks_forwarding {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "r0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "r1"
  simulation.code_unit.decl 4 in 0 continuous hierarchy "r2"
  simulation.code_unit.decl 5 in 0 initial hierarchy "forcer"
  simulation.storage.decl 0 in 0 : !simulation.logic<4> design
  simulation.net.decl 0 in 0 : !simulation.packed_array<11 : 0 x !simulation.logic<1>> design
  simulation.net.decl 1 in 0 : !simulation.logic<4> design
  simulation.net.decl 2 in 0 : !simulation.logic<4> design
  simulation.driver.decl 0 in 0 drives 0 : !simulation.packed_array<11 : 0 x !simulation.logic<1>> design {driven_low = 0 : i64, driven_width = 4 : i64}
  simulation.driver.decl 1 in 0 drives 0 : !simulation.packed_array<11 : 0 x !simulation.logic<1>> design {driven_low = 4 : i64, driven_width = 4 : i64}
  simulation.driver.decl 2 in 0 drives 0 : !simulation.packed_array<11 : 0 x !simulation.logic<1>> design {driven_low = 8 : i64, driven_width = 4 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %t = simulation.context.net %ctx[0] : !simulation.net<!simulation.packed_array<11 : 0 x !simulation.logic<1>>>
    %x = simulation.context.net %ctx[1] : !simulation.net<!simulation.logic<4>>
    %y = simulation.context.net %ctx[2] : !simulation.net<!simulation.logic<4>>
    %s = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<4>>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>>
    %p0 = simulation.spawn @r0(%ctx, %x, %o0) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>> -> !simulation.process
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>>
    %p1 = simulation.spawn @r1(%ctx, %y, %o1) : !simulation.context, !simulation.net<!simulation.logic<4>>, !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>> -> !simulation.process
    %o2 = simulation.context.driver %ctx[2] : !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>>
    %p2 = simulation.spawn @r2(%ctx, %t, %y, %o2) : !simulation.context, !simulation.net<!simulation.packed_array<11 : 0 x !simulation.logic<1>>>, !simulation.net<!simulation.logic<4>>, !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>> -> !simulation.process
    %p3 = simulation.spawn @forcer(%ctx, %s) : !simulation.context, !simulation.ref<!simulation.logic<4>> -> !simulation.process
    simulation.return
  }
  simulation.func private @r0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %o: !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.read %x : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
    %d = simulation.driver.extract %o from 0 : !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>> -> !simulation.driver<!simulation.logic<4>>
    simulation.driver.drive %d = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
    simulation.suspend.change %x to ^body : !simulation.net<!simulation.logic<4>>
  }
  simulation.func private @r1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %y: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}, %o: !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^body
  ^body:
    %v = simulation.net.read %y : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
    %d = simulation.driver.extract %o from 4 : !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>> -> !simulation.driver<!simulation.logic<4>>
    simulation.driver.drive %d = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
    simulation.suspend.change %y to ^body : !simulation.net<!simulation.logic<4>>
  }
  simulation.func private @r2(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %t: !simulation.net<!simulation.packed_array<11 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %y: !simulation.net<!simulation.logic<4>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}, %o: !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
    cf.br ^body
  ^body:
    %r = simulation.net.extract %t from 0 : !simulation.net<!simulation.packed_array<11 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<4>>
    %a = simulation.net.read %r : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
    %b = simulation.net.read %y : !simulation.net<!simulation.logic<4>> -> !simulation.logic<4>
    %v = simulation.logic.binary xor %a, %b : !simulation.logic<4>
    %d = simulation.driver.extract %o from 8 : !simulation.driver<!simulation.packed_array<11 : 0 x !simulation.logic<1>>> -> !simulation.driver<!simulation.logic<4>>
    simulation.driver.drive %d = %v : !simulation.driver<!simulation.logic<4>>, !simulation.logic<4>
    simulation.suspend.any %r, %y edges [0, 0] to ^body : !simulation.net<!simulation.logic<4>>, !simulation.net<!simulation.logic<4>>
  }
  simulation.func private @forcer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %s: !simulation.ref<!simulation.logic<4>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
    %c = simulation.logic.constant 5 : i4, 0 : i4 : !simulation.logic<4>
    simulation.override %s = %c assign false : !simulation.ref<!simulation.logic<4>>, !simulation.logic<4>
    simulation.return
  }
}

// -----

// `o[2] = w[0]` where `w` is port-collapsed with o[1:0] (23.3.3.7): w[0] is
// bit 0 of the run o[1:0], which the merged process drives after its reads,
// so the reader keeps its own process.
// CHECK-LABEL: simulation.design @alias_of_run
// CHECK: simulation.driver.decl 0 in 0 drives 0 : {{.*}} {driven_low = 0 : i64, driven_width = 2 : i64}
// CHECK: simulation.driver.decl 1 in 0 drives 0 : {{.*}} {driven_low = 2 : i64, driven_width = 1 : i64}
// CHECK-DAG: simulation.spawn @bit0.coalesced(
// CHECK-DAG: simulation.spawn @bit2(
simulation.design @alias_of_run {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.code_unit.decl 4 in 0 continuous hierarchy "bit2"
  simulation.net.decl 0 in 0 : !simulation.packed_array<2 : 0 x i1> design
  simulation.net.decl 1 in 0 : !simulation.packed_array<1 : 0 x i1> design
  simulation.net.decl 2 in 0 : i1 design
  simulation.net.connect.decl 0 in 0 1[0] to 0[0] width 2 reversed = false rhs_dominates = true
  simulation.driver.decl 0 in 0 drives 0 : !simulation.packed_array<2 : 0 x i1> design {driven_low = 0 : i64, driven_width = 1 : i64}
  simulation.driver.decl 1 in 0 drives 0 : !simulation.packed_array<2 : 0 x i1> design {driven_low = 1 : i64, driven_width = 1 : i64}
  simulation.driver.decl 2 in 0 drives 0 : !simulation.packed_array<2 : 0 x i1> design {driven_low = 2 : i64, driven_width = 1 : i64}
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %a = simulation.context.net %ctx[2] : !simulation.net<i1>
    %w = simulation.context.net %ctx[1] : !simulation.net<!simulation.packed_array<1 : 0 x i1>>
    %o0 = simulation.context.driver %ctx[0] : !simulation.driver<!simulation.packed_array<2 : 0 x i1>>
    %p0 = simulation.spawn @bit0(%ctx, %a, %o0) : !simulation.context, !simulation.net<i1>, !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.process
    %o1 = simulation.context.driver %ctx[1] : !simulation.driver<!simulation.packed_array<2 : 0 x i1>>
    %p1 = simulation.spawn @bit1(%ctx, %a, %o1) : !simulation.context, !simulation.net<i1>, !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.process
    %o2 = simulation.context.driver %ctx[2] : !simulation.driver<!simulation.packed_array<2 : 0 x i1>>
    %p2 = simulation.spawn @bit2(%ctx, %w, %o2) : !simulation.context, !simulation.net<!simulation.packed_array<1 : 0 x i1>>, !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.process
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
    %n = arith.constant true
    %w = arith.xori %v, %n : i1
    %d = simulation.driver.extract %o from 1 : !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %d = %w : !simulation.driver<i1>, i1
    simulation.suspend.change %a to ^body : !simulation.net<i1>
  }
  simulation.func private @bit2(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %w: !simulation.net<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %o: !simulation.driver<!simulation.packed_array<2 : 0 x i1>> {simulation.capture_kind = 5 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
    cf.br ^body
  ^body:
    %r = simulation.net.extract %w from 0 : !simulation.net<!simulation.packed_array<1 : 0 x i1>> -> !simulation.net<i1>
    %v = simulation.net.read %r : !simulation.net<i1> -> i1
    %d = simulation.driver.extract %o from 2 : !simulation.driver<!simulation.packed_array<2 : 0 x i1>> -> !simulation.driver<i1>
    simulation.driver.drive %d = %v : !simulation.driver<i1>, i1
    simulation.suspend.change %r to ^body : !simulation.net<i1>
  }
}
