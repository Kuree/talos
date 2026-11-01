// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.mlir 2> %t.trace
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=TRACE < %t.trace
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 1 : i64}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s --check-prefix=SMALL
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 0 : i64}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s --check-prefix=UNLIMITED

// IEEE 1800-2023 4.3, 9.2.2.2.1, 10.3.2: the complete, exclusive outputs of a
// repeatable activation already hold what its live input lanes compute, so
// running it after a change elsewhere is not observable. Its generated wakes
// cover one hull of live lanes per source watch. The source wait keeps its whole
// sensitivity for the generic scheduler. Rows are [state, actor, continuation,
// edge = change, node, route, low bit, width, kernel, owner], sorted by state.
// CHECK: llvm.mlir.global internal constant @__talos_aot_static_fanout_v1(
// One live nibble of the source.
// CHECK-SAME: [2 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 4,
// Bits 7:6 and 1:0 are live: one wake covers the hole, an unobservable rerun.
// CHECK-SAME: [4 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 8,
// The live watch keeps its wake and the dead one (state 7) has none.
// CHECK-SAME: [6 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 8,
// CHECK-NOT: [7 : i32,
// A branch condition is live: one bit of the selector, and both data sources.
// CHECK-SAME: [9 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 1,
// CHECK-SAME: [10 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 8,
// CHECK-SAME: [11 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 8,
// With no live lane at all, the activation keeps its source wait: it needs an
// owner even though no wake could change its outputs.
// CHECK-SAME: [13 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 8,
// A repeated write is an intermediate publication, so its owner is not
// repeatable: every sensitivity stays, although only a nibble reaches the output.
// CHECK-SAME: [15 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 8,

// The source wait of cycle_a watches all of the root cycle_b writes, but only
// the other half is live, so the sensitivity is no ordering edge and no cycle.
// CHECK-SAME: [17 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 8,
// TRACE: talos eval dependency: owner=[[A:[0-9]+]] {{.*}}body=cycle_a.__talos_eval_body_0 successors=[[B:[0-9]+]]{{$}}
// TRACE: talos eval dependency: owner=[[B]] {{.*}}body=cycle_b.__talos_eval_body_0 successors={{$}}

// Lane analysis stays within the inline budget: above it, wakes are whole.
// SMALL: llvm.mlir.global internal constant @__talos_aot_static_fanout_v1(
// SMALL-SAME: [2 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 8,
// SMALL-SAME: [7 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 8,
// Zero removes the budget, as for every other native inline decision.
// UNLIMITED: llvm.mlir.global internal constant @__talos_aot_static_fanout_v1(
// UNLIMITED-SAME: [2 : i32, {{[0-9]+}} : i32, {{[0-9]+}} : i32, 0 : i32, {{[0-9]+}} : i32, 1 : i32, 0, 4,

!vref = !simulation.ref<i8>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", llvm.target_triple = "x86_64-unknown-linux-gnu", schedule.native_scheduler = 3 : i32, native.debug_timing} {
  simulation.design @live_lanes {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : i1 design
    simulation.storage.decl 1 in 0 : i8 design
    simulation.storage.decl 2 in 0 : i8 design
    simulation.storage.decl 3 in 0 : i8 design
    simulation.storage.decl 4 in 0 : i8 design
    simulation.storage.decl 5 in 0 : i8 design
    simulation.storage.decl 6 in 0 : i8 design
    simulation.storage.decl 7 in 0 : i8 design
    simulation.storage.decl 8 in 0 : i8 design
    simulation.storage.decl 9 in 0 : i8 design
    simulation.storage.decl 10 in 0 : i8 design
    simulation.storage.decl 11 in 0 : i8 design
    simulation.storage.decl 12 in 0 : i8 design
    simulation.storage.decl 13 in 0 : i8 design
    simulation.storage.decl 14 in 0 : i8 design
    simulation.storage.decl 15 in 0 : i8 design
    simulation.storage.decl 16 in 0 : !simulation.logic<16> design
    simulation.storage.decl 17 in 0 : !simulation.logic<8> design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 always hierarchy "clock"
    simulation.code_unit.decl 9 in 0 initial hierarchy "check"
    simulation.code_unit.decl 10 in 0 continuous hierarchy "cycle_a"
    simulation.code_unit.decl 11 in 0 continuous hierarchy "cycle_b"
    simulation.code_unit.decl 3 in 0 continuous hierarchy "low_nibble"
    simulation.code_unit.decl 4 in 0 continuous hierarchy "hull"
    simulation.code_unit.decl 5 in 0 continuous hierarchy "dead_watch"
    simulation.code_unit.decl 6 in 0 continuous hierarchy "control"
    simulation.code_unit.decl 7 in 0 continuous hierarchy "no_live_lane"
    simulation.code_unit.decl 8 in 0 continuous hierarchy "repeated_write"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %s1 = simulation.context.storage %ctx[1] : !vref
      %s2 = simulation.context.storage %ctx[2] : !vref
      %s3 = simulation.context.storage %ctx[3] : !vref
      %s4 = simulation.context.storage %ctx[4] : !vref
      %s5 = simulation.context.storage %ctx[5] : !vref
      %s6 = simulation.context.storage %ctx[6] : !vref
      %s7 = simulation.context.storage %ctx[7] : !vref
      %s8 = simulation.context.storage %ctx[8] : !vref
      %s9 = simulation.context.storage %ctx[9] : !vref
      %s10 = simulation.context.storage %ctx[10] : !vref
      %s11 = simulation.context.storage %ctx[11] : !vref
      %s12 = simulation.context.storage %ctx[12] : !vref
      %s13 = simulation.context.storage %ctx[13] : !vref
      %s14 = simulation.context.storage %ctx[14] : !vref
      %s15 = simulation.context.storage %ctx[15] : !vref
      %p0 = simulation.spawn @low_nibble(%ctx, %s1, %s2) : !simulation.context, !vref, !vref -> !simulation.process
      %p1 = simulation.spawn @hull(%ctx, %s3, %s4) : !simulation.context, !vref, !vref -> !simulation.process
      %p2 = simulation.spawn @dead_watch(%ctx, %s5, %s6, %s7) : !simulation.context, !vref, !vref, !vref -> !simulation.process
      %p3 = simulation.spawn @control(%ctx, %s8, %s9, %s10, %s11) : !simulation.context, !vref, !vref, !vref, !vref -> !simulation.process
      %p4 = simulation.spawn @no_live_lane(%ctx, %s12, %s13) : !simulation.context, !vref, !vref -> !simulation.process
      %p5 = simulation.spawn @repeated_write(%ctx, %s14, %s15) : !simulation.context, !vref, !vref -> !simulation.process
      %clk = simulation.context.storage %ctx[0] : !simulation.ref<i1>
      %zero = arith.constant false
      simulation.ref.store %zero to %clk : i1, !simulation.ref<i1>
      %clock = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !simulation.ref<i1> -> !simulation.process
      %check = simulation.spawn @check(%ctx) : !simulation.context -> !simulation.process
      %s16 = simulation.context.storage %ctx[16] : !simulation.ref<!simulation.logic<16>>
      %s17 = simulation.context.storage %ctx[17] : !simulation.ref<!simulation.logic<8>>
      %cycleA = simulation.spawn @cycle_a(%ctx, %s16, %s17) : !simulation.context, !simulation.ref<!simulation.logic<16>>, !simulation.ref<!simulation.logic<8>> -> !simulation.process
      %cycleB = simulation.spawn @cycle_b(%ctx, %s17, %s16) : !simulation.context, !simulation.ref<!simulation.logic<8>>, !simulation.ref<!simulation.logic<16>> -> !simulation.process
      simulation.return
    }
    simulation.func @cycle_a(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %root: !simulation.ref<!simulation.logic<16>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 16 : i64}, %out: !simulation.ref<!simulation.logic<8>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 17 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 10 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %root to ^body {site = #schedule.continuation<id = 60>} : !simulation.ref<!simulation.logic<16>>
    ^body:
      %low = simulation.ref.extract %root from 0 : !simulation.ref<!simulation.logic<16>> -> !simulation.ref<!simulation.logic<8>>
      %v = simulation.ref.load %low : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      simulation.ref.store %v to %out : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      cf.br ^wait
    }
    simulation.func @cycle_b(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %in: !simulation.ref<!simulation.logic<8>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 17 : i64}, %root: !simulation.ref<!simulation.logic<16>> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 16 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 11 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %in to ^body {site = #schedule.continuation<id = 61>} : !simulation.ref<!simulation.logic<8>>
    ^body:
      %v = simulation.ref.load %in : !simulation.ref<!simulation.logic<8>> -> !simulation.logic<8>
      %high = simulation.ref.extract %root from 8 : !simulation.ref<!simulation.logic<16>> -> !simulation.ref<!simulation.logic<8>>
      simulation.ref.store %v to %high : !simulation.logic<8>, !simulation.ref<!simulation.logic<8>>
      cf.br ^wait
    }
    simulation.func @check(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 9 : i64} {
      %delay = simulation.time.constant 3
      simulation.suspend.delay %delay to ^first
    ^first:
      %o1 = simulation.context.storage %ctx[2] : !vref
      %o2 = simulation.context.storage %ctx[4] : !vref
      %o3 = simulation.context.storage %ctx[7] : !vref
      %o4 = simulation.context.storage %ctx[11] : !vref
      %o5 = simulation.context.storage %ctx[13] : !vref
      %o6 = simulation.context.storage %ctx[15] : !vref
      %v1 = simulation.ref.load %o1 : !vref -> i8
      %v2 = simulation.ref.load %o2 : !vref -> i8
      %v3 = simulation.ref.load %o3 : !vref -> i8
      %v4 = simulation.ref.load %o4 : !vref -> i8
      %v5 = simulation.ref.load %o5 : !vref -> i8
      %v6 = simulation.ref.load %o6 : !vref -> i8
      %hi = simulation.context.storage %ctx[16] : !simulation.ref<!simulation.logic<16>>
      %hv = simulation.ref.load %hi : !simulation.ref<!simulation.logic<16>> -> !simulation.logic<16>
      %hfmt = simulation.bytes.constant "%0d"
      %hch = arith.constant 1 : i32
      simulation.display %ctx to %hch(%hfmt, %hv) newline = true radix = <decimal> flags = [0, 0] : !simulation.bytes, !simulation.logic<16>
      %fmt = simulation.bytes.constant "%0d %0d %0d %0d %0d %0d"
      %channel = arith.constant 1 : i32
      simulation.display %ctx to %channel(%fmt, %v1, %v2, %v3, %v4, %v5, %v6) newline = true radix = <decimal> flags = [0, 0, 0, 0, 0, 0, 0] : !simulation.bytes, i8, i8, i8, i8, i8, i8
      %zero32 = arith.constant 0 : i32
      simulation.finish %ctx, %zero32
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !simulation.ref<i1> {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 2
      simulation.suspend.delay %delay to ^toggle {site = #schedule.continuation<id = 1>, timing = #schedule.timing_site<id = 0, kind = calendar>}
    ^toggle:
      %old = simulation.ref.load %clk : !simulation.ref<i1> -> i1
      %one = arith.constant true
      %new = arith.xori %old, %one : i1
      simulation.ref.store %new to %clk : i1, !simulation.ref<i1>
      cf.br ^wait
    }
    simulation.func @low_nibble(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %o: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 3 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %a to ^body {site = #schedule.continuation<id = 2>} : !vref
    ^body:
      %v = simulation.ref.load %a : !vref -> i8
      %low = arith.trunci %v : i8 to i4
      %wide = arith.extui %low : i4 to i8
      simulation.ref.store %wide to %o : i8, !vref
      cf.br ^wait
    }
    simulation.func @hull(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %o: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 4 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %a to ^body {site = #schedule.continuation<id = 3>} : !vref
    ^body:
      %v = simulation.ref.load %a : !vref -> i8
      %c6 = arith.constant 6 : i8
      %c3 = arith.constant 3 : i8
      %high = arith.shrui %v, %c6 : i8
      %low = arith.andi %v, %c3 : i8
      %next = arith.addi %high, %low : i8
      simulation.ref.store %next to %o : i8, !vref
      cf.br ^wait
    }
    simulation.func @dead_watch(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %x: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}, %y: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}, %o: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 7 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 5 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.any %x, %y edges [0, 0] to ^body {site = #schedule.continuation<id = 4>} : !vref, !vref
    ^body:
      %v = simulation.ref.load %x : !vref -> i8
      %ignored = simulation.ref.load %y : !vref -> i8
      simulation.ref.store %v to %o : i8, !vref
      cf.br ^wait
    }
    simulation.func @control(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %s: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 8 : i64}, %c: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 9 : i64}, %d: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}, %o: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 11 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 6 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.any %s, %c, %d edges [0, 0, 0] to ^body {site = #schedule.continuation<id = 5>} : !vref, !vref, !vref
    ^body:
      %sv = simulation.ref.load %s : !vref -> i8
      %bit = arith.trunci %sv : i8 to i1
      %cv = simulation.ref.load %c : !vref -> i8
      %dv = simulation.ref.load %d : !vref -> i8
      cf.cond_br %bit, ^then, ^else
    ^then:
      simulation.ref.store %cv to %o : i8, !vref
      cf.br ^join
    ^else:
      simulation.ref.store %dv to %o : i8, !vref
      cf.br ^join
    ^join:
      cf.br ^wait
    }
    simulation.func @no_live_lane(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 12 : i64}, %o: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 13 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 7 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %a to ^body {site = #schedule.continuation<id = 6>} : !vref
    ^body:
      %ignored = simulation.ref.load %a : !vref -> i8
      %c = arith.constant 7 : i8
      simulation.ref.store %c to %o : i8, !vref
      cf.br ^wait
    }
    simulation.func @repeated_write(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %a: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 14 : i64}, %o: !vref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 15 : i64}) attributes {entry_kind = 7 : i32, code_unit_id = 8 : i64} {
      cf.br ^body
    ^wait:
      simulation.suspend.change %a to ^body {site = #schedule.continuation<id = 7>} : !vref
    ^body:
      %v = simulation.ref.load %a : !vref -> i8
      %low = arith.trunci %v : i8 to i4
      %wide = arith.extui %low : i4 to i8
      %c = arith.constant 0 : i8
      simulation.ref.store %c to %o : i8, !vref
      simulation.ref.store %wide to %o : i8, !vref
      cf.br ^wait
    }
  }
}
