// RUN: talos-opt %S/simulation-ranked-activity-domains.mlir --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.replicate set={test.replicate = 80 : i64}},test-talos-set-module-attributes{attrs="{schedule.native.max_inline_ops = 40 : i64}"},test-talos-replicate,simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' | FileCheck %s

// 80 ranked owners split into size-bounded chunks, in rank order, over two
// ready words. A multi-word set has no segment wrapper: the coordinator's word
// sweep calls each chunk from the word holding its first member, and each
// chunk's own test reads the word after earlier chunks have published into it
// (IEEE 1800-2023 4.5, 4.7). The coordinator polls termination after each
// word, so a chunk call is followed directly by the next chunk's test.
// CHECK-NOT: .segment(
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1.word_0(
// CHECK: %[[READY:.*]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
// CHECK-NEXT: %[[LOW:.*]] = llvm.load %[[READY]]
// CHECK-NEXT: %[[FIRST:.*]] = llvm.mlir.constant(1 : i64)
// CHECK-NEXT: llvm.and %[[LOW]], %[[FIRST]]
// CHECK: llvm.call @__talos_eval_ranked_group_0(%arg0)
// CHECK-NEXT: llvm.br ^[[NEXT:bb[0-9]+]]
// CHECK: ^[[NEXT]]:
// CHECK: %[[AGAIN:.*]] = llvm.load %{{.*}} : !llvm.ptr -> i64
// CHECK-NEXT: %[[SECOND:.*]] = llvm.mlir.constant(2 : i64)
// CHECK-NEXT: llvm.and %[[AGAIN]], %[[SECOND]]
// CHECK: llvm.call @__talos_eval_ranked_group_1(%arg0)
// CHECK-LABEL: llvm.func @__talos_eval_dispatch_v1.word_1(
// CHECK: %[[READY1:.*]] = llvm.mlir.addressof @__talos_aot_model_ingress_v1
// CHECK-NEXT: %[[ADDRESS:.*]] = llvm.getelementptr %[[READY1]][8]
// CHECK-NEXT: llvm.load %[[ADDRESS]]
// CHECK-NOT: .segment(
