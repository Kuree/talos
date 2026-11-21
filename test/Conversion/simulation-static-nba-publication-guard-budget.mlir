// RUN: talos-opt %S/simulation-static-nba-publication.mlir --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 800 : i64}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.llvm.mlir 2> %t.llvm.plan && FileCheck %s --check-prefix=INLINE < %t.llvm.plan && FileCheck %s --check-prefix=CALLS --implicit-check-not='llvm.call @__talos_eval_static_nba_publication_guard_v1' < %t.llvm.mlir
// RUN: talos-translate --mlir-to-llvmir %t.llvm.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.llvm.o
// RUN: %target_cxx %t.llvm.o %runtime_link_flags -o %t.llvm.exe && %t.llvm.exe --execution-tier=native | FileCheck %S/simulation-static-nba-publication.mlir --check-prefix=OUTPUT
// RUN: talos-opt %S/simulation-static-nba-publication.mlir --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 251 : i64}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.mixed.mlir 2> %t.mixed.plan && FileCheck %s --check-prefix=MIXED < %t.mixed.plan
// RUN: talos-opt %S/simulation-static-nba-publication.mlir --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 1 : i64}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.tiny.mlir 2> %t.tiny.plan && FileCheck %s --check-prefix=TINY < %t.tiny.plan && FileCheck %s --check-prefix=FALLBACK --implicit-check-not='llvm.call @__talos_eval_static_nba_publication' < %t.tiny.mlir
// RUN: talos-translate --mlir-to-llvmir %t.tiny.mlir | %llvm_dist/bin/opt -passes='coro-early,coro-split<reuse-storage>,coro-cleanup,default<O3>' | %llc -filetype=obj -relocation-model=pic -o %t.tiny.o
// RUN: %target_cxx %t.tiny.o %runtime_link_flags -o %t.tiny.exe && %t.tiny.exe --execution-tier=native | FileCheck %S/simulation-static-nba-publication.mlir --check-prefix=OUTPUT
// RUN: talos-opt %S/simulation-static-nba-publication.mlir --pass-pipeline='builtin.module(test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 0 : i64}"},simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off prune-native=true},convert-talos-sim-processes-to-llvm-coroutines,materialize-runtime-byte-globals)' -o %t.unlimited.mlir 2> %t.unlimited.plan && FileCheck %s --check-prefix=UNLIMITED < %t.unlimited.plan && FileCheck %s --check-prefix=CALLS < %t.unlimited.mlir

// Only eligibility checks are copied into the caller, with all copies charged
// against its current size. Publication bodies stay eligible for LLVM inlining.
// INLINE-COUNT-3: limit=800 decision=inline
// INLINE: guards complete: caller=__talos_eval_dispatch_v1 size={{[0-7][0-9][0-9]}} limit=800
// MIXED-COUNT-2: limit=251 decision=inline
// MIXED: limit=251 decision=fallback
// MIXED: guards complete: caller=__talos_eval_dispatch_v1 size={{2[0-5][0-9]}} limit=251
// TINY-COUNT-3: limit=1 decision=fallback
// UNLIMITED-COUNT-3: limit=18446744073709551615 decision=inline

// The existing fixture covers captured RHS and target, Active/#0 reads,
// neighbors of partial writes, X/Z, and an uncertified initial-waiter capture.
// Only the guard's true edge may enter the publication body. Rejection rejoins
// the unchanged generic commit path without entering a publication frame.
// CALLS-LABEL: llvm.func @__talos_eval_dispatch_v1(
// CALLS: llvm.mlir.addressof @__talos_aot_nba_dirty_roots_v1
// CALLS: llvm.mlir.constant(-4 : i64)
// CALLS: llvm.and
// CALLS: %[[READY:.*]] = llvm.icmp "eq"
// CALLS-NEXT: %[[NO:.*]] = llvm.mlir.constant(false) : i1
// CALLS-NEXT: llvm.cond_br %[[READY]], ^[[PUBLISH:bb[0-9]+]], ^[[JOIN:bb[0-9]+]](%[[NO]] : i1)
// CALLS: ^[[PUBLISH]]:
// CALLS-NEXT: %[[DONE:.*]] = llvm.call @__talos_eval_static_nba_publication_two_state_fast_v1
// CALLS-NEXT: llvm.br ^[[JOIN]](%[[DONE]] : i1)
// CALLS: llvm.call @__talos_eval_static_nba_publication_two_state_v1
// CALLS: llvm.call @__talos_eval_static_nba_publication_v1
// CALLS: {{^  }}}

// All variants have ordinary function attributes: neither noinline nor
// alwaysinline overrides LLVM's decision. Generic barriers remain noinline.
// CALLS-LABEL: llvm.func internal @__talos_eval_static_nba_publication_v1(
// CALLS-SAME: -> i1 {
// CALLS-LABEL: llvm.func internal @__talos_eval_static_nba_publication_two_state_v1(
// CALLS-SAME: -> i1 {
// CALLS-LABEL: llvm.func internal @__talos_eval_static_nba_publication_two_state_fast_v1(
// CALLS-SAME: -> i1 {

// FALLBACK-LABEL: llvm.func @__talos_eval_dispatch_v1(
// FALLBACK: llvm.call @__talos_aot_static_nba_commit_two_state_fast_v1
// FALLBACK: llvm.call @__talos_aot_static_nba_commit_two_state_v1
// FALLBACK: llvm.call @__talos_eval_four_state_nba_handoff_v1
// FALLBACK: {{^  }}}

module {}
