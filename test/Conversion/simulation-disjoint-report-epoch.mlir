// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-fold-small-domains),talos-sim-propagate-initialized-storage{vpi=off},simulation.func(canonicalize,cse)),test-talos-activation-regions{functions=pure_actor,checked_actor})' -o %t 2> %t.trace
// RUN: FileCheck %s < %t
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace

// IEEE 1800-2023 12.4.2/12.5.3: prove both multiple-match checks unreachable.
// Only then can initialized-storage propagation prove the shared report epoch
// stays unarmed and remove its resume flush (16.4.1/16.4.2). Keeping a live
// second report must keep that epoch and the distinct resume behavior.

// -----

module {
  simulation.design @pure_actor {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i32 design
    simulation.storage.decl 1 in 0 : i20 design {observability = 2 : i32}
    simulation.storage.decl 2 in 0 : i20 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "pure_actor"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @pure_actor(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // CHECK-LABEL: simulation.func @pure_actor
    // CHECK-NOT: simulation.context.storage %{{.*}}[0]
    // CHECK: simulation.ref.load
    // CHECK-NOT: simulation.assert.deferred_enqueue
    // CHECK-NOT: simulation.context.storage %{{.*}}[0]
    // CHECK: simulation.suspend.change
    // TRACE: regions @pure_actor valid=1
    simulation.func @pure_actor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %epoch_ref = simulation.context.storage %ctx[0] : !simulation.ref<i32>
      %input = simulation.context.storage %ctx[1] : !simulation.ref<i20>
      %output = simulation.context.storage %ctx[2] : !simulation.ref<i20>
      %zero32 = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      %zero = arith.constant 0 : i20
      %v1 = arith.constant 1 : i20
      %v2 = arith.constant 2 : i20
      %mask = arith.constant 63 : i20
      %v32 = arith.constant 32 : i20
      %true = arith.constant true
      %false = arith.constant false
      cf.br ^body
    ^resume:
      %epoch = simulation.ref.load %epoch_ref : !simulation.ref<i32> -> i32
      %pending = arith.andi %epoch, %one : i32
      %armed = arith.cmpi ne, %pending, %zero32 : i32
      cf.cond_br %armed, ^flush, ^body
    ^flush:
      %next = arith.addi %epoch, %one : i32
      simulation.ref.store %next to %epoch_ref : i32, !simulation.ref<i32>
      cf.br ^body
    ^body:
      %x = simulation.ref.load %input : !simulation.ref<i20> -> i20
      %low = arith.andi %x, %mask : i20
      %low_match = arith.cmpi eq, %low, %v32 : i20
      %p0 = arith.cmpi eq, %x, %zero : i20
      %low_count = arith.extui %low_match : i1 to i32
      %zero_count = arith.extui %p0 : i1 to i32
      %first_count = arith.addi %low_count, %zero_count : i32
      %first_multi = arith.cmpi sgt, %first_count, %one : i32
      cf.cond_br %first_multi, ^report1, ^second
    ^report1:
      %ticket1 = simulation.assert.deferred_enqueue 1 {simulation.deferred_epoch_storage = 0 : i64}
      %old1 = simulation.ref.load %epoch_ref : !simulation.ref<i32> -> i32
      %armed1 = arith.ori %old1, %one : i32
      simulation.ref.store %armed1 to %epoch_ref : i32, !simulation.ref<i32>
      cf.br ^second
    ^second:
      %p1 = arith.cmpi eq, %x, %v1 : i20
      cf.cond_br %p1, ^join(%true : i1), ^next_test
    ^next_test:
      %p2 = arith.cmpi eq, %x, %v2 : i20
      cf.cond_br %p2, ^join(%true : i1), ^join(%false : i1)
    ^join(%group: i1):
      %increment = arith.addi %zero_count, %one : i32
      %second_count = arith.select %group, %increment, %zero_count : i32
      %second_multi = arith.cmpi sgt, %second_count, %one : i32
      cf.cond_br %second_multi, ^report2, ^finish
    ^report2:
      %ticket2 = simulation.assert.deferred_enqueue 2 {simulation.deferred_epoch_storage = 0 : i64}
      %old2 = simulation.ref.load %epoch_ref : !simulation.ref<i32> -> i32
      %armed2 = arith.ori %old2, %one : i32
      simulation.ref.store %armed2 to %epoch_ref : i32, !simulation.ref<i32>
      cf.br ^finish
    ^finish:
      simulation.ref.store %x to %output : i20, !simulation.ref<i20>
      simulation.suspend.change %input to ^resume : !simulation.ref<i20>
    }
  }
}

// -----

module {
  simulation.design @checked_actor {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i32 design
    simulation.storage.decl 1 in 0 : i20 design {observability = 2 : i32}
    simulation.storage.decl 2 in 0 : i20 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "checked_actor"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @checked_actor(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // CHECK-LABEL: simulation.func @checked_actor
    // CHECK: %[[EPOCH:.*]] = simulation.context.storage %{{.*}}[0]
    // CHECK: simulation.ref.load %[[EPOCH]]
    // CHECK-NOT: simulation.assert.deferred_enqueue 1
    // CHECK: simulation.assert.deferred_enqueue 2
    // TRACE: regions @checked_actor valid=0
    simulation.func @checked_actor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      %epoch_ref = simulation.context.storage %ctx[0] : !simulation.ref<i32>
      %input = simulation.context.storage %ctx[1] : !simulation.ref<i20>
      %output = simulation.context.storage %ctx[2] : !simulation.ref<i20>
      %zero32 = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      %zero = arith.constant 0 : i20
      %v1 = arith.constant 0 : i20
      %v2 = arith.constant 2 : i20
      %mask = arith.constant 63 : i20
      %v32 = arith.constant 32 : i20
      %true = arith.constant true
      %false = arith.constant false
      cf.br ^body
    ^resume:
      %epoch = simulation.ref.load %epoch_ref : !simulation.ref<i32> -> i32
      %pending = arith.andi %epoch, %one : i32
      %armed = arith.cmpi ne, %pending, %zero32 : i32
      cf.cond_br %armed, ^flush, ^body
    ^flush:
      %next = arith.addi %epoch, %one : i32
      simulation.ref.store %next to %epoch_ref : i32, !simulation.ref<i32>
      cf.br ^body
    ^body:
      %x = simulation.ref.load %input : !simulation.ref<i20> -> i20
      %low = arith.andi %x, %mask : i20
      %low_match = arith.cmpi eq, %low, %v32 : i20
      %p0 = arith.cmpi eq, %x, %zero : i20
      %low_count = arith.extui %low_match : i1 to i32
      %zero_count = arith.extui %p0 : i1 to i32
      %first_count = arith.addi %low_count, %zero_count : i32
      %first_multi = arith.cmpi sgt, %first_count, %one : i32
      cf.cond_br %first_multi, ^report1, ^second
    ^report1:
      %ticket1 = simulation.assert.deferred_enqueue 1 {simulation.deferred_epoch_storage = 0 : i64}
      %old1 = simulation.ref.load %epoch_ref : !simulation.ref<i32> -> i32
      %armed1 = arith.ori %old1, %one : i32
      simulation.ref.store %armed1 to %epoch_ref : i32, !simulation.ref<i32>
      cf.br ^second
    ^second:
      %p1 = arith.cmpi eq, %x, %v1 : i20
      cf.cond_br %p1, ^join(%true : i1), ^next_test
    ^next_test:
      %p2 = arith.cmpi eq, %x, %v2 : i20
      cf.cond_br %p2, ^join(%true : i1), ^join(%false : i1)
    ^join(%group: i1):
      %increment = arith.addi %zero_count, %one : i32
      %second_count = arith.select %group, %increment, %zero_count : i32
      %second_multi = arith.cmpi sgt, %second_count, %one : i32
      cf.cond_br %second_multi, ^report2, ^finish
    ^report2:
      %ticket2 = simulation.assert.deferred_enqueue 2 {simulation.deferred_epoch_storage = 0 : i64}
      %old2 = simulation.ref.load %epoch_ref : !simulation.ref<i32> -> i32
      %armed2 = arith.ori %old2, %one : i32
      simulation.ref.store %armed2 to %epoch_ref : i32, !simulation.ref<i32>
      cf.br ^finish
    ^finish:
      simulation.ref.store %x to %output : i20, !simulation.ref<i20>
      simulation.suspend.change %input to ^resume : !simulation.ref<i20>
    }
  }
}
