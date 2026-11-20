// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph))' -o %t.base
// RUN: talos-opt %t.base --pass-pipeline='builtin.module(simulation.design(talos-sim-fuse-observed-processes))' -o %t.fused 2> %t.report && FileCheck %s --check-prefix=FUSED < %t.report && FileCheck %s --check-prefix=HISTORY < %t.fused
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.initial_level set={value = true}},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph),simulation.design(talos-sim-fuse-observed-processes))' -o /dev/null 2>&1 | FileCheck %s --check-prefix=SPLIT
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.period set={value = 0 : i64}},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph),simulation.design(talos-sim-fuse-observed-processes))' -o /dev/null 2>&1 | FileCheck %s --check-prefix=SPLIT
// RUN: talos-opt %s --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{simulation.snapshot_publications}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=off},talos-sim-verify-compute-graph),simulation.design(talos-sim-fuse-observed-processes))' -o /dev/null 2>&1 | FileCheck %s --check-prefix=SPLIT
// RUN: talos-opt %t.fused --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph{vpi=off},talos-sim-materialize-graph-regions,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.lowered && FileCheck %s --check-prefix=VIEW < %t.lowered

// The copy starts at X. X -> 0 at startup is a negedge, so only posedge
// waits share a wake. After each positive delay both samples occur in
// Observed, after the Active copy has settled (1800-2023 4.5, 9.4.2).
// Starting the source high, a zero delay, or a UPF snapshot observer keeps
// the original waits. X -> 1 on the copy is a real posedge. The two members
// also use the same sampled-history site ID with different data. Each ring
// must yield X on the first edge and its own prior value on the second.
// On the third edge the first member to run requests finish. Its poll must
// return before the other member can report the same edge a second time.
// HISTORY-LABEL: simulation.func private @__talos_observed_0_1_0(
// HISTORY: simulation.call @finish_on_third
// HISTORY-NEXT: %[[FIRST:.*]] = simulation.termination.requested
// HISTORY-NEXT: cf.cond_br %[[FIRST]], ^[[EXIT:bb[0-9]+]],
// HISTORY: simulation.assert.sampled_history {{.*}} id 1 depth 1
// HISTORY: ^[[EXIT]]:
// HISTORY-NEXT: simulation.return
// HISTORY: simulation.call @finish_on_third
// HISTORY-NEXT: %[[SECOND:.*]] = simulation.termination.requested
// HISTORY-NEXT: cf.cond_br %[[SECOND]],
// HISTORY: simulation.assert.sampled_history {{.*}} id 2 depth 1
// VIEW-LABEL: llvm.func @__talos_observed_0_1_0.__talos_coro_ramp(
// VIEW: %[[PLANE_X:[0-9]+]] = llvm.call @talos_rt_v1_sampled_plane(
// VIEW: %[[PLANE_V:[0-9]+]] = llvm.call @talos_rt_v1_sampled_plane(
// VIEW: llvm.getelementptr %[[PLANE_V]]
// VIEW: llvm.getelementptr %[[PLANE_X]]
// VIEW: llvm.getelementptr %[[PLANE_V]]
// VIEW: llvm.getelementptr %[[PLANE_X]]
// VIEW-NOT: llvm.call @talos_rt_v1_sampled_plane(
// VIEW: llvm.func
// FUSED: talos observed kernel: __talos_observed_0_1_0 members=2
// FUSED: talos observed kernels: kernels=1 members=2
// SPLIT: talos observed kernels: kernels=0 members=0

!bit4 = !simulation.logic<1>
!clock = !simulation.ref<!bit4>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", native.debug_timing, native.closed_executable} {
  simulation.design @periodic_copy {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit4 design
    simulation.storage.decl 1 in 0 : !bit4 design
    simulation.storage.decl 2 in 0 : !bit4 design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "generator"
    simulation.code_unit.decl 3 in 0 port_input hierarchy "port"
    simulation.code_unit.decl 4 in 0 always hierarchy "direct"
    simulation.code_unit.decl 5 in 0 always hierarchy "copy"
    simulation.code_unit.decl 6 in 0 initial hierarchy "stop"
    simulation.code_unit.decl 7 in 0 function hierarchy "finish_on_third"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !clock
      %copy = simulation.context.storage %ctx[1] : !clock
      %low = simulation.logic.constant false, false {test.initial_level} : !bit4
      simulation.ref.store %low to %clk : !bit4, !clock
      %flag = simulation.context.storage %ctx[2] : !clock
      simulation.ref.store %low to %flag : !bit4, !clock
      %p = simulation.spawn @generator(%ctx, %clk) : !simulation.context, !clock -> !simulation.process
      %q = simulation.spawn @port(%ctx, %clk, %copy) : !simulation.context, !clock, !clock -> !simulation.process
      %r = simulation.spawn @direct(%ctx, %clk) : !simulation.context, !clock -> !simulation.process
      %s = simulation.spawn @copy(%ctx, %copy) : !simulation.context, !clock -> !simulation.process
      %t = simulation.spawn @stop(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func private @generator(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      cf.br ^wait
    ^wait:
      %delay = simulation.time.constant 5 {test.period}
      simulation.suspend.delay %delay to ^tick
    ^tick:
      %old = simulation.ref.load %clk : !clock -> !bit4
      %next = simulation.logic.unary bit_not %old : (!bit4) -> !bit4
      simulation.ref.store %next to %clk : !bit4, !clock
      cf.br ^wait
    }
    simulation.func private @port(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %dest: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 9 : i32, code_unit_id = 3 : i64} {
      cf.br ^loop
    ^loop:
      %v = simulation.ref.load %clk : !clock -> !bit4
      simulation.ref.store %v to %dest : !bit4, !clock
      simulation.suspend.change %clk to ^loop : !clock
    }
    simulation.func private @direct(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 8 : i32} : !clock
    ^body:
      simulation.call @finish_on_third(%ctx) : (!simulation.context) -> ()
      %finished = simulation.termination.requested %ctx
      cf.cond_br %finished, ^done, ^sample
    ^done:
      simulation.return
    ^sample:
      %fd = arith.constant 1 : i32
      %data = simulation.logic.constant false, false : !bit4
      %gate = arith.constant true
      %prior = simulation.assert.sampled_history %ctx from %data gate %gate id 7 depth 1 : (!simulation.context, !bit4, i1) -> !bit4
      %flag = simulation.context.storage %ctx[2] : !clock
      %sampled = simulation.assert.sampled_read %ctx from %flag : (!simulation.context, !clock) -> !bit4
      %text = simulation.bytes.constant "direct %b %b"
      simulation.display %ctx to %fd(%text, %prior, %sampled) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, !bit4, !bit4
      cf.br ^wait
    }
    simulation.func private @copy(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !clock {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 3 : i32, home_region = 8 : i32, code_unit_id = 5 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body {resume_region = 8 : i32} : !clock
    ^body:
      simulation.call @finish_on_third(%ctx) : (!simulation.context) -> ()
      %finished = simulation.termination.requested %ctx
      cf.cond_br %finished, ^done, ^sample
    ^done:
      simulation.return
    ^sample:
      %fd = arith.constant 1 : i32
      %data = simulation.logic.constant true, false : !bit4
      %gate = arith.constant true
      %prior = simulation.assert.sampled_history %ctx from %data gate %gate id 7 depth 1 : (!simulation.context, !bit4, i1) -> !bit4
      %flag = simulation.context.storage %ctx[2] : !clock
      %sampled = simulation.assert.sampled_read %ctx from %flag : (!simulation.context, !clock) -> !bit4
      %text = simulation.bytes.constant "copy %b %b"
      simulation.display %ctx to %fd(%text, %prior, %sampled) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, !bit4, !bit4
      cf.br ^wait
    }
    simulation.func private @stop(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %first = simulation.time.constant 10
      simulation.suspend.delay %first to ^change
    ^change:
      %flag = simulation.context.storage %ctx[2] : !clock
      %one = simulation.logic.constant true, false : !bit4
      simulation.ref.store %one to %flag : !bit4, !clock
      %delay = simulation.time.constant 21
      simulation.suspend.delay %delay to ^done
    ^done:
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
    simulation.func private @finish_on_third(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 8 : i32, code_unit_id = 7 : i64} {
      %now = simulation.time.now %ctx
      %third = arith.constant 25 : i64
      %last = arith.cmpi eq, %now, %third : i64
      cf.cond_br %last, ^stop, ^out
    ^stop:
      %fd = arith.constant 1 : i32
      %text = simulation.bytes.constant "done"
      simulation.display %ctx to %fd(%text) newline = true radix = <decimal> flags = [0] : !simulation.bytes
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      cf.br ^out
    ^out:
      simulation.return
    }
  }
}
