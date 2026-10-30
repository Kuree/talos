// RUN: talos-opt %s --test-talos-simulation-to-native -o %t.mlir 2> %t.trace
// RUN: FileCheck %s --check-prefix=TRACE --implicit-check-not='talos eval owner: {{.*}}actor=5 ' < %t.trace
// RUN: FileCheck %s --check-prefix=GROUP < %t.mlir
// A -> runtime-only B -> C also has an A -> C shortcut. The stateful B has
// no generated ready bit. Its virtual boundary must still separate A and C.
// B's initial prefix writes A's gate. Keeping that prefix distinct from its
// resumed body avoids inventing a cyclic component around A.
// A retains its executor because B observes its publications. The trace must
// nevertheless retain A -> B -> C; removing virtual projection fails here.
// TRACE: talos eval owner: bit=0 actor=6 {{.*}}group=-
// TRACE: talos eval runtime boundary: component=[[PREFIX:[0-9]+]] body=<runtime:step2:0>
// TRACE-NEXT: talos eval component: owner=4294967295 component=[[PREFIX]] {{.*}}cyclic=0 successors=[[A:[0-9]+]],
// TRACE-NEXT: talos eval component: owner=0 component=[[A]] {{.*}}cyclic=0 successors=[[B:[0-9]+]], [[C:[0-9]+]],
// TRACE-NEXT: talos eval runtime boundary: component=[[B]] body=<runtime:step2:2>
// TRACE-NEXT: talos eval component: owner=4294967295 component=[[B]] {{.*}}cyclic=0 successors=[[C]],
// TRACE-NEXT: talos eval component: owner=1 component=[[C]]
// GROUP-LABEL: llvm.func @__talos_eval_ranked_group_0(
// GROUP-SAME: schedule.eval.ranked_members = array<i32: 1, 2, 3>
// GROUP-NOT: llvm.func @__talos_eval_ranked_group_1(
!ref = !simulation.ref<i1>
!vref = !simulation.ref<i8>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.debug_timing} {
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
    simulation.code_unit.decl 4 in 0 initial hierarchy "step2"
    simulation.code_unit.decl 5 in 0 continuous hierarchy "step3"
    simulation.code_unit.decl 6 in 0 continuous hierarchy "step4"
    simulation.code_unit.decl 7 in 0 continuous hierarchy "step5"
    simulation.code_unit.decl 8 in 0 initial hierarchy "check"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %s1 = simulation.context.storage %ctx[1] : !vref
      %s2 = simulation.context.storage %ctx[2] : !vref
      %s3 = simulation.context.storage %ctx[3] : !vref
      %s4 = simulation.context.storage %ctx[4] : !vref
      %s5 = simulation.context.storage %ctx[5] : !vref
      %gate = simulation.context.storage %ctx[6] : !vref
      %remaining = arith.constant true
      %zero = arith.constant false
      simulation.ref.store %zero to %clk : i1, !ref
      %clock = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p5 = simulation.spawn @step5(%ctx, %s4, %s5) : !simulation.context, !vref, !vref -> !simulation.process
      %p4 = simulation.spawn @step4(%ctx, %s3, %s4) : !simulation.context, !vref, !vref -> !simulation.process
      %p3 = simulation.spawn @step3(%ctx, %s2, %s3, %s1) : !simulation.context, !vref, !vref, !vref -> !simulation.process
      %p2 = simulation.spawn @step2(%ctx, %s1, %s2, %remaining) : !simulation.context, !vref, !vref, i1 -> !simulation.process
      %p1 = simulation.spawn @step1(%ctx, %clk, %s1, %gate) : !simulation.context, !ref, !vref, !vref -> !simulation.process
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

    simulation.func @step1(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %gate: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.any %input, %gate edges [0, 0] to ^body {site = #schedule.continuation<id = 2>} : !ref, !vref
    ^body:
      %v = simulation.ref.load %input : !ref -> i1
      %wide = arith.extui %v : i1 to i8
      %one = arith.constant 1 : i8
      %next = arith.addi %wide, %one : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @step2(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %remaining: i1 {simulation.capture_kind = 2 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 4 : i64} {
      %gate = simulation.context.storage %ctx[6] : !vref
      %seven = arith.constant 7 : i8
      simulation.ref.store %seven to %gate : i8, !vref
      cf.br ^wait(%remaining : i1)
    ^wait(%again: i1):
      simulation.suspend.change %input to ^body(%again : i1) : !vref
    ^body(%previous: i1):
      %v = simulation.ref.load %input : !vref -> i8
      %one = arith.constant 1 : i8
      %value = arith.addi %v, %one : i8
      simulation.ref.store %value to %output : i8, !vref
      %fmt = simulation.bytes.constant "boundary %0d count %0d"
      %count = arith.extui %previous : i1 to i8
      %channel = arith.constant 1 : i32
      simulation.display %ctx to %channel(%fmt, %value, %count) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i8, i8
      %last = arith.constant false
      cf.cond_br %previous, ^wait(%last : i1), ^done
    ^done:
      simulation.return
    }
    simulation.func @step3(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %shortcut: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.any %input, %shortcut edges [0, 0] to ^body {site = #schedule.continuation<id = 4>} : !vref, !vref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      %a = simulation.ref.load %shortcut : !vref -> i8
      %sum = arith.addi %v, %a : i8
      %one = arith.constant 1 : i8
      %next = arith.addi %sum, %one : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @step4(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 6 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %input to ^body {site = #schedule.continuation<id = 5>} : !vref
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
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}
