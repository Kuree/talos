// RUN: talos-opt %S/simulation-eval-word-sweep-handoffs.mlir --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.deferred set="{resume_region = 3 : i32}"},test-talos-replicate,simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.priority.mlir 2> %t.priority.trace
// RUN: FileCheck %s --check-prefix=PRIORITY < %t.priority.mlir

// The priority cancellation waiter is runtime-owned, so this variant keeps a
// runtime calendar; with `aaa` deferred, word 2 is shared with the deferred
// owner. The NBA cut drains runtime work, then the deferred owner runs from
// the per-owner switch, which must survive although only the commit path
// emitted after the sweep branches to it. Priority work is polled after each
// owner of a word: a pending priority signal returns TALOS_RT_AOT_CHECKPOINT
// (20) before the next owner (IEEE 1800-2023 4.4.2.3-4.4.2.4).
// PRIORITY-LABEL: llvm.func internal @__talos_eval_dispatch_v1.__talos_pending(
// PRIORITY: llvm.call @talos_rt_v1_scheduler_prepare_eval_nba
// PRIORITY: llvm.switch %{{.*}} : i64, ^{{bb[0-9]+}} [
// PRIORITY-NEXT: 129: ^
// PRIORITY-NEXT: ]
// PRIORITY-LABEL: llvm.func @__talos_eval_dispatch_v1.word_0(
// PRIORITY: llvm.call @talos_rt_v1_scheduler_priority_signal_pending(%arg0)
// PRIORITY-NEXT: llvm.mlir.constant(0 : i32)
// PRIORITY-NEXT: llvm.icmp "ne"
// PRIORITY-NEXT: llvm.mlir.constant(20 : i32)
