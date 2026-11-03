// RUN: talos-opt %s --split-input-file --test-talos-simulation-to-native -o %t.mlir 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace
// RUN: FileCheck %s --check-prefix=FLOP < %t.mlir
// RUN: FileCheck %s --check-prefix=COMB < %t.mlir
// RUN: FileCheck %s --check-prefix=BOTH < %t.mlir
// RUN: FileCheck %s --check-prefix=NONE < %t.mlir
// RUN: FileCheck %s --check-prefix=BODY < %t.mlir

// Eval owners that wait at one signal event control for their whole life are
// created already waiting there (IEEE 1800-2023 9.2: no implied order between
// initial and always procedures). An always_ff owner
// takes no time-zero activation; always_comb and continuous owners take theirs
// as a generated ready bit after all procedures have started (9.2.2.2), the
// same bit every wake of a direct owner raises, whoever the writer is.
// The suspending task call keeps the `stim` initial out of the generated
// schedule, so the first two designs are static eval islands; the third is
// fully generated. The clock's delay wait and the initial procedures are not
// admitted.
// TRACE: talos started owners: admitted=4 time_zero=2 entry-kind=1 wait=1
// TRACE: talos started owners: admitted=0 time_zero=0 entry-kind=1 entry-prefix=1 thread=4 wait=1
// TRACE: talos started owners: admitted=2 time_zero=1 entry-kind=2 wait=1
//
// Each spawn plan sets TALOS_RT_SPAWN_STARTED (4) and names its start record,
// whose last field is TALOS_RT_PROCESS_START_TIME_ZERO. An owner with a
// retained bytecode body is also TALOS_RT_SPAWN_VIRTUAL (8): the runtime keeps
// a frameless record, and its descriptor offers only the bytecode tier (2)
// and names no native executor (two-tier P1c). The always_ff wait record is
// the one posedge (1) entry of an edge (3) wait its suspension would store.
// FLOP-LABEL: llvm.mlir.global external constant @flop.__talos_process_descriptor(
// FLOP: %[[TIERS:.*]] = llvm.mlir.constant(2 : i32) : i32
// FLOP-NEXT: llvm.insertvalue %[[TIERS]], %{{.*}}[3]
// FLOP-NOT: __talos_native_execute
// FLOP: llvm.mlir.addressof @flop.__talos_bytecode_entry
// It also gets no native body or wrapper (two-tier P1d), while a process
// that is not admitted, such as the clock, keeps its coroutine.
// NONE-NOT: @flop.__talos_coro_ramp
// NONE-NOT: @flop.__talos_table_body
// NONE-NOT: @flop.__talos_group_body
// NONE-NOT: @flop.__talos_native_execute
// NONE-NOT: @flop.__talos_table.plan
// BODY: llvm.func @clock.__talos_coro_ramp(
// FLOP-LABEL: llvm.mlir.global internal constant @flop.__talos_spawn_plan(
// FLOP: llvm.insertvalue %{{.*}}, %{{.*}}[10]
// FLOP-NEXT: %[[STARTED:.*]] = llvm.mlir.constant(12 : i32) : i32
// FLOP-NEXT: llvm.insertvalue %[[STARTED]], %{{.*}}[11]
// FLOP-NEXT: llvm.mlir.addressof @flop.__talos_start :
// FLOP-LABEL: llvm.mlir.global internal constant @flop.__talos_start(
// FLOP: llvm.mlir.addressof @flop.__talos_start_wait
// FLOP-NEXT: llvm.insertvalue %{{.*}}, %{{.*}}[4]
// FLOP-NEXT: %[[ZERO:.*]] = llvm.mlir.constant(0 : i32) : i32
// FLOP-NEXT: llvm.insertvalue %[[ZERO]], %{{.*}}[5]
// FLOP-LABEL: llvm.mlir.global internal constant @flop.__talos_start_wait(
// FLOP: llvm.insertvalue %{{.*}}, %{{.*}}[0]
// FLOP-NEXT: %[[KIND:.*]] = llvm.mlir.constant(3 : i32) : i32
// FLOP-NEXT: llvm.insertvalue %[[KIND]], %{{.*}}[1]
// FLOP: llvm.insertvalue %{{.*}}, %{{.*}}[6, 0, 0]
// FLOP-NEXT: %[[POSEDGE:.*]] = llvm.mlir.constant(1 : i32) : i32
// FLOP-NEXT: llvm.insertvalue %[[POSEDGE]], %{{.*}}[6, 0, 1]
//
// The always_comb owner takes its time-zero activation; its record is one
// change (2) entry over the 8-bit input.
// COMB-LABEL: llvm.mlir.global internal constant @comb.__talos_start(
// COMB: llvm.mlir.addressof @comb.__talos_start_wait
// COMB-NEXT: llvm.insertvalue %{{.*}}, %{{.*}}[4]
// COMB-NEXT: %[[TIME_ZERO:.*]] = llvm.mlir.constant(1 : i32) : i32
// COMB-NEXT: llvm.insertvalue %[[TIME_ZERO]], %{{.*}}[5]
// COMB-LABEL: llvm.mlir.global internal constant @comb.__talos_start_wait(
// COMB: llvm.insertvalue %{{.*}}, %{{.*}}[0]
// COMB-NEXT: %[[CHANGE:.*]] = llvm.mlir.constant(2 : i32) : i32
// COMB-NEXT: llvm.insertvalue %[[CHANGE]], %{{.*}}[1]
// COMB: llvm.insertvalue %{{.*}}, %{{.*}}[6, 0, 2]
// COMB-NOT: [6, 1,
// COMB: llvm.return
// Outside a static eval island too (third design).
// COMB-LABEL: llvm.mlir.global internal constant @gate.__talos_start(
// COMB: llvm.mlir.addressof @gate.__talos_start_wait
// COMB-NEXT: llvm.insertvalue %{{.*}}, %{{.*}}[4]
// COMB-NEXT: %[[GATE_TIME_ZERO:.*]] = llvm.mlir.constant(1 : i32) : i32
// COMB-NEXT: llvm.insertvalue %[[GATE_TIME_ZERO]], %{{.*}}[5]
//
// `always @(posedge clk or d)` written as a procedural event control: two
// entries (posedge, change) of an edge wait, and the active-self suppression
// flag (4) its suspension would set.
// BOTH-LABEL: llvm.mlir.global internal constant @both.__talos_start_wait(
// BOTH: llvm.insertvalue %{{.*}}, %{{.*}}[1]
// BOTH-NEXT: %[[FLAGS:.*]] = llvm.mlir.constant(4 : i32) : i32
// BOTH-NEXT: llvm.insertvalue %[[FLAGS]], %{{.*}}[2]
// BOTH-NEXT: %[[COUNT:.*]] = llvm.mlir.constant(2 : i32) : i32
// BOTH-NEXT: llvm.insertvalue %[[COUNT]], %{{.*}}[3]
// BOTH: llvm.insertvalue %{{.*}}, %{{.*}}[6, 0, 0]
// BOTH-NEXT: %[[EDGE0:.*]] = llvm.mlir.constant(1 : i32) : i32
// BOTH-NEXT: llvm.insertvalue %[[EDGE0]], %{{.*}}[6, 0, 1]
// BOTH: llvm.insertvalue %{{.*}}, %{{.*}}[6, 1, 0]
// BOTH-NEXT: %[[EDGE1:.*]] = llvm.mlir.constant(0 : i32) : i32
// BOTH-NEXT: llvm.insertvalue %[[EDGE1]], %{{.*}}[6, 1, 1]
// BOTH-NEXT: %[[WIDTH1:.*]] = llvm.mlir.constant(8 : i32) : i32
// BOTH-NEXT: llvm.insertvalue %[[WIDTH1]], %{{.*}}[6, 1, 2]
//
// NONE-NOT: @clock.__talos_start
// NONE-NOT: @stim.__talos_start
// NONE-NOT: @self.__talos_start
// NONE-NOT: @named.__talos_start
// NONE-NOT: @prefix.__talos_start
// NONE-NOT: @calls.__talos_start
// NONE-NOT: @recurses.__talos_start
!ref = !simulation.ref<i1>
!vref = !simulation.ref<i8>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.debug_timing} {
  simulation.design @started {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "flop"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "comb"
    simulation.code_unit.decl 5 in 0 continuous hierarchy "assign"
    simulation.code_unit.decl 6 in 0 initial hierarchy "stim"
    simulation.code_unit.decl 7 in 0 task hierarchy "pause"
    simulation.code_unit.decl 8 in 0 always hierarchy "both"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %d = simulation.context.storage %ctx[1] : !vref
      %q = simulation.context.storage %ctx[2] : !vref
      %c = simulation.context.storage %ctx[3] : !vref
      %a = simulation.context.storage %ctx[4] : !vref
      %b = simulation.context.storage %ctx[5] : !vref
      %zero = arith.constant false
      simulation.ref.store %zero to %clk : i1, !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @flop(%ctx, %clk, %d, %q) : !simulation.context, !ref, !vref, !vref -> !simulation.process
      %p2 = simulation.spawn @comb(%ctx, %q, %c) : !simulation.context, !vref, !vref -> !simulation.process
      %p3 = simulation.spawn @assign(%ctx, %c, %a) : !simulation.context, !vref, !vref -> !simulation.process
      %p4 = simulation.spawn @stim(%ctx, %d, %a, %b) : !simulation.context, !vref, !vref, !vref -> !simulation.process
      %p5 = simulation.spawn @both(%ctx, %clk, %d, %b) : !simulation.context, !ref, !vref, !vref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 2
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !ref -> i1
      %one = arith.constant true
      %new = arith.xori %old, %one : i1
      simulation.ref.store %new to %clk : i1, !ref
      cf.br ^wait
    }
    simulation.func @flop(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {site = #schedule.continuation<id = 2>} : !ref
    ^body:
      %v = simulation.ref.load %d : !vref -> i8
      simulation.ref.store %v to %q : i8, !vref
      cf.br ^wait
    }
    simulation.func @comb(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %c: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %q to ^body {site = #schedule.continuation<id = 4>} : !vref
    ^body:
      %v = simulation.ref.load %q : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %v, %one : i8
      simulation.ref.store %next to %c : i8, !vref
      cf.br ^wait
    }
    simulation.func @assign(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %c: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %a: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %c to ^body {site = #schedule.continuation<id = 5>} : !vref
    ^body:
      %v = simulation.ref.load %c : !vref -> i8
      %two = arith.constant 2 : i8
      %next = arith.addi %v, %two : i8
      simulation.ref.store %next to %a : i8, !vref
      cf.br ^wait
    }
    simulation.func @both(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %b: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 8 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %clk, %d edges [1, 0] to ^body {site = #schedule.continuation<id = 7>, schedule.procedural_event_wait} : !ref, !vref
    ^body:
      %v = simulation.ref.load %d : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %v, %one : i8
      simulation.ref.store %next to %b : i8, !vref
      cf.br ^wait
    }
    simulation.func private @pause(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 12 : i32, code_unit_id = 7 : i64} {
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^done {timing = #schedule.timing_site<id = 1, kind = calendar>}
    ^done:
      simulation.return
    }
    simulation.func @stim(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %a: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}, %b: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %five = arith.constant 5 : i8
      simulation.ref.store %five to %d : i8, !vref
      cf.br ^call
    ^call:
      simulation.task.call @pause(%ctx) arguments 1 to ^done : !simulation.context
    ^done:
      %x = simulation.ref.load %a : !vref -> i8
      %y = simulation.ref.load %b : !vref -> i8
      %fmt = simulation.bytes.constant "%0d %0d"
      %channel = arith.constant 1 : i32
      simulation.display %ctx to %channel(%fmt, %x, %y) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i8, i8
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}

// -----

// Owners observed as threads keep their first activation: process identity
// (IEEE 1800-2023 9.7), a named block a disable can target (9.6.2), and an
// entry that does more than arm its wait.
// The second TRACE line in the header checks this split; none of its owners
// gets a start record (NONE lines in the header).
!ref = !simulation.ref<i1>
!vref = !simulation.ref<i8>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.debug_timing} {
  simulation.design @observed {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "self"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "named"
    simulation.code_unit.decl 5 in 0 always hierarchy "prefix"
    simulation.code_unit.decl 6 in 0 initial hierarchy "stim"
    simulation.code_unit.decl 7 in 0 task hierarchy "pause"
    simulation.code_unit.decl 8 in 0 always_ff hierarchy "calls"
    simulation.code_unit.decl 9 in 0 function hierarchy "identity"
    simulation.code_unit.decl 10 in 0 always_ff hierarchy "recurses"
    simulation.code_unit.decl 11 in 0 function hierarchy "ping"
    simulation.code_unit.decl 12 in 0 function hierarchy "pong"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %d = simulation.context.storage %ctx[1] : !vref
      %q1 = simulation.context.storage %ctx[2] : !vref
      %q2 = simulation.context.storage %ctx[3] : !vref
      %q3 = simulation.context.storage %ctx[4] : !vref
      %q4 = simulation.context.storage %ctx[5] : !vref
      %q5 = simulation.context.storage %ctx[6] : !vref
      %zero = arith.constant false
      simulation.ref.store %zero to %clk : i1, !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @self(%ctx, %clk, %q1) : !simulation.context, !ref, !vref -> !simulation.process
      %p2 = simulation.spawn @named(%ctx, %clk, %d, %q2) : !simulation.context, !ref, !vref, !vref -> !simulation.process
      %p3 = simulation.spawn @prefix(%ctx, %clk, %d, %q3) : !simulation.context, !ref, !vref, !vref -> !simulation.process
      %p4 = simulation.spawn @stim(%ctx, %d, %q1, %q2, %q3) : !simulation.context, !vref, !vref, !vref, !vref -> !simulation.process
      %p5 = simulation.spawn @calls(%ctx, %clk, %q4) : !simulation.context, !ref, !vref -> !simulation.process
      %p6 = simulation.spawn @recurses(%ctx, %clk, %d, %q5) : !simulation.context, !ref, !vref, !vref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 2
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !ref -> i1
      %one = arith.constant true
      %new = arith.xori %old, %one : i1
      simulation.ref.store %new to %clk : i1, !ref
      cf.br ^wait
    }
    simulation.func @self(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {site = #schedule.continuation<id = 2>} : !ref
    ^body:
      %current = simulation.process.current
      %null = simulation.process.null
      %same = simulation.process.equal %current, %null
      %value = arith.extui %same : i1 to i8
      simulation.ref.store %value to %q : i8, !vref
      cf.br ^wait
    }
    simulation.func @named(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {site = #schedule.continuation<id = 3>} : !ref
    ^body:
      %scope = simulation.control.enter 10
      %v = simulation.ref.load %d : !vref -> i8
      simulation.ref.store %v to %q : i8, !vref
      simulation.control.leave %scope
      cf.br ^wait
    }
    simulation.func @prefix(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      %seven = arith.constant 7 : i8
      simulation.ref.store %seven to %q : i8, !vref
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {site = #schedule.continuation<id = 4>} : !ref
    ^body:
      %v = simulation.ref.load %d : !vref -> i8
      simulation.ref.store %v to %q : i8, !vref
      cf.br ^wait
    }
    // process::self reached through a called function names the caller's
    // process (9.7).
    simulation.func @calls(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 8 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {site = #schedule.continuation<id = 5>} : !ref
    ^body:
      %same = simulation.call @identity(%ctx) : (!simulation.context) -> i1
      %value = arith.extui %same : i1 to i8
      simulation.ref.store %value to %q : i8, !vref
      cf.br ^wait
    }
    simulation.func private @identity(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) -> i1 attributes {entry_kind = 8 : i32, code_unit_id = 9 : i64} {
      %current = simulation.process.current
      %null = simulation.process.null
      %same = simulation.process.equal %current, %null
      simulation.return %same : i1
    }
    // A recursive pair whose only observation is in the cycle.
    simulation.func @recurses(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 10 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {site = #schedule.continuation<id = 6>} : !ref
    ^body:
      %v = simulation.ref.load %d : !vref -> i8
      %r = simulation.call @ping(%ctx, %v) : (!simulation.context, i8) -> i8
      simulation.ref.store %r to %q : i8, !vref
      cf.br ^wait
    }
    simulation.func private @ping(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %v: i8 {simulation.capture_kind = 2 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 11 : i64} {
      %zero = arith.constant 0 : i8
      %done = arith.cmpi eq, %v, %zero : i8
      cf.cond_br %done, ^leaf, ^next
    ^leaf:
      simulation.return %v : i8
    ^next:
      %one = arith.constant 1 : i8
      %less = arith.subi %v, %one : i8
      %r = simulation.call @pong(%ctx, %less) : (!simulation.context, i8) -> i8
      simulation.return %r : i8
    }
    simulation.func private @pong(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %v: i8 {simulation.capture_kind = 2 : i32}) -> i8 attributes {entry_kind = 8 : i32, code_unit_id = 12 : i64} {
      %current = simulation.process.current
      %null = simulation.process.null
      %same = simulation.process.equal %current, %null
      %bit = arith.extui %same : i1 to i8
      %r = simulation.call @ping(%ctx, %v) : (!simulation.context, i8) -> i8
      %sum = arith.addi %r, %bit : i8
      simulation.return %sum : i8
    }
    simulation.func private @pause(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 12 : i32, code_unit_id = 7 : i64} {
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^done {timing = #schedule.timing_site<id = 1, kind = calendar>}
    ^done:
      simulation.return
    }
    simulation.func @stim(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %q1: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %q2: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %q3: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %five = arith.constant 5 : i8
      simulation.ref.store %five to %d : i8, !vref
      cf.br ^call
    ^call:
      simulation.task.call @pause(%ctx) arguments 1 to ^done : !simulation.context
    ^done:
      %a = simulation.ref.load %q1 : !vref -> i8
      %b = simulation.ref.load %q2 : !vref -> i8
      %c = simulation.ref.load %q3 : !vref -> i8
      %q4 = simulation.context.storage %ctx[5] : !vref
      %q5 = simulation.context.storage %ctx[6] : !vref
      %e = simulation.ref.load %q4 : !vref -> i8
      %f = simulation.ref.load %q5 : !vref -> i8
      %fmt = simulation.bytes.constant "%0d %0d %0d %0d %0d"
      %channel = arith.constant 1 : i32
      simulation.display %ctx to %channel(%fmt, %a, %b, %c, %e, %f) newline = true radix = <decimal> flags = [0, 0, 0, 0, 0, 0] : !simulation.bytes, i8, i8, i8, i8, i8
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}

// -----

// Without the runtime-only process, the design is fully generated and not a
// static eval island. A runtime writer's transition still raises a direct
// owner's generated ready bit, so both owners are created at their waits and
// the always_comb owner's time-zero activation is that bit (third TRACE line,
// last COMB lines).
!ref = !simulation.ref<i1>
!vref = !simulation.ref<i8>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.debug_timing} {
  simulation.design @not_island {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "flop"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "gate"
    simulation.code_unit.decl 5 in 0 initial hierarchy "stim"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %d = simulation.context.storage %ctx[1] : !vref
      %q = simulation.context.storage %ctx[2] : !vref
      %c = simulation.context.storage %ctx[3] : !vref
      %zero = arith.constant false
      simulation.ref.store %zero to %clk : i1, !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @flop(%ctx, %clk, %d, %q) : !simulation.context, !ref, !vref, !vref -> !simulation.process
      %p2 = simulation.spawn @gate(%ctx, %q, %c) : !simulation.context, !vref, !vref -> !simulation.process
      %p3 = simulation.spawn @stim(%ctx, %d, %c) : !simulation.context, !vref, !vref -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 2
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !ref -> i1
      %one = arith.constant true
      %new = arith.xori %old, %one : i1
      simulation.ref.store %new to %clk : i1, !ref
      cf.br ^wait
    }
    simulation.func @flop(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {site = #schedule.continuation<id = 2>} : !ref
    ^body:
      %v = simulation.ref.load %d : !vref -> i8
      simulation.ref.store %v to %q : i8, !vref
      cf.br ^wait
    }
    simulation.func @gate(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %c: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %q to ^body {site = #schedule.continuation<id = 3>} : !vref
    ^body:
      %v = simulation.ref.load %q : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %v, %one : i8
      simulation.ref.store %next to %c : i8, !vref
      cf.br ^wait
    }
    simulation.func @stim(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %c: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %five = arith.constant 5 : i8
      simulation.ref.store %five to %d : i8, !vref
      %delay = simulation.time.constant 5
      simulation.suspend.delay %delay to ^done {site = #schedule.continuation<id = 4>, timing = #schedule.timing_site<id = 1, kind = calendar>}
    ^done:
      %v = simulation.ref.load %c : !vref -> i8
      %fmt = simulation.bytes.constant "%0d"
      %channel = arith.constant 1 : i32
      simulation.display %ctx to %channel(%fmt, %v) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i8
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}
