// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-coalesce-continuous-drivers{vpi=off},simulation.func(canonicalize,cse)))' | FileCheck %s
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-coalesce-continuous-drivers{vpi=full}))' | FileCheck %s --check-prefix=FULL

// `assign n[i] = m[i] ? d[i] : mem[a][i];` for each bit of a variable `n`
// (IEEE 1800-2023 6.5 continuous assignment to a variable, 11.4.11). Each
// assignment lowers to a diamond; both arms are safe to evaluate (11.3.5: no
// side effect or run-time error; an array element read at an invalid index
// yields the Table 7-1 default, 7.4.5), so the merged process
// evaluates them, selects per bit and stores the word once. The two-state
// select of bits is (m & d) | (~m & mem[a]), with one read of the element.
// CHECK-LABEL: simulation.design @select_lanes
// CHECK: simulation.func private @bit0.coalesced(
// CHECK-SAME: %[[MEM:[^:]*]]: !simulation.ref<!simulation.unpacked_array
// CHECK-SAME: %[[N:[^:]*]]: !simulation.ref<!simulation.packed_array<1 : 0 x i1>>
// CHECK-NOT: cf.cond_br
// CHECK: %[[E:.*]] = simulation.ref.array_element %[[MEM]]
// CHECK-DAG: %[[MV:.*]] = simulation.net.read {{.*}} -> i2
// CHECK-DAG: %[[DV:.*]] = simulation.net.read {{.*}} -> i2
// CHECK-DAG: %[[EV:.*]] = simulation.ref.extract %[[E]] from 0 : {{.*}} -> !simulation.ref<i2>
// CHECK-DAG: %[[LV:.*]] = simulation.ref.load %[[EV]] : !simulation.ref<i2> -> i2
// CHECK: %[[NOT:.*]] = arith.xori %[[MV]], %{{.*}} : i2
// CHECK-DAG: %[[T:.*]] = arith.andi %[[MV]], %[[DV]] : i2
// CHECK-DAG: %[[F:.*]] = arith.andi %[[NOT]], %[[LV]] : i2
// CHECK: %[[W:.*]] = arith.ori %[[T]], %[[F]] : i2
// CHECK: %[[NV:.*]] = simulation.ref.extract %[[N]] from 0 : {{.*}} -> !simulation.ref<i2>
// CHECK: simulation.ref.store %[[W]] to %[[NV]] {simulation.continuous_store} : i2, !simulation.ref<i2>
// FULL-LABEL: simulation.design @select_lanes
// FULL-DAG: simulation.spawn @bit0(
// FULL-DAG: simulation.spawn @bit1(
simulation.design @select_lanes {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.storage.decl 0 in 0 : !simulation.unpacked_array<0 : 1 x !simulation.packed_array<1 : 0 x i1>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>> design
  simulation.storage.decl 1 in 0 : !simulation.packed_array<1 : 0 x i1> design
  simulation.net.decl 0 in 0 : !simulation.packed_array<1 : 0 x i1> design
  simulation.net.decl 1 in 0 : !simulation.packed_array<1 : 0 x i1> design
  simulation.net.decl 2 in 0 : i1 design
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %mem = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<1 : 0 x i1>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>
    %n = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.packed_array<1 : 0 x i1>>
    %m = simulation.context.net %ctx[0] : !simulation.net<!simulation.packed_array<1 : 0 x i1>>
    %d = simulation.context.net %ctx[1] : !simulation.net<!simulation.packed_array<1 : 0 x i1>>
    %a = simulation.context.net %ctx[2] : !simulation.net<i1>
    %p0 = simulation.spawn @bit0(%ctx, %mem, %n, %m, %d, %a) : !simulation.context, !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<1 : 0 x i1>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>, !simulation.ref<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<i1> -> !simulation.process
    %p1 = simulation.spawn @bit1(%ctx, %mem, %n, %m, %d, %a) : !simulation.context, !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<1 : 0 x i1>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>, !simulation.ref<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<i1> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %mem: !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<1 : 0 x i1>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %n: !simulation.ref<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %m: !simulation.net<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %d: !simulation.net<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %a: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    %true = arith.constant true
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 0 : !simulation.net<!simulation.packed_array<1 : 0 x i1>> -> !simulation.net<i1>
    %c = simulation.net.read %mv : !simulation.net<i1> -> i1
    %nc = arith.xori %c, %true : i1
    cf.cond_br %nc, ^else, ^then
  ^then:
    %dv = simulation.net.extract %d from 0 : !simulation.net<!simulation.packed_array<1 : 0 x i1>> -> !simulation.net<i1>
    %x = simulation.net.read %dv : !simulation.net<i1> -> i1
    cf.br ^join(%x : i1)
  ^else:
    %av = simulation.net.read %a : !simulation.net<i1> -> i1
    %ai = arith.extui %av : i1 to i65
    %e = simulation.ref.array_element %mem[%ai] : (!simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<1 : 0 x i1>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>, i65) -> !simulation.ref<!simulation.packed_array<1 : 0 x i1>>
    %b = simulation.ref.subelement %e[[1]] : !simulation.ref<!simulation.packed_array<1 : 0 x i1>> -> !simulation.ref<i1>
    %y = simulation.ref.load %b : !simulation.ref<i1> -> i1
    cf.br ^join(%y : i1)
  ^join(%v: i1):
    %t = simulation.ref.subelement %n[[1]] : !simulation.ref<!simulation.packed_array<1 : 0 x i1>> -> !simulation.ref<i1>
    simulation.ref.store %v to %t {simulation.continuous_store} : i1, !simulation.ref<i1>
    %dw = simulation.net.extract %d from 0 : !simulation.net<!simulation.packed_array<1 : 0 x i1>> -> !simulation.net<i1>
    simulation.suspend.any %mv, %dw, %a, %mem edges [0, 0, 0, 0] to ^h : !simulation.net<i1>, !simulation.net<i1>, !simulation.net<i1>, !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<1 : 0 x i1>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %mem: !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<1 : 0 x i1>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %n: !simulation.ref<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %m: !simulation.net<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %d: !simulation.net<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %a: !simulation.net<i1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    %true = arith.constant true
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 1 : !simulation.net<!simulation.packed_array<1 : 0 x i1>> -> !simulation.net<i1>
    %c = simulation.net.read %mv : !simulation.net<i1> -> i1
    %nc = arith.xori %c, %true : i1
    cf.cond_br %nc, ^else, ^then
  ^then:
    %dv = simulation.net.extract %d from 1 : !simulation.net<!simulation.packed_array<1 : 0 x i1>> -> !simulation.net<i1>
    %x = simulation.net.read %dv : !simulation.net<i1> -> i1
    cf.br ^join(%x : i1)
  ^else:
    %av = simulation.net.read %a : !simulation.net<i1> -> i1
    %ai = arith.extui %av : i1 to i65
    %e = simulation.ref.array_element %mem[%ai] : (!simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<1 : 0 x i1>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>, i65) -> !simulation.ref<!simulation.packed_array<1 : 0 x i1>>
    %b = simulation.ref.subelement %e[[0]] : !simulation.ref<!simulation.packed_array<1 : 0 x i1>> -> !simulation.ref<i1>
    %y = simulation.ref.load %b : !simulation.ref<i1> -> i1
    cf.br ^join(%y : i1)
  ^join(%v: i1):
    %t = simulation.ref.subelement %n[[0]] : !simulation.ref<!simulation.packed_array<1 : 0 x i1>> -> !simulation.ref<i1>
    simulation.ref.store %v to %t {simulation.continuous_store} : i1, !simulation.ref<i1>
    %dw = simulation.net.extract %d from 1 : !simulation.net<!simulation.packed_array<1 : 0 x i1>> -> !simulation.net<i1>
    simulation.suspend.any %mv, %dw, %a, %mem edges [0, 0, 0, 0] to ^h : !simulation.net<i1>, !simulation.net<i1>, !simulation.net<i1>, !simulation.ref<!simulation.unpacked_array<0 : 1 x !simulation.packed_array<1 : 0 x i1>, #simulation.storage_layout<size = 2, alignment = 1, stride = 1, offsets = []>>>
  }
}

// -----

// An arm that may trap (a division whose divisor can be zero) runs only on
// its path, so the members keep their processes.
// CHECK-LABEL: simulation.design @trapping_arm
// CHECK-DAG: simulation.spawn @bit0(
// CHECK-DAG: simulation.spawn @bit1(
// CHECK-NOT: coalesced
simulation.design @trapping_arm {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.storage.decl 0 in 0 : !simulation.packed_array<1 : 0 x i1> design
  simulation.net.decl 0 in 0 : !simulation.packed_array<1 : 0 x i1> design
  simulation.net.decl 1 in 0 : i4 design
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %n = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.packed_array<1 : 0 x i1>>
    %m = simulation.context.net %ctx[0] : !simulation.net<!simulation.packed_array<1 : 0 x i1>>
    %q = simulation.context.net %ctx[1] : !simulation.net<i4>
    %p0 = simulation.spawn @bit0(%ctx, %n, %m, %q) : !simulation.context, !simulation.ref<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<i4> -> !simulation.process
    %p1 = simulation.spawn @bit1(%ctx, %n, %m, %q) : !simulation.context, !simulation.ref<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<!simulation.packed_array<1 : 0 x i1>>, !simulation.net<i4> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %m: !simulation.net<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %q: !simulation.net<i4> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    %c7 = arith.constant 7 : i4
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 0 : !simulation.net<!simulation.packed_array<1 : 0 x i1>> -> !simulation.net<i1>
    %c = simulation.net.read %mv : !simulation.net<i1> -> i1
    cf.cond_br %c, ^div, ^zero
  ^div:
    %qv = simulation.net.read %q : !simulation.net<i4> -> i4
    %r = arith.divui %c7, %qv : i4
    %rb = arith.trunci %r : i4 to i1
    cf.br ^join(%rb : i1)
  ^zero:
    %f = arith.constant false
    cf.br ^join(%f : i1)
  ^join(%v: i1):
    %t = simulation.ref.subelement %n[[1]] : !simulation.ref<!simulation.packed_array<1 : 0 x i1>> -> !simulation.ref<i1>
    simulation.ref.store %v to %t {simulation.continuous_store} : i1, !simulation.ref<i1>
    simulation.suspend.any %mv, %q edges [0, 0] to ^h : !simulation.net<i1>, !simulation.net<i4>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %m: !simulation.net<!simulation.packed_array<1 : 0 x i1>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %q: !simulation.net<i4> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    %c7 = arith.constant 7 : i4
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 1 : !simulation.net<!simulation.packed_array<1 : 0 x i1>> -> !simulation.net<i1>
    %c = simulation.net.read %mv : !simulation.net<i1> -> i1
    cf.cond_br %c, ^div, ^zero
  ^div:
    %qv = simulation.net.read %q : !simulation.net<i4> -> i4
    %r = arith.divui %c7, %qv : i4
    %rb = arith.trunci %r : i4 to i1
    cf.br ^join(%rb : i1)
  ^zero:
    %f = arith.constant false
    cf.br ^join(%f : i1)
  ^join(%v: i1):
    %t = simulation.ref.subelement %n[[0]] : !simulation.ref<!simulation.packed_array<1 : 0 x i1>> -> !simulation.ref<i1>
    simulation.ref.store %v to %t {simulation.continuous_store} : i1, !simulation.ref<i1>
    simulation.suspend.any %mv, %q edges [0, 0] to ^h : !simulation.net<i1>, !simulation.net<i4>
  }
}

// -----

// The four-state lowering of `n[i] = m[i] ? d[i] : e[i]` (11.4.11): a known
// false condition takes e, a known true one d, and an X/Z condition merges
// both through logic.mux. If-conversion selects the value of the path taken.
// Folding a lane for m[i] = 0, 1, X and Z leaves e[i], d[i] and twice the
// merge of both, so the lane is `m[i] ? d[i] : e[i]`, and the lanes become
// one per-bit logic.bitwise_mux (Table 11-20 per bit).
// CHECK-LABEL: simulation.design @logic_select
// CHECK: simulation.func private @bit0.coalesced(%{{[^%]*}}%{{[^%]*}}%[[M:[^:]*]]:{{[^%]*}}%[[D:[^:]*]]:{{[^%]*}}%[[E:[^:]*]]:
// CHECK-NOT: cf.cond_br
// CHECK-NOT: arith.select
// CHECK-DAG: %[[MV:.*]] = simulation.net.extract %[[M]] from 0 {{.*}} -> !simulation.net<!simulation.logic<2>>
// CHECK-DAG: %[[C:.*]] = simulation.net.read %[[MV]]
// CHECK-DAG: %[[DV:.*]] = simulation.net.extract %[[D]] from 0 {{.*}} -> !simulation.net<!simulation.logic<2>>
// CHECK-DAG: %[[A:.*]] = simulation.net.read %[[DV]]
// CHECK-DAG: %[[EV:.*]] = simulation.net.extract %[[E]] from 0 {{.*}} -> !simulation.net<!simulation.logic<2>>
// CHECK-DAG: %[[B:.*]] = simulation.net.read %[[EV]]
// CHECK: %[[R:.*]] = simulation.logic.bitwise_mux %[[C]] ? %[[A]] : %[[B]] : !simulation.logic<2>
// CHECK: simulation.ref.store %[[R]] to {{.*}} {simulation.continuous_store} : !simulation.logic<2>, !simulation.ref<!simulation.logic<2>>
// CHECK-NOT: simulation.ref.store
simulation.design @logic_select {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.storage.decl 0 in 0 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design
  simulation.net.decl 0 in 0 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design
  simulation.net.decl 1 in 0 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design
  simulation.net.decl 2 in 0 : !simulation.packed_array<1 : 0 x !simulation.logic<1>> design
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %n = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %m = simulation.context.net %ctx[0] : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %d = simulation.context.net %ctx[1] : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %e = simulation.context.net %ctx[2] : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>
    %p0 = simulation.spawn @bit0(%ctx, %n, %m, %d, %e) : !simulation.context, !simulation.ref<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>, !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>, !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>, !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.process
    %p1 = simulation.spawn @bit1(%ctx, %n, %m, %d, %e) : !simulation.context, !simulation.ref<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>, !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>, !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>>, !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %m: !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %d: !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %e: !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    %true = arith.constant true
    %false = arith.constant false
    %x = simulation.logic.constant false, true : !simulation.logic<1>
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 0 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %c = simulation.net.read %mv : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    %r = simulation.logic.reduction or %c : !simulation.logic<1> -> !simulation.logic<1>
    %rb = simulation.logic.to_bits %r : !simulation.logic<1> -> i1
    %rl = simulation.logic.from_bits %rb : i1 -> !simulation.logic<1>
    %known = simulation.logic.compare case_eq %r, %rl : (!simulation.logic<1>, !simulation.logic<1>) -> i1
    %t = simulation.logic.is_true %c : !simulation.logic<1>
    %nt = arith.xori %t, %true : i1
    %isfalse = arith.andi %known, %nt : i1
    %unknown = arith.xori %known, %true : i1
    cf.cond_br %isfalse, ^else(%x, %false : !simulation.logic<1>, i1), ^then(%unknown : i1)
  ^then(%u: i1):
    %dv = simulation.net.extract %d from 0 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %a = simulation.net.read %dv : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    cf.cond_br %u, ^else(%a, %u : !simulation.logic<1>, i1), ^join(%a : !simulation.logic<1>)
  ^else(%pa: !simulation.logic<1>, %merge: i1):
    %ev = simulation.net.extract %e from 0 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %b = simulation.net.read %ev : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    cf.cond_br %merge, ^ambiguous(%pa, %b : !simulation.logic<1>, !simulation.logic<1>), ^join(%b : !simulation.logic<1>)
  ^ambiguous(%l: !simulation.logic<1>, %rr: !simulation.logic<1>):
    %mx = simulation.logic.mux %x ? %l : %rr : (!simulation.logic<1>, !simulation.logic<1>, !simulation.logic<1>) -> !simulation.logic<1>
    cf.br ^join(%mx : !simulation.logic<1>)
  ^join(%v: !simulation.logic<1>):
    %tn = simulation.ref.subelement %n[[1]] : !simulation.ref<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.ref<!simulation.logic<1>>
    simulation.ref.store %v to %tn {simulation.continuous_store} : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
    %dw = simulation.net.extract %d from 0 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %ew = simulation.net.extract %e from 0 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    simulation.suspend.any %mv, %dw, %ew edges [0, 0, 0] to ^h : !simulation.net<!simulation.logic<1>>, !simulation.net<!simulation.logic<1>>, !simulation.net<!simulation.logic<1>>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %m: !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %d: !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}, %e: !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    %true = arith.constant true
    %false = arith.constant false
    %x = simulation.logic.constant false, true : !simulation.logic<1>
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 1 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %c = simulation.net.read %mv : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    %r = simulation.logic.reduction or %c : !simulation.logic<1> -> !simulation.logic<1>
    %rb = simulation.logic.to_bits %r : !simulation.logic<1> -> i1
    %rl = simulation.logic.from_bits %rb : i1 -> !simulation.logic<1>
    %known = simulation.logic.compare case_eq %r, %rl : (!simulation.logic<1>, !simulation.logic<1>) -> i1
    %t = simulation.logic.is_true %c : !simulation.logic<1>
    %nt = arith.xori %t, %true : i1
    %isfalse = arith.andi %known, %nt : i1
    %unknown = arith.xori %known, %true : i1
    cf.cond_br %isfalse, ^else(%x, %false : !simulation.logic<1>, i1), ^then(%unknown : i1)
  ^then(%u: i1):
    %dv = simulation.net.extract %d from 1 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %a = simulation.net.read %dv : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    cf.cond_br %u, ^else(%a, %u : !simulation.logic<1>, i1), ^join(%a : !simulation.logic<1>)
  ^else(%pa: !simulation.logic<1>, %merge: i1):
    %ev = simulation.net.extract %e from 1 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %b = simulation.net.read %ev : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
    cf.cond_br %merge, ^ambiguous(%pa, %b : !simulation.logic<1>, !simulation.logic<1>), ^join(%b : !simulation.logic<1>)
  ^ambiguous(%l: !simulation.logic<1>, %rr: !simulation.logic<1>):
    %mx = simulation.logic.mux %x ? %l : %rr : (!simulation.logic<1>, !simulation.logic<1>, !simulation.logic<1>) -> !simulation.logic<1>
    cf.br ^join(%mx : !simulation.logic<1>)
  ^join(%v: !simulation.logic<1>):
    %tn = simulation.ref.subelement %n[[0]] : !simulation.ref<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.ref<!simulation.logic<1>>
    simulation.ref.store %v to %tn {simulation.continuous_store} : !simulation.logic<1>, !simulation.ref<!simulation.logic<1>>
    %dw = simulation.net.extract %d from 1 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    %ew = simulation.net.extract %e from 1 : !simulation.net<!simulation.packed_array<1 : 0 x !simulation.logic<1>>> -> !simulation.net<!simulation.logic<1>>
    simulation.suspend.any %mv, %dw, %ew edges [0, 0, 0] to ^h : !simulation.net<!simulation.logic<1>>, !simulation.net<!simulation.logic<1>>, !simulation.net<!simulation.logic<1>>
  }
}

// -----

// One condition for every lane, `n[i] = s ? d[i] : 1'bz`: the lanes become
// one logic.mux on the shared one-bit condition. A known condition passes the
// Z of the false operand (11.4.11); an X one merges per Table 11-20.
// CHECK-LABEL: simulation.design @shared_condition
// CHECK: simulation.func private @bit0.coalesced(%{{[^%]*}}%{{[^%]*}}%[[S:[^:]*]]:{{[^%]*}}%[[D:[^:]*]]:
// CHECK-DAG: %[[Z:.*]] = simulation.logic.constant -1 : i2, -1 : i2 : !simulation.logic<2>
// CHECK-DAG: %[[C:.*]] = simulation.net.read %[[S]] : !simulation.net<!simulation.logic<1>> -> !simulation.logic<1>
// CHECK-DAG: %[[DV:.*]] = simulation.net.extract %[[D]] from 0 {{.*}} -> !simulation.net<!simulation.logic<2>>
// CHECK-DAG: %[[A:.*]] = simulation.net.read %[[DV]]
// CHECK: %[[R:.*]] = simulation.logic.mux %[[C]] ? %[[A]] : %[[Z]] : (!simulation.logic<1>, !simulation.logic<2>, !simulation.logic<2>) -> !simulation.logic<2>
// CHECK: simulation.ref.store %[[R]] to
!pa = !simulation.packed_array<1 : 0 x !simulation.logic<1>>
!l1 = !simulation.logic<1>
simulation.design @shared_condition {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.storage.decl 0 in 0 : !pa design
  simulation.net.decl 0 in 0 : !l1 design
  simulation.net.decl 1 in 0 : !pa design
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %n = simulation.context.storage %ctx[0] : !simulation.ref<!pa>
    %m = simulation.context.net %ctx[0] : !simulation.net<!l1>
    %d = simulation.context.net %ctx[1] : !simulation.net<!pa>
    %p0 = simulation.spawn @bit0(%ctx, %n, %m, %d) : !simulation.context, !simulation.ref<!pa>, !simulation.net<!l1>, !simulation.net<!pa> -> !simulation.process
    %p1 = simulation.spawn @bit1(%ctx, %n, %m, %d) : !simulation.context, !simulation.ref<!pa>, !simulation.net<!l1>, !simulation.net<!pa> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<!pa> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %m: !simulation.net<!l1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %d: !simulation.net<!pa> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^h
  ^h:
    %c = simulation.net.read %m : !simulation.net<!l1> -> !l1
    %dv = simulation.net.extract %d from 0 : !simulation.net<!pa> -> !simulation.net<!l1>
    %a = simulation.net.read %dv : !simulation.net<!l1> -> !l1
    %z = simulation.logic.constant true, true : !l1
    %v = simulation.logic.mux %c ? %a : %z : (!l1, !l1, !l1) -> !l1
    %tn = simulation.ref.subelement %n[[1]] : !simulation.ref<!pa> -> !simulation.ref<!l1>
    simulation.ref.store %v to %tn {simulation.continuous_store} : !l1, !simulation.ref<!l1>
    simulation.suspend.any %m, %dv edges [0, 0] to ^h : !simulation.net<!l1>, !simulation.net<!l1>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<!pa> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %m: !simulation.net<!l1> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %d: !simulation.net<!pa> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^h
  ^h:
    %c = simulation.net.read %m : !simulation.net<!l1> -> !l1
    %dv = simulation.net.extract %d from 1 : !simulation.net<!pa> -> !simulation.net<!l1>
    %a = simulation.net.read %dv : !simulation.net<!l1> -> !l1
    %z = simulation.logic.constant true, true : !l1
    %v = simulation.logic.mux %c ? %a : %z : (!l1, !l1, !l1) -> !l1
    %tn = simulation.ref.subelement %n[[0]] : !simulation.ref<!pa> -> !simulation.ref<!l1>
    simulation.ref.store %v to %tn {simulation.continuous_store} : !l1, !simulation.ref<!l1>
    simulation.suspend.any %m, %dv edges [0, 0] to ^h : !simulation.net<!l1>, !simulation.net<!l1>
  }
}

// -----

// `n[i] = (m[i] & d[i]) | (~m[i] & 1'b1)` is no conditional: for m[i] = X and
// d[i] = 1 it is X (Tables 11-11, 11-12, 11-15), where `m[i] ? d[i] : 1`
// gives 1 (Table 11-20). The lanes stay bitwise operations.
// CHECK-LABEL: simulation.design @and_or_lanes
// CHECK: simulation.func private @bit0.coalesced(
// CHECK-NOT: simulation.logic.bitwise_mux
// CHECK-NOT: simulation.logic.mux
// CHECK: simulation.logic.binary or {{.*}} : !simulation.logic<2>
// CHECK: simulation.ref.store
!pa = !simulation.packed_array<1 : 0 x !simulation.logic<1>>
!l1 = !simulation.logic<1>
simulation.design @and_or_lanes {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.storage.decl 0 in 0 : !pa design
  simulation.net.decl 0 in 0 : !pa design
  simulation.net.decl 1 in 0 : !pa design
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %n = simulation.context.storage %ctx[0] : !simulation.ref<!pa>
    %m = simulation.context.net %ctx[0] : !simulation.net<!pa>
    %d = simulation.context.net %ctx[1] : !simulation.net<!pa>
    %p0 = simulation.spawn @bit0(%ctx, %n, %m, %d) : !simulation.context, !simulation.ref<!pa>, !simulation.net<!pa>, !simulation.net<!pa> -> !simulation.process
    %p1 = simulation.spawn @bit1(%ctx, %n, %m, %d) : !simulation.context, !simulation.ref<!pa>, !simulation.net<!pa>, !simulation.net<!pa> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<!pa> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %m: !simulation.net<!pa> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %d: !simulation.net<!pa> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 0 : !simulation.net<!pa> -> !simulation.net<!l1>
    %c = simulation.net.read %mv : !simulation.net<!l1> -> !l1
    %dv = simulation.net.extract %d from 0 : !simulation.net<!pa> -> !simulation.net<!l1>
    %a = simulation.net.read %dv : !simulation.net<!l1> -> !l1
    %one = simulation.logic.constant true, false : !l1
    %t = simulation.logic.binary and %c, %a : !l1
    %nc = simulation.logic.unary bit_not %c : (!l1) -> !l1
    %f = simulation.logic.binary and %nc, %one : !l1
    %v = simulation.logic.binary or %t, %f : !l1
    %tn = simulation.ref.subelement %n[[1]] : !simulation.ref<!pa> -> !simulation.ref<!l1>
    simulation.ref.store %v to %tn {simulation.continuous_store} : !l1, !simulation.ref<!l1>
    simulation.suspend.any %mv, %dv edges [0, 0] to ^h : !simulation.net<!l1>, !simulation.net<!l1>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<!pa> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %m: !simulation.net<!pa> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}, %d: !simulation.net<!pa> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 1 : !simulation.net<!pa> -> !simulation.net<!l1>
    %c = simulation.net.read %mv : !simulation.net<!l1> -> !l1
    %dv = simulation.net.extract %d from 1 : !simulation.net<!pa> -> !simulation.net<!l1>
    %a = simulation.net.read %dv : !simulation.net<!l1> -> !l1
    %one = simulation.logic.constant true, false : !l1
    %t = simulation.logic.binary and %c, %a : !l1
    %nc = simulation.logic.unary bit_not %c : (!l1) -> !l1
    %f = simulation.logic.binary and %nc, %one : !l1
    %v = simulation.logic.binary or %t, %f : !l1
    %tn = simulation.ref.subelement %n[[0]] : !simulation.ref<!pa> -> !simulation.ref<!l1>
    simulation.ref.store %v to %tn {simulation.continuous_store} : !l1, !simulation.ref<!l1>
    simulation.suspend.any %mv, %dv edges [0, 0] to ^h : !simulation.net<!l1>, !simulation.net<!l1>
  }
}
