// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels{defer=true}))' -o %t.mlir 2> %t.log
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=REPORT < %t.log

// Clock classes that may change twice in one time slot after time zero. Their
// opposite-edge members may then share a slot with a kernel (IEEE 1800-2023
// 9.4.2, Table 9-2), so nothing is masked and the report names the reason.

// One activation stores the clock twice: a slot may hold a posedge and a
// negedge, so `fall` may run after the posedge kernel and `q` keeps its NBA.

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {native.debug_timing} {
  simulation.design @pulse {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "rise"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "fall"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %r = simulation.context.storage %ctx[2] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @rise(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @fall(%ctx, %clk, %q, %r) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^pulse
    ^pulse:
      simulation.ref.store %one to %clk : !bit, !ref
      simulation.ref.store %zero to %clk : !bit, !ref
      cf.br ^wait
    }
    // CHECK-LABEL: simulation.design @pulse
    // CHECK-LABEL: simulation.func private @rise
    // CHECK: simulation.nba.enqueue
    // REPORT: talos clocked kernel class 0: two stores
    // REPORT: talos clocked kernel: __talos_clocked_0_2_0 members=1 eligible=1
    // REPORT-NEXT: talos clocked kernel rejection: root accessed by event activation = 1
    simulation.func private @rise(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @fall(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge negedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %q : !ref -> !bit
      %old = simulation.ref.load %r : !ref -> !bit
      %next = simulation.logic.binary xor %v, %old : !bit
      simulation.nba.enqueue %next to %r : (!bit, !ref) -> ()
      cf.br ^wait
    }
  }
}

// -----

// The second store is one plain branch away, in the same activation.

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {native.debug_timing} {
  simulation.design @branch {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "rise"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @rise(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^set
    ^set:
      simulation.ref.store %one to %clk : !bit, !ref
      cf.br ^clear
    ^clear:
      simulation.ref.store %zero to %clk : !bit, !ref
      cf.br ^wait
    }
    // REPORT: talos clocked kernel class 0: two stores
    simulation.func private @rise(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
  }
}

// -----

// A second periodic process writes the clock in later slots: two changes may
// share a slot, so `q` keeps its NBA.

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {native.debug_timing} {
  simulation.design @two_writers {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "set"
    simulation.code_unit.decl 3 in 0 initial hierarchy "clear"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "rise"
    simulation.code_unit.decl 5 in 0 always_ff hierarchy "fall"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %r = simulation.context.storage %ctx[2] : !ref
      %p0 = simulation.spawn @set(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @clear(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p2 = simulation.spawn @rise(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @fall(%ctx, %clk, %q, %r) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func @set(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 10
      %one = simulation.logic.constant true, false : !bit
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^store
    ^store:
      simulation.ref.store %one to %clk : !bit, !ref
      cf.br ^wait
    }
    simulation.func @clear(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 3 : i64} {
      %delay = simulation.time.constant 10
      %zero = simulation.logic.constant false, false : !bit
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^store
    ^store:
      simulation.ref.store %zero to %clk : !bit, !ref
      cf.br ^wait
    }
    // CHECK-LABEL: simulation.design @two_writers
    // CHECK-LABEL: simulation.func private @rise
    // CHECK: simulation.nba.enqueue
    // REPORT: talos clocked kernel class 0: second writer
    // REPORT: talos clocked kernel: __talos_clocked_0_2_0 members=1 eligible=1
    // REPORT-NEXT: talos clocked kernel rejection: root accessed by event activation = 1
    simulation.func private @rise(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @fall(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge negedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %q : !ref -> !bit
      %old = simulation.ref.load %r : !ref -> !bit
      %next = simulation.logic.binary xor %v, %old : !bit
      simulation.nba.enqueue %next to %r : (!bit, !ref) -> ()
      cf.br ^wait
    }
  }
}

// -----

// IEEE 1800-2023 4.9.4: delayed NBAs issued at time zero both land in the
// NBA region at time 10, a posedge and then a negedge (4.6(b)), whatever the
// phases of the block that issued them.

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {native.debug_timing} {
  simulation.design @delayed {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "rise"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @rise(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %ten = simulation.time.constant 10
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %one to %clk after %ten : (!bit, !ref, !simulation.time) -> ()
      simulation.nba.enqueue %zero to %clk after %ten : (!bit, !ref, !simulation.time) -> ()
      simulation.return
    }
    // REPORT: talos clocked kernel class 0: nba writer
    simulation.func private @rise(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
  }
}

// -----

// The periodic process stores the clock through a call: the call may write
// it any number of times.

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {native.debug_timing} {
  simulation.design @call {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "rise"
    simulation.code_unit.decl 4 in 0 function hierarchy "toggle"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %p0 = simulation.spawn @clock(%ctx) : !simulation.context -> !simulation.process
      %p1 = simulation.spawn @rise(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^toggle
    ^toggle:
      simulation.call @toggle(%ctx) : (!simulation.context) -> ()
      cf.br ^wait
    }
    simulation.func @toggle(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %old = simulation.ref.load %clk : !ref -> !bit
      %next = simulation.logic.unary bit_not %old : (!bit) -> !bit
      simulation.ref.store %next to %clk : !bit, !ref
      simulation.return
    }
    // REPORT: talos clocked kernel class 0: writer effect
    simulation.func private @rise(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
  }
}

// -----

// The clock follows another variable: its writer is not periodic and may run
// more than once in a slot.

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {native.debug_timing} {
  simulation.design @aperiodic {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "source"
    simulation.code_unit.decl 3 in 0 always hierarchy "clock"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "rise"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %src = simulation.context.storage %ctx[2] : !ref
      %p0 = simulation.spawn @source(%ctx, %src) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @clock(%ctx, %src, %clk) : !simulation.context, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @rise(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func @source(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      cf.br ^wait
    ^wait:
      simulation.suspend.delay %delay to ^toggle
    ^toggle:
      %old = simulation.ref.load %src : !ref -> !bit
      %next = simulation.logic.unary bit_not %old : (!bit) -> !bit
      simulation.ref.store %next to %src : !bit, !ref
      cf.br ^wait
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %src: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %src to ^body : !ref
    ^body:
      %old = simulation.ref.load %clk : !ref -> !bit
      %next = simulation.logic.unary bit_not %old : (!bit) -> !bit
      simulation.ref.store %next to %clk : !bit, !ref
      cf.br ^wait
    }
    // REPORT: talos clocked kernel class 0: aperiodic writer
    simulation.func private @rise(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
  }
}
