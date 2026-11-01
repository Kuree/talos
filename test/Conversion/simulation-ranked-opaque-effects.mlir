// RUN: not talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o /dev/null 2> %t.trace
// RUN: FileCheck %s < %t.trace

// An effect outside the state inventory orders only what it can depend on: an
// unknown read needs every writer first, and only an unknown write precedes
// every other actor. So the observer below, whose event read is such an effect,
// is a sink, and the unrelated owner gets no edge from it. Treating it as both
// would join every owner of the design into one cycle through it (IEEE 1800-2023
// 4.7 leaves their order free). Lowering then rejects this body's runtime call in
// the eval closure, which is why the trace stops there.
// CHECK: talos eval dependency: owner=0 island=0 body=after.__talos_eval_body_0 successors=2{{$}}
// CHECK-NEXT: talos eval dependency: owner=1 island=0 body=writer.__talos_eval_body_0 successors=2{{$}}
// CHECK-NEXT: talos eval boundary: owner=2 island=0 body=observer.__talos_eval_body_0 successors={{$}}

!vref = !simulation.ref<i8>
!eref = !simulation.ref<!simulation.event>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.debug_timing} {
  simulation.design @opaque_effects {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !simulation.event design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 continuous hierarchy "writer"
    simulation.code_unit.decl 3 in 0 always hierarchy "observer"
    simulation.code_unit.decl 4 in 0 continuous hierarchy "after"
    simulation.code_unit.decl 5 in 0 initial hierarchy "check"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %e = simulation.context.storage %ctx[0] : !eref
      %s1 = simulation.context.storage %ctx[1] : !vref
      %s2 = simulation.context.storage %ctx[2] : !vref
      %s3 = simulation.context.storage %ctx[3] : !vref
      %s4 = simulation.context.storage %ctx[4] : !vref
      %s5 = simulation.context.storage %ctx[5] : !vref
      %p0 = simulation.spawn @writer(%ctx, %s1, %s2) : !simulation.context, !vref, !vref -> !simulation.process
      %p1 = simulation.spawn @observer(%ctx, %e, %s2, %s3) : !simulation.context, !eref, !vref, !vref -> !simulation.process
      %p2 = simulation.spawn @after(%ctx, %s4, %s5) : !simulation.context, !vref, !vref -> !simulation.process
      %c = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @writer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 2 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %input to ^body {site = #schedule.continuation<id = 2>} : !vref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      simulation.ref.store %v to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @observer(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %event: !eref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.change %input to ^body {site = #schedule.continuation<id = 3>} : !vref
    ^body:
      %ev = simulation.ref.load %event : !eref -> !simulation.event
      %hit = simulation.event.triggered %ev
      %v = simulation.ref.load %input : !vref -> i8
      %one = arith.constant 1 : i8
      %next = arith.select %hit, %one, %v : i8
      simulation.ref.store %next to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @after(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %input: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}, %output: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %input to ^body {site = #schedule.continuation<id = 4>} : !vref
    ^body:
      %v = simulation.ref.load %input : !vref -> i8
      simulation.ref.store %v to %output : i8, !vref
      cf.br ^wait
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 5 : i64} {
      %delay = simulation.time.constant 3
      simulation.suspend.delay %delay to ^first
    ^first:
      %o = simulation.context.storage %ctx[3] : !vref
      %v = simulation.ref.load %o : !vref -> i8
      %o2 = simulation.context.storage %ctx[5] : !vref
      %v2 = simulation.ref.load %o2 : !vref -> i8
      %fmt = simulation.bytes.constant "%0d %0d"
      %channel = arith.constant 1 : i32
      simulation.display %ctx to %channel(%fmt, %v, %v2) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i8, i8
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}
