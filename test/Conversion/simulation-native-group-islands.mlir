// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.llvm.mlir
// RUN: FileCheck %s --check-prefix=PLAN < %t.llvm.mlir
// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' --mlir-print-ir-before=lower-native-state-access -o /dev/null 2>&1 | FileCheck %s --check-prefix=OWNER

// Typed accesses carry their group member until lowering.
// Each member writes its own output byte.
// OWNER-LABEL: llvm.func @__talos_eval_ranked_group_0(
// OWNER: schedule.state.store %{{.*}}, @__talos_state_value[2] {alignment = 1 : i64, owner = 1 : i32} : i8
// OWNER: schedule.state.store %{{.*}}, @__talos_state_value[3] {alignment = 1 : i64, owner = 2 : i32} : i8
// OWNER: schedule.state.store %{{.*}}, @__talos_state_value[4] {alignment = 1 : i64, owner = 3 : i32} : i8
// OWNER: schedule.state.store %{{.*}}, @__talos_state_value[5] {alignment = 1 : i64, owner = 4 : i32} : i8

// The NBA producer stays outside the sweep. Independent ready consumers
// share one group, keeping their individual activation predicates.
// PLAN-LABEL: llvm.func @__talos_eval_ranked_group_0(
// PLAN-SAME: schedule.eval.control_flow_dataflow
// PLAN-SAME: schedule.eval.ranked_members = array<i32: 1, 2, 3, 4>
// step4 never receives an activation: its output store stays on the arm
// taken only when its own bit (8) of the shared ready word is set.
// PLAN: %[[BIT:.*]] = llvm.mlir.constant(8 : i64) : i64
// PLAN-NEXT: llvm.load {{.*}}schedule.eval.activation_entry = 3 : i32
// PLAN: %[[MINE:.*]] = llvm.and %{{.*}}, %[[BIT]] : i64
// PLAN-NEXT: %[[ZERO:.*]] = llvm.mlir.constant(0 : i64) : i64
// PLAN-NEXT: %[[ACTIVE:.*]] = llvm.icmp "ne" %[[MINE]], %[[ZERO]] : i64
// PLAN-NEXT: llvm.cond_br %[[ACTIVE]], ^[[ARM:bb[0-9]+]], ^[[JOIN:bb[0-9]+]](
// PLAN-NEXT: ^[[ARM]]:
// PLAN-NOT: llvm.store
// PLAN: llvm.store {{.*}} : i8, !llvm.ptr
// PLAN-NOT: llvm.store
// PLAN: ^[[JOIN]](
// PLAN-LABEL: llvm.func @__talos_eval_dispatch_v1(
// PLAN: llvm.call @__talos_eval_ranked_group_0

!ref = !simulation.ref<i1>
!vref = !simulation.ref<i8>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32} {
  simulation.design @forward_chain {
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
    simulation.code_unit.decl 3 in 0 always hierarchy "step1"
    simulation.code_unit.decl 4 in 0 always hierarchy "step2"
    simulation.code_unit.decl 5 in 0 always hierarchy "step3"
    simulation.code_unit.decl 6 in 0 always hierarchy "step4"
    simulation.code_unit.decl 7 in 0 always hierarchy "step5"
    simulation.code_unit.decl 8 in 0 initial hierarchy "check"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %s1 = simulation.context.storage %ctx[1] : !vref
      %s2 = simulation.context.storage %ctx[2] : !vref
      %s3 = simulation.context.storage %ctx[3] : !vref
      %s4 = simulation.context.storage %ctx[4] : !vref
      %s5 = simulation.context.storage %ctx[5] : !vref
      %s6 = simulation.context.storage %ctx[6] : !vref
      %zero = arith.constant false
      simulation.ref.store %zero to %clk : i1, !ref
      %clock = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p5 = simulation.spawn @step5(%ctx, %s1, %s5) : !simulation.context, !vref, !vref -> !simulation.process
      %p4 = simulation.spawn @step4(%ctx, %s6, %s4) : !simulation.context, !vref, !vref -> !simulation.process
      %p3 = simulation.spawn @step3(%ctx, %s1, %s3) : !simulation.context, !vref, !vref -> !simulation.process
      %p2 = simulation.spawn @step2(%ctx, %s1, %s2) : !simulation.context, !vref, !vref -> !simulation.process
      %p1 = simulation.spawn @step1(%ctx, %clk, %s1) : !simulation.context, !ref, !vref -> !simulation.process
      %c = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
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
    simulation.func @step1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %input to ^body {site = #schedule.continuation<id = 2>} : !ref
    ^body:
      %v = simulation.ref.load %input : !ref -> i1
      %wide = arith.extui %v : i1 to i8
      %one = arith.constant 1 : i8
      %next = arith.addi %wide, %one : i8
      simulation.nba.enqueue %next to %output : (i8, !vref) -> ()
      cf.br ^wait
    }
    simulation.func @step2(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %input to ^body {site = #schedule.continuation<id = 3>} : !vref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %v, %one : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @step3(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %input to ^body {site = #schedule.continuation<id = 4>} : !vref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %v, %one : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @step4(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 6 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %input to ^body {site = #schedule.continuation<id = 5>} : !vref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %v, %one : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @step5(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 7 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %input to ^body {site = #schedule.continuation<id = 6>} : !vref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %v, %one : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 8 : i64} {
      %output = simulation.context.storage %ctx[5] : !vref
      %delay = simulation.time.constant 3
      simulation.suspend.delay %delay to ^first
    ^first:
      %a = simulation.ref.load %output : !vref -> i8
      %fmt = simulation.bytes.constant "chain %0d"
      %channel = arith.constant 1 : i32
      simulation.display %ctx to %channel(%fmt, %a) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i8
      %again = simulation.time.constant 2
      simulation.suspend.delay %again to ^done
    ^done:
      %b = simulation.ref.load %output : !vref -> i8
      %fmt2 = simulation.bytes.constant "chain %0d"
      %channel2 = arith.constant 1 : i32
      simulation.display %ctx to %channel2(%fmt2, %b) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i8
      %idle = simulation.context.storage %ctx[4] : !vref
      %idleValue = simulation.ref.load %idle : !vref -> i8
      %idleFmt = simulation.bytes.constant "idle %0d"
      simulation.display %ctx to %channel2(%idleFmt, %idleValue) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i8
      // Observe every independent output so all four tested owners stay live.
      %second = simulation.context.storage %ctx[2] : !vref
      %third = simulation.context.storage %ctx[3] : !vref
      %secondValue = simulation.ref.load %second : !vref -> i8
      %thirdValue = simulation.ref.load %third : !vref -> i8
      %othersFmt = simulation.bytes.constant "other islands %0d %0d"
      simulation.display %ctx to %channel2(%othersFmt, %secondValue, %thirdValue) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i8, i8
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}
