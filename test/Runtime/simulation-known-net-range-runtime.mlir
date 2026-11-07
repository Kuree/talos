// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-verify-compute-graph),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' --mlir-print-ir-after=schedule-version-known-activations -o %t.mlir 2> %t.activation.mlir
// RUN: FileCheck %s --check-prefix=GUARD < %t.activation.mlir
// RUN: talos-translate --mlir-to-llvmir %t.mlir | opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s
// RUN: talos-translate --mlir-to-llvmir %t.mlir | opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o3.o
// RUN: %target_cxx %t.o3.o %runtime_link_flags -o %t.o3.exe && %t.o3.exe --execution-tier=native | FileCheck %s
// RUN: %t.o3.exe --execution-tier=bytecode | FileCheck %s

// LRM 6.7.1: the middle two elements remain undriven Z. A guard covers only
// the observed high element (7.4.1), so they do not prevent specialization.
// Calls switch known -> X -> Z -> known. An explicit low-element X write
// stays inside the fused helper. A conditional high-element X write must not
// change the earlier snapshot and must affect the later read (4.6(a), 4.7).
// Case equality checks both planes, including X versus Z (11.4.5).
// CHECK: known net ranges 1 1 1 1 1 1 1 1
// GUARD-LABEL: simulation.func private @compute
// GUARD-SAME: schedule.native.known_activation
// GUARD: simulation.net.extract %{{.*}} from 24
// GUARD: schedule.known.value
// GUARD: cf.cond_br
// GUARD: simulation.net.read %{{.*}} {schedule.native.known_read}
// GUARD-LABEL: simulation.func private @refresh
// GUARD-SAME: schedule.native.known_activation
// GUARD: schedule.known.value
// GUARD: cf.cond_br
// GUARD: simulation.driver.drive %{{.*}} {schedule.native.known_store}

!c = !simulation.context
!l8 = !simulation.logic<8>
!array = !simulation.packed_array<3 : 0 x !l8>
!net = !simulation.net<!array>
!driver = !simulation.driver<!array>
!d8 = !simulation.driver<!l8>
module attributes {
  llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128",
  llvm.target_triple = "x86_64-unknown-linux-gnu",
  native.optimization_level = 3 : i32
} {
  simulation.design @known_net_ranges {
    simulation.scope.decl 0
    simulation.net.decl 0 in 0 : !array design
    simulation.driver.decl 0 in 0 drives 0 : !array design {driven_low = 0 : i64, driven_width = 8 : i64}
    simulation.driver.decl 1 in 0 drives 0 : !array design {driven_low = 24 : i64, driven_width = 8 : i64}
    // A conflicting drive through one collapsed member must invalidate the
    // later read of its alias, even though that writer's own net is unread.
    simulation.net.decl 1 in 0 : !l8 design
    simulation.net.decl 2 in 0 : !l8 design
    simulation.driver.decl 2 in 0 drives 1 : !l8 design
    simulation.driver.decl 3 in 0 drives 1 : !l8 design
    simulation.net.connect.decl 0 in 0 1[0] to 2[0] width 8 reversed = false rhs_dominates = false
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "initial"
    simulation.code_unit.decl 3 in 0 function hierarchy "compute"
    simulation.code_unit.decl 4 in 0 function hierarchy "observe"
    simulation.code_unit.decl 5 in 0 function hierarchy "refresh"
    simulation.code_unit.decl 6 in 0 function hierarchy "defer"
    simulation.func @root(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %p = simulation.spawn @initial(%ctx) : !c -> !simulation.process
      simulation.return
    }
    simulation.func private @initial(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %d = simulation.context.driver %ctx[1] : !driver
      %hi = simulation.driver.extract %d from 24 : !driver -> !d8
      %three = simulation.logic.constant 3 : i8, 0 : i8 : !l8
      %one = simulation.logic.constant 1 : i8, 0 : i8 : !l8
      %x = simulation.logic.constant 0 : i8, -1 : i8 : !l8
      %z = simulation.logic.constant -1 : i8, -1 : i8 : !l8
      %zero = simulation.logic.constant 0 : i8, 0 : i8 : !l8
      %conflicting = simulation.context.driver %ctx[2] : !d8
      simulation.driver.drive %conflicting = %zero : !d8, !l8
      %false = arith.constant false
      %true = arith.constant true
      simulation.driver.drive %hi = %three : !d8, !l8
      %a:3 = simulation.call @compute(%ctx, %false) : (!c, i1) -> (!l8, !l8, !l8)
      %pow = simulation.logic.constant 195 : i8, 0 : i8 : !l8
      %a0 = simulation.logic.compare case_eq %a#0, %pow : (!l8, !l8) -> i1
      %a1 = simulation.logic.compare case_eq %a#1, %three : (!l8, !l8) -> i1
      %alias0 = simulation.logic.compare case_eq %a#2, %x : (!l8, !l8) -> i1
      %pair0 = arith.andi %a0, %a1 : i1
      %ok0 = arith.andi %pair0, %alias0 : i1
      %b:3 = simulation.call @compute(%ctx, %true) : (!c, i1) -> (!l8, !l8, !l8)
      %b0 = simulation.logic.compare case_eq %b#0, %pow : (!l8, !l8) -> i1
      %b1 = simulation.logic.compare case_eq %b#1, %x : (!l8, !l8) -> i1
      %alias1 = simulation.logic.compare case_eq %b#2, %x : (!l8, !l8) -> i1
      %pair1 = arith.andi %b0, %b1 : i1
      %ok1 = arith.andi %pair1, %alias1 : i1
      %c:3 = simulation.call @compute(%ctx, %false) : (!c, i1) -> (!l8, !l8, !l8)
      %c0 = simulation.logic.compare case_eq %c#0, %x : (!l8, !l8) -> i1
      %c1 = simulation.logic.compare case_eq %c#1, %x : (!l8, !l8) -> i1
      %alias2 = simulation.logic.compare case_eq %c#2, %x : (!l8, !l8) -> i1
      %pair2 = arith.andi %c0, %c1 : i1
      %ok2 = arith.andi %pair2, %alias2 : i1
      simulation.driver.drive %hi = %z : !d8, !l8
      %e:3 = simulation.call @compute(%ctx, %false) : (!c, i1) -> (!l8, !l8, !l8)
      %e0 = simulation.logic.compare case_eq %e#0, %x : (!l8, !l8) -> i1
      %e1 = simulation.logic.compare case_eq %e#1, %z : (!l8, !l8) -> i1
      %alias3 = simulation.logic.compare case_eq %e#2, %x : (!l8, !l8) -> i1
      %pair3 = arith.andi %e0, %e1 : i1
      %ok3 = arith.andi %pair3, %alias3 : i1
      simulation.driver.drive %hi = %one : !d8, !l8
      %f:3 = simulation.call @compute(%ctx, %false) : (!c, i1) -> (!l8, !l8, !l8)
      %f0 = simulation.logic.compare case_eq %f#0, %one : (!l8, !l8) -> i1
      %f1 = simulation.logic.compare case_eq %f#1, %one : (!l8, !l8) -> i1
      %alias4 = simulation.logic.compare case_eq %f#2, %x : (!l8, !l8) -> i1
      %pair4 = arith.andi %f0, %f1 : i1
      %ok4 = arith.andi %pair4, %alias4 : i1
      // Returning the whole snapshot demands the Z holes too. Its guard
      // must fail and preserve all of them in the exact original copy.
      %observed:2 = simulation.call @observe(%ctx) : (!c) -> (!array, !l8)
      %lo = simulation.aggregate.extract %observed#0[3] : (!array) -> !l8
      %hole = simulation.aggregate.extract %observed#0[1] : (!array) -> !l8
      %lo_ok = simulation.logic.compare case_eq %lo, %x : (!l8, !l8) -> i1
      %hole_ok = simulation.logic.compare case_eq %hole, %z : (!l8, !l8) -> i1
      %observed_ok = simulation.logic.compare case_eq %observed#1, %one : (!l8, !l8) -> i1
      %fields_ok = arith.andi %lo_ok, %hole_ok : i1
      %ok5 = arith.andi %fields_ok, %observed_ok : i1
      // The first known publication must clear old X; the next can leave
      // zero planes untouched. A later Z entry must fall back and clear Z.
      %r0 = simulation.call @refresh(%ctx) : (!c) -> !l8
      %r1 = simulation.call @refresh(%ctx) : (!c) -> !l8
      %low_driver = simulation.context.driver %ctx[0] : !driver
      %low_view = simulation.driver.extract %low_driver from 0 : !driver -> !d8
      simulation.driver.drive %low_view = %z : !d8, !l8
      %r2 = simulation.call @refresh(%ctx) : (!c) -> !l8
      %r3 = simulation.call @refresh(%ctx) : (!c) -> !l8
      %r0_ok = simulation.logic.compare case_eq %r0, %one : (!l8, !l8) -> i1
      %r1_ok = simulation.logic.compare case_eq %r1, %one : (!l8, !l8) -> i1
      %r2_ok = simulation.logic.compare case_eq %r2, %one : (!l8, !l8) -> i1
      %r3_ok = simulation.logic.compare case_eq %r3, %one : (!l8, !l8) -> i1
      %first_pair = arith.andi %r0_ok, %r1_ok : i1
      %second_pair = arith.andi %r2_ok, %r3_ok : i1
      %ok6 = arith.andi %first_pair, %second_pair : i1
      // A separate activation changes only the raw contribution. The net
      // remains known; the next publication must still clear the raw plane.
      simulation.call @defer(%ctx) : (!c) -> ()
      %r4 = simulation.call @refresh(%ctx) : (!c) -> !l8
      %raw4 = simulation.driver.read %low_view : !d8 -> !l8
      %r5 = simulation.call @refresh(%ctx) : (!c) -> !l8
      %raw5 = simulation.driver.read %low_view : !d8 -> !l8
      %r4_ok = simulation.logic.compare case_eq %r4, %one : (!l8, !l8) -> i1
      %raw4_ok = simulation.logic.compare case_eq %raw4, %one : (!l8, !l8) -> i1
      %r5_ok = simulation.logic.compare case_eq %r5, %one : (!l8, !l8) -> i1
      %raw5_ok = simulation.logic.compare case_eq %raw5, %one : (!l8, !l8) -> i1
      %net_pair = arith.andi %r4_ok, %r5_ok : i1
      %raw_pair = arith.andi %raw4_ok, %raw5_ok : i1
      %ok7 = arith.andi %net_pair, %raw_pair : i1
      %format = simulation.bytes.constant "known net ranges %0d %0d %0d %0d %0d %0d %0d %0d"
      %stdout = arith.constant 1 : i32
      simulation.display %ctx to %stdout(%format, %ok0, %ok1, %ok2, %ok3, %ok4, %ok5, %ok6, %ok7)
          newline = true radix = <decimal> flags = [0, 0, 0, 0, 0, 0, 0, 0, 0] : !simulation.bytes, i1, i1, i1, i1, i1, i1, i1, i1
      simulation.return
    }
    simulation.func private @compute(%ctx: !c {simulation.capture_kind = 0 : i32}, %corrupt: i1 {simulation.capture_kind = 2 : i32}) -> (!l8, !l8, !l8)
        attributes {entry_kind = 8 : i32, code_unit_id = 3 : i64, schedule.eval.inductive_two_state} {
      %n = simulation.context.net %ctx[0] : !net
      %snapshot = simulation.net.read %n : !net -> !array
      cf.cond_br %corrupt, ^change, ^work
    ^change:
      %d = simulation.context.driver %ctx[1] : !driver
      %hi = simulation.driver.extract %d from 24 : !driver -> !d8
      %x = simulation.logic.constant 0 : i8, -1 : i8 : !l8
      simulation.driver.drive %hi = %x : !d8, !l8
      cf.br ^work
    ^work:
      %value = simulation.aggregate.extract %snapshot[0] : (!array) -> !l8
      %p0 = simulation.logic.binary mul %value, %value : !l8
      %p1 = simulation.logic.binary mul %p0, %value : !l8
      %p2 = simulation.logic.binary mul %p1, %value : !l8
      %p3 = simulation.logic.binary mul %p2, %value : !l8
      %p4 = simulation.logic.binary mul %p3, %value : !l8
      %p5 = simulation.logic.binary mul %p4, %value : !l8
      %p6 = simulation.logic.binary mul %p5, %value : !l8
      %p7 = simulation.logic.binary mul %p6, %value : !l8
      %p8 = simulation.logic.binary mul %p7, %value : !l8
      %p9 = simulation.logic.binary mul %p8, %value : !l8
      %p10 = simulation.logic.binary mul %p9, %value : !l8
      %p11 = simulation.logic.binary mul %p10, %value : !l8
      %p12 = simulation.logic.binary mul %p11, %value : !l8
      %p13 = simulation.logic.binary mul %p12, %value : !l8
      %p14 = simulation.logic.binary mul %p13, %value : !l8
      %p15 = simulation.logic.binary mul %p14, %value : !l8
      %out = simulation.context.driver %ctx[0] : !driver
      %lo = simulation.driver.extract %out from 0 : !driver -> !d8
      %unknown = simulation.logic.constant 0 : i8, -1 : i8 : !l8
      simulation.driver.drive %lo = %unknown : !d8, !l8
      %conflicting = simulation.context.driver %ctx[3] : !d8
      %ones = simulation.logic.constant -1 : i8, 0 : i8 : !l8
      simulation.driver.drive %conflicting = %ones : !d8, !l8
      %alias = simulation.context.net %ctx[2] : !simulation.net<!l8>
      %resolved = simulation.net.read %alias : !simulation.net<!l8> -> !l8
      %after = simulation.net.read %n : !net -> !array
      %fresh = simulation.aggregate.extract %after[0] : (!array) -> !l8
      simulation.return %p15, %fresh, %resolved : !l8, !l8, !l8
    }
    simulation.func private @defer(%ctx: !c {simulation.capture_kind = 0 : i32})
        attributes {entry_kind = 8 : i32, code_unit_id = 6 : i64} {
      %d = simulation.context.driver %ctx[0] : !driver
      %lo = simulation.driver.extract %d from 0 : !driver -> !d8
      %x = simulation.logic.constant 0 : i8, -1 : i8 : !l8
      simulation.driver.drive %lo = %x {schedule.defer_net_resolution} : !d8, !l8
      simulation.return
    }
    simulation.func private @refresh(%ctx: !c {simulation.capture_kind = 0 : i32}) -> !l8
        attributes {entry_kind = 8 : i32, code_unit_id = 5 : i64, schedule.eval.inductive_two_state} {
      %n = simulation.context.net %ctx[0] : !net
      %all = simulation.net.read %n : !net -> !array
      %value = simulation.aggregate.extract %all[0] : (!array) -> !l8
      %r0 = simulation.logic.binary mul %value, %value : !l8
      %r1 = simulation.logic.binary mul %r0, %value : !l8
      %r2 = simulation.logic.binary mul %r1, %value : !l8
      %r3 = simulation.logic.binary mul %r2, %value : !l8
      %r4 = simulation.logic.binary mul %r3, %value : !l8
      %r5 = simulation.logic.binary mul %r4, %value : !l8
      %r6 = simulation.logic.binary mul %r5, %value : !l8
      %r7 = simulation.logic.binary mul %r6, %value : !l8
      %r8 = simulation.logic.binary mul %r7, %value : !l8
      %r9 = simulation.logic.binary mul %r8, %value : !l8
      %r10 = simulation.logic.binary mul %r9, %value : !l8
      %r11 = simulation.logic.binary mul %r10, %value : !l8
      %r12 = simulation.logic.binary mul %r11, %value : !l8
      %r13 = simulation.logic.binary mul %r12, %value : !l8
      %r14 = simulation.logic.binary mul %r13, %value : !l8
      %r15 = simulation.logic.binary mul %r14, %value : !l8
      %out = simulation.context.driver %ctx[0] : !driver
      %lo = simulation.driver.extract %out from 0 : !driver -> !d8
      simulation.driver.drive %lo = %r15 : !d8, !l8
      %after = simulation.net.read %n : !net -> !array
      %fresh = simulation.aggregate.extract %after[3] : (!array) -> !l8
      simulation.return %fresh : !l8
    }
    simulation.func private @observe(%ctx: !c {simulation.capture_kind = 0 : i32}) -> (!array, !l8)
        attributes {entry_kind = 8 : i32, code_unit_id = 4 : i64, schedule.eval.inductive_two_state} {
      %n = simulation.context.net %ctx[0] : !net
      %all = simulation.net.read %n : !net -> !array
      %value = simulation.aggregate.extract %all[0] : (!array) -> !l8
      %q0 = simulation.logic.binary mul %value, %value : !l8
      %q1 = simulation.logic.binary mul %q0, %value : !l8
      %q2 = simulation.logic.binary mul %q1, %value : !l8
      %q3 = simulation.logic.binary mul %q2, %value : !l8
      %q4 = simulation.logic.binary mul %q3, %value : !l8
      %q5 = simulation.logic.binary mul %q4, %value : !l8
      %q6 = simulation.logic.binary mul %q5, %value : !l8
      %q7 = simulation.logic.binary mul %q6, %value : !l8
      %q8 = simulation.logic.binary mul %q7, %value : !l8
      %q9 = simulation.logic.binary mul %q8, %value : !l8
      %q10 = simulation.logic.binary mul %q9, %value : !l8
      %q11 = simulation.logic.binary mul %q10, %value : !l8
      %q12 = simulation.logic.binary mul %q11, %value : !l8
      %q13 = simulation.logic.binary mul %q12, %value : !l8
      %q14 = simulation.logic.binary mul %q13, %value : !l8
      %q15 = simulation.logic.binary mul %q14, %value : !l8
      simulation.return %all, %q15 : !array, !l8
    }
  }
}
