// RUN: talos-opt %S/simulation-private-write-only.mlir --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false}))' | FileCheck %s --check-prefix=OFF --implicit-check-not=compute_graph --implicit-check-not=effect_summary --implicit-check-not=fragment_abi --implicit-check-not='#schedule.continuation'
// RUN: talos-opt %S/simulation-private-write-only.mlir --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph,talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-build-compute-graph,talos-sim-verify-compute-graph))' -o /dev/null
// RUN: talos-opt %S/simulation-private-packed-ssa.mlir --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=read},talos-sim-materialize-compute-fusion))' | FileCheck %s --check-prefix=READ --implicit-check-not=compute_graph --implicit-check-not=effect_summary --implicit-check-not=fragment_abi --implicit-check-not='#schedule.continuation'
// RUN: talos-opt %S/simulation-private-packed-ssa.mlir --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=read},talos-sim-materialize-compute-fusion,talos-sim-build-compute-graph{vpi=read},talos-sim-verify-compute-graph))' -o /dev/null
// RUN: talos-opt %S/simulation-private-write-only.mlir --pass-pipeline='builtin.module(simulation.design(talos-sim-build-compute-graph{vpi=full},talos-sim-materialize-compute-fusion{materialize-eval-bodies=false},talos-sim-verify-compute-graph))' | FileCheck %s --check-prefix=UNCHANGED

// Promotion can change canonical accesses without any fusion plan or cloned
// evaluator. The graph, per-function summaries, fragment ABI and executable
// sites describe the old revision and must be invalidated on the early exit.
// A fresh graph must verify; an unchanged pass must retain its valid graph.
// The original fixtures also check that observable state is preserved under
// IEEE 1800-2023 4.3/4.6/10.4.1 and read-only VPI.

// OFF: simulation.design @write_only
// OFF: simulation.func private @write(
// OFF: %[[DEAD:.*]] = simulation.context.storage %arg0[0]
// OFF-NOT: simulation.ref.store {{.*}} to %[[DEAD]]
// OFF: %[[LIVE:.*]] = simulation.context.storage %arg0[1]
// OFF: simulation.ref.store %arg1 to %[[LIVE]]
// OFF: simulation.return

// READ: simulation.design @private_packed_ssa
// READ: simulation.func private @whole(
// READ: simulation.ref.store %arg1
// READ-NOT: simulation.ref.load
// READ: simulation.return %arg1

// UNCHANGED: simulation.design @write_only attributes {compute_graph =
// UNCHANGED: simulation.func private @write(
// UNCHANGED-SAME: effect_summary =
// UNCHANGED-SAME: fragment_abi =
// UNCHANGED: %[[DEAD:.*]] = simulation.context.storage %arg0[0]
// UNCHANGED-COUNT-2: simulation.ref.store %arg1 to %[[DEAD]]
