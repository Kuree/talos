// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.mlir 2> %t.trace
// RUN: FileCheck %s --check-prefix=PLAN < %t.trace

// Four processes form a real feedback ring. The second writes a pulse and
// must retain its own ready predicate. Its publications are all forward.
// A seed propagates
// around it and holds after the seed drops. Opening the ring clears every
// stage, including those reached again by the feedback edge (1800-2023 4.5).
// PLAN: talos repeatable activations: 3
// The last publisher closes the ring and retains its convergence poll.
// PLAN: talos eval refined convergence: owners=3
// PLAN-NEXT: talos eval executor inventory: tier1=3 tier2=1 runtime_checkpoints=0
// PLAN: talos eval component: owner=3 {{.*}}cyclic=1 {{.*}}feedback=0

!ref = !simulation.ref<i1>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable, schedule.force_generic_nba, native.debug_timing} {
  simulation.design @feedback_ring {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i1 design
    simulation.storage.decl 2 in 0 : i1 design
    simulation.storage.decl 3 in 0 : i1 design
    simulation.storage.decl 4 in 0 : i1 design
    simulation.storage.decl 5 in 0 : i1 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always_comb hierarchy "first"
    simulation.code_unit.decl 3 in 0 always_comb hierarchy "second"
    simulation.code_unit.decl 4 in 0 always_comb hierarchy "third"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "last"
    simulation.code_unit.decl 6 in 0 initial hierarchy "drive"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %a = simulation.context.storage %ctx[0] : !ref
      %b = simulation.context.storage %ctx[1] : !ref
      %c = simulation.context.storage %ctx[2] : !ref
      %d = simulation.context.storage %ctx[3] : !ref
      %seed = simulation.context.storage %ctx[4] : !ref
      %gate = simulation.context.storage %ctx[5] : !ref
      %p0 = simulation.spawn @first(%ctx, %d, %seed, %a) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p1 = simulation.spawn @second(%ctx, %a, %b) : !simulation.context, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @third(%ctx, %b, %c) : !simulation.context, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @last(%ctx, %c, %gate, %d) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %reader = simulation.spawn @drive(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @first(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %enable: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}, %out: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 2 : i64} {
      cf.br ^eval
    ^eval:
      %value = simulation.ref.load %in : !ref -> i1
      %enable_bit = simulation.ref.load %enable : !ref -> i1
      %next = arith.ori %value, %enable_bit : i1
      simulation.ref.store %next to %out : i1, !ref
      simulation.suspend.any %in, %enable edges [0, 0] to ^eval {site = #schedule.continuation<id = 1>} : !ref, !ref
    }
    simulation.func @second(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %out: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 3 : i64} {
      cf.br ^eval
    ^eval:
      %value = simulation.ref.load %in : !ref -> i1
      %pulse = arith.constant false
      simulation.ref.store %pulse to %out : i1, !ref
      simulation.ref.store %value to %out : i1, !ref
      simulation.suspend.change %in to ^eval {site = #schedule.continuation<id = 2>} : !ref
    }
    simulation.func @third(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %out: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 4 : i64} {
      cf.br ^eval
    ^eval:
      %value = simulation.ref.load %in : !ref -> i1
      simulation.ref.store %value to %out : i1, !ref
      simulation.suspend.change %in to ^eval {site = #schedule.continuation<id = 3>} : !ref
    }
    simulation.func @last(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %enable: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}, %out: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
      cf.br ^eval
    ^eval:
      %value = simulation.ref.load %in : !ref -> i1
      %enable_bit = simulation.ref.load %enable : !ref -> i1
      %next = arith.andi %value, %enable_bit : i1
      simulation.ref.store %next to %out : i1, !ref
      simulation.suspend.any %in, %enable edges [0, 0] to ^eval {site = #schedule.continuation<id = 4>} : !ref, !ref
    }
    simulation.func @drive(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %seed = simulation.context.storage %ctx[4] : !ref
      %gate = simulation.context.storage %ctx[5] : !ref
      %on = arith.constant true
      %off = arith.constant false
      %delay = simulation.time.constant 2
      simulation.suspend.delay %delay to ^set
    ^set:
      simulation.ref.store %on to %seed : i1, !ref
      simulation.ref.store %on to %gate : i1, !ref
      simulation.suspend.delay %delay to ^hold
    ^hold:
      simulation.ref.store %off to %seed : i1, !ref
      simulation.suspend.delay %delay to ^inspect
    ^inspect:
      %ref_a = simulation.context.storage %ctx[0] : !ref
      %held_a = simulation.ref.load %ref_a : !ref -> i1
      %ref_b = simulation.context.storage %ctx[1] : !ref
      %held_b = simulation.ref.load %ref_b : !ref -> i1
      %ref_c = simulation.context.storage %ctx[2] : !ref
      %held_c = simulation.ref.load %ref_c : !ref -> i1
      %ref_d = simulation.context.storage %ctx[3] : !ref
      %held_d = simulation.ref.load %ref_d : !ref -> i1
      %fmt = simulation.bytes.constant "%b%b%b%b"
      %fd = arith.constant 1 : i32
      simulation.display %ctx to %fd(%fmt, %held_a, %held_b, %held_c, %held_d) newline = true radix = <decimal> flags = [0, 0, 0, 0, 0] : !simulation.bytes, i1, i1, i1, i1
      simulation.ref.store %off to %gate : i1, !ref
      simulation.suspend.delay %delay to ^check
    ^check:
      %final_a = simulation.ref.load %ref_a : !ref -> i1
      %final_b = simulation.ref.load %ref_b : !ref -> i1
      %final_c = simulation.ref.load %ref_c : !ref -> i1
      %final_d = simulation.ref.load %ref_d : !ref -> i1
      simulation.display %ctx to %fd(%fmt, %final_a, %final_b, %final_c, %final_d) newline = true radix = <decimal> flags = [0, 0, 0, 0, 0] : !simulation.bytes, i1, i1, i1, i1
      %status = arith.constant 0 : i32
      simulation.finish %ctx, %status
      simulation.return
    }
  }
}
