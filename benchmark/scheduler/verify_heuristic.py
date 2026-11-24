#!/usr/bin/env python3
"""Ask whether any legal order strictly improves a heuristic's lexicographic cost.

Emit a single standalone SMT-LIB decision instance. Only the lowering contract
fixes slots in this query. The heuristic supplies the comparison threshold.
"""

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import time

from eval_rank import (
    chain_domains,
    movable_runs,
    read_contract,
    read_forwarded,
    read_group_members,
    slot_key,
)
from forward_rank import Z3


def spans(values):
    """Inclusive consecutive spans of integer slots, in increasing order."""
    start = last = values[0]
    for value in values[1:]:
        if value != last + 1:
            yield start, last
            start = value
        last = value
    yield start, last


def bounded_count(bits, fixed, limit):
    """At most 'limit' true flags after constant folding."""
    budget = limit - fixed
    if budget < 0:
        return "false"
    if budget >= len(bits):
        return "true"
    return f"((_ at-most {budget}) {' '.join(bits)})"


def better_instance(nodes, edges, groups, chains, policy="native"):
    """Encode all permissible permutations and a global strictly-better cost."""
    if policy == "graph-only":
        # Deliberately omit native-body slot types, forwarding and checkpoint
        # requirements. Keep the original SCC/island order and all graph edges.
        # This counterfactual can be queried, but has no executable-order output.
        runs = []
        for n in nodes:
            if not runs or (runs[-1][0].component, runs[-1][0].island) != (
                n.component,
                n.island,
            ):
                runs.append([])
            runs[-1].append(n)
        movable_chains = []
    else:
        if policy not in ("native", "free-forwarding"):
            raise ValueError(f"unknown policy {policy}")
        fixed, movable_chains = chain_domains(
            nodes, groups, chains if policy == "native" else [], False
        )
        runs = movable_runs(nodes, groups, fixed)
    pos = {n.index: n.slot for n in nodes}
    by_id = {n.index: n for n in nodes}
    linked = {v for chain in movable_chains for v in chain}
    run_of = {}
    term = {}
    slot_options = {}
    constraints = ["(set-logic QF_FD)"]
    witness = []
    for i, run in enumerate(runs):
        first = run[0].slot
        width = max(1, (len(run) - 1).bit_length())
        choices = defaultdict(list)
        for n in run:
            key = None if policy == "graph-only" else slot_key(n, groups, False)
            choices[key].append(n.slot)
        classes = defaultdict(list)
        for n in run:
            v = n.index
            run_of[v] = i
            key = None if policy == "graph-only" else slot_key(n, groups, False)
            slots = choices[key]
            if v in linked:
                slots = [
                    s for s in slots if groups[n.wrapper] == groups[nodes[s].wrapper]
                ]
            slot_options[v] = (slots[0], slots[-1])
            if len(slots) == 1:
                term[v] = f"(_ bv{slots[0] - first} {width})"
            else:
                term[v] = f"r{v}"
                constraints.append(f"(declare-const r{v} (_ BitVec {width}))")
                witness.append(f"(assert (= r{v} (_ bv{pos[v] - first} {width})))")
                ranges = []
                for lo, hi in spans(slots):
                    low = f"(_ bv{lo - first} {width})"
                    high = f"(_ bv{hi - first} {width})"
                    ranges.append(
                        f"(= r{v} {low})"
                        if lo == hi
                        else f"(and (bvule {low} r{v}) (bvule r{v} {high}))"
                    )
                constraints.append(f"(assert (or {' '.join(ranges)}))")
            classes[key].append(term[v])
        for values in classes.values():
            if len(values) > 1:
                constraints.append(f"(assert (distinct {' '.join(values)}))")
    for chain in movable_chains:
        first, *others = sorted(chain, key=pos.get)
        width = max(1, (len(runs[run_of[first]]) - 1).bit_length())
        for v in others:
            diff = pos[v] - pos[first]
            constraints.append(
                f"(assert (and (bvult {term[first]} {term[v]}) (= {term[v]} (bvadd {term[first]} (_ bv{diff} {width})))))"
            )

    fixed_edges = 0
    fixed_receivers = set()
    incoming = defaultdict(list)
    edge_bits = []
    old_back = [(a, b) for a, b in edges if pos[a] >= pos[b]]
    for i, (a, b) in enumerate(edges):
        older_back = pos[a] >= pos[b]
        if a == b or a not in run_of or run_of[a] != run_of.get(b):
            fixed = older_back
        elif slot_options[a][1] < slot_options[b][0]:
            fixed = False
        elif slot_options[a][0] > slot_options[b][1]:
            fixed = True
        else:
            relation = f"(bvuge {term[a]} {term[b]})"
            if policy != "graph-only" and not older_back and not by_id[b].repeatable:
                constraints.append(f"(assert (not {relation}))")
                continue
            bit = f"e{i}"
            constraints.append(f"(define-fun {bit} () Bool {relation})")
            edge_bits.append(bit)
            incoming[b].append(bit)
            continue
        if fixed:
            fixed_edges += 1
            fixed_receivers.add(b)
    receiver_bits = []
    for b, bits in incoming.items():
        if b not in fixed_receivers:
            name = f"y{b}"
            constraints.append(f"(define-fun {name} () Bool (or {' '.join(bits)}))")
            receiver_bits.append(name)

    owners = len({b for a, b in old_back})
    count = len(old_back)
    fewer_receivers = bounded_count(receiver_bits, len(fixed_receivers), owners - 1)
    same_or_fewer = bounded_count(receiver_bits, len(fixed_receivers), owners)
    fewer_edges = bounded_count(edge_bits, fixed_edges, count - 1)
    strict = f"(or {fewer_receivers} (and {same_or_fewer} {fewer_edges}))"
    # Include both exact objective counts in the positive control. Only that
    # control pins the movable ranks to the heuristic's proposed order.
    at_most_edges = bounded_count(edge_bits, fixed_edges, count)
    witness.append(
        f"(assert (and {same_or_fewer} (not {fewer_receivers}) {at_most_edges} (not {fewer_edges})))"
    )
    return constraints + witness, constraints + [f"(assert {strict})"], (owners, count)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("contract", type=Path)
    p.add_argument("--lowering-log", type=Path, required=True)
    p.add_argument("--output-dir", type=Path, required=True)
    p.add_argument(
        "--policy",
        choices=["native", "free-forwarding", "graph-only"],
        default="native",
    )
    p.add_argument("--timeout-ms", type=int, default=10000)
    p.add_argument("--z3")
    args = p.parse_args()
    if args.timeout_ms <= 0:
        p.error("--timeout-ms must be positive")
    start = time.perf_counter()
    nodes, edges, digest = read_contract(args.contract)
    log = args.lowering_log.read_text()
    if f"RF native contract {digest} " not in log:
        p.error("lowering evidence does not match the graph")
    groups = read_group_members(args.lowering_log)
    chains, unconditional = read_forwarded(args.lowering_log)
    counts = re.findall(r"repeatable ranked members:.* unconditional=(\d+)", log)
    if args.policy == "native" and (
        not counts or int(counts[-1]) != len(unconditional)
    ):
        p.error("incomplete native forwarding evidence")
    witness, better, cost = better_instance(nodes, edges, groups, chains, args.policy)
    solver = Z3(args.z3, args.timeout_ms, args.output_dir)
    before = time.perf_counter()
    incumbent, _ = solver.check("heuristic-witness", witness)
    decision_start = time.perf_counter()
    status, _ = solver.check("strictly-better", better)
    end = time.perf_counter()
    result = dict(
        policy=args.policy,
        contract_sha256=digest,
        lowering_sha256=hashlib.sha256(args.lowering_log.read_bytes()).hexdigest(),
        heuristic_backward_destinations=cost[0],
        heuristic_backward_edges=cost[1],
        strictly_better=status,
        heuristic_witness=incumbent,
        heuristic_optimal=(
            None
            if incumbent != "sat"
            else {"unsat": True, "sat": False, "unknown": None}[status]
        ),
        construction_seconds=before - start,
        witness_seconds=decision_start - before,
        decision_seconds=end - decision_start,
        total_seconds=end - start,
    )
    (args.output_dir / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
