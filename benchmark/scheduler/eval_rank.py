#!/usr/bin/env python3
"""Rank certified native evaluators while preserving their execution contract.

The input is a frozen compiler inventory (H, N and E records) and the lowering
log for that same design. Each evaluator has one entry rank. A body cannot
acquire an internal suspension while retaining its direct-call ABI. A runtime
checkpoint, clocked/deferred evaluator, or ineligible body stays at its original
position. Ranks may move within a contiguous compatible region of the same
island and SCC. Hard edges protect non-repeatable receivers against new backward
wakes. All original wake edges stay live. Minimize backward-wake receivers,
then backward edges. These are static costs, not retired host instructions.
"""

import argparse
from collections import defaultdict
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import time

from forward_rank import Z3


@dataclass(frozen=True)
class Node:
    index: int
    slot: int
    component: int
    island: int
    real: int
    boundary: int
    clocked: int
    repeatable: int
    two_state: int
    checkpoint: int
    deferred: int
    convergence: int
    wrapper: str
    body: str


def read_contract(path):
    data = path.read_bytes()
    nodes, edges = [], set()
    lines = iter(data.decode().splitlines())
    header, count, real = next(lines).split()
    if header != "H":
        raise ValueError("missing native eval inventory header")
    for line in lines:
        fields = line.split()
        if fields[0] == "N":
            nodes.append(Node(*map(int, fields[1:13]), *fields[13:]))
        elif fields[0] == "E":
            a, b = map(int, fields[1:])
            edges.add((a, b))
        else:
            raise ValueError(f"unexpected inventory record: {line}")
    ids = set(range(int(count)))
    if (
        len(nodes) != int(count)
        or {n.index for n in nodes} != ids
        or {n.slot for n in nodes} != ids
        or sum(n.real for n in nodes) != int(real)
        or any(a not in ids or b not in ids for a, b in edges)
    ):
        raise ValueError("invalid node or slot inventory")
    return (
        sorted(nodes, key=lambda n: n.slot),
        sorted(edges),
        hashlib.sha256(data).hexdigest(),
    )


def read_group_members(log):
    text = log.read_text()
    # A compiler can emit ranked helpers even when its optional shared runtime
    # calendar is ineligible. Use the actual emitted ownership inventory.
    pairs = re.findall(r"^talos eval owner:.*? group=(\S+) executor=(\S+)", text, re.M)
    if not pairs:
        raise ValueError("missing emitted evaluator ownership records")
    groups = {wrapper: group for group, wrapper in pairs if group != "-"}
    counts = re.findall(r"^talos ranked groups:.*?\bmembers=(\d+)\b", text, re.M)
    if not counts or int(counts[-1]) != len(groups):
        raise ValueError("incomplete emitted native evaluator inventory")
    return groups


def calendar_admission(log):
    flags = re.findall(
        r"^talos eval runtime-calendar eligibility:.*?\beligible=([01])\b",
        log.read_text(),
        re.M,
    )
    return flags[-1] if flags else None


def eligible(n, groups):
    return (
        n.real
        and not (n.boundary or n.clocked or n.checkpoint or n.deferred)
        and n.wrapper in groups
    )


def movable_runs(nodes, groups, protected):
    runs = []
    key = None
    for n in nodes:
        if not eligible(n, groups) or n.wrapper in protected:
            key = None
            continue
        shape = (n.component, n.island)
        if key != shape:
            runs.append([])
        runs[-1].append(n)
        key = shape
    return runs


def at_most(variables, budget):
    if budget >= len(variables):
        return "true"
    return f"((_ at-most {budget}) " + " ".join(variables) + ")"


def slot_key(n, groups, keep_helpers):
    # A raw-call slot keeps its state-domain and guarded/repeatable execution
    # form. Other native calls may lie between two slots of the same type.
    return (
        n.two_state,
        n.repeatable,
        n.convergence,
        groups[n.wrapper] if keep_helpers else None,
    )


def optimize_run(solver, members, edges, fixed_back, tag, groups, keep_helpers, chains):
    base = {n.index: n.slot for n in members}
    by_id = {n.index: n for n in members}
    before = [(a, b) for a, b in edges if base[a] >= base[b]]

    def cost(back):
        return len({b for _, b in back} - fixed_back), len(back)

    upper = cost(before)
    # Self-loops and wakes already forced by frozen crossing edges cannot
    # benefit from permuting this region. The current order attains the bound.
    self_edges = [(a, b) for a, b in edges if a == b]
    floor = cost(self_edges)
    if upper == floor:
        return base, True, 0
    lo = members[0].slot
    width = max(1, (len(members) - 1).bit_length())

    def numeral(value):
        return f"(_ bv{value - lo} {width})"

    choices = defaultdict(list)
    for n in members:
        choices[slot_key(n, groups, keep_helpers)].append(n.slot)
    # Vertices without an internal edge are unconstrained fillers of their
    # own slot type. Place these in the remaining slots after SAT.
    bundles = [chain for chain in chains if chain[0] in base]
    linked = {v for chain in bundles for v in chain}
    active = sorted({n for a, b in edges if a != b for n in (a, b)} | linked)
    terms = ["(set-logic QF_FD)"]
    value_vars = []
    for j, v in enumerate(active):
        terms.append(f"(declare-const r{v} (_ BitVec {width}))")
        allowed = choices[slot_key(by_id[v], groups, keep_helpers)]
        if v in linked:
            allowed = [
                s
                for s in allowed
                if groups[by_id[v].wrapper] == groups[members[s - lo].wrapper]
            ]
        terms.append(
            "(assert (or "
            + " ".join(f"(= r{v} {numeral(slot)})" for slot in allowed)
            + "))"
        )
        for bit in range(width):
            name = f"c{j * width + bit}"
            terms.append(
                f"(define-fun {name} () Bool (= ((_ extract {bit} {bit}) r{v}) #b1))"
            )
            value_vars.append(name)
    terms.append("(assert (distinct " + " ".join(f"r{v}" for v in active) + "))")
    # Preserve the physical relative offsets of the forwarded values, while
    # allowing an entire certified chain to move together inside its helper.
    for chain in bundles:
        first, *rest = sorted(chain, key=base.get)
        for v in rest:
            gap = base[v] - base[first]
            terms.append(
                f"(assert (and (bvult r{first} r{v}) (= r{v} (bvadd r{first} (_ bv{gap} {width})))))"
            )
    # Seed the solver with a checked, deterministic rank permutation. This
    # also supplies a feasible answer when a bounded cardinality query times out.
    chosen = base.copy()

    def measure(r):
        return cost([(a, b) for a, b in edges if r[a] >= r[b]])

    hard = [(a, b) for a, b in edges if base[a] < base[b] and not by_id[b].repeatable]
    for slots in choices.values():
        nodes = [members[pos - lo].index for pos in slots]
        for i, a in enumerate(nodes):
            for b in nodes[i + 1 :]:
                if a in linked or b in linked:
                    continue
                chosen[a], chosen[b] = chosen[b], chosen[a]
                score = measure(chosen)
                if score < upper and all(chosen[u] < chosen[v] for u, v in hard):
                    upper = score
                else:
                    chosen[a], chosen[b] = chosen[b], chosen[a]
    incoming = defaultdict(list)
    for i, (a, b) in enumerate(edges):
        e = "true" if a == b else f"(bvuge r{a} r{b})"
        terms.append(f"(define-fun e{i} () Bool {e})")
        if not by_id[b].repeatable and base[a] < base[b]:
            terms.append(f"(assert (not e{i}))")
        incoming[b].append(f"e{i}")
    primary = [
        "(or " + " ".join(v) + ")" for b, v in incoming.items() if b not in fixed_back
    ]
    secondary = [f"e{i}" for i in range(len(edges))]
    queries = 0
    for level, expr in enumerate([primary, secondary]):
        lower = floor[level]
        high = upper[level]
        while lower < high:
            k = (lower + high) // 2
            status, values = solver.check(
                f"{tag}-{level}-{k}",
                terms + [f"(assert {at_most(expr, k)})"],
                value_vars,
            )
            queries += 1
            if status == "unknown":
                return chosen, False, queries
            if status == "unsat":
                lower = k + 1
                continue
            chosen = {
                v: lo
                + sum(
                    (values[f"c{j * width + bit}"] == "true") << bit
                    for bit in range(width)
                )
                for j, v in enumerate(active)
            }
            used = set(chosen.values())
            remaining = {
                key: iter([slot for slot in slots if slot not in used])
                for key, slots in choices.items()
            }
            for n in members:
                if n.index not in chosen:
                    chosen[n.index] = next(remaining[slot_key(n, groups, keep_helpers)])
            upper = cost([(a, b) for a, b in edges if chosen[a] >= chosen[b]])
            high = upper[level]
        terms.append(f"(assert {at_most(expr, high)})")
    return chosen, True, queries


def solve(
    nodes, edges, groups, solver, keep_helpers=False, protected=frozenset(), chains=()
):
    original = {n.index: n.slot for n in nodes}
    ranks = original.copy()
    runs = movable_runs(nodes, groups, protected)
    membership = {n.index: i for i, group in enumerate(runs) for n in group}
    internal = defaultdict(list)
    fixed_back = set()
    for a, b in edges:
        if a in membership and membership[a] == membership.get(b):
            internal[membership[a]].append((a, b))
        elif original[a] >= original[b]:
            fixed_back.add(b)
    exact = True
    queries = 0
    for i, group in enumerate(runs):
        selected, proven, checks = optimize_run(
            solver,
            group,
            internal[i],
            fixed_back,
            f"eval-{i}",
            groups,
            keep_helpers,
            chains,
        )
        ranks.update(selected)
        exact &= proven
        queries += checks
    # Independently check all edges including those excluded from the SMT
    # subproblems. Fixed intervals cannot introduce a new crossing backedge.
    if sorted(ranks.values()) != list(range(len(nodes))):
        raise RuntimeError("ranked plan is not a permutation")
    for n in nodes:
        if n.index not in membership and ranks[n.index] != n.slot:
            raise RuntimeError("moved a protected evaluator or runtime boundary")
    for group in runs:
        slots = {n.slot: slot_key(n, groups, keep_helpers) for n in group}
        if any(
            slots[ranks[n.index]] != slot_key(n, groups, keep_helpers) for n in group
        ):
            raise RuntimeError("incompatible native eval slot")
        if {ranks[n.index] for n in group} != {n.slot for n in group}:
            raise RuntimeError("crossed an evaluator interval")
    by_id = {n.index: n for n in nodes}
    for chain in chains:
        if len({ranks[v] - original[v] for v in chain}) != 1 or any(
            groups[by_id[v].wrapper] != groups[nodes[ranks[v]].wrapper] for v in chain
        ):
            raise RuntimeError("broke a certified native eval chain")
    previous = {(a, b) for a, b in edges if original[a] >= original[b]}
    back = {(a, b) for a, b in edges if ranks[a] >= ranks[b]}
    for a, b in back - previous:
        if (
            a not in membership
            or membership[a] != membership.get(b)
            or not by_id[b].repeatable
        ):
            raise RuntimeError("unproved evaluator retry")
    return sorted(ranks, key=ranks.get), dict(
        optimal=exact,
        queries=queries,
        native_units=len(nodes),
        eligible_owners=sum(bool(eligible(n, groups)) for n in nodes),
        selectable_owners=len(membership),
        frozen_order_slots=len(nodes) - len(membership),
        movable_slots=sum(len(g) for g in runs if len(g) > 1),
        prior_backward_owners=len({b for _, b in previous}),
        backward_owners=len({b for _, b in back}),
        prior_backward_edges=len(previous),
        backward_edges=len(back),
        changed_slots=sum(ranks[i] != original[i] for i in ranks),
    )


def read_forwarded(log):
    """Read the backend's actual dataflow candidates and predicate certificates."""
    chains = []
    unguarded = set()
    for line in log.read_text().splitlines():
        if line.startswith("RF eval chain "):
            chain = []
            for pair in line.split()[3:]:
                wrapper, flag = pair.rsplit("=", 1)
                chain.append(wrapper)
                if flag == "1":
                    unguarded.add(wrapper)
            chains.append(chain)
    return chains, unguarded


def chain_domains(nodes, groups, chains, keep_helpers):
    by_wrapper = {n.wrapper: n for n in nodes if n.real}
    # A chain crossing a fixed checkpoint, component or missing alias cannot
    # move as one unit in this representation. Repartition after fixing it.
    protected = set()
    while True:
        runs = movable_runs(nodes, groups, protected)
        membership = {n.wrapper: i for i, run in enumerate(runs) for n in run}
        fixed_before = len(protected)
        for chain in chains:
            intervals = {membership.get(w) for w in chain}
            if len(intervals) != 1 or None in intervals:
                protected.update(chain)
        if len(protected) == fixed_before:
            break
    movable = [
        tuple(by_wrapper[w].index for w in chain)
        for chain in chains
        if not protected.intersection(chain)
    ]
    return protected, movable


def certify(
    nodes,
    edges,
    groups,
    protected,
    solver,
    ranks,
    keep_helpers,
    forced_cut=None,
    chains=(),
):
    """SMT replay on every executable unit, including protected and external slots.

    Existing real suspension points already separate units. A new internal
    split needs a certified continuation ABI. The observed raw native bodies
    have one entry and one exit rank and do not advertise such an ABI.
    """
    terms = ["(set-logic QF_LIA)"]
    runs = movable_runs(nodes, groups, protected)
    by_id = {n.index: n for n in nodes}
    options = {}
    for members in runs:
        choices = defaultdict(list)
        for n in members:
            choices[slot_key(n, groups, keep_helpers)].append(n.slot)
        for n in members:
            options[n.index] = choices[slot_key(n, groups, keep_helpers)]
    for n in nodes:
        i = n.index
        terms.extend(
            [
                f"(declare-const r{i} Int)",
                f"(declare-const end{i} Int)",
                f"(declare-const cut{i} Bool)",
                f"(declare-const native{i} Bool)",
                f"(assert (= r{i} {ranks[i]}))",
                f"(assert (= cut{i} (< r{i} end{i})))",
                f"(assert (<= r{i} end{i}))",
            ]
        )
        # Ownership comes from the actual grouped wrapper inventory. A cut
        # inside one protected raw evaluator would destroy its executable ABI.
        if n.wrapper in groups:
            terms.extend(
                [f"(assert native{i})", f"(assert (=> native{i} (= r{i} end{i})))"]
            )
        else:
            terms.extend([f"(assert (not native{i}))", f"(assert (= end{i} r{i}))"])
        if i not in options:
            terms.append(f"(assert (= r{i} {n.slot}))")
        else:
            terms.append(
                "(assert (or " + " ".join(f"(= r{i} {v})" for v in options[i]) + "))"
            )
    for group in runs:
        if len(group) > 1:
            terms.append(
                "(assert (distinct " + " ".join(f"r{n.index}" for n in group) + "))"
            )
    for chain in chains:
        first, *rest = chain
        for v in rest:
            terms.append(
                f"(assert (= (- r{v} r{first}) {by_id[v].slot - by_id[first].slot}))"
            )
        for v in chain:
            slots = [
                n.slot
                for n in nodes
                if groups.get(n.wrapper) == groups[by_id[v].wrapper]
            ]
            terms.append(
                "(assert (or " + " ".join(f"(= r{v} {s})" for s in slots) + "))"
            )
    for a, b in edges:
        # A receiver with no repeatability certificate cannot acquire a new
        # backward publication. An existing backward wake is still live.
        if by_id[a].slot < by_id[b].slot and not by_id[b].repeatable:
            terms.append(f"(assert (< end{a} r{b}))")
    if forced_cut is not None:
        terms.append(f"(assert cut{forced_cut})")
    status, _ = solver.check(
        "eval-contract" if forced_cut is None else "eval-unsupported-split", terms
    )
    return status


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("contract", type=Path)
    parser.add_argument("--lowering-log", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--summary", required=True, type=Path)
    parser.add_argument("--timeout-ms", type=int, default=3000)
    parser.add_argument("--keep-helpers", action="store_true")
    parser.add_argument(
        "--allow-dataflow-changes",
        action="store_true",
        help="allow changing the baseline unconditional dataflow chains for a diagnostic comparison",
    )
    parser.add_argument(
        "--verify-lowering",
        type=Path,
        help="also verify the rebuilt compiler log against the required native ownership and forwarding certificates",
    )
    parser.add_argument("--z3")
    parser.add_argument("--dump-smt", type=Path)
    args = parser.parse_args()
    start = time.perf_counter()
    nodes, edges, digest = read_contract(args.contract)

    def check_digest(log):
        if f"RF native contract {digest} " not in log.read_text():
            raise ValueError("lowering log belongs to a different native graph")

    check_digest(args.lowering_log)
    groups = read_group_members(args.lowering_log)
    chains, unconditional = read_forwarded(args.lowering_log)
    protected, movable = chain_domains(
        nodes, groups, [] if args.allow_dataflow_changes else chains, args.keep_helpers
    )
    if not args.allow_dataflow_changes:
        match = re.search(
            r"repeatable ranked members:.* unconditional=(\d+)",
            args.lowering_log.read_text(),
        )
        if not match or int(match[1]) != len(unconditional):
            raise ValueError("incomplete dataflow certificate inventory")
    solver = Z3(args.z3, args.timeout_ms, args.dump_smt)
    order, report = solve(
        nodes, edges, groups, solver, args.keep_helpers, protected, movable
    )
    ranks = {n: i for i, n in enumerate(order)}
    if (
        certify(
            nodes,
            edges,
            groups,
            protected,
            solver,
            ranks,
            args.keep_helpers,
            chains=movable,
        )
        != "sat"
    ):
        raise RuntimeError("native eval constraints did not validate the emitted plan")
    tagged = next((n.index for n in nodes if eligible(n, groups)), None)
    if (
        tagged is not None
        and certify(
            nodes,
            edges,
            groups,
            protected,
            solver,
            ranks,
            args.keep_helpers,
            tagged,
            chains=movable,
        )
        != "unsat"
    ):
        raise RuntimeError("an uncertified split escaped the native evaluator contract")
    report.update(
        native_contract="sat",
        unsupported_split="unsat" if tagged is not None else None,
        anchored_chain_members=len(protected),
        movable_chains=len(movable),
        retained_dataflow_chain_members=len(protected) + sum(map(len, movable)),
        baseline_unconditional=len(unconditional),
    )
    if args.verify_lowering:
        check_digest(args.verify_lowering)
        if calendar_admission(args.verify_lowering) != calendar_admission(
            args.lowering_log
        ):
            raise RuntimeError(
                "native runtime-calendar admission changed in the rebuilt compiler log"
            )
        rebuilt = read_group_members(args.verify_lowering)
        missing = groups.keys() - rebuilt.keys()
        if missing:
            raise RuntimeError(f"lost {len(missing)} required native evaluators")
        after_chains, after_unconditional = read_forwarded(args.verify_lowering)
        if not args.allow_dataflow_changes:
            if not unconditional <= after_unconditional:
                raise RuntimeError("a required unconditional evaluator lost its proof")
            lowered_paths = {tuple(chain) for chain in after_chains}
            if any(tuple(chain) not in lowered_paths for chain in chains):
                raise RuntimeError("a required lowered dataflow chain changed")
        installed = f"RF installed checked native order changed={report['changed_slots']} feedback={report['backward_edges']}"
        if installed not in args.verify_lowering.read_text():
            raise RuntimeError("native order was not installed in this lowering")
        report.update(
            verified_grouped_evaluators=len(rebuilt),
            verified_unconditional=len(after_unconditional),
        )
    report.update(
        seconds=time.perf_counter() - start,
        contract_sha256=digest,
        grouped_wrappers=len(groups),
    )
    args.output.write_text(digest + "\n" + "\n".join(map(str, order)) + "\n")
    args.summary.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
