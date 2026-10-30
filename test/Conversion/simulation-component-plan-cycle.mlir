// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-replicate,simulation.design(talos-sim-build-compute-graph,schedule-plan-combinational-statements{component-sections=true},talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' | FileCheck %s
// A small genuine cycle and an unrelated 33-owner DAG share a source executor.
// The planner retains the cycle's actors and compiles the separate DAG.
// CHECK-DAG: simulation.spawn @step2
// CHECK-DAG: simulation.spawn @step3
// CHECK-DAG: simulation.spawn @__talos_region_kernel_0_0
// CHECK-DAG: simulation.spawn @__talos_region_kernel_1_0
// CHECK-NOT: simulation.spawn @prefix
// CHECK-NOT: simulation.spawn @cone
// CHECK: simulation.return
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
    simulation.code_unit.decl 41 in 0 continuous hierarchy "prefix"
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design {test.replicate = 32 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always hierarchy "step1"
    simulation.code_unit.decl 4 in 0 continuous hierarchy "step2"
    simulation.code_unit.decl 5 in 0 continuous hierarchy "step3"
    simulation.code_unit.decl 6 in 0 continuous hierarchy "step4"
    simulation.code_unit.decl 7 in 0 continuous hierarchy "step5"
    simulation.code_unit.decl 8 in 0 initial hierarchy "check"
    simulation.code_unit.decl 9 in 0 continuous hierarchy "cone#" {test.replicate = 32 : i64, test.replicate_stride = {id = 1 : i64}}
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %s1 = simulation.context.storage %ctx[1] : !vref
      %s2 = simulation.context.storage %ctx[2] : !vref
      %s3 = simulation.context.storage %ctx[3] : !vref
      %s4 = simulation.context.storage %ctx[4] : !vref
      %s5 = simulation.context.storage %ctx[5] : !vref
      %zero = arith.constant false
      simulation.ref.store %zero to %clk : i1, !ref
      %clock = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p5 = simulation.spawn @step5(%ctx, %s4, %s5) : !simulation.context, !vref, !vref -> !simulation.process
      %p4 = simulation.spawn @step4(%ctx, %s3, %s4) : !simulation.context, !vref, !vref -> !simulation.process
      %p3 = simulation.spawn @step3(%ctx, %s2, %s3, %s1, %clk) : !simulation.context, !vref, !vref, !vref, !ref -> !simulation.process
      %p2 = simulation.spawn @step2(%ctx, %s1, %s2, %s3, %clk) : !simulation.context, !vref, !vref, !vref, !ref -> !simulation.process
      %prefix = simulation.spawn @prefix(%ctx) : !simulation.context -> !simulation.process
      %cone = simulation.spawn @"cone#"(%ctx) {test.replicate = 32 : i64} : !simulation.context -> !simulation.process
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
      %next = arith.constant 2 : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @step2(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %route: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %config: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.any %input, %route, %config edges [0, 0, 0] to ^body {site = #schedule.continuation<id = 3>} : !vref, !vref, !ref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      %other = simulation.ref.load %route : !vref -> i8
      %select = simulation.ref.load %config : !ref -> i1
      %next = arith.andi %other, %v : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @step3(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %route: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %config: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.any %input, %route, %config edges [0, 0, 0] to ^body {site = #schedule.continuation<id = 4>} : !vref, !vref, !ref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      %other = simulation.ref.load %route : !vref -> i8
      %select = simulation.ref.load %config : !ref -> i1
      %next = arith.ori %v, %other : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @step4(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 6 : i64} {
      // The extra language sensitivity connects the selected cone to this
      // tail. Their different external activity domains must still keep
      // source fusion and knownness fallbacks separate.
      %extra = simulation.context.storage %ctx[7] : !vref
      cf.br ^body
    ^wait:
      simulation.suspend.any %input, %extra edges [0, 0] to ^body {site = #schedule.continuation<id = 5>} : !vref, !vref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %v, %one : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @step5(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 7 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %input to ^body {site = #schedule.continuation<id = 6>} : !vref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %v, %one : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @prefix(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 41 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %in = simulation.context.storage %ctx[1] : !vref
      %out = simulation.context.storage %ctx[6] : !vref
      cf.br ^body
    ^body:
      %v = simulation.ref.load %in : !vref -> i8
      %clock = simulation.ref.load %clk : !ref -> i1
      %wide = arith.extui %clock : i1 to i8
      %value = arith.xori %v, %wide : i8
      simulation.ref.store %value to %out : i8, !vref
      simulation.suspend.any %in, %clk edges [0, 0] to ^body : !vref, !ref
    }
    simulation.func @"cone#"(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 7 : i32, code_unit_id = 9 : i64, test.replicate = 32 : i64, test.replicate_stride = {code_unit_id = 1 : i64}} {
      %input = simulation.context.storage %ctx[6] : !vref
      %output = simulation.context.storage %ctx[7] {test.replicate_stride = {id = 1 : i64}} : !vref
      cf.br ^body
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.addi %v, %one : i8
      simulation.ref.store %next to %output : i8, !vref
      simulation.suspend.change %input to ^body : !vref
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
      %probe = simulation.context.storage %ctx[7] {test.replicate = 32 : i64, test.replicate_stride = {id = 1 : i64}} : !vref
      %probeValue = simulation.ref.load %probe {test.replicate = 32 : i64} : !vref -> i8
      %probeFormat = simulation.bytes.constant "cone %0d"
      simulation.display %ctx to %channel(%probeFormat, %probeValue) newline = true radix = <decimal> flags = [0, 0] {test.replicate = 32 : i64} : !simulation.bytes, i8
      %again = simulation.time.constant 2
      simulation.suspend.delay %again to ^done
    ^done:
      %b = simulation.ref.load %output : !vref -> i8
      %after = simulation.ref.load %probe {test.replicate = 32 : i64} : !vref -> i8
      %afterFormat = simulation.bytes.constant "after %0d"
      simulation.display %ctx to %channel(%afterFormat, %after) newline = true radix = <decimal> flags = [0, 0] {test.replicate = 32 : i64} : !simulation.bytes, i8
      %fmt2 = simulation.bytes.constant "chain %0d"
      %channel2 = arith.constant 1 : i32
      simulation.display %ctx to %channel2(%fmt2, %b) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, i8
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}
