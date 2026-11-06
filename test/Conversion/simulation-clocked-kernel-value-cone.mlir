// RUN: %split-file %s %t
// RUN: talos-opt %t/independent.mlir --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels))' | FileCheck %s
// RUN: talos-opt %t/control.mlir --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels))' | FileCheck %s --check-prefix=CONTROL
// RUN: talos-opt %t/intermediate.mlir --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels))' | FileCheck %s --check-prefix=INTERMEDIATE
// RUN: talos-opt %t/independent.mlir --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels,simulation.func(talos-sim-thread-suspension),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe
// RUN: %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// A reader of one combinational output exposes only its value cone, while
// control-only and overwritten publications remain in the cone. Preserve
// old Active/#0 observations and old RHS values (IEEE 1800-2023 4.3-4.9.4).
// An odd number of edges also detects a missing direct-store wake.
// OUTPUT: {{^}}1 1 1{{$}}

//--- independent.mlir
!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32} {
  simulation.design @separate_outputs {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "toggle"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "follow"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "route"
    simulation.code_unit.decl 6 in 0 initial hierarchy "sampler"
    simulation.code_unit.decl 7 in 0 initial hierarchy "report"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %r = simulation.context.storage %ctx[2] : !ref
      %seen = simulation.context.storage %ctx[3] : !ref
      %inactive_seen = simulation.context.storage %ctx[6] : !ref
      %routed_q = simulation.context.storage %ctx[4] : !ref
      %routed_r = simulation.context.storage %ctx[5] : !ref
      %init = simulation.logic.constant false, false : !bit
      simulation.ref.store %init to %clk : !bit, !ref
      simulation.ref.store %init to %q : !bit, !ref
      simulation.ref.store %init to %r : !bit, !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @toggle(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @follow(%ctx, %clk, %q, %r) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @route(%ctx, %q, %r, %routed_q, %routed_r) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @sampler(%ctx, %clk, %routed_r, %seen, %inactive_seen) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      %p5 = simulation.spawn @report(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    // CHECK-LABEL: simulation.func private @__talos_clocked_0_{{[0-9]+}}_0
    // CHECK: simulation.suspend.edge posedge
    // follow reads the incoming q and retains its NBA to r.
    // CHECK: simulation.ref.load
    // CHECK-NEXT: simulation.nba.enqueue
    // CHECK: simulation.logic.unary logical_not
    // CHECK-NEXT: simulation.ref.store {{.*}}schedule.eval.nba_equivalent_store
    // CHECK-NOT: simulation.nba.enqueue
    // CHECK: cf.br
    simulation.func private @toggle(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @follow(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %value = simulation.ref.load %q : !ref -> !bit
      simulation.nba.enqueue %value to %r : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func @route(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %routed_q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}, %routed_r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
      cf.br ^body
    ^body:
      %a = simulation.ref.load %q : !ref -> !bit
      %b = simulation.ref.load %r : !ref -> !bit
      simulation.ref.store %a to %routed_q : !bit, !ref
      simulation.ref.store %b to %routed_r : !bit, !ref
      simulation.suspend.any %q, %r edges [0, 0] to ^body : !ref, !ref
    }
    simulation.func @sampler(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %routed_r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %inactive_seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %zero_delay = simulation.time.constant 0
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %value = simulation.ref.load %routed_r : !ref -> !bit
      simulation.ref.store %value to %seen : !bit, !ref
      simulation.suspend.delay %zero_delay to ^inactive
    ^inactive:
      %after_zero = simulation.ref.load %routed_r : !ref -> !bit
      simulation.ref.store %after_zero to %inactive_seen : !bit, !ref
      cf.br ^wait
    }
    simulation.func @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 7 : i64} {
      %delay = simulation.time.constant 86
      simulation.suspend.delay %delay to ^done
    ^done:
      %q = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[3] : !ref
      %a = simulation.ref.load %q : !ref -> !bit
      %b = simulation.ref.load %seen : !ref -> !bit
      %inactive_seen = simulation.context.storage %ctx[6] : !ref
      %c = simulation.ref.load %inactive_seen : !ref -> !bit
      %stdout = arith.constant -2147483647 : i32
      %format = simulation.bytes.constant "%b %b %b"
      simulation.display %ctx to %stdout(%format, %a, %b, %c) newline = true radix = <binary> flags = [0, 0, 0, 0] : !simulation.bytes, !bit, !bit, !bit
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}

//--- control.mlir
!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32} {
  // CONTROL-LABEL: simulation.design @control_dependency
  simulation.design @control_dependency {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "toggle"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "follow"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "route"
    simulation.code_unit.decl 6 in 0 initial hierarchy "sampler"
    simulation.code_unit.decl 7 in 0 initial hierarchy "report"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %r = simulation.context.storage %ctx[2] : !ref
      %seen = simulation.context.storage %ctx[3] : !ref
      %inactive_seen = simulation.context.storage %ctx[6] : !ref
      %routed_q = simulation.context.storage %ctx[4] : !ref
      %routed_r = simulation.context.storage %ctx[5] : !ref
      %init = simulation.logic.constant false, false : !bit
      simulation.ref.store %init to %clk : !bit, !ref
      simulation.ref.store %init to %q : !bit, !ref
      simulation.ref.store %init to %r : !bit, !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @toggle(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @follow(%ctx, %clk, %q, %r) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @route(%ctx, %q, %r, %routed_q, %routed_r) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @sampler(%ctx, %clk, %routed_r, %seen, %inactive_seen) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      %p5 = simulation.spawn @report(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    // CONTROL-LABEL: simulation.func private @toggle(
    // CONTROL: simulation.nba.enqueue
    simulation.func private @toggle(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @follow(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %value = simulation.ref.load %q : !ref -> !bit
      simulation.nba.enqueue %value to %r : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func @route(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %routed_q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}, %routed_r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
      cf.br ^body
    ^body:
      %a = simulation.ref.load %q : !ref -> !bit
      %b = simulation.ref.load %r : !ref -> !bit
      %condition = simulation.logic.is_true %a : !bit
      %not_b = simulation.logic.unary logical_not %b : (!bit) -> !bit
      cf.cond_br %condition, ^yes, ^no
    ^yes:
      simulation.ref.store %b to %routed_r : !bit, !ref
      cf.br ^done
    ^no:
      simulation.ref.store %not_b to %routed_r : !bit, !ref
      cf.br ^done
    ^done:
      simulation.ref.store %a to %routed_q : !bit, !ref
      simulation.suspend.any %q, %r edges [0, 0] to ^body : !ref, !ref
    }
    simulation.func @sampler(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %routed_r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %inactive_seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %zero_delay = simulation.time.constant 0
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %value = simulation.ref.load %routed_r : !ref -> !bit
      simulation.ref.store %value to %seen : !bit, !ref
      simulation.suspend.delay %zero_delay to ^inactive
    ^inactive:
      %after_zero = simulation.ref.load %routed_r : !ref -> !bit
      simulation.ref.store %after_zero to %inactive_seen : !bit, !ref
      cf.br ^wait
    }
    simulation.func @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 7 : i64} {
      %delay = simulation.time.constant 86
      simulation.suspend.delay %delay to ^done
    ^done:
      %q = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[3] : !ref
      %a = simulation.ref.load %q : !ref -> !bit
      %b = simulation.ref.load %seen : !ref -> !bit
      %inactive_seen = simulation.context.storage %ctx[6] : !ref
      %c = simulation.ref.load %inactive_seen : !ref -> !bit
      %stdout = arith.constant -2147483647 : i32
      %format = simulation.bytes.constant "%b %b %b"
      simulation.display %ctx to %stdout(%format, %a, %b, %c) newline = true radix = <binary> flags = [0, 0, 0, 0] : !simulation.bytes, !bit, !bit, !bit
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}

//--- intermediate.mlir
!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32} {
  // INTERMEDIATE-LABEL: simulation.design @intermediate_dependency
  simulation.design @intermediate_dependency {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "toggle"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "follow"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "route"
    simulation.code_unit.decl 6 in 0 initial hierarchy "sampler"
    simulation.code_unit.decl 7 in 0 initial hierarchy "report"
    simulation.func @root(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 0 : i32, code_unit_id = 1 : i64} {
      %clk = simulation.context.storage %ctx[0] : !ref
      %q = simulation.context.storage %ctx[1] : !ref
      %r = simulation.context.storage %ctx[2] : !ref
      %seen = simulation.context.storage %ctx[3] : !ref
      %inactive_seen = simulation.context.storage %ctx[6] : !ref
      %routed_q = simulation.context.storage %ctx[4] : !ref
      %routed_r = simulation.context.storage %ctx[5] : !ref
      %init = simulation.logic.constant false, false : !bit
      simulation.ref.store %init to %clk : !bit, !ref
      simulation.ref.store %init to %q : !bit, !ref
      simulation.ref.store %init to %r : !bit, !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @toggle(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @follow(%ctx, %clk, %q, %r) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @route(%ctx, %q, %r, %routed_q, %routed_r) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @sampler(%ctx, %clk, %routed_r, %seen, %inactive_seen) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      %p5 = simulation.spawn @report(%ctx) : !simulation.context -> !simulation.process
      simulation.return
    }
    simulation.func @clock(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 2 : i64} {
      %delay = simulation.time.constant 5
      %one = simulation.logic.constant true, false : !bit
      %zero = simulation.logic.constant false, false : !bit
      cf.br ^low
    ^low:
      simulation.suspend.delay %delay to ^rise
    ^rise:
      simulation.nba.enqueue %one to %clk : (!bit, !ref) -> ()
      simulation.suspend.delay %delay to ^fall
    ^fall:
      simulation.nba.enqueue %zero to %clk : (!bit, !ref) -> ()
      cf.br ^low
    }
    // INTERMEDIATE-LABEL: simulation.func private @toggle(
    // INTERMEDIATE: simulation.nba.enqueue
    simulation.func private @toggle(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 3 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %old = simulation.ref.load %q : !ref -> !bit
      %next = simulation.logic.unary logical_not %old : (!bit) -> !bit
      simulation.nba.enqueue %next to %q : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func private @follow(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 4 : i64} {
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %value = simulation.ref.load %q : !ref -> !bit
      simulation.nba.enqueue %value to %r : (!bit, !ref) -> ()
      cf.br ^wait
    }
    simulation.func @route(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 1 : i64}, %r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 2 : i64}, %routed_q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 4 : i64}, %routed_r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 5 : i64} {
      cf.br ^body
    ^body:
      %a = simulation.ref.load %q : !ref -> !bit
      %b = simulation.ref.load %r : !ref -> !bit
      simulation.ref.store %a to %routed_q : !bit, !ref
      simulation.ref.store %a to %routed_r : !bit, !ref
      simulation.ref.store %b to %routed_r : !bit, !ref
      simulation.suspend.any %q, %r edges [0, 0] to ^body : !ref, !ref
    }
    simulation.func @sampler(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %routed_r: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 5 : i64}, %seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 3 : i64}, %inactive_seen: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 6 : i64}) attributes {entry_kind = 1 : i32, code_unit_id = 6 : i64} {
      %zero_delay = simulation.time.constant 0
      cf.br ^wait
    ^wait:
      simulation.suspend.edge posedge %clk to ^body : !ref
    ^body:
      %value = simulation.ref.load %routed_r : !ref -> !bit
      simulation.ref.store %value to %seen : !bit, !ref
      simulation.suspend.delay %zero_delay to ^inactive
    ^inactive:
      %after_zero = simulation.ref.load %routed_r : !ref -> !bit
      simulation.ref.store %after_zero to %inactive_seen : !bit, !ref
      cf.br ^wait
    }
    simulation.func @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 7 : i64} {
      %delay = simulation.time.constant 86
      simulation.suspend.delay %delay to ^done
    ^done:
      %q = simulation.context.storage %ctx[4] : !ref
      %seen = simulation.context.storage %ctx[3] : !ref
      %a = simulation.ref.load %q : !ref -> !bit
      %b = simulation.ref.load %seen : !ref -> !bit
      %inactive_seen = simulation.context.storage %ctx[6] : !ref
      %c = simulation.ref.load %inactive_seen : !ref -> !bit
      %stdout = arith.constant -2147483647 : i32
      %format = simulation.bytes.constant "%b %b %b"
      simulation.display %ctx to %stdout(%format, %a, %b, %c) newline = true radix = <binary> flags = [0, 0, 0, 0] : !simulation.bytes, !bit, !bit, !bit
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}
