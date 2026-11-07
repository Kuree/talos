// RUN: talos-opt %s --split-input-file --pass-pipeline='builtin.module(test-talos-replicate,simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.mlir 2>&1 | FileCheck %s --check-prefix=PLAN
// RUN: FileCheck %s --check-prefix=LOWER < %t.mlir

// IEEE 1800-2023 4.4.2.3 and 4.5: a deferred kernel resumes in the Inactive
// region, so the eval coordinator runs it only after the edge's Active work.
// Deferred owners take the highest bits; the lowest pending bit is deferred
// only once no Active owner is pending.
//
// IEEE 1800-2023 9.2.3 and 20.2: after `$finish` no remaining event of the
// slot runs, including a deferred owner. A coordinator without a runtime
// calendar reads the termination latch before one; the calendar coordinator's
// NBA cut reports the finish itself (TALOS_RT_EVAL_NBA_TERMINATED).

// The finisher is a generated Active owner. The coordinator polls the latch
// when the selected bit is deferred and stops on a finish.

// PLAN: talos eval owner: bit=0 {{.*}}executor={{[^ ]*}}{{$}}
// PLAN-NEXT: talos eval owner: bit=1 {{.*}} deferred{{$}}
// The finisher reads what the deferred kernel writes. An owner that runs only
// after every Active owner of its pass cannot interleave with an Active sweep,
// so it orders nothing there; its publications start the next pass.
// PLAN: talos eval boundary: owner=0 {{.*}}body=finisher.__talos_eval_body_0 successors=0{{$}}
// PLAN-NEXT: talos eval boundary: owner=1 {{.*}}body=kernel.__talos_eval_body_0 successors={{$}}

// LOWER-LABEL: llvm.func @__talos_eval_dispatch_v1(
// LOWER-NOT: prepare_eval_nba
// LOWER: ^[[SWITCH:bb[0-9]+]](%[[OWNER:.*]]: i64):
// LOWER-NEXT: llvm.switch %[[OWNER]] : i64, ^[[STOPPED:bb[0-9]+]] [
// LOWER: %[[BIT:.*]] = "llvm.intr.cttz"
// LOWER-NEXT: %[[FIRST:.*]] = llvm.mlir.constant(1 : i64)
// LOWER-NEXT: %[[DEFERRED:.*]] = llvm.icmp "uge" %[[BIT]], %[[FIRST]]
// LOWER-NEXT: llvm.cond_br %[[DEFERRED]], ^[[POLL:bb[0-9]+]], ^[[SWITCH]](%[[BIT]] : i64)
// LOWER-NEXT: ^[[POLL]]:
// LOWER-NEXT: %[[LATCH:.*]] = llvm.call @talos_rt_v1_scheduler_termination_requested(%arg1)
// LOWER-NEXT: %[[ZERO:.*]] = llvm.mlir.constant(0 : i32)
// LOWER-NEXT: %[[FINISHED:.*]] = llvm.icmp "ne" %[[LATCH]], %[[ZERO]]
// LOWER-NEXT: llvm.cond_br %[[FINISHED]], ^[[STOPPED]], ^[[CUT:bb[0-9]+]]{{$}}
// A runtime scheduler call first asks whether runtime work below the Inactive
// region (1) remains; if so the coordinator returns with the deferred bit
// still pending (DEFERRED, 4). A generated driver (word 0) runs it at once.
// LOWER: ^[[CUT]]:
// LOWER-NEXT: %[[YIELD:.*]] = llvm.mlir.addressof @__talos_eval_runtime_yield_v1
// LOWER-NEXT: %[[WORD:.*]] = llvm.load %[[YIELD]]
// LOWER-NEXT: %[[COMMIT_WORD:.*]] = llvm.mlir.constant(0 : i32)
// LOWER-NEXT: %[[GENERATED:.*]] = llvm.icmp "eq" %[[WORD]], %[[COMMIT_WORD]]
// LOWER-NEXT: llvm.cond_br %[[GENERATED]], ^[[SWITCH]](%[[BIT]] : i64), ^[[DRIVEN:bb[0-9]+]]{{$}}
// LOWER: ^[[DRIVEN]]:
// LOWER-NEXT: %[[FIRST_CUT:.*]] = llvm.mlir.constant(3 : i32)
// LOWER-NEXT: %[[IS_FIRST:.*]] = llvm.icmp "eq" %[[WORD]], %[[FIRST_CUT]]
// LOWER-NEXT: llvm.cond_br %[[IS_FIRST]], ^{{bb[0-9]+}}, ^[[ASK:bb[0-9]+]]{{$}}
// LOWER: ^[[ASK]]:
// LOWER-NEXT: %[[INACTIVE:.*]] = llvm.mlir.constant(1 : i32)
// LOWER-NEXT: %[[PENDING:.*]] = llvm.call @talos_rt_v1_scheduler_runtime_work_pending(%arg1, %[[INACTIVE]])
// LOWER: llvm.cond_br %{{.*}}, ^[[YIELDED:bb[0-9]+]], ^[[SWITCH]](%[[BIT]] : i64)
// LOWER: ^[[YIELDED]]:
// LOWER: %[[DEFERRED_WORD:.*]] = llvm.mlir.constant(4 : i32)
// LOWER-NEXT: llvm.store %[[DEFERRED_WORD]], %[[YIELD]]

!clk = !simulation.ref<i1>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable, native.debug_timing} {
  simulation.design @deferred_finish {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "t.kernel"
    simulation.code_unit.decl 4 in 0 always hierarchy "t.finisher"
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i32 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %q = simulation.context.storage %ctx[1] : !int
      %n = simulation.context.storage %ctx[2] : !int
      %false = arith.constant false
      %zero = arith.constant 0 : i32
      simulation.ref.store %false to %clk : i1, !clk
      simulation.ref.store %zero to %q : i32, !int
      simulation.ref.store %zero to %n : i32, !int
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %k = simulation.spawn @kernel(%ctx, %clk, %q) : !simulation.context, !clk, !int -> !simulation.process
      %f = simulation.spawn @finisher(%ctx, %clk, %n) : !simulation.context, !clk, !int -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !clk -> i1
      %true = arith.constant true
      %new = arith.xori %old, %true : i1
      simulation.ref.store %new to %clk : i1, !clk
      cf.br ^wait
    }
    // `always @(posedge clk) q <= q + 1` as a deferred clocked kernel.
    simulation.func @kernel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 3 : i32, schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 2>} : !clk
    ^body:
      %old = simulation.ref.load %q : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %q : i32, !int
      cf.br ^wait
    }
    // `always @(posedge clk) if (++n == 3) $finish` stays in Active.
    simulation.func @finisher(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %n: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 3>} : !clk
    ^body:
      %old = simulation.ref.load %n : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      %q = simulation.context.storage %ctx[1] : !int
      %seen = simulation.ref.load %q : !int -> i32
      %mixed = arith.xori %new, %seen : i32
      simulation.ref.store %mixed to %n : i32, !int
      %three = arith.constant 3 : i32
      %done = arith.cmpi eq, %new, %three : i32
      cf.cond_br %done, ^finish, ^wait
    ^finish:
      %status = arith.constant 1 : i32
      simulation.finish %ctx, %status
      cf.br ^wait
    }
  }
}

// -----

// The finisher is a runtime-owned `initial` loop, so the coordinator keeps a
// runtime calendar. A deferred bit first takes the NBA cut, which drains
// runtime Active and Inactive work. A cut that ran the `$finish` (and the
// final procedures) reports TALOS_RT_EVAL_NBA_TERMINATED (-2): the coordinator
// returns OK at once, running no owner and committing nothing. Otherwise,
// once quiescent, it runs the lowest pending deferred owner without polling
// the latch again: nothing has run since the cut.

// PLAN: talos eval owner: bit=0 {{.*}} deferred{{$}}

// LOWER-LABEL: llvm.func @__talos_eval_dispatch_v1(
// LOWER: llvm.call @talos_rt_v1_scheduler_prepare_eval_nba(%arg1, %[[REGION:[0-9]+]])
// LOWER: %[[EMPTY:.*]] = llvm.icmp "eq" %{{.*}}, %{{.*}} : i64
// LOWER-NEXT: llvm.cond_br %[[EMPTY]], ^[[CUT:bb[0-9]+]], ^[[SELECT:bb[0-9]+]]
// LOWER: ^[[SELECT]]:
// LOWER: %[[DEFERRED:.*]] = llvm.icmp "uge"
// LOWER-NEXT: llvm.cond_br %[[DEFERRED]], ^[[CUT]], ^[[SWITCH:bb[0-9]+]](
// LOWER: %[[CUT_REGION:.*]] = llvm.load %[[REGION]] {{.*}}: !llvm.ptr -> i32
// LOWER-NEXT: %[[TERMINATED:.*]] = llvm.mlir.constant(-2 : i32)
// LOWER-NEXT: %[[ENDED:.*]] = llvm.icmp "eq" %[[CUT_REGION]], %[[TERMINATED]]
// LOWER-NEXT: %[[OK:.*]] = llvm.mlir.constant(0 : i32)
// LOWER-NEXT: llvm.cond_br %[[ENDED]], ^{{bb[0-9]+}}(%[[OK]] : i32), ^[[RUNNING:bb[0-9]+]]
// LOWER: ^[[RUNNING]]:
// LOWER: llvm.cond_br %{{.*}}, ^{{bb[0-9]+}}, ^[[QUIESCENT:bb[0-9]+]]
// LOWER-NEXT: ^[[QUIESCENT]]:
// LOWER-NEXT: llvm.mlir.addressof @__talos_aot_model_ingress_v1
// LOWER: "llvm.intr.cttz"
// LOWER: llvm.br ^[[SWITCH]](

!clk = !simulation.ref<i1>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable, native.debug_timing} {
  simulation.design @deferred_finish_runtime {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "t.kernel"
    simulation.code_unit.decl 4 in 0 initial hierarchy "t.finisher"
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i32 design
    simulation.storage.decl 2 in 0 : i32 design
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %q = simulation.context.storage %ctx[1] : !int
      %n = simulation.context.storage %ctx[2] : !int
      %false = arith.constant false
      %zero = arith.constant 0 : i32
      simulation.ref.store %false to %clk : i1, !clk
      simulation.ref.store %zero to %q : i32, !int
      simulation.ref.store %zero to %n : i32, !int
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %k = simulation.spawn @kernel(%ctx, %clk, %q) : !simulation.context, !clk, !int -> !simulation.process
      %f = simulation.spawn @finisher(%ctx, %clk, %n) : !simulation.context, !clk, !int -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !clk -> i1
      %true = arith.constant true
      %new = arith.xori %old, %true : i1
      simulation.ref.store %new to %clk : i1, !clk
      cf.br ^wait
    }
    // `always @(posedge clk) q <= q + 1` as a deferred clocked kernel.
    simulation.func @kernel(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 3 : i32, schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 2>} : !clk
    ^body:
      %old = simulation.ref.load %q : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %q : i32, !int
      cf.br ^wait
    }
    // `always @(posedge clk) if (++n == 3) $finish` stays in Active.
    simulation.func @finisher(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %n: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 3>} : !clk
    ^body:
      %old = simulation.ref.load %n : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %n : i32, !int
      %three = arith.constant 3 : i32
      %done = arith.cmpi eq, %new, %three : i32
      cf.cond_br %done, ^finish, ^wait
    ^finish:
      %status = arith.constant 1 : i32
      simulation.finish %ctx, %status
      cf.br ^wait
    }
  }
}

// -----

// Every owner of a two-word set is deferred, so no word is swept. Once no
// Active owner is pending, the coordinator scans the deferred words directly,
// polls the latch, takes the Inactive cut and runs the lowest pending
// deferred owner from the per-owner switch (IEEE 1800-2023 4.4.2.3, 4.5,
// 9.2.3, 20.2).
// PLAN: talos eval owner: bit=0 {{.*}} deferred{{$}}
// PLAN: talos eval owner: bit=69 {{.*}} deferred{{$}}
// LOWER-LABEL: llvm.func @__talos_eval_dispatch_v1(
// LOWER: ^[[SWITCH:bb[0-9]+]](%[[OWNER:.*]]: i64):
// LOWER-NEXT: llvm.switch %[[OWNER]] : i64, ^{{bb[0-9]+}} [
// LOWER-NEXT: 0: ^
// LOWER: 69: ^
// LOWER-NEXT: ]
// LOWER: "llvm.intr.cttz"
// LOWER: llvm.call @talos_rt_v1_scheduler_termination_requested(%arg1)
// LOWER: llvm.getelementptr %{{.*}}[8] : (!llvm.ptr) -> !llvm.ptr, i8
// LOWER-NEXT: %[[HIGH:.*]] = llvm.load
// LOWER-NEXT: %[[DEFERRED_HIGH:.*]] = llvm.mlir.constant(63 : i64)
// LOWER-NEXT: llvm.and %[[HIGH]], %[[DEFERRED_HIGH]]
// LOWER-NOT: @__talos_eval_dispatch_v1.word_

!clk = !simulation.ref<i1>
!int = !simulation.ref<i32>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.closed_executable, native.debug_timing} {
  simulation.design @all_deferred {
    simulation.scope.decl 0 hierarchy "t"
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "t.root"
    simulation.code_unit.decl 2 in 0 always hierarchy "t.clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "t.kernel#" {test.replicate = 70 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i32 design
    simulation.storage.decl 2 in 0 : i32 design {test.replicate = 70 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clk
      %n = simulation.context.storage %ctx[1] : !int
      %false = arith.constant false
      %zero = arith.constant 0 : i32
      simulation.ref.store %false to %clk : i1, !clk
      simulation.ref.store %zero to %n : i32, !int
      %c = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !clk -> !simulation.process
      %q = simulation.context.storage %ctx[2] {test.replicate = 70 : i64, test.replicate_stride = {id = 1 : i64}} : !int
      %k = simulation.spawn @"kernel#"(%ctx, %clk, %q) {test.replicate = 70 : i64} : !simulation.context, !clk, !int -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !clk -> i1
      %true = arith.constant true
      %new = arith.xori %old, %true : i1
      simulation.ref.store %new to %clk : i1, !clk
      cf.br ^wait
    }
    simulation.func @"kernel#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clk {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !int {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64, test.replicate_stride = {simulation.descriptor_id = 1 : i64}}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64, test.replicate = 70 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 3 : i32, schedule.procedural_event_wait, schedule.repeating_always_wait, site = #schedule.continuation<id = 2>} : !clk
    ^body:
      %old = simulation.ref.load %q : !int -> i32
      %one = arith.constant 1 : i32
      %new = arith.addi %old, %one : i32
      simulation.ref.store %new to %q : i32, !int
      cf.br ^wait
    }
  }
}
