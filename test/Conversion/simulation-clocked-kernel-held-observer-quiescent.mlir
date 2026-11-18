// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels))' | FileCheck %s --check-prefix=CHECK --check-prefix=IMM
// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels{defer=true}))' | FileCheck %s --check-prefix=CHECK --check-prefix=DEF

// IEEE 1800-2023 4.4, 4.5, 4.6, 4.7, 10.4.2: a clocked kernel may store a
// member's NBA directly when a held-state observer of the root sees nothing
// but the members' NBAs change its cone in the kernel's time-slot phase. The
// reference may then apply all of those NBAs before the observer evaluates,
// which is what the direct stores produce. Anything else that changes the
// cone in that phase, or that the reference must apply first, keeps the NBAs
// (see also simulation-clocked-kernel-held-observer-runtime.mlir).

// A: @shift holds y when its 2-bit `case` selector is X/Z (12.5). Only the
// member's NBAs change its cone in the edge's phase. The clock's time-zero
// NBA of 0 is no posedge (Table 9-2), so the kernel never runs at time zero.
// sel and x are stored directly; z, seen only by a transparent process, is
// stored directly in every design below.
// CHECK-LABEL: simulation.design @quiescent
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<2>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @quiescent {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x, %z) : !simulation.context, !ref, !sref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @shift(%ctx, %sel, %x, %y) : !simulation.context, !sref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %s1 = simulation.ref.load %x : !ref -> !bit
      %n1 = simulation.logic.unary logical_not %s1 : (!bit) -> !bit
      simulation.nba.enqueue %n1 to %x : (!bit, !ref) -> ()
      %s2 = simulation.ref.load %z : !tref -> !tri
      %inc2 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n2 = simulation.logic.binary add %s2, %inc2 : !tri
      simulation.nba.enqueue %n2 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %v = simulation.logic.unary bit_not %v0 : (!bit) -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !sref, !ref
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// B: @other writes en with a blocking store in the kernel's phase. @shift
// must still evaluate on the members' old values with the new en before their
// NBA region, so sel and x keep their NBAs.
// CHECK-LABEL: simulation.design @blocking_cone_write
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @blocking_cone_write {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x, %z) : !simulation.context, !ref, !sref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @shift(%ctx, %sel, %x, %y, %en) : !simulation.context, !sref, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @other(%ctx, %clk, %en) : !simulation.context, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %s1 = simulation.ref.load %x : !ref -> !bit
      %n1 = simulation.logic.unary logical_not %s1 : (!bit) -> !bit
      simulation.nba.enqueue %n1 to %x : (!bit, !ref) -> ()
      %s2 = simulation.ref.load %z : !tref -> !tri
      %inc2 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n2 = simulation.logic.binary add %s2, %inc2 : !tri
      simulation.nba.enqueue %n2 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %e = simulation.ref.load %en : !ref -> !bit
      %v = simulation.logic.binary xor %v0, %e : !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x, %en edges [0, 0, 0] to ^body : !sref, !ref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %en : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.ref.store %next to %en : !bit, !ref
      cf.br ^wait
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// C: x keeps its NBA because @other samples it after the edge. @regs executes
// that NBA before sel's (4.6(a)), and they apply in that order (4.6(b)), so a
// direct store of sel would apply first; sel keeps its NBA too.
// Deferred, the kernel runs after @other's Active sampling, so nothing
// exposes x and every NBA is stored: no member keeps one.
// CHECK-LABEL: simulation.design @kept_member_nba
// IMM: simulation.func private @__talos_clocked_0_1_0(
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// IMM: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// IMM-NOT: simulation.nba.enqueue
// IMM: {{^    }$}}
// DEF: simulation.func private @__talos_clocked_0_1_0(
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<2>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// DEF-NOT: simulation.nba.enqueue
// DEF: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @kept_member_nba {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x, %z) : !simulation.context, !ref, !sref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @shift(%ctx, %sel, %x, %y) : !simulation.context, !sref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @other(%ctx, %clk, %x, %seen) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %s1 = simulation.ref.load %x : !ref -> !bit
      %n1 = simulation.logic.unary logical_not %s1 : (!bit) -> !bit
      simulation.nba.enqueue %n1 to %x : (!bit, !ref) -> ()
      %s2 = simulation.ref.load %z : !tref -> !tri
      %inc2 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n2 = simulation.logic.binary add %s2, %inc2 : !tri
      simulation.nba.enqueue %n2 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %v = simulation.logic.unary bit_not %v0 : (!bit) -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !sref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %x : !ref -> !bit
      simulation.ref.store %v to %seen : !bit, !ref
      cf.br ^wait
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// D: as C, but x has its own member. The reference may execute @regs before
// @regs_x (4.7) and apply sel first, so sel is stored directly and x stays.
// Deferred, the kernel runs after @other's Active sampling, so nothing
// exposes x and every NBA is stored: no member keeps one.
// CHECK-LABEL: simulation.design @other_member_nba
// IMM: simulation.func private @__talos_clocked_0_1_0(
// IMM: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<2>,
// IMM: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// IMM-NOT: simulation.nba.enqueue
// IMM: {{^    }$}}
// DEF: simulation.func private @__talos_clocked_0_1_0(
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<2>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// DEF-NOT: simulation.nba.enqueue
// DEF: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @other_member_nba {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %z) : !simulation.context, !ref, !sref, !tref -> !simulation.process
      %p2 = simulation.spawn @regs_x(%ctx, %clk, %x) : !simulation.context, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @shift(%ctx, %sel, %x, %y) : !simulation.context, !sref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @other(%ctx, %clk, %x, %seen) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p5 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %s1 = simulation.ref.load %z : !tref -> !tri
      %inc1 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n1 = simulation.logic.binary add %s1, %inc1 : !tri
      simulation.nba.enqueue %n1 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func private @regs_x(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %x : !ref -> !bit
      %n0 = simulation.logic.unary logical_not %s0 : (!bit) -> !bit
      simulation.nba.enqueue %n0 to %x : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %v = simulation.logic.unary bit_not %v0 : (!bit) -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !sref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %x : !ref -> !bit
      simulation.ref.store %v to %seen : !bit, !ref
      cf.br ^wait
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// E: r reaches @shift only by making @decode run again. @other's time-zero NBA
// lands in the time-zero phase where the clock moves to 0. That move is no
// posedge, so the kernel never runs then, and r is stored directly.
// CHECK-LABEL: simulation.design @no_posedge_at_time_zero
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @no_posedge_at_time_zero {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %r, %z) : !simulation.context, !ref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @decode(%ctx, %r, %q, %sel, %x, %t) : !simulation.context, !ref, !ref, !sref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @shift(%ctx, %sel, %x, %y) : !simulation.context, !sref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @other(%ctx, %q) : !simulation.context, !ref -> !simulation.process
      %p5 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %r : !ref -> !bit
      %n0 = simulation.logic.unary logical_not %s0 : (!bit) -> !bit
      simulation.nba.enqueue %n0 to %r : (!bit, !ref) -> ()
      %s1 = simulation.ref.load %z : !tref -> !tri
      %inc1 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n1 = simulation.logic.binary add %s1, %inc1 : !tri
      simulation.nba.enqueue %n1 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @decode(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %t: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 8 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 7 : i64} {
      %two = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %rv = simulation.ref.load %r : !ref -> !bit
      %qv = simulation.ref.load %q : !ref -> !bit
      simulation.ref.store %two to %sel : !sel, !sref
      simulation.ref.store %qv to %x : !bit, !ref
      simulation.ref.store %rv to %t : !bit, !ref
      simulation.suspend.any %r, %q edges [0, 0] to ^body : !ref, !ref
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %v = simulation.logic.unary bit_not %v0 : (!bit) -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !sref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %one = simulation.logic.constant true, false : !bit
      simulation.nba.enqueue %one to %q : (!bit, !ref) -> ()
      simulation.return
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// F: as E, but the clock moves to 1 at time zero, a posedge from x. The
// kernel can run in the phase where @other's NBA lands, so r keeps its NBA.
// CHECK-LABEL: simulation.design @posedge_at_time_zero
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @posedge_at_time_zero {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %r, %z) : !simulation.context, !ref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @decode(%ctx, %r, %q, %sel, %x, %t) : !simulation.context, !ref, !ref, !sref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @shift(%ctx, %sel, %x, %y) : !simulation.context, !sref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @other(%ctx, %q) : !simulation.context, !ref -> !simulation.process
      %p5 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant true, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %r : !ref -> !bit
      %n0 = simulation.logic.unary logical_not %s0 : (!bit) -> !bit
      simulation.nba.enqueue %n0 to %r : (!bit, !ref) -> ()
      %s1 = simulation.ref.load %z : !tref -> !tri
      %inc1 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n1 = simulation.logic.binary add %s1, %inc1 : !tri
      simulation.nba.enqueue %n1 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @decode(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %t: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 8 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 7 : i64} {
      %two = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %rv = simulation.ref.load %r : !ref -> !bit
      %qv = simulation.ref.load %q : !ref -> !bit
      simulation.ref.store %two to %sel : !sel, !sref
      simulation.ref.store %qv to %x : !bit, !ref
      simulation.ref.store %rv to %t : !bit, !ref
      simulation.suspend.any %r, %q edges [0, 0] to ^body : !ref, !ref
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %v = simulation.logic.unary bit_not %v0 : (!bit) -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !sref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %one = simulation.logic.constant true, false : !bit
      simulation.nba.enqueue %one to %q : (!bit, !ref) -> ()
      simulation.return
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// G: the clock generator enqueues en and then causes the edge with a
// blocking store. Its NBA executes before the members are triggered, so the
// reference applies it first (4.6(b)) and @shift can never see the members'
// new values with the old en. sel and x keep their NBAs.
// CHECK-LABEL: simulation.design @nba_before_edge
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @nba_before_edge {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk, %en) : !simulation.context, !ref, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x, %z) : !simulation.context, !ref, !sref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @shift(%ctx, %sel, %x, %y, %en) : !simulation.context, !sref, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      %old = simulation.ref.load %en : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %en : (!bit, !ref) -> ()
      simulation.ref.store %one to %clk : !bit, !ref
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.ref.store %zero to %clk : !bit, !ref
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %s1 = simulation.ref.load %x : !ref -> !bit
      %n1 = simulation.logic.unary logical_not %s1 : (!bit) -> !bit
      simulation.nba.enqueue %n1 to %x : (!bit, !ref) -> ()
      %s2 = simulation.ref.load %z : !tref -> !tri
      %inc2 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n2 = simulation.logic.binary add %s2, %inc2 : !tri
      simulation.nba.enqueue %n2 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %e = simulation.ref.load %en : !ref -> !bit
      %v = simulation.logic.binary xor %v0, %e : !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x, %en edges [0, 0, 0] to ^body : !sref, !ref, !ref
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// H: @async enqueues en on the same posedge, or on arst, which never changes.
// It runs in the kernel's phase only after the edge, as the members do, so the
// members may execute first (4.7) and sel and x are stored directly.
// CHECK-LABEL: simulation.design @multi_edge_writer
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<2>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @multi_edge_writer {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x, %z) : !simulation.context, !ref, !sref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @shift(%ctx, %sel, %x, %y, %en) : !simulation.context, !sref, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @async(%ctx, %clk, %arst, %en) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %s1 = simulation.ref.load %x : !ref -> !bit
      %n1 = simulation.logic.unary logical_not %s1 : (!bit) -> !bit
      simulation.nba.enqueue %n1 to %x : (!bit, !ref) -> ()
      %s2 = simulation.ref.load %z : !tref -> !tri
      %inc2 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n2 = simulation.logic.binary add %s2, %inc2 : !tri
      simulation.nba.enqueue %n2 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %e = simulation.ref.load %en : !ref -> !bit
      %v = simulation.logic.binary xor %v0, %e : !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x, %en edges [0, 0, 0] to ^body : !sref, !ref, !ref
    }
    simulation.func private @async(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %arst: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 11 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 9 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %clk, %arst edges [1, 1] to ^body : !ref, !ref
    ^body:
      %old = simulation.ref.load %en : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %en : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// I: as H, but @reset toggles arst with a blocking store at the edge. @async
// may then run on arst before the clock edge reaches the members, and its NBA
// would apply first. sel and x keep their NBAs.
// CHECK-LABEL: simulation.design @multi_edge_writer_reset
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @multi_edge_writer_reset {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x, %z) : !simulation.context, !ref, !sref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @shift(%ctx, %sel, %x, %y, %en) : !simulation.context, !sref, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @async(%ctx, %clk, %arst, %en) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @reset(%ctx, %clk, %arst) : !simulation.context, !ref, !ref -> !simulation.process
      %p5 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %s1 = simulation.ref.load %x : !ref -> !bit
      %n1 = simulation.logic.unary logical_not %s1 : (!bit) -> !bit
      simulation.nba.enqueue %n1 to %x : (!bit, !ref) -> ()
      %s2 = simulation.ref.load %z : !tref -> !tri
      %inc2 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n2 = simulation.logic.binary add %s2, %inc2 : !tri
      simulation.nba.enqueue %n2 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %e = simulation.ref.load %en : !ref -> !bit
      %v = simulation.logic.binary xor %v0, %e : !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x, %en edges [0, 0, 0] to ^body : !sref, !ref, !ref
    }
    simulation.func private @async(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %arst: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 11 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 9 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %clk, %arst edges [1, 1] to ^body : !ref, !ref
    ^body:
      %old = simulation.ref.load %en : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %en : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func @reset(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %arst: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 11 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 10 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %a = simulation.ref.load %arst : !ref -> !bit
      %na = simulation.logic.unary logical_not %a : (!bit) -> !bit
      simulation.ref.store %na to %arst : !bit, !ref
      cf.br ^wait
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// J: @other reads y after a #0 at the edge, before the NBA region. Seeing y
// recomputed from direct stores would differ from the reference, so the
// exposure of y reaches sel and x through @shift and they keep their NBAs.
// CHECK-LABEL: simulation.design @held_output_reader
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @held_output_reader {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x, %z) : !simulation.context, !ref, !sref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @shift(%ctx, %sel, %x, %y) : !simulation.context, !sref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @other(%ctx, %clk, %y, %seen) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %s1 = simulation.ref.load %x : !ref -> !bit
      %n1 = simulation.logic.unary logical_not %s1 : (!bit) -> !bit
      simulation.nba.enqueue %n1 to %x : (!bit, !ref) -> ()
      %s2 = simulation.ref.load %z : !tref -> !tri
      %inc2 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n2 = simulation.logic.binary add %s2, %inc2 : !tri
      simulation.nba.enqueue %n2 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %v = simulation.logic.unary bit_not %v0 : (!bit) -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !sref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %zero_delay = simulation.time.constant 0
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^inactive : !ref
    ^inactive:
      simulation.suspend.delay %zero_delay to ^read
    ^read:
      %v = simulation.ref.load %y : !ref -> !bit
      simulation.ref.store %v to %seen : !bit, !ref
      cf.br ^wait
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// K: as B, but @shift reads en without waiting on it, so it never evaluates
// in the kernel's phase and no exposure reaches sel or x. The blocking write
// of en in that phase still decides what @shift reads after the stores, so
// sel and x keep their NBAs.
// CHECK-LABEL: simulation.design @unwatched_cone_write
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @unwatched_cone_write {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x, %z) : !simulation.context, !ref, !sref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @shift(%ctx, %sel, %x, %y, %en) : !simulation.context, !sref, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @other(%ctx, %clk, %en) : !simulation.context, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %s1 = simulation.ref.load %x : !ref -> !bit
      %n1 = simulation.logic.unary logical_not %s1 : (!bit) -> !bit
      simulation.nba.enqueue %n1 to %x : (!bit, !ref) -> ()
      %s2 = simulation.ref.load %z : !tref -> !tri
      %inc2 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n2 = simulation.logic.binary add %s2, %inc2 : !tri
      simulation.nba.enqueue %n2 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %e = simulation.ref.load %en : !ref -> !bit
      %v = simulation.logic.binary xor %v0, %e : !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !sref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %en : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.ref.store %next to %en : !bit, !ref
      cf.br ^wait
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// L: as E, but the clock's time-zero block also writes elsewhere (a display).
// The edge proof does not reason about other writes and keeps time zero, so r
// keeps its NBA as in F.
// CHECK-LABEL: simulation.design @time_zero_side_effect
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @time_zero_side_effect {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %r, %z) : !simulation.context, !ref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @decode(%ctx, %r, %q, %sel, %x, %t) : !simulation.context, !ref, !ref, !sref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @shift(%ctx, %sel, %x, %y) : !simulation.context, !sref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @other(%ctx, %q) : !simulation.context, !ref -> !simulation.process
      %p5 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      %stdout = arith.constant -2147483647 : i32
      %format = simulation.bytes.constant "start"
      simulation.display %ctx to %stdout(%format) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %r : !ref -> !bit
      %n0 = simulation.logic.unary logical_not %s0 : (!bit) -> !bit
      simulation.nba.enqueue %n0 to %r : (!bit, !ref) -> ()
      %s1 = simulation.ref.load %z : !tref -> !tri
      %inc1 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n1 = simulation.logic.binary add %s1, %inc1 : !tri
      simulation.nba.enqueue %n1 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @decode(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %t: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 8 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 7 : i64} {
      %two = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %rv = simulation.ref.load %r : !ref -> !bit
      %qv = simulation.ref.load %q : !ref -> !bit
      simulation.ref.store %two to %sel : !sel, !sref
      simulation.ref.store %qv to %x : !bit, !ref
      simulation.ref.store %rv to %t : !bit, !ref
      simulation.suspend.any %r, %q edges [0, 0] to ^body : !ref, !ref
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %v = simulation.logic.unary bit_not %v0 : (!bit) -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !sref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %one = simulation.logic.constant true, false : !bit
      simulation.nba.enqueue %one to %q : (!bit, !ref) -> ()
      simulation.return
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// M: @regs_x writes d with a blocking store and keeps x's NBA; @regs reads d
// for s. The kernel's value of s orders @regs_x first, so x's NBA applies
// before s's (4.6(b)) and @hold can never see s's new value with x's old one.
// s keeps its NBA.
// Deferred, @other's sampling no longer exposes x, so every NBA is stored.
// CHECK-LABEL: simulation.design @member_dep
// IMM: simulation.func private @__talos_clocked_0_1_0(
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// IMM: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// IMM-NOT: simulation.nba.enqueue
// IMM: {{^    }$}}
// DEF: simulation.func private @__talos_clocked_0_1_0(
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// DEF-NOT: simulation.nba.enqueue
// DEF: {{^    }$}}

!bit = !simulation.logic<1>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @member_dep {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !tri design
    simulation.storage.decl 7 in 0 : !tri design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "hold"
    simulation.code_unit.decl 6 in 0 initial hierarchy "other"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %s = simulation.context.storage %ctx[1] : !ref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %d = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %z = simulation.context.storage %ctx[6] : !tref
      %w = simulation.context.storage %ctx[7] : !tref
      %z0 = simulation.logic.constant false, false : !bit
      simulation.ref.store %z0 to %s : !bit, !ref
      simulation.ref.store %z0 to %x : !bit, !ref
      simulation.ref.store %z0 to %d : !bit, !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @a_regs_x(%ctx, %clk, %x, %d) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @z_regs(%ctx, %clk, %s, %d, %z) : !simulation.context, !ref, !ref, !ref, !tref -> !simulation.process
      %p3 = simulation.spawn @hold(%ctx, %s, %x, %y) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @other(%ctx, %clk, %x, %seen) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p5 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    // always_ff @(posedge clk) begin d = ~d; x <= ~x; end
    simulation.func private @a_regs_x(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %d: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %d0 = simulation.ref.load %d : !ref -> !bit
      %d1 = simulation.logic.unary logical_not %d0 : (!bit) -> !bit
      simulation.ref.store %d1 to %d : !bit, !ref
      %s0 = simulation.ref.load %x : !ref -> !bit
      %n0 = simulation.logic.unary logical_not %s0 : (!bit) -> !bit
      simulation.nba.enqueue %n0 to %x : (!bit, !ref) -> ()
      cf.br ^wait
    }
    // always_ff @(posedge clk) begin s <= d; z <= z + 1; end
    simulation.func private @z_regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %s: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %d: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %dv = simulation.ref.load %d : !ref -> !bit
      simulation.nba.enqueue %dv to %s : (!bit, !ref) -> ()
      %s1 = simulation.ref.load %z : !tref -> !tri
      %inc1 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n1 = simulation.logic.binary add %s1, %inc1 : !tri
      simulation.nba.enqueue %n1 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    // always_comb case ({x, s}) 2'b01: y = 1; 2'b10: y = 0; endcase
    simulation.func @hold(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %s: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      cf.br ^body
    ^body:
      %sv = simulation.ref.load %s : !ref -> !bit
      %xv = simulation.ref.load %x : !ref -> !bit
      %a = simulation.logic.compare case_eq %sv, %one : (!bit, !bit) -> i1
      cf.cond_br %a, ^s1, ^s0
    ^s1:
      %b = simulation.logic.compare case_eq %xv, %zero : (!bit, !bit) -> i1
      cf.cond_br %b, ^set1, ^wait
    ^s0:
      %c = simulation.logic.compare case_eq %sv, %zero : (!bit, !bit) -> i1
      cf.cond_br %c, ^s0x, ^wait
    ^s0x:
      %e = simulation.logic.compare case_eq %xv, %one : (!bit, !bit) -> i1
      cf.cond_br %e, ^set0, ^wait
    ^set1:
      simulation.ref.store %one to %y : !bit, !ref
      cf.br ^wait
    ^set0:
      simulation.ref.store %zero to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %s, %x edges [0, 0] to ^body : !ref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %x : !ref -> !bit
      simulation.ref.store %v to %seen : !bit, !ref
      cf.br ^wait
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// N: as H, but @async also writes d with a blocking store, which a member
// reads. @async may have to execute before that member, so en's NBA applies
// first; sel and x keep their NBAs.
// CHECK-LABEL: simulation.design @multi_edge_writer_dep
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @multi_edge_writer_dep {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x, %z, %t) : !simulation.context, !ref, !sref, !ref, !tref, !ref -> !simulation.process
      %p2 = simulation.spawn @shift(%ctx, %sel, %x, %y, %en) : !simulation.context, !sref, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @async(%ctx, %clk, %arst, %en, %t) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %d: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 8 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %n1 = simulation.ref.load %d : !ref -> !bit
      simulation.nba.enqueue %n1 to %x : (!bit, !ref) -> ()
      %s2 = simulation.ref.load %z : !tref -> !tri
      %inc2 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n2 = simulation.logic.binary add %s2, %inc2 : !tri
      simulation.nba.enqueue %n2 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %e = simulation.ref.load %en : !ref -> !bit
      %v = simulation.logic.binary xor %v0, %e : !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x, %en edges [0, 0, 0] to ^body : !sref, !ref, !ref
    }
    simulation.func private @async(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %arst: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 11 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}, %d: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 8 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 9 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %clk, %arst edges [1, 1] to ^body : !ref, !ref
    ^body:
      %d0 = simulation.ref.load %d : !ref -> !bit
      %d1 = simulation.logic.unary logical_not %d0 : (!bit) -> !bit
      simulation.ref.store %d1 to %d : !bit, !ref
      %old = simulation.ref.load %en : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %en : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// O: @regs enqueues sel (seen by @shift) and x2 (kept, seen by @shift2);
// @regs_x enqueues x (kept, seen by @shift) and sel2 (seen by @shift2). Each
// observer alone could see its selector stored before its kept input, but
// that needs @regs before @regs_x for one and the reverse for the other. One
// reference order serves both only if no member both stores and keeps, so
// every held-observed NBA stays.
// Deferred, @other's Active reads no longer expose x and x2, so every NBA is
// stored and no member keeps one.
// CHECK-LABEL: simulation.design @crossed_observers
// IMM: simulation.func private @__talos_clocked_0_1_0(
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// IMM: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// IMM-NOT: simulation.nba.enqueue
// IMM: {{^    }$}}
// DEF: simulation.func private @__talos_clocked_0_1_0(
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<2>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<2>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// DEF-NOT: simulation.nba.enqueue
// DEF: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @crossed_observers {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !sel design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "shift2"
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.code_unit.decl 8 in 0 always_ff hierarchy "tail_reg"
    simulation.code_unit.decl 9 in 0 always_comb hierarchy "tail"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %sel2 = simulation.context.storage %ctx[4] : !sref
      %x2 = simulation.context.storage %ctx[5] : !ref
      %y2 = simulation.context.storage %ctx[6] : !ref
      %seen = simulation.context.storage %ctx[7] : !ref
      %seen2 = simulation.context.storage %ctx[8] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x2) : !simulation.context, !ref, !sref, !ref -> !simulation.process
      %p2 = simulation.spawn @regs_x(%ctx, %clk, %x, %sel2) : !simulation.context, !ref, !ref, !sref -> !simulation.process
      %p3 = simulation.spawn @shift(%ctx, %sel, %x, %y) : !simulation.context, !sref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @shift2(%ctx, %sel2, %x2, %y2) : !simulation.context, !sref, !ref, !ref -> !simulation.process
      %p5 = simulation.spawn @other(%ctx, %clk, %x, %x2, %seen, %seen2) : !simulation.context, !ref, !ref, !ref, !ref, !ref -> !simulation.process
      %zt = simulation.context.storage %ctx[9] : !tref
      %wt = simulation.context.storage %ctx[10] : !tref
      %ptr = simulation.spawn @tail_reg(%ctx, %clk, %zt) : !simulation.context, !ref, !tref -> !simulation.process
      %ptc = simulation.spawn @tail(%ctx, %zt, %wt) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x2: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %s1 = simulation.ref.load %x2 : !ref -> !bit
      %n1 = simulation.logic.unary logical_not %s1 : (!bit) -> !bit
      simulation.nba.enqueue %n1 to %x2 : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @regs_x(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %sel2: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %x : !ref -> !bit
      %n0 = simulation.logic.unary logical_not %s0 : (!bit) -> !bit
      simulation.nba.enqueue %n0 to %x : (!bit, !ref) -> ()
      %s1 = simulation.ref.load %sel2 : !sref -> !sel
      %inc1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n1 = simulation.logic.binary add %s1, %inc1 : !sel
      simulation.nba.enqueue %n1 to %sel2 : (!sel, !sref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %v = simulation.logic.unary bit_not %v0 : (!bit) -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !sref, !ref
    }
    simulation.func @shift2(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 7 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %v = simulation.logic.unary bit_not %v0 : (!bit) -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !sref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %x2: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}, %seen2: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 8 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %x : !ref -> !bit
      simulation.ref.store %v to %seen : !bit, !ref
      %v2 = simulation.ref.load %x2 : !ref -> !bit
      simulation.ref.store %v2 to %seen2 : !bit, !ref
      cf.br ^wait
    }
    simulation.func private @tail_reg(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 8 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      %one = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n = simulation.logic.binary add %v, %one : !tri
      simulation.nba.enqueue %n to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 9 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// P: @regs_x, keeping x, also enqueues storage 5 (w), which @regs, storing
// sel, enqueues too (as x2). Executing it after @regs would apply its w last (4.6(b)), unlike the
// kernel, so it cannot trail the stored sel, and sel keeps its NBA.
// Deferred, nothing exposes x and every NBA into a held cone is stored, w by
// both members in kernel order, which is their NBA order (4.6(b)). Only v,
// which nothing reads, keeps its NBA.
// CHECK-LABEL: simulation.design @shared_nba_root
// IMM: simulation.func private @__talos_clocked_0_1_0(
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// IMM: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// IMM: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// IMM-NOT: simulation.nba.enqueue
// IMM: {{^    }$}}
// DEF: simulation.func private @__talos_clocked_0_1_0(
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// DEF: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<2>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<2>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// DEF: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// DEF-NOT: simulation.nba.enqueue
// DEF: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @shared_nba_root {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !sel design
    simulation.storage.decl 4 in 0 : !sel design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !sel design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "shift2"
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.code_unit.decl 8 in 0 always_ff hierarchy "tail_reg"
    simulation.code_unit.decl 9 in 0 always_comb hierarchy "tail"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !sref
      %sel2 = simulation.context.storage %ctx[4] : !sref
      %x2 = simulation.context.storage %ctx[5] : !ref
      %y2 = simulation.context.storage %ctx[6] : !sref
      %seen = simulation.context.storage %ctx[7] : !ref
      %seen2 = simulation.context.storage %ctx[8] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p2 = simulation.spawn @regs_x(%ctx, %clk, %x, %x2, %sel, %sel2) : !simulation.context, !ref, !ref, !ref, !sref, !sref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x2) : !simulation.context, !ref, !sref, !ref -> !simulation.process
      %p3 = simulation.spawn @shift(%ctx, %sel, %x, %y) : !simulation.context, !sref, !ref, !sref -> !simulation.process
      %p5 = simulation.spawn @other(%ctx, %clk, %x, %x2, %seen, %seen2) : !simulation.context, !ref, !ref, !ref, !ref, !ref -> !simulation.process
      %zt = simulation.context.storage %ctx[9] : !tref
      %wt = simulation.context.storage %ctx[10] : !tref
      %ptr = simulation.spawn @tail_reg(%ctx, %clk, %zt) : !simulation.context, !ref, !tref -> !simulation.process
      %ptc = simulation.spawn @tail(%ctx, %zt, %wt) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs_x(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %w: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %v: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %x : !ref -> !bit
      %n0 = simulation.logic.unary logical_not %s0 : (!bit) -> !bit
      simulation.nba.enqueue %n0 to %x : (!bit, !ref) -> ()
      %n1 = simulation.logic.constant true, false : !bit
      simulation.nba.enqueue %n1 to %w : (!bit, !ref) -> ()
      %q = simulation.ref.load %sel : !sref -> !sel
      simulation.nba.enqueue %q to %v : (!sel, !sref) -> ()
      cf.br ^wait
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x2: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %n1 = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %n1 to %x2 : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant false, false : !bit
      cf.br ^body
    ^body:
      %v0 = simulation.ref.load %x : !ref -> !bit
      %e0 = simulation.logic.compare case_eq %v0, %c0 : (!bit, !bit) -> i1
      cf.cond_br %e0, ^set, ^wait
    ^set:
      %s = simulation.ref.load %sel : !sref -> !sel
      simulation.ref.store %s to %y : !sel, !sref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !sref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %x2: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}, %seen2: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 8 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %x : !ref -> !bit
      simulation.ref.store %v to %seen : !bit, !ref
      %v2 = simulation.ref.load %x2 : !ref -> !bit
      simulation.ref.store %v2 to %seen2 : !bit, !ref
      cf.br ^wait
    }
    simulation.func private @tail_reg(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 8 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      %one = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n = simulation.logic.binary add %v, %one : !tri
      simulation.nba.enqueue %n to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 9 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}

// -----

// Q: @s1 (negedge clk or posedge rst, rst constant) enqueues r and then p;
// @m2 enqueues q. @h2 watches q and r and reads p. @s1's kernel would store p
// and keep r, but r applies before p (4.6(b)), so @h2 woken by q or r could
// see the new p only after the new r: p stays an NBA and @s1 keeps both.
// @m2's kernel may then store q, relying on @s1 to apply its NBAs after its
// members, which no kernel later contradicts.
// CHECK-LABEL: simulation.design @cross_kernel
// CHECK-NOT: @__talos_clocked_0_4096_0
// CHECK: simulation.func private @s1(
// CHECK: simulation.nba.enqueue
// CHECK: simulation.nba.enqueue
// CHECK: simulation.func private @__talos_clocked_0_770_0(
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @cross_kernel {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "s1"
    simulation.code_unit.decl 5 in 0 always_ff hierarchy "m2"
    simulation.code_unit.decl 6 in 0 always_comb hierarchy "h2"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %p = simulation.context.storage %ctx[1] : !ref
      %r = simulation.context.storage %ctx[2] : !ref
      %q = simulation.context.storage %ctx[3] : !ref
      %y = simulation.context.storage %ctx[4] : !ref
      %rst = simulation.context.storage %ctx[5] : !ref
      %u = simulation.context.storage %ctx[6] : !ref
      %seen = simulation.context.storage %ctx[7] : !ref
      %c0 = simulation.logic.constant false, false : !bit
      simulation.ref.store %c0 to %clk : !bit, !ref
      simulation.ref.store %c0 to %p : !bit, !ref
      simulation.ref.store %c0 to %r : !bit, !ref
      simulation.ref.store %c0 to %q : !bit, !ref
      simulation.ref.store %c0 to %rst : !bit, !ref
      %p0 = simulation.spawn @clock(%ctx, %clk, %u, %seen) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @s1(%ctx, %clk, %rst, %r, %p) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @m2(%ctx, %clk, %q, %r, %u) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @h2(%ctx, %q, %r, %p, %y) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func private @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %u: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      %d = simulation.time.constant 5
      simulation.suspend.delay %d to ^toggle
    ^toggle:
      %uv = simulation.ref.load %u : !ref -> !bit
      simulation.ref.store %uv to %seen : !bit, !ref
      %v = simulation.ref.load %clk : !ref -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      simulation.ref.store %n to %clk : !bit, !ref
      simulation.suspend.delay %d to ^toggle
    }
    simulation.func private @s1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %rst: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %p: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %clk, %rst edges [2, 1] to ^body : !ref, !ref
    ^body:
      %rv = simulation.ref.load %r : !ref -> !bit
      %rn = simulation.logic.unary bit_not %rv : (!bit) -> !bit
      simulation.nba.enqueue %rn to %r : (!bit, !ref) -> ()
      %pv = simulation.ref.load %p : !ref -> !bit
      %pn = simulation.logic.unary bit_not %pv : (!bit) -> !bit
      simulation.nba.enqueue %pn to %p : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @m2(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %u: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge negedge %clk to ^body : !ref
    ^body:
      %qv = simulation.ref.load %q : !ref -> !bit
      %rv = simulation.ref.load %r : !ref -> !bit
      %x = simulation.logic.binary xor %qv, %rv : !bit
      %n = simulation.logic.unary bit_not %x : (!bit) -> !bit
      simulation.nba.enqueue %n to %q : (!bit, !ref) -> ()
      simulation.nba.enqueue %qv to %u : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @h2(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %p: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 6 : i64} {
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      cf.br ^body
    ^body:
      %qv = simulation.ref.load %q : !ref -> !bit
      %rv = simulation.ref.load %r : !ref -> !bit
      %pv = simulation.ref.load %p : !ref -> !bit
      %e0 = simulation.logic.compare case_eq %qv, %one : (!bit, !bit) -> i1
      %e1 = simulation.logic.compare case_eq %rv, %zero : (!bit, !bit) -> i1
      %e = arith.andi %e0, %e1 : i1
      cf.cond_br %e, ^set, ^wait
    ^set:
      simulation.ref.store %pv to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %q, %r edges [0, 0] to ^body : !ref, !ref
    }
  }
}

// -----

// R: @m enqueues x[0][idx] and then sel; @h holds y unless sel === 1 and
// x === 0. Planning admits both, but a store into a dynamic select of a static
// view keeps its NBA. @m would then store sel and keep x, whose NBA it
// executes first (4.6(b)), so sel keeps its NBA as well.
// CHECK-LABEL: simulation.design @demote
// CHECK: simulation.func private @__talos_clocked_0_769_0(
// CHECK-NOT: nba_equivalent_store
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// CHECK-NOT: nba_equivalent_store
// CHECK: simulation.nba.enqueue %{{.+}} to %{{.+}} {{.*}}: (!simulation.logic<1>,
// CHECK-NOT: nba_equivalent_store
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
!nib = !simulation.logic<4>
!nref = !simulation.ref<!nib>
!two = !simulation.logic<2>
!tref = !simulation.ref<!two>
!iref = !simulation.ref<i64>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @demote {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !nib design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : i64 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "m"
    simulation.code_unit.decl 6 in 0 always_comb hierarchy "h"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !ref
      %x = simulation.context.storage %ctx[2] : !nref
      %y = simulation.context.storage %ctx[3] : !ref
      %idx = simulation.context.storage %ctx[4] : !iref
      %c0 = simulation.logic.constant false, false : !bit
      %n0 = simulation.logic.constant 0 : i4, 0 : i4 : !nib
      simulation.ref.store %c0 to %clk : !bit, !ref
      simulation.ref.store %c0 to %sel : !bit, !ref
      simulation.ref.store %n0 to %x : !nib, !nref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p2 = simulation.spawn @m(%ctx, %clk, %sel, %x, %idx) : !simulation.context, !ref, !ref, !nref, !iref -> !simulation.process
      %p4 = simulation.spawn @h(%ctx, %sel, %x, %y) : !simulation.context, !ref, !nref, !ref -> !simulation.process
      simulation.return
    }
    simulation.func private @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      %d = simulation.time.constant 5
      simulation.suspend.delay %d to ^toggle
    ^toggle:
      %v = simulation.ref.load %clk : !ref -> !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      simulation.ref.store %n to %clk : !bit, !ref
      simulation.suspend.delay %d to ^toggle
    }
    simulation.func private @m(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !nref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %idx: !iref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %one = simulation.logic.constant true, false : !bit
      %i = simulation.ref.load %idx : !iref -> i64
      %lo = simulation.ref.extract %x from 0 : !nref -> !tref
      %b = simulation.ref.dyn_extract %lo from %i : (!tref, i64) -> !ref
      simulation.nba.enqueue %one to %b : (!bit, !ref) -> ()
      simulation.nba.enqueue %one to %sel : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @h(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !nref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 6 : i64} {
      %one = simulation.logic.constant true, false : !bit
      %z4 = simulation.logic.constant 0 : i4, 0 : i4 : !nib
      cf.br ^body
    ^body:
      %sv = simulation.ref.load %sel : !ref -> !bit
      %xv = simulation.ref.load %x : !nref -> !nib
      %e0 = simulation.logic.compare case_eq %sv, %one : (!bit, !bit) -> i1
      %e1 = simulation.logic.compare case_eq %xv, %z4 : (!nib, !nib) -> i1
      %e = arith.andi %e0, %e1 : i1
      cf.cond_br %e, ^set, ^wait
    ^set:
      simulation.ref.store %one to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x edges [0, 0] to ^body : !ref, !nref
    }
  }
}

// -----

// S: @other's time-zero NBA of en wakes @shift in the time-zero phase where
// the clock moves to 0. That move is no posedge, so the kernel never runs at
// time zero and @shift's reads there follow no kernel; with en landing before
// the edge phase in later slots too, sel and x are stored directly.
// CHECK-LABEL: simulation.design @time_zero_observer
// CHECK: simulation.func private @__talos_clocked_0_1_0(
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<2>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<1>,
// CHECK: simulation.ref.store %{{.+}} to %{{.+}} {schedule.eval.nba_equivalent_store} : !simulation.logic<3>,
// CHECK-NOT: simulation.nba.enqueue
// CHECK: {{^    }$}}

!bit = !simulation.logic<1>
!sel = !simulation.logic<2>
!tri = !simulation.logic<3>
!ref = !simulation.ref<!bit>
!sref = !simulation.ref<!sel>
!tref = !simulation.ref<!tri>
module attributes {schedule.native_scheduler = 1 : i32} {
  simulation.design @time_zero_observer {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !sel design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !tri design
    simulation.storage.decl 10 in 0 : !tri design
    simulation.storage.decl 11 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "regs"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "shift"
    simulation.code_unit.decl 5 in 0 initial hierarchy "other"
    simulation.code_unit.decl 6 in 0 always_ff hierarchy "regs_x"
    simulation.code_unit.decl 7 in 0 always_comb hierarchy "decode"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "tail"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "async"
    simulation.code_unit.decl 10 in 0 initial hierarchy "reset"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %sel = simulation.context.storage %ctx[1] : !sref
      %x = simulation.context.storage %ctx[2] : !ref
      %y = simulation.context.storage %ctx[3] : !ref
      %en = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[5] : !ref
      %r = simulation.context.storage %ctx[6] : !ref
      %q = simulation.context.storage %ctx[7] : !ref
      %t = simulation.context.storage %ctx[8] : !ref
      %z = simulation.context.storage %ctx[9] : !tref
      %w = simulation.context.storage %ctx[10] : !tref
      %arst = simulation.context.storage %ctx[11] : !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @regs(%ctx, %clk, %sel, %x, %z) : !simulation.context, !ref, !sref, !ref, !tref -> !simulation.process
      %p2 = simulation.spawn @shift(%ctx, %sel, %x, %y, %en) : !simulation.context, !sref, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @other(%ctx, %en) : !simulation.context, !ref -> !simulation.process
      %p4 = simulation.spawn @tail(%ctx, %z, %w) : !simulation.context, !tref, !tref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      %start = simulation.logic.constant false, false : !bit
      simulation.nba.enqueue %start to %clk : (!bit, !ref) -> ()
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    simulation.func private @regs(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %s0 = simulation.ref.load %sel : !sref -> !sel
      %inc0 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %n0 = simulation.logic.binary add %s0, %inc0 : !sel
      simulation.nba.enqueue %n0 to %sel : (!sel, !sref) -> ()
      %s1 = simulation.ref.load %x : !ref -> !bit
      %n1 = simulation.logic.unary logical_not %s1 : (!bit) -> !bit
      simulation.nba.enqueue %n1 to %x : (!bit, !ref) -> ()
      %s2 = simulation.ref.load %z : !tref -> !tri
      %inc2 = simulation.logic.constant 1 : i3, 0 : i3 : !tri
      %n2 = simulation.logic.binary add %s2, %inc2 : !tri
      simulation.nba.enqueue %n2 to %z : (!tri, !tref) -> ()
      cf.br ^wait
    }
    simulation.func @shift(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %sel: !sref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %x: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      %c0 = simulation.logic.constant 0 : i2, 0 : i2 : !sel
      %c1 = simulation.logic.constant 1 : i2, 0 : i2 : !sel
      %c2 = simulation.logic.constant -2 : i2, 0 : i2 : !sel
      %c3 = simulation.logic.constant -1 : i2, 0 : i2 : !sel
      cf.br ^body
    ^body:
      %s = simulation.ref.load %sel : !sref -> !sel
      %v0 = simulation.ref.load %x : !ref -> !bit
      %e = simulation.ref.load %en : !ref -> !bit
      %v = simulation.logic.binary xor %v0, %e : !bit
      %n = simulation.logic.unary bit_not %v : (!bit) -> !bit
      %e0 = simulation.logic.compare case_eq %s, %c0 : (!sel, !sel) -> i1
      cf.cond_br %e0, ^same, ^t1
    ^t1:
      %e1 = simulation.logic.compare case_eq %s, %c1 : (!sel, !sel) -> i1
      cf.cond_br %e1, ^flip, ^t2
    ^t2:
      %e2 = simulation.logic.compare case_eq %s, %c2 : (!sel, !sel) -> i1
      cf.cond_br %e2, ^same, ^t3
    ^t3:
      %e3 = simulation.logic.compare case_eq %s, %c3 : (!sel, !sel) -> i1
      cf.cond_br %e3, ^flip, ^wait
    ^same:
      simulation.ref.store %v to %y : !bit, !ref
      cf.br ^wait
    ^flip:
      simulation.ref.store %n to %y : !bit, !ref
      cf.br ^wait
    ^wait:
      simulation.suspend.any %sel, %x, %en edges [0, 0, 0] to ^body : !sref, !ref, !ref
    }
    simulation.func @other(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %one = simulation.logic.constant true, false : !bit
      simulation.nba.enqueue %one to %en : (!bit, !ref) -> ()
      simulation.return
    }
    simulation.func @tail(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %z: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %w: !tref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^body:
      %v = simulation.ref.load %z : !tref -> !tri
      simulation.ref.store %v to %w : !tri, !tref
      simulation.suspend.change %z to ^body : !tref
    }
  }
}
