// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-unroll-loops,test-talos-replicate,test-talos-simulation-to-native)' | FileCheck %s --check-prefix=CHEAP
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.cost set={value=128 : index} remove=test.cost},test-talos-unroll-loops,test-talos-replicate,test-talos-simulation-to-native)' | FileCheck %s --check-prefix=COSTLY

// All three bodies are repeatable. In a two-state group, a large first body
// must still be predicated on its own ready bit when just a peer is woken.
// The two small downstream bodies remain eligible for speculative evaluation.
// CHEAP-LABEL: llvm.func @__talos_eval_ranked_group_0(
// CHEAP-SAME: schedule.eval.ranked_members = array<i32: 0, 1, 2>
// CHEAP-SAME: schedule.eval.unconditional_members = array<i32: 0, 1, 2>
// COSTLY-LABEL: llvm.func @__talos_eval_ranked_group_0(
// COSTLY-SAME: schedule.eval.ranked_members = array<i32: 0, 1, 2>
// COSTLY-SAME: schedule.eval.unconditional_members = array<i32: 1, 2>

!ref = !simulation.ref<i1>
!vref = !simulation.ref<i8>
module attributes {native.two_state, llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, schedule.native.max_inline_ops = 50000 : i64} {
  simulation.design @forward_chain {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "step1"
    simulation.code_unit.decl 4 in 0 continuous hierarchy "link#" {test.replicate = 2 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.code_unit.decl 6 in 0 initial hierarchy "check"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %s1 = simulation.context.storage %ctx[1] : !vref
      %zero = arith.constant false
      simulation.ref.store %zero to %clk : i1, !ref
      %clock = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %in = simulation.context.storage %ctx[1] {test.replicate = 2 : i64, test.replicate_stride = {id = 1 : i64}} : !vref
      %out = simulation.context.storage %ctx[2] {test.replicate = 2 : i64, test.replicate_stride = {id = 1 : i64}} : !vref
      %link = simulation.spawn @"link#"(%ctx, %in, %out) {test.replicate = 2 : i64} : !simulation.context, !vref, !vref -> !simulation.process
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

    simulation.func @step1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %input to ^body {site = #schedule.continuation<id = 2>} : !ref
    ^body:
      %v = simulation.ref.load %input : !ref -> i1
      %wide = arith.extui %v : i1 to i8
      %one = arith.constant 1 : i8
      %zero = arith.constant 0 : index
      %steps = arith.constant {test.cost} 1 : index
      %step = arith.constant 1 : index
      %next = scf.for %i = %zero to %steps step %step iter_args(%acc = %wide) -> i8 {
        %sum = arith.addi %acc, %one : i8
        %v2 = arith.xori %sum, %wide : i8
        scf.yield %v2 : i8
      }
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @"link#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64, test.replicate = 2 : i64, test.replicate_stride = {code_unit_id = 1 : i64, simulation.descriptor_id = 1 : i64}} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %input to ^body : !vref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %v, %one : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %output = simulation.context.storage %ctx[3] : !vref
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
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}
