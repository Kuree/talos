// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-propagate-initialized-storage{vpi=off}))' | FileCheck %s

// IEEE 1800-2023 6.8, Table 6-7: an uninitialized two-state variable starts
// at 0. Its only write runs on an edge whose condition is false while every
// read sees 0, so no write ever runs and every read is 0. This is a
// deferred-report epoch whose reports were all proved impossible: it is only
// advanced once armed, and nothing arms it any more.

module {
  simulation.design @guarded {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "proc"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @proc(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // CHECK-LABEL: simulation.func @proc
    // CHECK-NOT: simulation.ref.load
    // CHECK: %[[ZERO:.*]] = arith.constant 0 : i32
    // CHECK: arith.andi %[[ZERO]]
    simulation.func @proc(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<i32>
      %epoch = simulation.ref.load %ref : !simulation.ref<i32> -> i32
      %bit = arith.andi %epoch, %c1 : i32
      %armed = arith.cmpi ne, %bit, %c0 : i32
      cf.cond_br %armed, ^bump, ^wait
    ^bump:
      %next = arith.addi %epoch, %c1 : i32
      simulation.ref.store %next to %ref : i32, !simulation.ref<i32>
      cf.br ^wait
    }
  }
}

// -----

// The write is not guarded: reads keep loading.

module {
  simulation.design @unguarded {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "proc"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @proc(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // CHECK-LABEL: simulation.func @proc
    // CHECK: simulation.ref.load
    simulation.func @proc(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %c1 = arith.constant 1 : i32
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<i32>
      %epoch = simulation.ref.load %ref : !simulation.ref<i32> -> i32
      %next = arith.addi %epoch, %c1 : i32
      simulation.ref.store %next to %ref : i32, !simulation.ref<i32>
      cf.br ^wait
    }
  }
}

// -----

// The guard holds at the initial value: the write runs and reads keep loading.

module {
  simulation.design @armed {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "proc"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @proc(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // CHECK-LABEL: simulation.func @proc
    // CHECK: simulation.ref.load
    simulation.func @proc(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<i32>
      %epoch = simulation.ref.load %ref : !simulation.ref<i32> -> i32
      %bit = arith.andi %epoch, %c1 : i32
      %even = arith.cmpi eq, %bit, %c0 : i32
      cf.cond_br %even, ^bump, ^wait
    ^bump:
      %next = arith.addi %epoch, %c1 : i32
      simulation.ref.store %next to %ref : i32, !simulation.ref<i32>
      cf.br ^wait
    }
  }
}

// -----

// A constant initializer precedes every process; the later write runs only
// when the value differs from it, so every read sees the initializer.

module {
  simulation.design @initialized {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "proc"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<i32>
      %five = arith.constant 5 : i32
      simulation.ref.store %five to %ref : i32, !simulation.ref<i32>
      %p = simulation.spawn @proc(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // CHECK-LABEL: simulation.func @proc
    // CHECK-NOT: simulation.ref.load
    // CHECK: arith.constant 5 : i32
    simulation.func @proc(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %c5 = arith.constant 5 : i32
      %c9 = arith.constant 9 : i32
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<i32>
      %value = simulation.ref.load %ref : !simulation.ref<i32> -> i32
      %changed = arith.cmpi ne, %value, %c5 : i32
      cf.cond_br %changed, ^reset, ^wait
    ^reset:
      simulation.ref.store %c9 to %ref : i32, !simulation.ref<i32>
      cf.br ^wait
    }
  }
}

// -----

// Never written: two-state storage keeps its default 0 (Table 6-7). A
// four-state one starts at X, which this pass only propagates from an
// initializer, so its read stays.

module {
  simulation.design @unwritten {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i8 design
    simulation.storage.decl 1 in 0 : !simulation.logic<8> design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "proc"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @proc(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // CHECK-LABEL: simulation.func @proc
    // CHECK: arith.constant 0 : i8
    // CHECK: simulation.ref.load %{{.*}} : !simulation.ref<!simulation.logic<8>>
    // CHECK-NOT: simulation.ref.load
    simulation.func @proc(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %two = simulation.context.storage %ctx[0] : !simulation.ref<i8>
      %four = simulation.context.storage %ctx[1] : !simulation.ref<!simulation.logic<8>>
      %a = simulation.ref.load %two : !simulation.ref<i8> -> i8
      %b = simulation.ref.load %four : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %stdout = arith.constant -2147483647 : i32
      %format = simulation.bytes.constant "%h %h"
      simulation.display %ctx to %stdout(%format, %a, %b) newline = true radix = <hex> flags = [0, 0, 0] : !simulation.bytes, i8, !simulation.logic<8>
      simulation.return
    }
  }
}

// -----

// The guard reads another storage, whose value is not known: the write may
// run, and reads of both keep loading.

module {
  simulation.design @foreign_guard {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i32 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "proc"
    simulation.code_unit.decl 3 in 0 initial hierarchy "drive"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @proc(%ctx) : !simulation.context -> !simulation.process
      %d = simulation.spawn @drive(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @drive(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %delay = simulation.time.constant 3
      %true = arith.constant true
      %flag = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      simulation.suspend.delay %delay to ^set
    ^set:
      simulation.ref.store %true to %flag : i1, !simulation.ref<i1>
      simulation.return
    }
    // CHECK-LABEL: simulation.func @proc
    // CHECK: simulation.ref.load %{{.*}} : !simulation.ref<i1>
    // CHECK: simulation.ref.load %{{.*}} : !simulation.ref<i32>
    simulation.func @proc(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %c1 = arith.constant 1 : i32
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      %flag = simulation.context.storage %ctx[1] : !simulation.ref<i1>
      %armed = simulation.ref.load %flag : !simulation.ref<i1> -> i1
      cf.cond_br %armed, ^bump, ^wait
    ^bump:
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<i32>
      %epoch = simulation.ref.load %ref : !simulation.ref<i32> -> i32
      %next = arith.addi %epoch, %c1 : i32
      simulation.ref.store %next to %ref : i32, !simulation.ref<i32>
      cf.br ^wait
    }
  }
}

// -----

// The write's block has a second entry that no condition guards.

module {
  simulation.design @two_entries {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i32 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "proc"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @proc(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    // CHECK-LABEL: simulation.func @proc
    // CHECK: simulation.ref.load
    simulation.func @proc(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %c0 = arith.constant 0 : i32
      %c1 = arith.constant 1 : i32
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^body
    ^body:
      %ref = simulation.context.storage %ctx[0] : !simulation.ref<i32>
      %epoch = simulation.ref.load %ref : !simulation.ref<i32> -> i32
      %bit = arith.andi %epoch, %c1 : i32
      %armed = arith.cmpi ne, %bit, %c0 : i32
      cf.cond_br %armed, ^bump, ^other
    ^other:
      simulation.suspend.delay %delay to ^bump
    ^bump:
      %next = arith.addi %epoch, %c1 : i32
      simulation.ref.store %next to %ref : i32, !simulation.ref<i32>
      cf.br ^wait
    }
  }
}
