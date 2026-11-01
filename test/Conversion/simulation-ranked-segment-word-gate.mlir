// RUN: talos-opt %S/simulation-ranked-activity-domains.mlir --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.replicate set={test.replicate = 80 : i64}},test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 40 : i64}"},test-talos-replicate,simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s

// A size-split segment holds chunks of 80 owners, in rank order. One test skips
// all the chunks of an idle ready word, so a sweep never fetches their branches,
// and each word has its own test. A chunk's own test still reads the word after
// earlier chunks have published into it.
// CHECK-LABEL: llvm.func @__talos_eval_ranked_group_5.segment(
// CHECK: %[[READY:.*]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
// CHECK-NEXT: %[[LOW:.*]] = llvm.load %[[READY]]
// CHECK-NEXT: %[[ZERO:.*]] = llvm.mlir.constant(0 : i64)
// CHECK-NEXT: %[[ACTIVE:.*]] = llvm.icmp "ne" %[[LOW]], %[[ZERO]]
// CHECK-NEXT: llvm.cond_br %[[ACTIVE]], ^[[FIRST:bb[0-9]+]], ^[[SECOND:bb[0-9]+]]
// CHECK: ^[[FIRST]]:
// CHECK-NEXT: llvm.load %[[READY]]
// CHECK: ^[[SECOND]]:
// CHECK-NEXT: %[[ADDRESS:.*]] = llvm.getelementptr %[[READY]][8]
// CHECK-NEXT: %[[HIGH:.*]] = llvm.load %[[ADDRESS]]
// CHECK-NEXT: %[[ZERO2:.*]] = llvm.mlir.constant(0 : i64)
// CHECK-NEXT: %[[ACTIVE2:.*]] = llvm.icmp "ne" %[[HIGH]], %[[ZERO2]]
// CHECK-NEXT: llvm.cond_br %[[ACTIVE2]], ^{{bb[0-9]+}}, ^[[END:bb[0-9]+]]
// CHECK: ^[[END]]:
// CHECK-NEXT: llvm.return
