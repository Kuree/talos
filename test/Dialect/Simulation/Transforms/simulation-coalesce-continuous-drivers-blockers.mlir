// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-coalesce-continuous-drivers{vpi=off}))' | FileCheck %s

// Continuous assignments the pass keeps as separate processes.

// Adjacent fields of one packed struct variable written in different state
// domains (a two-state `bit` field and a four-state `logic` field) do not form
// one word.
// CHECK-LABEL: simulation.design @mixed_domains
// CHECK-DAG: simulation.spawn @ua(
// CHECK-DAG: simulation.spawn @ub(
// CHECK-NOT: coalesced
!S = !simulation.packed_struct<[#simulation.field<name = "a", type = !simulation.packed_array<3 : 0 x i1>, ordinal = 0, packedOffset = 4>, #simulation.field<name = "b", type = !simulation.packed_array<3 : 0 x !simulation.logic<1>>, ordinal = 1, packedOffset = 0>]>
!A = !simulation.packed_array<3 : 0 x i1>
!B = !simulation.packed_array<3 : 0 x !simulation.logic<1>>
simulation.design @mixed_domains {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "ua"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "ub"
  simulation.storage.decl 0 in 0 : !S design
  simulation.storage.decl 1 in 0 : !A design
  simulation.storage.decl 2 in 0 : !B design
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %s = simulation.context.storage %ctx[0] : !simulation.ref<!S>
    %x = simulation.context.storage %ctx[1] : !simulation.ref<!A>
    %y = simulation.context.storage %ctx[2] : !simulation.ref<!B>
    %p0 = simulation.spawn @ua(%ctx, %s, %x) : !simulation.context, !simulation.ref<!S>, !simulation.ref<!A> -> !simulation.process
    %p1 = simulation.spawn @ub(%ctx, %s, %y) : !simulation.context, !simulation.ref<!S>, !simulation.ref<!B> -> !simulation.process
    simulation.return
  }
  simulation.func private @ua(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %s: !simulation.ref<!S> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !simulation.ref<!A> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^h
  ^h:
    %v = simulation.ref.load %x : !simulation.ref<!A> -> !A
    %t = simulation.ref.subelement %s[[0]] : !simulation.ref<!S> -> !simulation.ref<!A>
    simulation.ref.store %v to %t {simulation.continuous_store} : !A, !simulation.ref<!A>
    simulation.suspend.change %x to ^h : !simulation.ref<!A>
  }
  simulation.func private @ub(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %s: !simulation.ref<!S> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %y: !simulation.ref<!B> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^h
  ^h:
    %v = simulation.ref.load %y : !simulation.ref<!B> -> !B
    %t = simulation.ref.subelement %s[[1]] : !simulation.ref<!S> -> !simulation.ref<!B>
    simulation.ref.store %v to %t {simulation.continuous_store} : !B, !simulation.ref<!B>
    simulation.suspend.change %y to ^h : !simulation.ref<!B>
  }
}

// -----

// A join that selects between two handles: the merged process would select
// a reference, which no handle analysis follows.
// CHECK-LABEL: simulation.design @handle_argument
// CHECK-DAG: simulation.spawn @bit0(
// CHECK-DAG: simulation.spawn @bit1(
// CHECK-NOT: coalesced
simulation.design @handle_argument {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "bit0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "bit1"
  simulation.storage.decl 0 in 0 : i2 design
  simulation.storage.decl 1 in 0 : i4 design
  simulation.net.decl 0 in 0 : i2 design
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %n = simulation.context.storage %ctx[0] : !simulation.ref<i2>
    %x = simulation.context.storage %ctx[1] : !simulation.ref<i4>
    %m = simulation.context.net %ctx[0] : !simulation.net<i2>
    %p0 = simulation.spawn @bit0(%ctx, %n, %x, %m) : !simulation.context, !simulation.ref<i2>, !simulation.ref<i4>, !simulation.net<i2> -> !simulation.process
    %p1 = simulation.spawn @bit1(%ctx, %n, %x, %m) : !simulation.context, !simulation.ref<i2>, !simulation.ref<i4>, !simulation.net<i2> -> !simulation.process
    simulation.return
  }
  simulation.func private @bit0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !simulation.ref<i4> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %m: !simulation.net<i2> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 0 : !simulation.net<i2> -> !simulation.net<i1>
    %c = simulation.net.read %mv : !simulation.net<i1> -> i1
    %x0 = simulation.ref.extract %x from 0 : !simulation.ref<i4> -> !simulation.ref<i1>
    %x2 = simulation.ref.extract %x from 2 : !simulation.ref<i4> -> !simulation.ref<i1>
    cf.cond_br %c, ^a, ^b
  ^a:
    cf.br ^join(%x0 : !simulation.ref<i1>)
  ^b:
    cf.br ^join(%x2 : !simulation.ref<i1>)
  ^join(%r: !simulation.ref<i1>):
    %v = simulation.ref.load %r : !simulation.ref<i1> -> i1
    %t = simulation.ref.extract %n from 0 : !simulation.ref<i2> -> !simulation.ref<i1>
    simulation.ref.store %v to %t {simulation.continuous_store} : i1, !simulation.ref<i1>
    simulation.suspend.any %mv, %x edges [0, 0] to ^h : !simulation.net<i1>, !simulation.ref<i4>
  }
  simulation.func private @bit1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !simulation.ref<i4> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %m: !simulation.net<i2> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 1 : !simulation.net<i2> -> !simulation.net<i1>
    %c = simulation.net.read %mv : !simulation.net<i1> -> i1
    %x0 = simulation.ref.extract %x from 1 : !simulation.ref<i4> -> !simulation.ref<i1>
    %x2 = simulation.ref.extract %x from 3 : !simulation.ref<i4> -> !simulation.ref<i1>
    cf.cond_br %c, ^a, ^b
  ^a:
    cf.br ^join(%x0 : !simulation.ref<i1>)
  ^b:
    cf.br ^join(%x2 : !simulation.ref<i1>)
  ^join(%r: !simulation.ref<i1>):
    %v = simulation.ref.load %r : !simulation.ref<i1> -> i1
    %t = simulation.ref.extract %n from 1 : !simulation.ref<i2> -> !simulation.ref<i1>
    simulation.ref.store %v to %t {simulation.continuous_store} : i1, !simulation.ref<i1>
    simulation.suspend.any %mv, %x edges [0, 0] to ^h : !simulation.net<i1>, !simulation.ref<i4>
  }
}

// -----

// Delayed continuous assignments (IEEE 1800-2023 10.3.3) schedule each
// update after their own delay, and a store outside the block that suspends
// does not run on every activation.
// CHECK-LABEL: simulation.design @delays_and_conditional_writes
// CHECK-DAG: simulation.spawn @d0(
// CHECK-DAG: simulation.spawn @d1(
// CHECK-DAG: simulation.spawn @c0(
// CHECK-DAG: simulation.spawn @c1(
// CHECK-NOT: coalesced
simulation.design @delays_and_conditional_writes {
  simulation.scope.decl 0
  simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
  simulation.code_unit.decl 2 in 0 continuous hierarchy "d0"
  simulation.code_unit.decl 3 in 0 continuous hierarchy "d1"
  simulation.code_unit.decl 4 in 0 continuous hierarchy "c0"
  simulation.code_unit.decl 5 in 0 continuous hierarchy "c1"
  simulation.storage.decl 0 in 0 : i2 design
  simulation.storage.decl 1 in 0 : i2 design
  simulation.net.decl 0 in 0 : i2 design
  simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
    %n = simulation.context.storage %ctx[0] : !simulation.ref<i2>
    %k = simulation.context.storage %ctx[1] : !simulation.ref<i2>
    %m = simulation.context.net %ctx[0] : !simulation.net<i2>
    %p0 = simulation.spawn @d0(%ctx, %n, %m) : !simulation.context, !simulation.ref<i2>, !simulation.net<i2> -> !simulation.process
    %p1 = simulation.spawn @d1(%ctx, %n, %m) : !simulation.context, !simulation.ref<i2>, !simulation.net<i2> -> !simulation.process
    %p2 = simulation.spawn @c0(%ctx, %k, %m) : !simulation.context, !simulation.ref<i2>, !simulation.net<i2> -> !simulation.process
    %p3 = simulation.spawn @c1(%ctx, %k, %m) : !simulation.context, !simulation.ref<i2>, !simulation.net<i2> -> !simulation.process
    simulation.return
  }
  simulation.func private @d0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %m: !simulation.net<i2> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64, simulation.propagation_delays = array<i64: 1>} {
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 0 : !simulation.net<i2> -> !simulation.net<i1>
    %v = simulation.net.read %mv : !simulation.net<i1> -> i1
    %t = simulation.ref.extract %n from 0 : !simulation.ref<i2> -> !simulation.ref<i1>
    simulation.ref.store %v to %t {simulation.continuous_store} : i1, !simulation.ref<i1>
    simulation.suspend.change %mv to ^h : !simulation.net<i1>
  }
  simulation.func private @d1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %n: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %m: !simulation.net<i2> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64, simulation.propagation_delays = array<i64: 2>} {
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 1 : !simulation.net<i2> -> !simulation.net<i1>
    %v = simulation.net.read %mv : !simulation.net<i1> -> i1
    %t = simulation.ref.extract %n from 1 : !simulation.ref<i2> -> !simulation.ref<i1>
    simulation.ref.store %v to %t {simulation.continuous_store} : i1, !simulation.ref<i1>
    simulation.suspend.change %mv to ^h : !simulation.net<i1>
  }
  simulation.func private @c0(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %k: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %m: !simulation.net<i2> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 0 : !simulation.net<i2> -> !simulation.net<i1>
    %v = simulation.net.read %mv : !simulation.net<i1> -> i1
    cf.cond_br %v, ^set, ^wait
  ^set:
    %t = simulation.ref.extract %k from 0 : !simulation.ref<i2> -> !simulation.ref<i1>
    simulation.ref.store %v to %t {simulation.continuous_store} : i1, !simulation.ref<i1>
    cf.br ^wait
  ^wait:
    simulation.suspend.change %mv to ^h : !simulation.net<i1>
  }
  simulation.func private @c1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %k: !simulation.ref<i2> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %m: !simulation.net<i2> {simulation.capture_kind = 4 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
    cf.br ^h
  ^h:
    %mv = simulation.net.extract %m from 1 : !simulation.net<i2> -> !simulation.net<i1>
    %v = simulation.net.read %mv : !simulation.net<i1> -> i1
    cf.cond_br %v, ^set, ^wait
  ^set:
    %t = simulation.ref.extract %k from 1 : !simulation.ref<i2> -> !simulation.ref<i1>
    simulation.ref.store %v to %t {simulation.continuous_store} : i1, !simulation.ref<i1>
    cf.br ^wait
  ^wait:
    simulation.suspend.change %mv to ^h : !simulation.net<i1>
  }
}
