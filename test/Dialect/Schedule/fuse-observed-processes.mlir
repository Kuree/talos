// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-fuse-observed-processes))' -o %t.mlir 2> %t.log
// RUN: FileCheck %s --check-prefix=REPORT < %t.log
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=GONE < %t.mlir

// Concurrent assertions evaluate their properties in the Observed region
// (IEEE 1800-2023 4.4.2.5). Processes that wait for the same edge of the same
// root become one process that runs every member's start-up code, waits once,
// and runs each activation in turn (4.7). Each member keeps its loop-carried
// attempt state through its own exit block. Members may branch before their
// first wait and need not list blocks in dominance order. An operand captured
// with different argument attributes stays a separate argument.
// REPORT: talos observed kernel: __talos_observed_0_{{[0-9_]+}} members=3
// REPORT: talos observed kernels: kernels=1 members=3
// Rejected on the same clock: a write to design state, process identity used
// directly, through a callee, or by disabling its children, a spawned action
// that draws a random number (18.14.1), an extra operation beside the wait, a
// spawn whose handle is kept, a partial watched root, a second wait, and a
// wait that resumes outside the Observed region. A different root and a
// different edge form groups of their own.
// REPORT: talos observed kernel rejection: design write = 1
// REPORT: talos observed kernel rejection: process-dependent operation = 3
// REPORT: talos observed kernel rejection: random state or opaque effect = 1
// REPORT: talos observed kernel rejection: shape = 1
// REPORT: talos observed kernel rejection: single member = 2
// REPORT: talos observed kernel rejection: spawn = 1
// REPORT: talos observed kernel rejection: wait = 2
// REPORT: talos observed kernel rejection: watched root = 1
// GONE-NOT: simulation.func private @first(
// GONE-NOT: simulation.func private @second(
// GONE-NOT: simulation.func private @third(
// CHECK-LABEL: simulation.design @observed
// CHECK: simulation.spawn @__talos_observed_0_{{[0-9_]+}}(%{{[^,]*}}, %{{[^,]*}}, %{{[^,]*}}, %{{[^,]*}}) :
// CHECK-LABEL: simulation.func private @__talos_observed_0_{{[0-9_]+}}(
// CHECK-SAME: !simulation.context
// CHECK-SAME: !simulation.ref<i1>
// CHECK-SAME: !simulation.ref<i8> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}
// CHECK-SAME: !simulation.ref<i8> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64, test.marked}
// CHECK-SAME: home_region = 8
// Start-up code: each member's start exit enters the next member.
// CHECK: %[[FIRST:.*]] = simulation.ref.alloc
// CHECK: cf.br ^[[START1:bb[0-9]+]](%[[FIRST]] :
// CHECK: ^[[START1]](%[[A0:[0-9]+]]: !simulation.ref<i64>):
// CHECK: %[[SECOND:.*]] = simulation.ref.alloc
// CHECK: cf.br ^[[START2:bb[0-9]+]](%[[SECOND]] :
// CHECK: ^[[START2]](%[[B0:[0-9]+]]: !simulation.ref<i64>):
// CHECK: cf.cond_br
// CHECK: %[[START:[0-9]+]] = simulation.ref.load
// CHECK: cf.br ^[[WAIT:bb[0-9]+]](%[[A0]], %[[B0]] :
// CHECK: ^[[WAIT]](%[[A:[0-9]+]]: !simulation.ref<i64>, %[[B:[0-9]+]]: !simulation.ref<i64>):
// CHECK-NEXT: simulation.suspend.edge posedge %{{.*}} to ^[[ACT:bb[0-9]+]] {resume_region = 8 : i32
// CHECK-NOT: simulation.suspend
// CHECK: ^[[ACT]]:
// CHECK-NEXT: cf.br ^{{.*}}(%[[A]] :
// The first member's activation ends at its exit, which enters the second.
// CHECK: simulation.ref.store
// CHECK-NEXT: cf.br ^[[EXIT1:bb[0-9]+]](
// CHECK: ^[[EXIT1]](%[[NEXT1:[0-9]+]]: !simulation.ref<i64>):
// The second member forwards its loop value twice and is cloned with each
// definition before its uses.
// CHECK-NEXT: cf.br ^{{.*}}(%[[B]], %[[B]] :
// CHECK: arith.addi
// CHECK: simulation.ref.store
// CHECK-NEXT: cf.br ^[[EXIT2:bb[0-9]+]](
// CHECK: ^[[EXIT2]](%[[NEXT2:[0-9]+]]: !simulation.ref<i64>):
// The third member has no loop values and compares with its start-up value;
// its exit closes the activation.
// CHECK: arith.cmpi ne, %{{.*}}, %[[START]] : i8
// CHECK: cf.br ^[[WAIT]](%[[NEXT1]], %[[NEXT2]] :
!state = !simulation.ref<i64>
!clk = !simulation.ref<i1>
!byte = !simulation.ref<i8>
module attributes {native.debug_timing} {
  simulation.design @observed {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "first"
    simulation.code_unit.decl 3 in 0 always hierarchy "second"
    simulation.code_unit.decl 4 in 0 always hierarchy "third"
    simulation.code_unit.decl 5 in 0 always hierarchy "other_root"
    simulation.code_unit.decl 6 in 0 always hierarchy "falling"
    simulation.code_unit.decl 7 in 0 always hierarchy "writer"
    simulation.code_unit.decl 8 in 0 always hierarchy "identity"
    simulation.code_unit.decl 9 in 0 always hierarchy "indirect"
    simulation.code_unit.decl 10 in 0 always hierarchy "disabler"
    simulation.code_unit.decl 11 in 0 always hierarchy "randomized"
    simulation.code_unit.decl 12 in 0 always hierarchy "busy_wait"
    simulation.code_unit.decl 13 in 0 always hierarchy "kept"
    simulation.code_unit.decl 14 in 0 always hierarchy "partial"
    simulation.code_unit.decl 15 in 0 always hierarchy "twice"
    simulation.code_unit.decl 16 in 0 always hierarchy "active"
    simulation.code_unit.decl 17 in 0 fork hierarchy "action"
    simulation.code_unit.decl 18 in 0 function hierarchy "whoami"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %other = simulation.context.storage %ctx[1] : !clk
      %data = simulation.context.storage %ctx[2] : !byte
      %p0 = simulation.spawn @first(%ctx, %clk, %data) : !simulation.context, !clk, !byte -> !simulation.process
      %p1 = simulation.spawn @other_root(%ctx, %other, %data) : !simulation.context, !clk, !byte -> !simulation.process
      %p2 = simulation.spawn @falling(%ctx, %clk, %data) : !simulation.context, !clk, !byte -> !simulation.process
      %p3 = simulation.spawn @writer(%ctx, %clk, %data) : !simulation.context, !clk, !byte -> !simulation.process
      %p4 = simulation.spawn @identity(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %p5 = simulation.spawn @indirect(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %p6 = simulation.spawn @disabler(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %p7 = simulation.spawn @randomized(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %p8 = simulation.spawn @busy_wait(%ctx, %clk, %data) : !simulation.context, !clk, !byte -> !simulation.process
      %p9 = simulation.spawn @kept(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %kept = simulation.process.equal %p9, %p9
      %p10 = simulation.spawn @partial(%ctx, %data) : !simulation.context, !byte -> !simulation.process
      %p11 = simulation.spawn @twice(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %p12 = simulation.spawn @active(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %p13 = simulation.spawn @second(%ctx, %clk, %data) : !simulation.context, !clk, !byte -> !simulation.process
      %p14 = simulation.spawn @third(%ctx, %clk, %data) : !simulation.context, !clk, !byte -> !simulation.process
      simulation.return
    }
    simulation.func private @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %data: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 2 : i64} {
      %zero = arith.constant 0 : i64
      %attempts = simulation.ref.alloc %zero : i64 -> !state
      cf.br ^wait(%attempts : !state)
    ^wait(%s: !state):
      simulation.suspend.edge posedge %clk to ^body(%s : !state) {resume_region = 8 : i32} : !clk
    ^body(%t: !state):
      %v = simulation.ref.load %data : !byte -> i8
      %c = arith.constant 0 : i8
      %bad = arith.cmpi eq, %v, %c : i8
      cf.cond_br %bad, ^count(%t : !state), ^wait(%t : !state)
    ^count(%u: !state):
      %n = simulation.ref.load %u : !state -> i64
      %one = arith.constant 1 : i64
      %m = arith.addi %n, %one : i64
      simulation.ref.store %m to %u : i64, !state
      cf.br ^wait(%u : !state)
    }
    // Forwards its loop value twice, and lists a use before its definition.
    simulation.func private @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %data: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 3 : i64} {
      %zero = arith.constant 0 : i64
      %attempts = simulation.ref.alloc %zero : i64 -> !state
      cf.br ^wait(%attempts : !state)
    ^wait(%s: !state):
      simulation.suspend.edge posedge %clk to ^body(%s, %s : !state, !state) {resume_region = 8 : i32} : !clk
    ^body(%t: !state, %t2: !state):
      cf.br ^define
    ^use:
      simulation.ref.store %m to %t2 : i64, !state
      cf.br ^wait(%t : !state)
    ^define:
      %n = simulation.ref.load %t : !state -> i64
      %two = arith.constant 2 : i64
      %m = arith.addi %n, %two : i64
      cf.br ^use
    }
    // Branches before its first wait, and its body uses a value defined after
    // that branch. Its data capture is marked differently.
    simulation.func private @third(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %data: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64, test.marked}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 4 : i64} {
      %v = simulation.ref.load %data : !byte -> i8
      %c = arith.constant 0 : i8
      %low = arith.cmpi eq, %v, %c : i8
      cf.cond_br %low, ^a, ^b
    ^a:
      cf.br ^join
    ^b:
      cf.br ^join
    ^join:
      %start = simulation.ref.load %data : !byte -> i8
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 8 : i32} : !clk
    ^body:
      %w = simulation.ref.load %data : !byte -> i8
      %moved = arith.cmpi ne, %w, %start : i8
      cf.br ^wait
    }
    simulation.func private @other_root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %data: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 8 : i32} : !clk
    ^body:
      %v = simulation.ref.load %data : !byte -> i8
      cf.br ^wait
    }
    simulation.func private @falling(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %data: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge negedge %clk to ^body {resume_region = 8 : i32} : !clk
    ^body:
      %v = simulation.ref.load %data : !byte -> i8
      cf.br ^wait
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %data: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 7 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 8 : i32} : !clk
    ^body:
      %c = arith.constant 1 : i8
      simulation.ref.store %c to %data : i8, !byte
      cf.br ^wait
    }
    simulation.func private @identity(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 8 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 8 : i32} : !clk
    ^body:
      %self = simulation.process.current
      cf.br ^wait
    }
    simulation.func private @indirect(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 9 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 8 : i32} : !clk
    ^body:
      simulation.call @whoami(%ctx) : (!simulation.context) -> ()
      cf.br ^wait
    }
    simulation.func private @whoami(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 18 : i64} {
      %self = simulation.process.current
      simulation.return
    }
    simulation.func private @disabler(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 10 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 8 : i32} : !clk
    ^body:
      simulation.children.disable
      cf.br ^wait
    }
    simulation.func private @randomized(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 11 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 8 : i32} : !clk
    ^body:
      %child = simulation.spawn @action(%ctx) : !simulation.context -> !simulation.process
      cf.br ^wait
    }
    simulation.func private @action(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 17 : i64} {
      %value = simulation.random.next %ctx : (!simulation.context) -> i64
      simulation.return
    }
    simulation.func private @busy_wait(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %data: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 12 : i64} {
      cf.br ^wait
    ^wait:
      %v = simulation.ref.load %data : !byte -> i8
      simulation.suspend.edge posedge %clk to ^body {resume_region = 8 : i32} : !clk
    ^body:
      cf.br ^wait
    }
    simulation.func private @kept(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 13 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 8 : i32} : !clk
    ^body:
      cf.br ^wait
    }
    simulation.func private @partial(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %data: !byte {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 14 : i64} {
      %bit = simulation.ref.extract %data from 0 : !byte -> !clk
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %bit to ^body {resume_region = 8 : i32} : !clk
    ^body:
      cf.br ^wait
    }
    simulation.func private @twice(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 15 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^again {resume_region = 8 : i32} : !clk
    ^again:
      simulation.suspend.edge posedge %clk to ^wait {resume_region = 8 : i32} : !clk
    }
    simulation.func private @active(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 16 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !clk
    ^body:
      cf.br ^wait
    }
  }
}
