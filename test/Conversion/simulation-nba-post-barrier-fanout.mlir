// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.mlir 2> %t.plan
// RUN: FileCheck %s --check-prefix=PLAN < %t.plan && FileCheck %s --check-prefix=GUARD < %t.mlir
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{simulation.snapshot_publications}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o /dev/null 2>&1 | FileCheck %s --check-prefix=SNAPSHOT

// The flipped register drives only a plain Active copy. The copy output is
// edge sensitive, so the transitive private-cone proof rejects the register.
// Both positive edges must still occur after their respective NBA commits
// (1800-2023 4.5, 4.6, 9.4.2). A snapshot observer keeps canonical replay.
// PLAN: talos native NBA batch: candidates=1 roots=1 private-cone=0 unread=0 wide=0 slots=0 barrier-local=1
// SNAPSHOT: talos native NBA batch: candidates=0 roots=1 private-cone=0 unread=0 wide=0 slots=0 barrier-local=0
// GUARD: llvm.call @talos_rt_v1_static_nba_batch_word_guard(

!ref = !simulation.ref<i1>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", native.closed_executable, native.debug_timing, schedule.native_scheduler = 3 : i32} {
  simulation.design @barrier_cone {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "writer"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "forward"
    simulation.code_unit.decl 5 in 0 always hierarchy "observer"
    simulation.code_unit.decl 6 in 0 initial hierarchy "stop"
    simulation.code_unit.decl 7 in 0 fork hierarchy "completed"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %c = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %y = simulation.context.storage %ctx[2] : !ref
      %p = simulation.spawn @clock(%ctx, %c) : !simulation.context, !ref -> !simulation.process
      %r = simulation.spawn @writer(%ctx, %c, %q) : !simulation.context, !ref, !ref -> !simulation.process
      %s = simulation.spawn @forward(%ctx, %q, %y) : !simulation.context, !ref, !ref -> !simulation.process
      %t = simulation.spawn @observer(%ctx, %y) : !simulation.context, !ref -> !simulation.process
      %u = simulation.spawn @stop(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %c: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %d = simulation.time.constant 5
      simulation.suspend.delay %d to ^tick
    ^tick:
      %v = simulation.ref.load %c : !ref -> i1
      %one = arith.constant true
      %n = arith.xori %v, %one : i1
      simulation.ref.store %n to %c : i1, !ref
      cf.br ^wait
    }
    simulation.func private @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %c: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %c to ^assign : !ref
    ^assign:
      %v = simulation.ref.load %q : !ref -> i1
      %one = arith.constant true
      %n = arith.xori %v, %one : i1
      simulation.nba.enqueue %n to %q : (i1, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @forward(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      cf.br ^copy
    ^copy:
      %v = simulation.ref.load %q : !ref -> i1
      simulation.ref.store %v to %y : i1, !ref
      simulation.suspend.change %q to ^copy : !ref
    }
    simulation.func private @observer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %y: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %y to ^report : !ref
    ^report:
      %now = simulation.time.now %ctx
      %fd = arith.constant 1 : i32
      %fmt = simulation.bytes.constant "rise %d"
      simulation.display %ctx to %fd(%fmt, %now) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i64
      cf.br ^wait
    }
    simulation.func private @stop(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %d = simulation.time.constant 31
      simulation.suspend.delay %d to ^end
    ^end:
      %child = simulation.spawn @completed(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @completed(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 13 : i32, code_unit_id = 7 : i64} {
      %exit = arith.constant 0 : i32
      simulation.finish %ctx, %exit
      simulation.return
    }
  }
}
