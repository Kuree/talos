#!/usr/bin/env python3
"""Measure constrained-random compilation and simulation with replay checks.

Example:
  python3 benchmark/randomization/run.py --compiler build/tools/driver/talos \
    --output-dir build/random-bench --case independent --fields 32 64 128

Keep JSON output from the base revision, then pass it as --baseline FILE to
check identical seeded output and report runtime speedups. Build directories
and binaries stay in the caller's chosen output directory.
"""

import argparse
import json
from pathlib import Path
import statistics
import subprocess
import time


def run(command, timeout):
    start = time.perf_counter()
    result = subprocess.run(
        [str(arg) for arg in command],
        check=True,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return time.perf_counter() - start, result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--case",
        choices=["relational", "independent", "popcount", "native-functions"],
        default="relational",
    )
    parser.add_argument("--iterations", type=int, default=10000)
    parser.add_argument("--fields", type=int, nargs="+", default=[64])
    parser.add_argument("--changing", type=int, nargs="+", choices=[0, 1], default=[0, 1])
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--seed", type=int, default=13)
    parser.add_argument("--timeout", type=float, default=300)
    parser.add_argument("--baseline", type=Path)
    args = parser.parse_args()
    if args.iterations <= 0 or args.repetitions <= 0 or any(n <= 0 for n in args.fields):
        parser.error("iterations, repetitions and field counts must be positive")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    baseline = {}
    if args.baseline:
        baseline = {row["name"]: row for row in json.loads(args.baseline.read_text())}
    rows = []
    for fields in args.fields if args.case == "independent" else [None]:
        for changing in args.changing:
            name = f"{args.case}-{fields or 0}-{changing}"
            binary = (args.output_dir / name).resolve()
            command = [
                args.compiler.resolve(), "--std=1800-2023", "-O3", "--compile-threads=2",
                f"-GITERATIONS={args.iterations}", f"-GCHANGING={changing}",
                "-o", binary, Path(__file__).with_name(f"{args.case}.sv").resolve(),
            ]
            if fields:
                command.append(f"-GFIELDS={fields}")
            compile_seconds, _ = run(command, args.timeout)
            timings, outputs = [], []
            for _ in range(args.repetitions):
                seconds, output = run([binary, f"+ntb_random_seed={args.seed}"], args.timeout)
                timings.append(seconds)
                outputs.append(output)
            if len(set(outputs)) != 1:
                raise RuntimeError(f"{name}: seeded replay changed across runs")
            row = dict(
                name=name, iterations=args.iterations, seed=args.seed,
                compile_seconds=compile_seconds, simulation_seconds=timings,
                median_seconds=statistics.median(timings), output=outputs[0],
            )
            if name in baseline:
                previous = baseline[name]
                if (previous["iterations"] != args.iterations or
                        previous["seed"] != args.seed or previous["output"] != outputs[0]):
                    raise RuntimeError(f"{name}: output differs from baseline")
                row["speedup"] = previous["median_seconds"] / row["median_seconds"]
            rows.append(row)
    print(json.dumps(rows, indent=2))


if __name__ == "__main__":
    main()
