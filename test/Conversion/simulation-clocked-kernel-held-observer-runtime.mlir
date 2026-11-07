// RUN: talos-opt %s --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-fuse-clocked-kernels))' -o %t.sim.mlir
// RUN: FileCheck %s --check-prefix=KEEP --implicit-check-not='schedule.eval.nba_equivalent_store' < %t.sim.mlir
// RUN: talos-opt %s --test-talos-activation-regions='functions=route,route_explicit idempotence=true reaching-values=true' -o /dev/null 2>&1 | FileCheck %s --check-prefix=PROOF
// RUN: talos-opt %t.sim.mlir --pass-pipeline='builtin.module(simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.o
// RUN: %target_cxx %t.o %runtime_link_flags -o %t.exe && %t.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O0>' | %llc -filetype=obj -relocation-model=pic -o %t.o0.o
// RUN: %target_cxx %t.o0.o %runtime_link_flags -o %t.o0.exe && %t.o0.exe --execution-tier=native | FileCheck %s --check-prefix=OUTPUT

// IEEE 1800-2023 4.4.2.2-4.4.2.4/10.4.2: gate drops in Inactive before
// en's NBA. Both held outputs must therefore keep startup X. Publishing en
// in Active could capture1 before #0, persisting after gate drops. Both
// observers are idempotent on fixed inputs; that cannot certify moving an
// input across event regions. Independent enable roots exercise both hold
// guards separately. Statement fusion has a separate convex Active
// contract with whole held-state activations; clocked fusion must retain NBA.
// KEEP: simulation.nba.enqueue
// PROOF-LABEL: regions @route valid=1
// PROOF-NEXT: idempotent=1
// PROOF-LABEL: regions @route_explicit valid=1
// PROOF-NEXT: idempotent=1
// OUTPUT: {{^}}NBA holds 1 1{{$}}

!bit = !simulation.logic<1>
!ref = !simulation.ref<!bit>
module attributes {llvm.data_layout = "e-m:e-p:64:64-i64:64-n8:16:32:64-S128", schedule.native_scheduler = 3 : i32, native.closed_executable} {
  simulation.design @held_nba_observers {
    simulation.scope.decl 0
    simulation.storage.decl 0 in 0 : !bit design
    simulation.storage.decl 1 in 0 : !bit design
    simulation.storage.decl 2 in 0 : !bit design
    simulation.storage.decl 3 in 0 : !bit design
    simulation.storage.decl 4 in 0 : !bit design
    simulation.storage.decl 5 in 0 : !bit design
    simulation.storage.decl 6 in 0 : !bit design
    simulation.storage.decl 7 in 0 : !bit design
    simulation.storage.decl 8 in 0 : !bit design
    simulation.storage.decl 9 in 0 : !bit design
    simulation.storage.decl 10 in 0 : !bit design
    simulation.code_unit.decl 1 in 0 root_initializer hierarchy "root"
    simulation.code_unit.decl 2 in 0 initial hierarchy "clock"
    simulation.code_unit.decl 3 in 0 always_ff hierarchy "toggle"
    simulation.code_unit.decl 4 in 0 always_ff hierarchy "follow"
    simulation.code_unit.decl 5 in 0 always_comb hierarchy "route"
    simulation.code_unit.decl 6 in 0 initial hierarchy "sampler"
    simulation.code_unit.decl 7 in 0 initial hierarchy "report"
    simulation.code_unit.decl 8 in 0 always_comb hierarchy "route_explicit"
    simulation.code_unit.decl 9 in 0 always_ff hierarchy "toggle_explicit"
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
      %explicit_enable = simulation.context.storage %ctx[10] : !ref
      simulation.ref.store %init to %explicit_enable : !bit, !ref
      %gate = simulation.context.storage %ctx[7] : !ref
      %true = simulation.logic.constant true, false : !bit
      simulation.ref.store %true to %gate : !bit, !ref
      %data = simulation.context.storage %ctx[9] : !ref
      simulation.ref.store %true to %data : !bit, !ref
      %p0 = simulation.spawn @clock(%ctx, %clk) : !simulation.context, !ref -> !simulation.process
      %p1 = simulation.spawn @toggle(%ctx, %clk, %q) : !simulation.context, !ref, !ref -> !simulation.process
      %p2 = simulation.spawn @follow(%ctx, %clk, %q, %r) : !simulation.context, !ref, !ref, !ref -> !simulation.process
      %p3 = simulation.spawn @route(%ctx, %q, %r, %routed_q, %routed_r) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      %p4 = simulation.spawn @sampler(%ctx, %clk, %routed_r, %seen, %inactive_seen) : !simulation.context, !ref, !ref, !ref, !ref -> !simulation.process
      %p5 = simulation.spawn @report(%ctx) : !simulation.context -> !simulation.process
      %p6 = simulation.spawn @route_explicit(%ctx, %explicit_enable) : !simulation.context, !ref -> !simulation.process
      %p7 = simulation.spawn @toggle_explicit(%ctx, %clk, %explicit_enable) : !simulation.context, !ref, !ref -> !simulation.process
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
    simulation.func private @toggle_explicit(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %clk: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 0 : i64}, %q: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 5 : i32, code_unit_id = 9 : i64} {
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
      %gate = simulation.context.storage %ctx[7] : !ref
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      %a = simulation.ref.load %q : !ref -> !bit
      %g = simulation.ref.load %gate : !ref -> !bit
      %a1 = simulation.logic.compare case_eq %a, %one : (!bit, !bit) -> i1
      %g1 = simulation.logic.compare case_eq %g, %one : (!bit, !bit) -> i1
      %enable = arith.andi %a1, %g1 : i1
      cf.cond_br %enable, ^capture, ^publish
    ^capture:
      simulation.ref.store %one to %routed_q : !bit, !ref
      cf.br ^publish
    ^publish:
      %b = simulation.ref.load %r : !ref -> !bit
      simulation.ref.store %b to %routed_r : !bit, !ref
      simulation.suspend.any %q, %r, %gate edges [0, 0, 0] to ^body : !ref, !ref, !ref
    }
    simulation.func @route_explicit(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}, %en: !ref {simulation.capture_kind = 3 : i32, simulation.descriptor_id = 10 : i64}) attributes {entry_kind = 4 : i32, code_unit_id = 8 : i64} {
      %gate = simulation.context.storage %ctx[7] : !ref
      %held = simulation.context.storage %ctx[8] : !ref
      %data = simulation.context.storage %ctx[9] : !ref
      %one = simulation.logic.constant true, false : !bit
      cf.br ^body
    ^body:
      %old = simulation.ref.load %held : !ref -> !bit
      %a = simulation.ref.load %en : !ref -> !bit
      %g = simulation.ref.load %gate : !ref -> !bit
      %a1 = simulation.logic.compare case_eq %a, %one : (!bit, !bit) -> i1
      %g1 = simulation.logic.compare case_eq %g, %one : (!bit, !bit) -> i1
      %enable = arith.andi %a1, %g1 : i1
      cf.cond_br %enable, ^capture, ^hold
    ^capture:
      %value = simulation.ref.load %data : !ref -> !bit
      cf.br ^chosen(%value : !bit)
    ^hold:
      cf.br ^chosen(%old : !bit)
    ^chosen(%next: !bit):
      simulation.ref.store %next to %held : !bit, !ref
      simulation.suspend.any %en, %gate, %data edges [0, 0, 0] to ^body : !ref, !ref, !ref
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
      %gate = simulation.context.storage %ctx[7] : !ref
      %zero = simulation.logic.constant false, false : !bit
      simulation.ref.store %zero to %gate : !bit, !ref
      %after_zero = simulation.ref.load %routed_r : !ref -> !bit
      simulation.ref.store %after_zero to %inactive_seen : !bit, !ref
      cf.br ^wait
    }
    simulation.func @report(%ctx: !simulation.context {simulation.capture_kind = 0 : i32}) attributes {entry_kind = 1 : i32, code_unit_id = 7 : i64} {
      %delay = simulation.time.constant 6
      simulation.suspend.delay %delay to ^done
    ^done:
      %qi = simulation.context.storage %ctx[4] : !ref
      %qe = simulation.context.storage %ctx[8] : !ref
      %implicit = simulation.ref.load %qi : !ref -> !bit
      %explicit = simulation.ref.load %qe : !ref -> !bit
      %x = simulation.logic.constant false, true : !bit
      %ok_i = simulation.logic.compare case_eq %implicit, %x : (!bit, !bit) -> i1
      %ok_e = simulation.logic.compare case_eq %explicit, %x : (!bit, !bit) -> i1
      %stdout = arith.constant -2147483647 : i32
      %format = simulation.bytes.constant "NBA holds %0d %0d"
      simulation.display %ctx to %stdout(%format, %ok_i, %ok_e) newline = true radix = <decimal> flags = [0, 0, 0] : !simulation.bytes, i1, i1
      %zero = arith.constant 0 : i32
      simulation.finish %ctx, %zero
      simulation.return
    }
  }
}
