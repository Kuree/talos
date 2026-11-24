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

## Replay without building Talos

From the repository root, run the following command with Z3 on the path. It verifies each archived checksum, recomputes the heuristic cost from the edges, and checks the expected decisions. It also recomputes the cost of the supplied BlackParrot witness. Use `--z3 /path/to/z3` to choose the executable.

```sh
python3 benchmark/scheduler/paper/replay.py
```

The first query fixes the heuristic ranks and checks both feasibility and their reported cost. The second leaves all model-permitted ranks free and asks whether fewer destinations are possible, or whether the same destination count permits fewer edges. SAT in the first query and UNSAT in the second certify optimality. A SAT second query is a counterexample. An UNKNOWN result is inconclusive. The supplied SMT files have a 15-second solver timeout; a slower host can raise the timeout in a local copy. The recorded queries were replayed with Z3 4.13.4 and 4.15.5.

To regenerate the CVA6 queries, independently of the optimizer’s cardinality search, run the following commands. Set `build_dir` to an existing configured Talos native build. The `TalosRankGraph` target is optional and uses the project’s pinned Z3 when enabled.

```sh
build_dir=/path/to/talos-build
work=$(mktemp -d)
tar -xJf benchmark/scheduler/paper/cva6-2state.tar.xz -C "$work"
cmake --build "$build_dir" --target TalosRankGraph
python3 "$build_dir/tools/talos-rank/verify_heuristic.py" "$work/graph.contract" \
  --lowering-log "$work/lowering.log" --output-dir "$work/recheck" --timeout-ms 15000
cmp "$work/strictly-better.smt2" "$work/recheck/strictly-better.smt2"
```

The optimizer is also available to generate an order, including a better candidate on instances where one exists. Verify the rebuilt lowering log with `--verify-lowering` when making an executable-performance claim.

```sh
python3 "$build_dir/tools/talos-rank/eval_rank.py" "$work/graph.contract" \
  --lowering-log "$work/lowering.log" --output "$work/order.tsv" \
  --summary "$work/optimization.json" --dump-smt "$work/search"
```

To reuse the measured BlackParrot order, extract `blackparrot-2state.tar.xz` and pass its `improving.order` to the probe. This preserves the exact witness even if a later time-bounded search chooses a different incumbent.

For a new design, build the ordinary native Talos target and run the following command on a Ninja build with `compile_commands.json`.

```sh
python3 benchmark/scheduler/build_eval_probe.py "$build_dir"
```

Compile the design with the resulting `tools/driver/talos-eval-rank-probe`, the design’s usual flags, `--mlir-timing`, and `TALOS_EVAL_CONTRACT` pointing to an output file. Save the compiler log. To compile the solver's order, supply `TALOS_EVAL_ORDER` pointing to the generated order file and a fresh contract output path. The probe checks the graph digest before installing it. Use the ordinary driver for heuristic-only builds.

## What relaxing the model changed

On the same CVA6 instance and pinned AArch64 core, five alternating fresh optimization runs with Z3 4.13.4 gave the following medians. Time in libz3 includes SMT loading, checking, and model access. End-to-end time includes reading the frozen input, construction, optimization, validation, and writing the result. RTL elaboration and simulation are outside both timers.

| Native constraints | Time in libz3 | End-to-end oracle | Proved cost |
|---|---:|---:|---|
| Preserve forwarding and checkpoints | 1.19 s | 1.71 s | (109, 231) |
| Release forwarding-chain constraints, retain checkpoint positions and native slot forms | 2.69 s | 2.87 s | (109, 228) |

A separate `verify_heuristic.py --policy graph-only` ablation keeps the same graph, vertex granularity and contiguous SCC/island intervals, but releases native slot types, repeatability ordering, forwarding chains, and checkpoint positions. It asks the single global strictly-better question, rather than running the decomposed optimizer. In three alternating trials with a 15-second per-query timeout, the native better-order decision returned UNSAT every time (median 1.44 s). The graph-only decision returned UNKNOWN every time. Its timeout says nothing about whether a better order exists; the (109, 228) order from the less relaxed problem is already feasible in this larger space. This diagnostic emits SMT queries only. Eliminating a real event boundary requires its own language-semantic justification.

The separately executed 109-source-cut trial used runtime frames for split processes and lost grouped native evaluators in 61 processes. It cost about 730,398 host instructions per simulated cycle in the store window versus 145,002 for the native control. This is a different experiment from relaxing a scheduling constraint in Z3.
