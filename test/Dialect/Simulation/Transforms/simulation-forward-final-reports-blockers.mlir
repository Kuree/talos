// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{closed-model=true}))' -o %t
// RUN: FileCheck %s < %t
// RUN: talos-opt %s --split-input-file --mlir-disable-threading --pass-pipeline='builtin.module(simulation.design(talos-sim-forward-copy-processes{closed-model=true}))' -o %t.serial
// RUN: diff %t %t.serial

// Unsupported final-report proofs retain their event and report paths.
// An Observed report is outside the final-report certificate (16.4.1).
// CHECK-LABEL: simulation.design @observed_report
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @observed_report {
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
    simulation.func private @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %ticket: i64 {simulation.capture_kind = 1 : i32}, %captured: i32 {simulation.capture_kind = 1 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 4 : i64, home_region = 8 : i32} {
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

// A later change in p must resume and flush the original process (16.4.2).
// CHECK-LABEL: simulation.design @missing_sensitivity
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @missing_sensitivity {
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
      simulation.suspend.any %p edges [0] to ^resume {schedule.procedural_event_wait} : !simulation.ref<i1>
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

// The private epoch must actually invalidate a pending callback on resumption.
// CHECK-LABEL: simulation.design @missing_flush
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @missing_flush {
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
      %next = arith.addi %old, %zero : i32
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

// An ordinary surviving final failure cannot be removed.
// CHECK-LABEL: simulation.design @live_failure
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @live_failure {
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
      %ok = arith.cmpi eq, %pv, %av : i1
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

// A delayed publication is not a same-slot continuous equation (4.9.1).
// CHECK-LABEL: simulation.design @delayed_producer
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @delayed_producer {
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
      %delay = simulation.time.constant 1
      %true = arith.constant true
      cf.br ^body
    ^body:
      %v = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %not = arith.xori %v, %true : i1
      simulation.suspend.delay %delay to ^publish
    ^publish:
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

// An unassigned lane is not supplied by an incomplete producer (6.5).
// CHECK-LABEL: simulation.design @incomplete_producer
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @incomplete_producer {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i2 design
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
      %whole = simulation.context.storage %ctx[1] : !simulation.ref<i2>
      %p = simulation.ref.extract %whole from 0 : !simulation.ref<i2> -> !simulation.ref<i1>
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
      %av = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %pv = simulation.ref.load %p : !simulation.ref<i2> -> i2
      %limit = arith.constant 2 : i2
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
      simulation.suspend.any %a, %p edges [0, 0] to ^resume {schedule.procedural_event_wait} : !simulation.ref<i1>, !simulation.ref<i2>
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

// An independent writer invalidates the continuous equation (6.5).
// CHECK-LABEL: simulation.design @multiple_writers
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @multiple_writers {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @other(%ctx) : !simulation.context -> !simulation.process
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
    simulation.func private @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %zero = arith.constant false
      simulation.ref.store %zero to %p : i1, !simulation.ref<i1>
      simulation.return
    }
  }
}

// -----

// A cycle has no acyclic producer expansion certificate.
// CHECK-LABEL: simulation.design @cyclic_producers
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @cyclic_producers {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.code_unit.decl 5 in 0 continuous hierarchy "cycle"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @cycle(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @producer(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @producer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      %a = simulation.context.storage %ctx[3] : !simulation.ref<i1>
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
    simulation.func private @cycle(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %q = simulation.context.storage %ctx[3] : !simulation.ref<i1>
      cf.br ^body
    ^body:
      %v = simulation.ref.load %p : !simulation.ref<i1> -> i1
      simulation.ref.store %v to %q : i1, !simulation.ref<i1>
      simulation.suspend.change %p to ^body : !simulation.ref<i1>
    }
  }
}

// -----

// Action argument evaluation effects occur in Active even for canceled reports (16.4).
// CHECK-LABEL: simulation.design @argument_effect
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @argument_effect {
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
      %fmt = simulation.bytes.constant "argument effect"
      %fd = arith.constant -2147483647 : i32
      simulation.display %ctx to %fd(%fmt) newline = true radix = <decimal> flags = [0] : !simulation.bytes
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

// Four-state cutpoints retain their uncertainty and report paths.
// CHECK-LABEL: simulation.design @four_state_cutpoint
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @four_state_cutpoint {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.logic<1> design
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
      %a = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<1>>
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %true = arith.constant true
      cf.br ^body
    ^body:
      %raw = simulation.ref.load %a : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %v = simulation.logic.to_bits %raw : !simulation.logic<1> -> i1
      %not = arith.xori %v, %true : i1
      simulation.ref.store %not to %p : i1, !simulation.ref<i1>
      simulation.suspend.change %a to ^body : !simulation.ref<!simulation.logic<1>>
    }
    simulation.func private @monitor(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      %a = simulation.context.storage %ctx[0] : !simulation.ref<!simulation.logic<1>>
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
      %raw = simulation.ref.load %a : !simulation.ref<!simulation.logic<1>> -> !simulation.logic<1>
      %av = simulation.logic.to_bits %raw : !simulation.logic<1> -> i1
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
      simulation.suspend.any %a, %p edges [0, 0] to ^resume {schedule.procedural_event_wait} : !simulation.ref<!simulation.logic<1>>, !simulation.ref<i1>
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

// A live second report preserves the shared epoch and its existing flush.
// CHECK-LABEL: simulation.design @shared_live_report
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @shared_live_report {
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
      %live = simulation.assert.deferred_enqueue 2 {simulation.deferred_epoch_storage = 2 : i64}
      %before_live = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %arm_live = arith.ori %before_live, %one : i32
      simulation.ref.store %arm_live to %epoch : i32, !simulation.ref<i32>
      %live_child = simulation.spawn @report(%ctx, %live, %arm_live) : !simulation.context, i64, i32 -> !simulation.process
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

// An entry snapshot is not a fresh queue epoch after the original wait.
// CHECK-LABEL: simulation.design @stale_flush_snapshot
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @stale_flush_snapshot {
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
      %old = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      cf.br ^body
    ^resume:
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

// An entry snapshot does not become the settled value when a watched root changes.
// CHECK-LABEL: simulation.design @stale_predicate_snapshot
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @stale_predicate_snapshot {
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
      %av = simulation.ref.load %a : !simulation.ref<i1> -> i1
      %pv = simulation.ref.load %p : !simulation.ref<i1> -> i1
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

// An outside process that observes the private epoch retains its arm.
// CHECK-LABEL: simulation.design @loaded_epoch_display
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @loaded_epoch_display {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.code_unit.decl 5 in 0 initial hierarchy "observe"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @observe(%ctx) : !simulation.context -> !simulation.process
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
    simulation.func private @observe(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %epoch = simulation.context.storage %ctx[2] : !simulation.ref<i32>
      %value = simulation.ref.load %epoch : !simulation.ref<i32> -> i32
      %fmt = simulation.bytes.constant "%0d"
      %fd = arith.constant -2147483647 : i32
      simulation.display %ctx to %fd(%fmt, %value) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i32
      simulation.return
    }
  }
}

// -----

// An alias store with a different handle family invalidates exclusive ownership.
// CHECK-LABEL: simulation.design @unmodeled_writer
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @unmodeled_writer {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.code_unit.decl 5 in 0 initial hierarchy "alias"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @alias(%ctx) : !simulation.context -> !simulation.process
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
    simulation.func private @alias(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %erased = simulation.argument_ref.from_ref %p : !simulation.ref<i1> -> !simulation.argument_ref<i1>
      %zero = arith.constant false
      simulation.argument_ref.store %zero to %erased : i1, !simulation.argument_ref<i1>
      simulation.return
    }
  }
}

// -----

// A home-Active monitor with a Reactive resumption retains its report.
// CHECK-LABEL: simulation.design @reactive_monitor_resume
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @reactive_monitor_resume {
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
      simulation.suspend.any %a, %p edges [0, 0] to ^resume {schedule.procedural_event_wait, resume_region = 10 : i32} : !simulation.ref<i1>, !simulation.ref<i1>
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

// An expanded equation must resume in Active as well as start there.
// CHECK-LABEL: simulation.design @reactive_producer_resume
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @reactive_producer_resume {
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
      simulation.suspend.change %a to ^body {resume_region = 10 : i32} : !simulation.ref<i1>
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

// A callback must honor cancellation of its opaque report ticket.
// CHECK-LABEL: simulation.design @missing_maturity_gate
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @missing_maturity_gate {
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
      %valid = arith.andi %same, %same : i1
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

// A callback must require the captured queue epoch to remain current.
// CHECK-LABEL: simulation.design @reversed_epoch_gate
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @reversed_epoch_gate {
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
      %same = arith.cmpi ne, %current, %captured : i32
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

// An unmodeled nonlocal control effect is a proof boundary.
// CHECK-LABEL: simulation.design @unmodeled_control_effect
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @unmodeled_control_effect {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "producer"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "monitor"
    simulation.code_unit.decl 4 in 0 fork hierarchy "report"
    simulation.code_unit.decl 5 in 0 initial hierarchy "escape"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p0 = simulation.spawn @monitor(%ctx) : !simulation.context -> !simulation.process
      %p2 = simulation.spawn @escape(%ctx) : !simulation.context -> !simulation.process
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
    simulation.func private @escape(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      simulation.control.nonlocal_exit 99
      simulation.return
    }
  }
}

// -----

// A context import may invoke an export that invalidates the producer equation (35.5.3).
// CHECK-LABEL: simulation.design @mutating_context_export
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @mutating_context_export {
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
      %p = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %false = arith.constant false
      simulation.ref.store %false to %p : i1, !simulation.ref<i1>
      simulation.return %period : i32
    }
  }
}

// -----

// A canceled callback still enters its gate; extra queue consumption is observable.
// CHECK-LABEL: simulation.design @extra_callback_effect
// CHECK: simulation.func private @monitor(
// CHECK: simulation.assert.deferred_enqueue
// CHECK: simulation.spawn @report
// CHECK: simulation.suspend.any
module {
  simulation.design @extra_callback_effect {
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
      %other_ticket = arith.constant 42 : i64
      %other = simulation.assert.deferred_mature %other_ticket : i64
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
