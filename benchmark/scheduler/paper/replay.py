#!/usr/bin/env python3
"""Replay the archived SMT-LIB decisions using an external Z3 executable."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile


def replay(archive, z3):
    with tarfile.open(archive, "r:xz") as package:
        manifest = json.loads(package.extractfile("manifest.json").read())
        checks = {
            "heuristic-witness.smt2": manifest["feasibility"],
            "strictly-better.smt2": manifest["strictly_better"],
        }
        if "improving-witness.smt2" in manifest["sha256"]:
            checks["improving-witness.smt2"] = "sat"
        answers = {}
        for name, digest in manifest["sha256"].items():
            data = package.extractfile(name).read()
            if hashlib.sha256(data).hexdigest() != digest:
                raise ValueError(f"{archive.name}: digest mismatch for {name}")
            if name in checks:
                proc = subprocess.run(
                    [z3, "-in", "-smt2"], input=data, capture_output=True, check=True
                )
                actual = proc.stdout.decode().strip()
                if actual != checks[name]:
                    raise ValueError(
                        f"{archive.name}: {name} returned {actual!r}, expected {checks[name]!r}"
                    )
                answers[name] = actual
        if answers.keys() != checks.keys():
            raise ValueError(f"{archive.name}: missing decision query")
        graph = package.extractfile("graph.contract").read().splitlines()
        slots = {}
        edges = []
        for line in graph:
            fields = line.split()
            if fields[0] == b"N":
                slots[int(fields[1])] = int(fields[2])
            elif fields[0] == b"E":
                edges.append((int(fields[1]), int(fields[2])))

        def cost(rank):
            backward = [b for a, b in edges if rank[a] >= rank[b]]
            return [len(set(backward)), len(backward)]

        if cost(slots) != manifest["heuristic_cost"]:
            raise ValueError(f"{archive.name}: heuristic cost mismatch")
        if "improving.order" in manifest["sha256"]:
            digest, *ids = package.extractfile("improving.order").read().splitlines()
            candidate = {int(n): i for i, n in enumerate(ids)}
            if (
                digest.decode() != manifest["sha256"]["graph.contract"]
                or len(ids) != len(slots)
                or candidate.keys() != slots.keys()
                or cost(candidate) != manifest["checked_solver_cost"]
                or not cost(candidate) < cost(slots)
            ):
                raise ValueError(f"{archive.name}: invalid improving witness")
    print(
        f"{manifest['design']} {tuple(manifest['heuristic_cost'])}  feasible={answers['heuristic-witness.smt2']}  strictly-better={answers['strictly-better.smt2']}"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archives", nargs="*", type=Path)
    parser.add_argument("--z3", default="z3")
    args = parser.parse_args()
    archives = args.archives or sorted(
        Path(__file__).resolve().parent.glob("*-2state.tar.xz")
    )
    if not archives:
        parser.error("no research instances found")
    for archive in archives:
        replay(archive, args.z3)


if __name__ == "__main__":
    main()
