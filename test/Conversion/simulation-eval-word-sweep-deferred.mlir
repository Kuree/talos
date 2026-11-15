// RUN: talos-opt %S/simulation-eval-word-sweep-handoffs.mlir --pass-pipeline='builtin.module(test-talos-edit-attributes{has=test.priority erase},test-talos-edit-attributes{has=test.deferred set="{resume_region = 3 : i32}"},test-talos-replicate,simulation.design(simulation.func(talos-sim-thread-process-cfg),talos-sim-build-compute-graph,talos-sim-verify-compute-graph,talos-sim-materialize-graph-regions,talos-sim-materialize-compute-fusion,talos-sim-specialize-static-state-nba,talos-sim-plan-static-superstep),encode-talos-sim-to-bytecode{vpi=off},convert-talos-sim-processes-to-llvm-coroutines)' -o %t.deferred.mlir 2> %t.deferred.trace
// RUN: FileCheck %s --check-prefix=DEFERRED < %t.deferred.mlir
// RUN: FileCheck %s --check-prefix=DEFERRED-PLAN < %t.deferred.trace

// IEEE 1800-2023 4.4.2.3: deferred owners run after all Active owners.
// DEFERRED-PLAN: talos eval owner: bit=128 {{.*}} group=- {{.*}}{{$}}
// DEFERRED-PLAN-NEXT: talos eval owner: bit=129 {{.*}} deferred{{$}}

// Word 2 holds Active owner 128 and deferred owner 129. The sweep gates that
// word (and only that word) on its Active bit; once no Active word is dirty, the coordinator
// scans the deferred bits directly, checks for a finish request, takes the
// Inactive cut and runs the deferred owner from the per-owner switch.
// DEFERRED-LABEL: llvm.func @__talos_eval_dispatch_v1(
// DEFERRED: llvm.switch %[[DEFERRED_BIT:.*]] : i64, ^{{bb[0-9]+}} [
// DEFERRED-NEXT: 129: ^
// DEFERRED-NEXT: ]
// DEFERRED: %[[INACTIVE:.*]] = llvm.mlir.constant(2 : i64)
// DEFERRED-NEXT: %[[PENDING:.*]] = llvm.and %{{.*}}, %[[INACTIVE]]
// DEFERRED: %[[MIXED:.*]] = llvm.mlir.constant(2 : i64)
// DEFERRED-NEXT: %[[IS_MIXED:.*]] = llvm.icmp "eq" %{{.*}}, %[[MIXED]]
// DEFERRED-NEXT: llvm.cond_br %[[IS_MIXED]], ^[[SHARED:bb[0-9]+]], ^{{bb[0-9]+}}(
// DEFERRED-NEXT: ^[[SHARED]]:
// DEFERRED-NEXT: %[[ACTIVE:.*]] = llvm.mlir.constant(1 : i64)
// DEFERRED-NEXT: llvm.and %{{.*}}, %[[ACTIVE]]
// DEFERRED: "llvm.intr.cttz"(%[[PENDING]])
// DEFERRED: llvm.call @talos_rt_v1_scheduler_termination_requested(
// DEFERRED-LABEL: llvm.func @__talos_eval_dispatch_v1.word_2(
// DEFERRED: llvm.mlir.constant(1 : i64)
// DEFERRED-NOT: llvm.mlir.constant(2 : i64)
// DEFERRED-NOT: llvm.func
// DEFERRED: llvm.call @__talos_eval_path_dispatch_v1_{{[0-9]+}}(%arg0)
// DEFERRED-NOT: llvm.mlir.constant(2 : i64)
// DEFERRED: llvm.func
