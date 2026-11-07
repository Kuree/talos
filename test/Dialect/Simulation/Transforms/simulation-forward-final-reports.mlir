// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{closed-model=true}))' -o %t
// RUN: FileCheck %s < %t
// RUN: talos-opt %s --split-input-file --mlir-disable-threading --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{closed-model=true}))' -o %t.serial
// RUN: diff %t %t.serial
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{census=true closed-model=true}))' 2>/dev/null | FileCheck %s --check-prefix=CENSUS

// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes))' | FileCheck %s --check-prefix=OPEN

// OPEN-LABEL: simulation.design @settled_final
// OPEN: simulation.assert.deferred_enqueue 1
// OPEN: simulation.spawn @report

// IEEE 1800-2023 16.4-16.4.2: p != a can fail in Active while the
// continuous p = !a is pending, but every such failure flushes before
// Postponed. Its direct predicate inputs are both in the original wait.
// This is a terminal-report proof, not an Active equality for p.
// CHECK-LABEL: simulation.design @settled_final
// CHECK: simulation.func private @monitor(
// CHECK: arith.cmpi ne
// CHECK-NOT: simulation.assert.deferred_enqueue
// CHECK-NOT: simulation.spawn @report
// CHECK: simulation.suspend.any
// CENSUS: simulation.assert.deferred_enqueue 1
// CENSUS: simulation.spawn @report
module {
  simulation.design @settled_final {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %true = arith.constant true
      cf.br ^body
    ^body:
      %v = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %not = arith.xori %v, %true : i1
      simulation.ref.store %not to %p : i1, !simulation.ref<i1>
      simulation.suspend.change %a to ^body : !simulation.ref<i1>
    }
    simulation.func private @monitor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      cf.br ^body
    ^resume:
      %old = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %bit = arith.andi %old, %one : i32
      %pending = arith.cmpi ne, %bit, %zero : i32
      cf.cond_br %pending, ^flush, ^body
    ^flush:
      %next = arith.addi %old, %one : i32
      simulation.ref.store %next to %epoch : i32, !simulation.ref<i32>
      cf.br ^body
    ^body:
      %av = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %pv = simulation.ref.load %p : !simulation.ref<i1> -> i1
      %ok = arith.cmpi ne, %pv, %av : i1
      cf.cond_br %ok, ^wait, ^fail
    ^fail:
      %ticket = simulation.assert.deferred_enqueue 1 {simulation.deferred_epoch_storage = 2 : i64}
      %previous = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %armed = arith.ori %previous, %one : i32
      simulation.ref.store %armed to %epoch : i32, !simulation.ref<i32>
      %child = simulation.spawn @report(%ctx, %ticket, %armed) : !simulation.context, i64, i32 -> !simulation.process
      cf.br ^wait
    ^wait:
      simulation.suspend.any %a, %p edges [0, 0] to ^resume {schedule.procedural_event_wait} : !simulation.ref<i1>, !simulation.ref<i1>
    }
    simulation.func private @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %ticket: i64 {simulation.capture_kind = 1 : i32}, %captured: i32 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64, home_region = 16 : i32} {
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %mature = simulation.assert.deferred_mature %ticket : i64
      %current = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %same = arith.cmpi eq, %current, %captured : i32
      %valid = arith.andi %mature, %same : i1
      cf.cond_br %valid, ^report, ^done
    ^report:
      %text = simulation.bytes.constant "unexpected final failure"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%text) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      simulation.return
    ^done:
      simulation.return
    }
  }
}

// -----

// Compose the wrap/nowrap/select equations with shared canonical leaves.
// Quantify arbitrary ptr_r bits, including the nominally out-of-range value3;
// no reset-reachability assumption is needed. A 2-bit addend permits overflow
// and must keep its report. Also cover a nonzero-offset cutpoint and packed
// two-state types in this recursive arithmetic proof.
// CHECK-LABEL: simulation.design @pointer_wrap
// CHECK: simulation.func private @monitor(
// CHECK-NOT: simulation.assert.deferred_enqueue
// CHECK-NOT: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @pointer_wrap {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i2 design
    simulation.storage.decl 1 in 0 : i2 design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.storage.decl 4 in 0 : i3 design
    simulation.storage.decl 5 in 0 : i2 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.code_unit.decl 5 in 0 continuous hierarchy "wrap"
    simulation.code_unit.decl 6 in 0 continuous hierarchy "nowrap"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @wrap(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @nowrap(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %w = simulation.context.storage %ctx[4] : !simulation.ref<i3>
      %n = simulation.context.storage %ctx[5] : !simulation.ref<i2>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i2>
      %zero = arith.constant 0 : i3
      cf.br ^body
    ^body:
      %wrap = simulation.ref.load %w : !simulation.ref<i3> -> i3
      %nowrap = simulation.ref.load %n : !simulation.ref<i2> -> i2
      %lo = arith.trunci %wrap : i3 to i2
      %negative = arith.cmpi slt, %wrap, %zero : i3
      %value = arith.select %negative, %nowrap, %lo : i2
      simulation.ref.store %value to %p : i2, !simulation.ref<i2>
      simulation.suspend.any %w, %n edges [0, 0] to ^body : !simulation.ref<i3>, !simulation.ref<i2>
    }
    simulation.func private @monitor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i2>
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      cf.br ^body
    ^resume:
      %old = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %bit = arith.andi %old, %one : i32
      %pending = arith.cmpi ne, %bit, %zero : i32
      cf.cond_br %pending, ^flush, ^body
    ^flush:
      %next = arith.addi %old, %one : i32
      simulation.ref.store %next to %epoch : i32, !simulation.ref<i32>
      cf.br ^body
    ^body:
      %pv = simulation.ref.load %p : !simulation.ref<i2> -> i2
      %limit = arith.constant 3 : i2
      %ok = arith.cmpi ult, %pv, %limit : i2
      cf.cond_br %ok, ^wait, ^fail
    ^fail:
      %ticket = simulation.assert.deferred_enqueue 1 {simulation.deferred_epoch_storage = 2 : i64}
      %previous = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %armed = arith.ori %previous, %one : i32
      simulation.ref.store %armed to %epoch : i32, !simulation.ref<i32>
      %child = simulation.spawn @report(%ctx, %ticket, %armed) : !simulation.context, i64, i32 -> !simulation.process
      cf.br ^wait
    ^wait:
      simulation.suspend.any %p edges [0] to ^resume {schedule.procedural_event_wait} : !simulation.ref<i2>
    }
    simulation.func private @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %ticket: i64 {simulation.capture_kind = 1 : i32}, %captured: i32 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64, home_region = 16 : i32} {
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %mature = simulation.assert.deferred_mature %ticket : i64
      %current = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %same = arith.cmpi eq, %current, %captured : i32
      %valid = arith.andi %mature, %same : i1
      cf.cond_br %valid, ^report, ^done
    ^report:
      %text = simulation.bytes.constant "unexpected final failure"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%text) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      simulation.return
    ^done:
      simulation.return
    }
    simulation.func private @wrap(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %a = simulation.context.storage %ctx[3] : !simulation.ref<i1>
      %w = simulation.context.storage %ctx[4] : !simulation.ref<i3>
      %slots = arith.constant 3 : i3
      cf.br ^body
    ^body:
      %rv = simulation.ref.load %r : !simulation.ref<i2> -> i2
      %av = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %r3 = arith.extui %rv : i2 to i3
      %a3 = arith.extui %av : i1 to i3
      %offset = arith.subi %r3, %slots : i3
      %value = arith.addi %offset, %a3 : i3
      simulation.ref.store %value to %w : i3, !simulation.ref<i3>
      simulation.suspend.any %r, %a edges [0, 0] to ^body : !simulation.ref<i2>, !simulation.ref<i1>
    }
    simulation.func private @nowrap(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 6 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %a = simulation.context.storage %ctx[3] : !simulation.ref<i1>
      %w = simulation.context.storage %ctx[5] : !simulation.ref<i2>
      cf.br ^body
    ^body:
      %rv = simulation.ref.load %r : !simulation.ref<i2> -> i2
      %av = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %a2 = arith.extui %av : i1 to i2
      %value = arith.addi %rv, %a2 : i2
      simulation.ref.store %value to %w : i2, !simulation.ref<i2>
      simulation.suspend.any %r, %a edges [0, 0] to ^body : !simulation.ref<i2>, !simulation.ref<i1>
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @pointer_overflow
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @pointer_overflow {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i2 design
    simulation.storage.decl 1 in 0 : i2 design
    simulation.storage.decl 3 in 0 : i2 design
    simulation.storage.decl 4 in 0 : i3 design
    simulation.storage.decl 5 in 0 : i2 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.code_unit.decl 5 in 0 continuous hierarchy "wrap"
    simulation.code_unit.decl 6 in 0 continuous hierarchy "nowrap"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @wrap(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @nowrap(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %w = simulation.context.storage %ctx[4] : !simulation.ref<i3>
      %n = simulation.context.storage %ctx[5] : !simulation.ref<i2>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i2>
      %zero = arith.constant 0 : i3
      cf.br ^body
    ^body:
      %wrap = simulation.ref.load %w : !simulation.ref<i3> -> i3
      %nowrap = simulation.ref.load %n : !simulation.ref<i2> -> i2
      %lo = arith.trunci %wrap : i3 to i2
      %negative = arith.cmpi slt, %wrap, %zero : i3
      %value = arith.select %negative, %nowrap, %lo : i2
      simulation.ref.store %value to %p : i2, !simulation.ref<i2>
      simulation.suspend.any %w, %n edges [0, 0] to ^body : !simulation.ref<i3>, !simulation.ref<i2>
    }
    simulation.func private @monitor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i2>
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      cf.br ^body
    ^resume:
      %old = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %bit = arith.andi %old, %one : i32
      %pending = arith.cmpi ne, %bit, %zero : i32
      cf.cond_br %pending, ^flush, ^body
    ^flush:
      %next = arith.addi %old, %one : i32
      simulation.ref.store %next to %epoch : i32, !simulation.ref<i32>
      cf.br ^body
    ^body:
      %pv = simulation.ref.load %p : !simulation.ref<i2> -> i2
      %limit = arith.constant 3 : i2
      %ok = arith.cmpi ult, %pv, %limit : i2
      cf.cond_br %ok, ^wait, ^fail
    ^fail:
      %ticket = simulation.assert.deferred_enqueue 1 {simulation.deferred_epoch_storage = 2 : i64}
      %previous = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %armed = arith.ori %previous, %one : i32
      simulation.ref.store %armed to %epoch : i32, !simulation.ref<i32>
      %child = simulation.spawn @report(%ctx, %ticket, %armed) : !simulation.context, i64, i32 -> !simulation.process
      cf.br ^wait
    ^wait:
      simulation.suspend.any %p edges [0] to ^resume {schedule.procedural_event_wait} : !simulation.ref<i2>
    }
    simulation.func private @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %ticket: i64 {simulation.capture_kind = 1 : i32}, %captured: i32 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64, home_region = 16 : i32} {
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %mature = simulation.assert.deferred_mature %ticket : i64
      %current = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %same = arith.cmpi eq, %current, %captured : i32
      %valid = arith.andi %mature, %same : i1
      cf.cond_br %valid, ^report, ^done
    ^report:
      %text = simulation.bytes.constant "unexpected final failure"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%text) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      simulation.return
    ^done:
      simulation.return
    }
    simulation.func private @wrap(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %a = simulation.context.storage %ctx[3] : !simulation.ref<i2>
      %w = simulation.context.storage %ctx[4] : !simulation.ref<i3>
      %slots = arith.constant 3 : i3
      cf.br ^body
    ^body:
      %rv = simulation.ref.load %r : !simulation.ref<i2> -> i2
      %av = simulation.ref.load %a : !simulation.ref<i2> -> i2
      %r3 = arith.extui %rv : i2 to i3
      %a3 = arith.extui %av : i2 to i3
      %offset = arith.subi %r3, %slots : i3
      %value = arith.addi %offset, %a3 : i3
      simulation.ref.store %value to %w : i3, !simulation.ref<i3>
      simulation.suspend.any %r, %a edges [0, 0] to ^body : !simulation.ref<i2>, !simulation.ref<i2>
    }
    simulation.func private @nowrap(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 6 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %a = simulation.context.storage %ctx[3] : !simulation.ref<i2>
      %w = simulation.context.storage %ctx[5] : !simulation.ref<i2>
      cf.br ^body
    ^body:
      %rv = simulation.ref.load %r : !simulation.ref<i2> -> i2
      %av = simulation.ref.load %a : !simulation.ref<i2> -> i2
      %value = arith.addi %rv, %av : i2
      simulation.ref.store %value to %w : i2, !simulation.ref<i2>
      simulation.suspend.any %r, %a edges [0, 0] to ^body : !simulation.ref<i2>, !simulation.ref<i2>
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @pointer_slice
// CHECK: simulation.func private @monitor(
// CHECK-NOT: simulation.assert.deferred_enqueue
// CHECK-NOT: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @pointer_slice {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i2 design
    simulation.storage.decl 1 in 0 : i2 design
    simulation.storage.decl 3 in 0 : i2 design
    simulation.storage.decl 4 in 0 : i3 design
    simulation.storage.decl 5 in 0 : i2 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.code_unit.decl 5 in 0 continuous hierarchy "wrap"
    simulation.code_unit.decl 6 in 0 continuous hierarchy "nowrap"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @wrap(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @nowrap(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %w = simulation.context.storage %ctx[4] : !simulation.ref<i3>
      %n = simulation.context.storage %ctx[5] : !simulation.ref<i2>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i2>
      %zero = arith.constant 0 : i3
      cf.br ^body
    ^body:
      %wrap = simulation.ref.load %w : !simulation.ref<i3> -> i3
      %nowrap = simulation.ref.load %n : !simulation.ref<i2> -> i2
      %lo = arith.trunci %wrap : i3 to i2
      %negative = arith.cmpi slt, %wrap, %zero : i3
      %value = arith.select %negative, %nowrap, %lo : i2
      simulation.ref.store %value to %p : i2, !simulation.ref<i2>
      simulation.suspend.any %w, %n edges [0, 0] to ^body : !simulation.ref<i3>, !simulation.ref<i2>
    }
    simulation.func private @monitor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i2>
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      cf.br ^body
    ^resume:
      %old = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %bit = arith.andi %old, %one : i32
      %pending = arith.cmpi ne, %bit, %zero : i32
      cf.cond_br %pending, ^flush, ^body
    ^flush:
      %next = arith.addi %old, %one : i32
      simulation.ref.store %next to %epoch : i32, !simulation.ref<i32>
      cf.br ^body
    ^body:
      %pv = simulation.ref.load %p : !simulation.ref<i2> -> i2
      %limit = arith.constant 3 : i2
      %ok = arith.cmpi ult, %pv, %limit : i2
      cf.cond_br %ok, ^wait, ^fail
    ^fail:
      %ticket = simulation.assert.deferred_enqueue 1 {simulation.deferred_epoch_storage = 2 : i64}
      %previous = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %armed = arith.ori %previous, %one : i32
      simulation.ref.store %armed to %epoch : i32, !simulation.ref<i32>
      %child = simulation.spawn @report(%ctx, %ticket, %armed) : !simulation.context, i64, i32 -> !simulation.process
      cf.br ^wait
    ^wait:
      simulation.suspend.any %p edges [0] to ^resume {schedule.procedural_event_wait} : !simulation.ref<i2>
    }
    simulation.func private @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %ticket: i64 {simulation.capture_kind = 1 : i32}, %captured: i32 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64, home_region = 16 : i32} {
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %mature = simulation.assert.deferred_mature %ticket : i64
      %current = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %same = arith.cmpi eq, %current, %captured : i32
      %valid = arith.andi %mature, %same : i1
      cf.cond_br %valid, ^report, ^done
    ^report:
      %text = simulation.bytes.constant "unexpected final failure"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%text) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      simulation.return
    ^done:
      simulation.return
    }
    simulation.func private @wrap(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %whole = simulation.context.storage %ctx[3] : !simulation.ref<i2>
      %a = simulation.ref.extract %whole from 1 : !simulation.ref<i2> -> !simulation.ref<i1>
      %w = simulation.context.storage %ctx[4] : !simulation.ref<i3>
      %slots = arith.constant 3 : i3
      cf.br ^body
    ^body:
      %rv = simulation.ref.load %r : !simulation.ref<i2> -> i2
      %av = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %r3 = arith.extui %rv : i2 to i3
      %a3 = arith.extui %av : i1 to i3
      %offset = arith.subi %r3, %slots : i3
      %value = arith.addi %offset, %a3 : i3
      simulation.ref.store %value to %w : i3, !simulation.ref<i3>
      simulation.suspend.any %r, %a edges [0, 0] to ^body : !simulation.ref<i2>, !simulation.ref<i1>
    }
    simulation.func private @nowrap(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 6 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<i2>
      %whole = simulation.context.storage %ctx[3] : !simulation.ref<i2>
      %a = simulation.ref.extract %whole from 1 : !simulation.ref<i2> -> !simulation.ref<i1>
      %w = simulation.context.storage %ctx[5] : !simulation.ref<i2>
      cf.br ^body
    ^body:
      %rv = simulation.ref.load %r : !simulation.ref<i2> -> i2
      %av = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %a2 = arith.extui %av : i1 to i2
      %value = arith.addi %rv, %a2 : i2
      simulation.ref.store %value to %w : i2, !simulation.ref<i2>
      simulation.suspend.any %r, %a edges [0, 0] to ^body : !simulation.ref<i2>, !simulation.ref<i1>
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @packed_pointer_wrap
// CHECK: simulation.func private @monitor(
// CHECK-NOT: simulation.assert.deferred_enqueue
// CHECK-NOT: simulation.spawn @report
// CHECK: simulation.suspend.any
!p1 = !simulation.packed_array<0 : 0 x i1>
!p2 = !simulation.packed_array<1 : 0 x i1>
!p3 = !simulation.packed_array<2 : 0 x i1>
module {
  simulation.design @packed_pointer_wrap {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !p2 design
    simulation.storage.decl 1 in 0 : !p2 design
    simulation.storage.decl 3 in 0 : !p1 design
    simulation.storage.decl 4 in 0 : !p3 design
    simulation.storage.decl 5 in 0 : !p2 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.code_unit.decl 5 in 0 continuous hierarchy "wrap"
    simulation.code_unit.decl 6 in 0 continuous hierarchy "nowrap"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @wrap(%ctx) : !simulation.context -> !simulation.process
      %p3 = simulation.spawn @nowrap(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %w = simulation.context.storage %ctx[4] : !simulation.ref<!p3>
      %n = simulation.context.storage %ctx[5] : !simulation.ref<!p2>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<!p2>
      %zero = arith.constant 0 : i3
      cf.br ^body
    ^body:
      %wrap_raw = simulation.ref.load %w : !simulation.ref<!p3> -> !p3
      %wrap = simulation.packed.flatten %wrap_raw : (!p3) -> i3
      %nowrap_raw = simulation.ref.load %n : !simulation.ref<!p2> -> !p2
      %nowrap = simulation.packed.flatten %nowrap_raw : (!p2) -> i2
      %lo = arith.trunci %wrap : i3 to i2
      %negative = arith.cmpi slt, %wrap, %zero : i3
      %value = arith.select %negative, %nowrap, %lo : i2
      %value_packed = simulation.packed.unflatten %value : (i2) -> !p2
      simulation.ref.store %value_packed to %p : !p2, !simulation.ref<!p2>
      simulation.suspend.any %w, %n edges [0, 0] to ^body : !simulation.ref<!p3>, !simulation.ref<!p2>
    }
    simulation.func private @monitor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<!p2>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<!p2>
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      cf.br ^body
    ^resume:
      %old = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %bit = arith.andi %old, %one : i32
      %pending = arith.cmpi ne, %bit, %zero : i32
      cf.cond_br %pending, ^flush, ^body
    ^flush:
      %next = arith.addi %old, %one : i32
      simulation.ref.store %next to %epoch : i32, !simulation.ref<i32>
      cf.br ^body
    ^body:
      %pv_raw = simulation.ref.load %p : !simulation.ref<!p2> -> !p2
      %pv = simulation.packed.flatten %pv_raw : (!p2) -> i2
      %limit = arith.constant 3 : i2
      %ok = arith.cmpi ult, %pv, %limit : i2
      cf.cond_br %ok, ^wait, ^fail
    ^fail:
      %ticket = simulation.assert.deferred_enqueue 1 {simulation.deferred_epoch_storage = 2 : i64}
      %previous = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %armed = arith.ori %previous, %one : i32
      simulation.ref.store %armed to %epoch : i32, !simulation.ref<i32>
      %child = simulation.spawn @report(%ctx, %ticket, %armed) : !simulation.context, i64, i32 -> !simulation.process
      cf.br ^wait
    ^wait:
      simulation.suspend.any %p edges [0] to ^resume {schedule.procedural_event_wait} : !simulation.ref<!p2>
    }
    simulation.func private @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %ticket: i64 {simulation.capture_kind = 1 : i32}, %captured: i32 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64, home_region = 16 : i32} {
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %mature = simulation.assert.deferred_mature %ticket : i64
      %current = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %same = arith.cmpi eq, %current, %captured : i32
      %valid = arith.andi %mature, %same : i1
      cf.cond_br %valid, ^report, ^done
    ^report:
      %text = simulation.bytes.constant "unexpected final failure"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%text) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      simulation.return
    ^done:
      simulation.return
    }
    simulation.func private @wrap(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!p2>
      %a = simulation.context.storage %ctx[3] : !simulation.ref<!p1>
      %w = simulation.context.storage %ctx[4] : !simulation.ref<!p3>
      %slots = arith.constant 3 : i3
      cf.br ^body
    ^body:
      %rv_raw = simulation.ref.load %r : !simulation.ref<!p2> -> !p2
      %rv = simulation.packed.flatten %rv_raw : (!p2) -> i2
      %av_raw = simulation.ref.load %a : !simulation.ref<!p1> -> !p1
      %av = simulation.packed.flatten %av_raw : (!p1) -> i1
      %r3 = arith.extui %rv : i2 to i3
      %a3 = arith.extui %av : i1 to i3
      %offset = arith.subi %r3, %slots : i3
      %value = arith.addi %offset, %a3 : i3
      %value_packed = simulation.packed.unflatten %value : (i3) -> !p3
      simulation.ref.store %value_packed to %w : !p3, !simulation.ref<!p3>
      simulation.suspend.any %r, %a edges [0, 0] to ^body : !simulation.ref<!p2>, !simulation.ref<!p1>
    }
    simulation.func private @nowrap(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 6 : i64} {
      %r = simulation.context.storage %ctx[0] : !simulation.ref<!p2>
      %a = simulation.context.storage %ctx[3] : !simulation.ref<!p1>
      %w = simulation.context.storage %ctx[5] : !simulation.ref<!p2>
      cf.br ^body
    ^body:
      %rv_raw = simulation.ref.load %r : !simulation.ref<!p2> -> !p2
      %rv = simulation.packed.flatten %rv_raw : (!p2) -> i2
      %av_raw = simulation.ref.load %a : !simulation.ref<!p1> -> !p1
      %av = simulation.packed.flatten %av_raw : (!p1) -> i1
      %a2 = arith.extui %av : i1 to i2
      %value = arith.addi %rv, %a2 : i2
      %value_packed = simulation.packed.unflatten %value : (i2) -> !p2
      simulation.ref.store %value_packed to %w : !p2, !simulation.ref<!p2>
      simulation.suspend.any %r, %a edges [0, 0] to ^body : !simulation.ref<!p2>, !simulation.ref<!p1>
    }
  }
}

// -----

// CHECK-LABEL: simulation.design @constant_query_export
// CHECK: simulation.func private @monitor(
// CHECK-NOT: simulation.assert.deferred_enqueue
// CHECK-NOT: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @constant_query_export {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.code_unit.decl 5 in 0 initial hierarchy "host"
    simulation.code_unit.decl 6 in 0 function hierarchy "period"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @host(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %true = arith.constant true
      cf.br ^body
    ^body:
      %v = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %not = arith.xori %v, %true : i1
      simulation.ref.store %not to %p : i1, !simulation.ref<i1>
      simulation.suspend.change %a to ^body : !simulation.ref<i1>
    }
    simulation.func private @monitor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %zero = arith.constant 0 : i32
      %one = arith.constant 1 : i32
      cf.br ^body
    ^resume:
      %old = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %bit = arith.andi %old, %one : i32
      %pending = arith.cmpi ne, %bit, %zero : i32
      cf.cond_br %pending, ^flush, ^body
    ^flush:
      %next = arith.addi %old, %one : i32
      simulation.ref.store %next to %epoch : i32, !simulation.ref<i32>
      cf.br ^body
    ^body:
      %av = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %pv = simulation.ref.load %p : !simulation.ref<i1> -> i1
      %ok = arith.cmpi ne, %pv, %av : i1
      cf.cond_br %ok, ^wait, ^fail
    ^fail:
      %ticket = simulation.assert.deferred_enqueue 1 {simulation.deferred_epoch_storage = 2 : i64}
      %previous = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %armed = arith.ori %previous, %one : i32
      simulation.ref.store %armed to %epoch : i32, !simulation.ref<i32>
      %child = simulation.spawn @report(%ctx, %ticket, %armed) : !simulation.context, i64, i32 -> !simulation.process
      cf.br ^wait
    ^wait:
      simulation.suspend.any %a, %p edges [0, 0] to ^resume {schedule.procedural_event_wait} : !simulation.ref<i1>, !simulation.ref<i1>
    }
    simulation.func private @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %ticket: i64 {simulation.capture_kind = 1 : i32}, %captured: i32 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64, home_region = 16 : i32} {
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %mature = simulation.assert.deferred_mature %ticket : i64
      %current = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %same = arith.cmpi eq, %current, %captured : i32
      %valid = arith.andi %mature, %same : i1
      cf.cond_br %valid, ^report, ^done
    ^report:
      %text = simulation.bytes.constant "unexpected final failure"
      %stdout = arith.constant -2147483647 : i32
      simulation.display %ctx to %stdout(%text) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      simulation.return
    ^done:
      simulation.return
    }
    simulation.func private @host(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %status = simulation.dpi.call "start" id 1 scope 0 context %ctx : !simulation.context() {abi_signature = [], is_context = true, is_pure = false, is_task = false, source_column = 1 : i32, source_file = "host.sv", source_line = 1 : i32} : () -> !runtime.status
      simulation.return
    }
    simulation.func @period(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i32 attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64, dpi.export, dpi.c_identifier = "get_period", dpi.export_id = 7 : i32, dpi.scope_id = 0 : i64, dpi.logical_inputs = 0 : i32, dpi.abi_signature = [#dpi.abi<kind = int, direction = result, width = 32, fourState = false, isSigned = true>]} {
      %period = arith.constant 1000 : i32
      simulation.return %period : i32
    }
  }
}
