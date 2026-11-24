# Native rank optimality oracle

Talos uses the heuristic on the compilation path. This optional offline experiment compares that emitted order with all schedules permitted by a frozen native-eval model. Reviewers can replay the decisions with a standalone Z3 executable. The archives include the graph, the subset of the lowering log consumed by the model, two SMT-LIB queries, expected results, and SHA-256 digests. BlackParrot also includes a concrete improving order and its feasibility query.

## Result for the paper

> On the evaluated two-state CVA6 native graph, the heuristic attained the lexicographic optimum of 109 distinct backward-wake destinations and 231 backward edges, subject to the captured native-evaluator, checkpoint and forwarding constraints.

For an edge from producer `u` to consumer `v`, the model counts a backward wake when `rank(u) >= rank(v)`. A self-edge counts once. The primary objective counts distinct destination nodes, including runtime boundary nodes. The secondary objective counts edges. These counts describe static scheduling opportunities. Simulation throughput is measured separately in retired host instructions per simulated cycle.

| Frozen two-state instance | Native units | Edges | Heuristic cost | Strictly better order | Interpretation |
|---|---:|---:|---|---|---|
| CVA6 | 6,639 | 9,204 | (109, 231) | UNSAT | Heuristic attains the modeled optimum. |
| BlackParrot | 5,803 | 10,263 | (68, 118) | SAT | A checked order obtains (59, 143). The primary objective improves. The optimum remains open. |
| RSD | 3,781 | 5,005 | (1,208, 1,208) | UNSAT | The two eligible owners have no movable slots. This is a fixed-order control. |

The saved BlackParrot counterexample was compiled and executed. Both binaries finished at cycle 292,724, produced identical console output and the expected signature `f8aff1ce`, and retained all 4,336 grouped native evaluators, all 3,103 unconditional members, and the baseline dataflow chains. Three alternating single-core PMU runs measured a median of **69,799.14** host instructions per simulated cycle for the heuristic and **69,760.61** for the solver order. This is a reduction of 38.53 instructions per cycle, or **0.0552%**, on this configuration and workload. This order is a checked improvement; Z3 reached its search budget before proving a BlackParrot optimum. [Measurement records](measurements.json)

Each instance uses the ranking graph from its matched O3 build. Native islands, SCCs, opaque boundaries, clocked and deferred work, compiled entry and exit forms, and required dataflow chains constrain which ranks are interchangeable. Chains can translate together into compatible slots. The oracle preserves the existing positions of protected checkpoints and the existing order of independent optimization intervals. These restrictions depend on the lowering and partly on the schedule chosen by the heuristic. The claim concerns this post-lowering search space. It does not establish global optimality over alternative lowerings, source cuts, or host instruction counts.

For CVA6, the lowering supplied 2,138 grouped evaluators, 303 forwarding chains, and 1,055 unconditional members. The guarded solver order reproduced the optimized baseline executable byte-for-byte in the measured worktree. The saved native graph is the input for the paper result; a different compiler revision or RTL configuration can yield a different instance.

## Compiler selection

The ordinary compiler implements both policies in C++. Use `--native-rank=heuristic` (the default) or `--native-rank=z3` with normal native code-generation flags. The following command enables timing diagnostics.

```sh
talos -O3 --two-state --vpi=off --native-rank=z3 --mlir-timing design.sv -o sim
```

The native MLIR pipeline accepts the same enum.

```sh
talos-opt input.mlir \
  --pass-pipeline='builtin.module(convert-talos-sim-processes-to-llvm-coroutines{native-rank=z3})'
```

The module pass `schedule-rank-native-processes{native-rank=z3}` runs the native preparation and process-materialization part of that pipeline. Both analyses consume the same activation dependencies, SCC identities and native eligibility facts. The Z3 analysis uses the compiler's linked Z3 library and a deterministic resource budget. It retains the incumbent on a tie or when search finds no verified improvement. A strict improvement triggers a second native process lowering from the same input IR. The compiler accepts it only if the graph matches and the emitted helpers, unconditional evaluations and forwarding chains retain their certificates. This repeats neither HDL elaboration nor LLVM optimization and object generation. With `--mlir-timing`, the compiler reports the heuristic and selected costs and whether the solve was bounded or proved optimal. A build configured with `TALOS_ENABLE_Z3=OFF` supports the heuristic and diagnoses an explicit request for Z3.

## Replay the frozen paper queries

The archives retain the original paper instances independently of later compiler changes. Extract one into a fresh directory, then invoke a standard Z3 executable on both SMT-LIB files.

```sh
work=$(mktemp -d)
tar -xJf benchmark/scheduler/paper/cva6-2state.tar.xz -C "$work"
z3 "$work/heuristic-witness.smt2"
z3 "$work/strictly-better.smt2"
```

For CVA6, the expected answers are `sat` and `unsat`. The first query fixes the heuristic ranks and checks their feasibility and cost. The second leaves every model-permitted rank free and asks whether fewer destinations are possible, or whether the same destination count permits fewer edges. A SAT second query is a counterexample. UNKNOWN is inconclusive. BlackParrot includes the archived witness for its improving order. The original queries have a 15-second timeout and were replayed with Z3 4.13.4 and 4.15.5. Each archive's manifest includes costs, expected decisions and input digests.

## What relaxing the model changed

On the same CVA6 instance and pinned AArch64 core, five alternating fresh optimization runs with Z3 4.13.4 gave the following medians. Time in libz3 includes SMT loading, checking, and model access. End-to-end time includes reading the frozen input, construction, optimization, validation, and writing the result. RTL elaboration and simulation are outside both timers.

| Native constraints | Time in libz3 | End-to-end oracle | Proved cost |
|---|---:|---:|---|
| Preserve forwarding and checkpoints | 1.19 s | 1.71 s | (109, 231) |
| Release forwarding-chain constraints, retain checkpoint positions and native slot forms | 2.69 s | 2.87 s | (109, 228) |

A separate graph-only ablation keeps the same graph, vertex granularity and contiguous SCC/island intervals, but releases native slot types, repeatability ordering, forwarding chains, and checkpoint positions. It asks the single global strictly-better question, rather than running the decomposed optimizer. In three alternating trials with a 15-second per-query timeout, the native better-order decision returned UNSAT every time (median 1.44 s). The graph-only decision returned UNKNOWN every time. Its timeout says nothing about whether a better order exists; the (109, 228) order from the less relaxed problem is already feasible in this larger space. This diagnostic emits SMT queries only. Eliminating a real event boundary requires its own language-semantic justification.

The separately executed 109-source-cut trial used runtime frames for split processes and lost grouped native evaluators in 61 processes. It cost about 730,398 host instructions per simulated cycle in the store window versus 145,002 for the native control. This is a different experiment from relaxing a scheduling constraint in Z3.
