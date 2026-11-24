#!/usr/bin/env python3
"""Find a zero-queue, minimum-cut static order for a finite scheduling wave.

Build the TalosRankGraph CMake target, then run
python3 <build-dir>/tools/talos-rank/forward_rank.py graph.json --rank-first -o plan.json.
Host builds with TALOS_ENABLE_Z3 use the project's Z3 in-process. Use --z3
to select a solver executable. The source script also runs with Python and
an external Z3. --cut-budget-ms controls optional refinement after the
minimum retry-owner count and a feasible cut schedule are established.

Input JSON has a 'processes' array and a 'dependencies' array. A process has a
unique 'name' and 'paths' (lists of globally unique operation labels in source
execution order). Paths can share labels in the same process, e.g. a branch
join. Each operation may start a new slice. A dependency [producer, consumer]
requires a forward handoff between different processes. Supply the visibility,
wake and sampled-value obligations for the wave, after resolving true event
region and clock boundaries. Different branch cases can contribute paths and
dependencies when the same static order must serve them all. "hard_dependencies"
uses the same syntax for causal edges that may never be retried. Supply logical
actions after applying guards, alias and observation analysis: a conservative
possible dependency can make the static model unsatisfiable even for acyclic
synthesized hardware. A real event wait separates activation waves.


Each cut is a distinct continuation entry before an operation. Source order
inside a slice comes from the original process CFG. A direct handoff to a
later slice is free of queue re-entries. The model forbids backward handoffs,
then minimizes distinct cut entries. With --local-retries, failure of the
zero-reentry query confines iteration to the finest cyclic SCCs, then minimizes
the number of distinct processes receiving backward wakes, then cut entries.
With --rank-first, allow an intact slice to straddle the fine SCC boundary.
The same dependency edges are eligible for retry, and the same source and
hard ordering constraints apply. Settle the SCCs of the chosen slices before
their consumers. A rank boundary is a static schedule site. Selecting a
preemption that prevents livelock requires a separate progress check.
With --native-eval-owners, connected source operations of a required native
activation share one rank variable throughout the search. The output includes
the contracted proof graph's result and, when available, expanded source ranks.
Membership in such a kernel makes a process eligible to run again; the number
of actual repeats depends on runtime changes. Independent process SCCs can be emitted
in condensation order, so the minimum cut counts of the SCCs add exactly.
"""

import argparse
from collections import defaultdict, deque
import json
from pathlib import Path
import re
import subprocess
import time

import rank_native


def components(vertices, successors):
    """Iterative Kosaraju, in condensation topological order."""
    reverse = [[] for _ in vertices]
    for source, targets in enumerate(successors):
        for target in targets:
            reverse[target].append(source)
    seen = set()
    finish = []
    for root in vertices:
        if root in seen:
            continue
        seen.add(root)
        stack = [(root, iter(successors[root]))]
        while stack:
            node, children = stack[-1]
            child = next(children, None)
            if child is None:
                stack.pop()
                finish.append(node)
            elif child not in seen:
                seen.add(child)
                stack.append((child, iter(successors[child])))
    seen.clear()
    groups = []
    for root in reversed(finish):
        if root in seen:
            continue
        group = []
        stack = [root]
        seen.add(root)
        while stack:
            node = stack.pop()
            group.append(node)
            for child in reverse[node]:
                if child not in seen:
                    stack.append(child)
                    seen.add(child)
        groups.append(sorted(group))
    return groups


class Model:
    def __init__(self, data, rank_first=False):
        self.rank_first = rank_first
        self.names = []
        self.labels = []
        self.owner = []
        self.indices = {}
        self.control = set()
        self.required = set()
        self.hard = set()
        self.members = []
        for proc in data["processes"]:
            name = proc["name"]
            owner = len(self.names)
            self.names.append(name)
            members = []
            for path in proc["paths"]:
                previous = None
                for label in path:
                    node = self.indices.get(label)
                    if node is None:
                        node = len(self.labels)
                        self.indices[label] = node
                        self.labels.append(label)
                        self.owner.append(owner)
                        members.append(node)
                    if self.owner[node] != owner:
                        raise ValueError(f"operation {label} belongs to two processes")
                    if previous is not None:
                        self.control.add((previous, node))
                    previous = node
            if not members:
                raise ValueError(f"empty process {name}")
            self.members.append(members)
        if len(set(self.names)) != len(self.names):
            raise ValueError("process names must be unique")
        for field in ("dependencies", "hard_dependencies"):
            for before, after in data.get(field, []):
                a, b = self.indices[before], self.indices[after]
                if self.owner[a] == self.owner[b]:
                    raise ValueError("use source paths for intra-process order")
                self.required.add((a, b))
                if field == "hard_dependencies":
                    self.hard.add((a, b))

        self.topology = (
            rank_native.Topology(self)
            if rank_native.supports(self)
            and (
                not rank_first
                or hasattr(rank_native.lib, "talos_rank_model_rank_first")
            )
            else None
        )

    def operation_components(self):
        if not hasattr(self, "_groups"):
            if self.topology:
                self._groups = self.topology.groups()
            else:
                adj = [[] for _ in self.labels]
                for a, b in self.control | self.required:
                    adj[a].append(b)
                self._groups = components(range(len(adj)), adj)
        return self._groups

    def cyclic_witness(self):
        """A strict edge on an operation-level cycle rules out any forward pass."""
        if self.topology:
            return self.topology.cycle() or None
        for group in self.operation_components():
            if len({self.owner[n] for n in group}) < 2:
                continue
            members = set(group)
            adj = defaultdict(list)
            strict = None
            for edges in (self.control, self.required):
                for a, b in edges:
                    if a in members and b in members:
                        adj[a].append(b)
                        if edges is self.required and strict is None:
                            strict = (a, b)
            a, b = strict
            parent = {b: None}
            frontier = deque([b])
            while a not in parent:
                node = frontier.popleft()
                for child in adj[node]:
                    if child not in parent:
                        parent[child] = node
                        frontier.append(child)
            cycle = [a]
            while cycle[-1] != b:
                cycle.append(parent[cycle[-1]])
            return [a, *reversed(cycle)]
        return None


class Z3:
    def __init__(self, binary, timeout_ms, dump):
        self.session = (
            rank_native.Session()
            if binary is None
            and rank_native.lib
            and hasattr(rank_native.lib, "talos_rank_solver")
            else None
        )
        self.binary = binary or "z3"
        self.timeout_ms = timeout_ms
        self.dump = dump
        if dump:
            dump.mkdir(parents=True, exist_ok=True)

    def check(self, name, terms, values=(), deadline=None):
        def timeout():
            if deadline is None:
                return self.timeout_ms
            left = int(1000 * (deadline - time.monotonic()))
            return min(left, self.timeout_ms) if self.timeout_ms else left

        remaining = timeout()
        if deadline is not None and remaining <= 0:
            return "unknown", {}
        script = [f"(set-option :timeout {remaining})", *terms, "(check-sat)"]

        if self.session:
            values_query = "(get-value (" + " ".join(values) + "))" if values else ""
            query = "\n".join(script) + "\n"
            if self.dump:
                (self.dump / f"{name}.smt2").write_text(query)
            output = self.session.run(query, values_query)
            lines = output.splitlines()
            if (
                not lines
                or lines[0] not in {"sat", "unsat", "unknown"}
                or "(error " in output
            ):
                raise RuntimeError(f"Z3 failed: {output[:300]}")
            if self.dump and lines[0] == "sat" and values:
                (self.dump / f"{name}-model.smt2").write_text(
                    query + values_query + "\n"
                )
            return lines[0], dict(
                re.findall(r"\(([rcy]\d+) (true|false|\d+)\)", output)
            )

        def execute(commands, suffix):
            text = "\n".join(commands) + "\n"
            if self.dump:
                (self.dump / f"{name}{suffix}.smt2").write_text(text)
            result = subprocess.run(
                [self.binary, "-in", "-smt2"],
                input=text,
                capture_output=True,
                text=True,
            )
            lines = result.stdout.splitlines()
            # The standalone model query repeats check-sat. If it times out,
            # get-value has no model and the process can also exit nonzero.
            if suffix == "-model" and lines[:1] == ["unknown"]:
                return "unknown", ""
            if (
                result.returncode
                or not lines
                or lines[0] not in {"sat", "unsat", "unknown"}
            ):
                raise RuntimeError(
                    f"Z3 failed: {result.stdout[:300]} {result.stderr[:300]}"
                )
            return lines[0], result.stdout

        status, output = execute(script, "")
        if status == "sat" and values:
            if deadline is not None:
                remaining = timeout()
                if remaining <= 0:
                    return "unknown", {}
                script[0] = f"(set-option :timeout {remaining})"
            status, output = execute(
                script + ["(get-value (" + " ".join(values) + "))"], "-model"
            )
        return status, dict(re.findall(r"\(([rcy]\d+) (true|false|\d+)\)", output))


def rank_constraints(control, required, nodes):
    return (
        ["(set-logic QF_LIA)"]
        + [f"(declare-const r{n} Int)" for n in nodes]
        + [f"(assert (>= r{n} 0))" for n in nodes]
        + [f"(assert (<= r{a} r{b}))" for a, b in control]
        + [f"(assert (< r{a} r{b}))" for a, b in required]
    )


def check_partition(nodes, control, required, cuts):
    """Check one cut set. Return ranks or a necessary clause for each cycle."""
    dense = {node: i for i, node in enumerate(nodes)}
    arcs = [[] for _ in nodes]
    for a, b in control:
        arcs[dense[a]].append((dense[b], None, 0))
        if b not in cuts:
            # An uncut boundary equates ranks. The forward half is immutable.
            arcs[dense[b]].append((dense[a], b, 0))
    for a, b in required:
        arcs[dense[a]].append((dense[b], None, 1))
    groups = components(range(len(nodes)), [[v for v, _, _ in row] for row in arcs])
    which = {v: i for i, group in enumerate(groups) for v in group}
    clauses = set()
    level = [0] * len(groups)
    for i, group in enumerate(groups):
        internal = []
        for a in group:
            for b, _, weight in arcs[a]:
                dest = which[b]
                if dest != i:
                    level[dest] = max(level[dest], level[i] + weight)
                elif weight:
                    internal.append((a, b))
        # Every cycle through a strict dependency must lose a reverse equality
        # edge. Its possible cut sites form a necessary disjunction, irrespective
        # of what other sites the solver might select.
        for a, b in internal[:32]:
            pred = {b: None}
            frontier = deque([b])
            while a not in pred:
                n = frontier.popleft()
                for v, site, _ in arcs[n]:
                    if which[v] == i and v not in pred:
                        pred[v] = (n, site)
                        frontier.append(v)
            cuttable = set()
            cur = a
            while cur != b:
                cur, site = pred[cur]
                if site is not None:
                    cuttable.add(site)
            if not cuttable:
                raise RuntimeError("immutable cycle escaped all-cuts feasibility check")
            clauses.add(tuple(sorted(cuttable)))
    return {n: level[which[dense[n]]] for n in nodes}, clauses


def representative_clauses(clauses):
    """In a positive hitting set, one variable per identical support suffices.

    Collapse only within a cost class. A later cycle can distinguish previously
    equivalent sites, so equivalence is recomputed on the full learned clauses.
    """
    keep = []
    indexed = defaultdict(list)
    for clause in sorted(clauses, key=lambda row: (len(row), row)):
        members = frozenset(clause)
        if any(prior <= members for g in clause for prior in indexed[g]):
            continue
        keep.append(clause)
        indexed[min(clause, key=lambda g: len(indexed[g]))].append(members)
    clauses = keep
    support = defaultdict(list)
    for i, clause in enumerate(clauses):
        for gate in clause:
            support[gate].append(i)
    by_support = {}
    for gate, rows in support.items():
        key = (gate < 0, tuple(rows))
        previous = by_support.get(key)
        if previous is None or gate < previous:
            by_support[key] = gate
    result = [[] for _ in clauses]
    for (_, rows), gate in sorted(by_support.items(), key=lambda row: row[1]):
        for i in rows:
            result[i].append(gate)
    return result


def cover_cycles(extra, owners, cuts, owner_limit, cut_limit):
    """Try extending a legal assignment before asking Z3 for a replacement."""
    chosen = {-p - 1 for p in owners} | {n + 1 for n in cuts}
    count = {False: len(cuts), True: len(owners)}
    limit = {False: cut_limit, True: owner_limit}
    clauses = sorted(extra, key=lambda clause: (len(clause), clause))
    frequency = defaultdict(int)
    for clause in clauses:
        for gate in clause:
            frequency[gate] += 1
    for clause in clauses:
        if not chosen.isdisjoint(clause):
            continue
        available = (
            gate
            for gate in clause
            if limit[gate < 0] is None or count[gate < 0] < limit[gate < 0]
        )
        gate = max(available, key=frequency.get, default=None)
        if gate is None:
            return None
        chosen.add(gate)
        count[gate < 0] += 1
    return {-g - 1 for g in chosen if g < 0}, {g - 1 for g in chosen if g > 0}


def cover_with_owners(clauses, owners, limit):
    """Greedily cover remaining clauses at fixed owners, with lazy set-cover gains."""
    from heapq import heapify, heappop, heappush

    hits = {-p - 1 for p in owners}
    support = defaultdict(int)
    count = 0
    for row in sorted(clauses):
        if not hits.isdisjoint(row):
            continue
        options = [g for g in row if g > 0]
        if not options:
            return None
        bit = 1 << count
        count += 1
        for g in options:
            support[g] |= bit
    todo = (1 << count) - 1
    heap = [(-bits.bit_count(), g) for g, bits in support.items()]
    heapify(heap)
    cuts = set()
    while todo and len(cuts) < limit:
        prev, g = heappop(heap)
        remaining = (todo & support[g]).bit_count()
        if remaining == 0:
            continue
        if -remaining != prev and heap and -remaining > heap[0][0]:
            heappush(heap, (-remaining, g))
        else:
            cuts.add(g - 1)
            todo &= ~support[g]
    return None if todo else cuts


def minimum_cuts(group_id, nodes, control, required, solver, max_iterations):
    clauses = set()
    chosen = set()
    bound = 0
    # The rank checker is the separation oracle for the exact Z3 cardinality
    # problem. A checked acyclic witness at the lower bound proves optimality.
    for _ in range(max_iterations):
        ranks, extra = check_partition(nodes, control, required, chosen)
        if not extra:
            return ranks, bound
        clauses.update(extra)
        variables = sorted({x for row in clauses for x in row})
        terms = ["(set-logic QF_FD)"] + [
            f"(declare-const c{n} Bool)" for n in variables
        ]
        terms += [
            "(assert (or " + " ".join(f"c{x}" for x in row) + "))"
            for row in sorted(clauses)
        ]
        while True:
            limit = (
                "(assert ((_ at-most "
                + str(bound)
                + ") "
                + " ".join(f"c{n}" for n in variables)
                + "))"
            )
            tag = f"group-{group_id}-cuts-{bound}"
            status, values = solver.check(
                tag, terms + [limit], [f"c{n}" for n in variables]
            )
            if status == "unknown":
                return None, bound
            if status == "sat":
                if len(values) != len(variables):
                    raise RuntimeError("missing Z3 cut assignment")
                chosen = {n for n in variables if values[f"c{n}"] == "true"}
                break
            bound += 1
    return None, bound


def retry_groups(model):
    """Find irreducible local settle regions at the finest allowed granularity."""
    kernels = []
    which = {}
    for group in model.operation_components():
        if len({model.owner[n] for n in group}) <= 1:
            continue
        i = len(kernels)
        kernels.append(sorted(group))
        which.update((n, i) for n in group)
    return kernels, which


def build_retry_graph(model, kernels, which, kernel_only):
    outer, outer_id = model.coarse_components
    nodes = (
        sorted(which)
        if kernel_only
        else [
            n
            for group in outer
            if len(group) > 1
            for owner in group
            for n in model.members[owner]
        ]
    )
    mandatory = set() if kernel_only else model.retry_boundaries
    local = {v: i for i, v in enumerate(nodes)}
    count = len(nodes)
    # Optional gates are signed IDs: positive for cuts, negative for owners.
    barriers = not kernel_only and not model.rank_first
    base = [[] for _ in range(count + (2 * len(kernels) if barriers else 0))]

    def add(a, b, strict, gate=0):
        base[a].append((b, strict, gate))

    def inport(n):
        return count + 2 * which[n] if barriers and n in which else local[n]

    def outport(n):
        return count + 2 * which[n] + 1 if barriers and n in which else local[n]

    if barriers:
        for n in which:
            add(inport(n), local[n], 0)
            add(local[n], outport(n), 0)
    for a, b in model.control:
        if a not in local or b not in local:
            continue
        if kernel_only:
            if a in which and which.get(b) == which[a]:
                add(local[a], local[b], 0)
        else:
            add(local[a], local[b], 0)
            if b not in mandatory:
                add(local[b], local[a], 0, b + 1)
            if barriers and which.get(a) != which.get(b):
                add(outport(a), inport(b), 1)
    for a, b in model.required:
        if (
            a not in local
            or b not in local
            or outer_id[model.owner[a]] != outer_id[model.owner[b]]
        ):
            continue
        if a in which and which.get(b) == which[a]:
            add(
                local[a],
                local[b],
                1,
                0 if (a, b) in model.hard else -1 - model.owner[b],
            )
        elif not kernel_only:
            add(outport(a), inport(b), 1)
    return nodes, local, base


def retry_plan(
    model,
    solver,
    kernels,
    which,
    owner_limit,
    cut_limit,
    initial_owners,
    initial_cuts,
    max_iterations,
    deadline=None,
):
    """Separate cycles in a graph with independently selectable cuts and retries.

    The refine loop learns necessary clauses only. A forward source edge is
    mandatory; its reverse equality disappears on a cut. Only intra-kernel
    dependencies may turn into a retry of the destination process. Barriers
    keep every acyclic consumer after the complete local fixed point.
    """
    kernel_only = cut_limit is None
    mandatory = set() if kernel_only else model.retry_boundaries
    if cut_limit is not None and cut_limit < len(mandatory):
        return "unsat", None, None, None
    if kernel_only not in model.retry_graphs:
        if model.topology:
            model.retry_graphs[kernel_only] = model.topology.graph(kernel_only)
        else:
            model.retry_graphs[kernel_only] = build_retry_graph(
                model, kernels, which, kernel_only
            )
    native = model.retry_graphs[kernel_only] if model.topology else None
    if native is None:
        outer, _ = model.coarse_components
        nodes, local, base = model.retry_graphs[kernel_only]
    clauses = set()
    owners, cuts = set(initial_owners), set(initial_cuts) | mandatory

    def var(gate):
        return f"y{-gate - 1}" if gate < 0 else f"c{gate - 1}"

    for _ in range(max_iterations):
        if deadline is not None and time.monotonic() >= deadline:
            return "unknown", None, None, None
        disabled = {-1 - p for p in owners} | {n + 1 for n in cuts}
        if native is not None:
            extra = native.check(disabled, 8, compact=not kernel_only)
            if extra is None:
                return "unsat", None, None, None
            ranks = (
                model.topology.expand(native) if not extra and not kernel_only else None
            )
        else:
            live = [
                [(b, s, g) for b, s, g in row if not g or g not in disabled]
                for row in base
            ]
            groups = components(
                range(len(base)), [[b for b, _, _ in row] for row in live]
            )
            part = {n: i for i, group in enumerate(groups) for n in group}
            levels = [0] * len(groups)
            extra = set()
            for i, group in enumerate(groups):
                strict = []
                for a in group:
                    for b, weight, gate in live[a]:
                        if i != part[b]:
                            levels[part[b]] = max(levels[part[b]], levels[i] + weight)
                        elif weight and len(strict) < 8:
                            strict.append((a, b, gate))
                for a, b, gate in strict:
                    prev = {b: None}
                    q = deque([b])
                    while a not in prev:
                        at = q.popleft()
                        for nxt, _, label in live[at]:
                            if part[nxt] == i and nxt not in prev:
                                prev[nxt] = at, label
                                q.append(nxt)
                    gates = {gate} if gate else set()
                    at = a
                    while at != b:
                        at, label = prev[at]
                        if label:
                            gates.add(label)
                    if not gates:
                        return "unsat", None, None, None
                    extra.add(tuple(sorted(gates)))
            ranks = {n: levels[part[local[n]]] for n in nodes} if not extra else None
        if not extra:
            if not kernel_only and not native:
                offset = 0
                for group in outer:
                    ids = [n for owner in group for n in model.members[owner]]
                    for n in ids:
                        ranks[n] = ranks.get(n, 0) + offset
                    offset = 1 + max(ranks[n] for n in ids)
            return "sat", owners, cuts, ranks
        clauses.update(extra)
        trial = cover_cycles(
            extra,
            owners,
            cuts - mandatory,
            owner_limit,
            None if kernel_only else cut_limit - len(mandatory),
        )
        if trial is not None:
            owners, new_cuts = trial
            cuts = new_cuts | mandatory
            continue
        # Pairwise disjoint pure-cut cycles require distinct additional
        # entries for every choice of retry owners. This dual bound can
        # refute a tight cardinality query before SAT encoding it.
        if not kernel_only:
            claimed = set()
            packing = 0
            for row in sorted(clauses, key=lambda row: (len(row), row)):
                if row[0] > 0 and claimed.isdisjoint(row):
                    claimed.update(row)
                    packing += 1
            model.cut_packing = max(model.cut_packing, len(mandatory) + packing)
            if model.cut_packing > cut_limit:
                return "unsat", None, None, None
        if not kernel_only:
            repaired = cover_with_owners(
                clauses, initial_owners, cut_limit - len(mandatory)
            )
            if repaired is not None:
                owners = set(initial_owners)
                cuts = repaired | mandatory
                continue
        reduced = representative_clauses(sorted(clauses))
        variables = sorted({g for clause in reduced for g in clause})
        terms = ["(set-logic QF_FD)"] + [
            f"(declare-const {var(g)} Bool)" for g in variables
        ]
        terms += [
            "(assert (or " + " ".join(map(var, clause)) + "))" for clause in reduced
        ]
        for bound, vs in (
            (owner_limit, [var(g) for g in variables if g < 0]),
            (
                None if kernel_only else cut_limit - len(mandatory),
                [var(g) for g in variables if g > 0],
            ),
        ):
            if vs and bound is not None:
                terms.append(f"(assert ((_ at-most {bound}) " + " ".join(vs) + "))")
        prefix = f"retry-owners-{owner_limit}-cuts-{cut_limit}"
        status, values = solver.check(
            prefix, terms, [var(v) for v in variables], deadline
        )
        if status != "sat":
            return status, None, None, None
        if len(values) != len(variables):
            raise RuntimeError("incomplete retry model")
        chosen = [v for v in variables if values[var(v)] == "true"]
        owners = {-v - 1 for v in chosen if v < 0}
        cuts = {v - 1 for v in chosen if v > 0} | mandatory
    return "unknown", None, None, None


def settle_summary(model, kernels):
    summary = [
        {
            "members": [model.labels[n] for n in group],
            "operations": len(group),
            "processes": sorted({model.names[model.owner[n]] for n in group}),
        }
        for group in kernels
    ]
    count = sum(len(group) for group in kernels)
    return dict(
        retry_groups=summary,
        operations_in_local_settle=count,
        operations_outside_local_settle=len(model.labels) - count,
    )


def prune_cut_sites(model, owners, cuts, deadline):
    """Restore each unneeded source equality with the chosen retry owners fixed."""
    gates = {n + 1 for n in cuts}
    owner_gates = {-p - 1 for p in owners}
    if model.topology:
        projected = model.retry_graphs[False].cut_subset_graph(gates | owner_gates)
        feasible = projected.feasible
    else:
        _, _, base = model.retry_graphs[False]
        # Keep unconditional and unselected retry edges; test the strict
        # dependencies for membership in a cycle after restoring an equality.
        live = [[(b, w, g) for b, w, g in row if g not in owner_gates] for row in base]
        strict = [(a, b) for a, row in enumerate(live) for b, w, _ in row if w]

        def feasible(disabled):
            adj = [[b for b, _, g in row if g not in disabled] for row in live]
            groups = components(range(len(adj)), adj)
            part = {n: i for i, group in enumerate(groups) for n in group}
            return all(part[a] != part[b] for a, b in strict)

    for gate in sorted(gates):
        if deadline is not None and time.monotonic() >= deadline:
            return {g - 1 for g in gates}, False
        gates.remove(gate)
        if not feasible(gates):
            gates.add(gate)
    # Removing a later gate only adds constraints, so earlier failed
    # omissions remain impossible with all the other surviving sites fixed.
    return {g - 1 for g in gates}, True


def order_settle_groups(model, ranks, cut_sites):
    """Keep each ranked process fragment intact and settle only cyclic groups.

    Contract only uncut source edges. At a chosen join, a same-rank incoming
    branch can stay separate at no extra cost. Paths already separated by a
    real wait can also belong to different fragments.
    Retain every source successor and every wake, including backward wakes.
    The condensation order puts consumers after the local fixed point.
    """
    parent = list(range(len(ranks)))

    def root(n):
        while n != parent[n]:
            parent[n] = parent[parent[n]]
            n = parent[n]
        return n

    for a, b in model.control:
        if b not in cut_sites:
            parent[root(b)] = root(a)
    groups_by_root = {}
    fragment = []
    members = []
    levels = []
    for n in range(len(model.labels)):
        i = groups_by_root.setdefault(root(n), len(members))
        if i == len(members):
            members.append([])
            levels.append(ranks[n])
        members[i].append(n)
        fragment.append(i)
    adj = [set() for _ in members]
    for edges in (model.control, model.required):
        for a, b in edges:
            i, j = fragment[a], fragment[b]
            if i != j:
                adj[i].add(j)
    kernels = []
    ordered = [0] * len(members)
    offset = 0
    for group in components(range(len(adj)), adj):
        if len(group) > 1:
            kernels.append([n for i in group for n in members[i]])
        local = {
            level: pos for pos, level in enumerate(sorted({levels[i] for i in group}))
        }
        for i in group:
            ordered[i] = offset + local[levels[i]]
        offset += len(local)
    return [ordered[i] for i in fragment], kernels


def isolate_retries(model, solver, max_iterations, cut_budget_ms):
    kernels, which = retry_groups(model)
    model.retry_graphs = {}
    model.cut_packing = 0
    if model.topology:
        model.retry_boundaries = model.topology.boundaries()
    else:
        adj = [set() for _ in model.names]
        for a, b in model.required:
            adj[model.owner[a]].add(model.owner[b])
        groups = components(range(len(adj)), adj)
        model.coarse_components = (
            groups,
            {owner: i for i, g in enumerate(groups) for owner in g},
        )
        model.retry_boundaries = (
            set()
            if model.rank_first
            else {b for a, b in model.control if which.get(a) != which.get(b)}
        )
    result = (
        dict(eligible_feedback_operations=len(which))
        if model.rank_first
        else settle_summary(model, kernels)
    )
    all_owners = {model.owner[n] for n in which}
    lower, upper = -1, len(all_owners)
    best = set(all_owners)
    if model.hard:
        status, _, _, _ = retry_plan(
            model, solver, kernels, which, upper, None, best, [], max_iterations
        )
        if status != "sat":
            return dict(
                result,
                status="unsat-even-with-retries" if status == "unsat" else "unknown",
            )
    while upper > lower + 1:
        bound = (upper + lower) // 2
        status, owners, _, _ = retry_plan(
            model, solver, kernels, which, bound, None, [], [], max_iterations
        )
        if status == "unknown":
            return dict(
                result,
                retry_owner_lower=lower + 1,
                retry_owner_upper=upper,
                status="bounded",
            )
        if status == "unsat":
            lower = bound
        else:
            best = owners
            upper = len(owners)
    result.update(
        minimum_retry_owners=upper,
        retry_owner_witness=sorted(model.names[p] for p in best),
    )
    # All legal boundaries give a feasible slice upper bound. Try low costs
    # first; for a large graph a solver timeout is a bound, never an optimum.
    permitted = {b for _, b in model.control}
    # Start with intact processes at the proved retry-owner count. Each
    # refinement of this candidate must hit a witnessed ordering cycle.
    # If the refinement cap is reached, all legal sites give a known fallback.
    initial_cuts = () if model.rank_first else permitted
    status, owners, seed_cuts, ranks = retry_plan(
        model,
        solver,
        kernels,
        which,
        upper,
        len(permitted),
        best,
        initial_cuts,
        max_iterations,
    )
    if model.rank_first and status == "unknown":
        status, owners, seed_cuts, ranks = retry_plan(
            model, solver, kernels, which, upper, len(permitted), best, permitted, 1
        )
    if status != "sat":
        raise RuntimeError(
            "missing feasible cut schedule at certified retry-owner count"
        )

    def verify(owners, cuts, ranks):
        if model.topology:
            actual, retries = model.topology.costs()
        else:
            if any(ranks[a] > ranks[b] for a, b in model.control):
                raise RuntimeError("source order violated")
            actual = {b for a, b in model.control if ranks[a] < ranks[b]}
            retries = {(a, b) for a, b in model.required if ranks[a] >= ranks[b]}
        if not actual <= cuts or not all(
            b in which and which.get(a) == which[b] and model.owner[b] in owners
            for a, b in retries
        ):
            raise RuntimeError("invalid local retry witness")
        return owners, actual, ranks, retries

    incumbent = verify(owners, seed_cuts, ranks)
    cuts_hi = len(incumbent[1])
    lower = len(model.retry_boundaries) - 1
    result["mandatory_kernel_boundary_cuts"] = len(model.retry_boundaries)
    bounded = False
    deadline = time.monotonic() + cut_budget_ms / 1000 if cut_budget_ms else None
    irredundant = False
    if model.rank_first and cuts_hi > lower + 1:
        sites, irredundant = prune_cut_sites(model, owners, incumbent[1], deadline)
        if len(sites) < cuts_hi:
            status, owners, _, ranks = retry_plan(
                model, solver, kernels, which, upper, len(sites), owners, sites, 1
            )
            if status != "sat":
                raise RuntimeError("restored source equalities have no rank witness")
            incumbent = verify(owners, sites, ranks)
            cuts_hi = len(incumbent[1])
    while cuts_hi > lower + 1:
        bound = (cuts_hi + lower) // 2
        status, owners, cuts, ranks = retry_plan(
            model,
            solver,
            kernels,
            which,
            upper,
            bound,
            best,
            [],
            max_iterations,
            deadline,
        )
        lower = max(lower, model.cut_packing - 1)
        if status == "unknown":
            bounded = True
            break
        if status == "unsat":
            lower = max(lower, bound)
        else:
            incumbent = verify(owners, cuts, ranks)
            cuts_hi = len(incumbent[1])
            irredundant = False
    owners, cuts, ranks, retries = incumbent
    if model.rank_first:
        result["cut_sites_irredundant_for_retry_owners"] = (
            irredundant or cuts_hi == lower + 1
        )
        ranks, scheduled_groups = order_settle_groups(model, ranks, cuts)
        if any(ranks[a] > ranks[b] for a, b in model.control) or cuts != {
            b for a, b in model.control if ranks[a] < ranks[b]
        }:
            raise RuntimeError("settling the ranked slices changed the source cuts")
        backward = {(a, b) for a, b in model.required if ranks[a] >= ranks[b]}
        if not backward <= retries or not backward.isdisjoint(model.hard):
            raise RuntimeError(
                "settling the ranked slices introduced a backward dependency"
            )
        retries = backward
        result.update(settle_summary(model, scheduled_groups))
    if {model.owner[b] for _, b in retries} != owners:
        raise RuntimeError("retry owners differ from the certified minimum")
    return dict(
        result,
        status="bounded-cuts" if bounded else "optimal-with-local-retries",
        cut_lower=lower + 1,
        cut_upper=cuts_hi,
        minimum_retry_owners=len(owners),
        retry_owner_witness=sorted(model.names[p] for p in owners),
        cuts=len(cuts),
        slices=len(model.names) + len(cuts),
        cut_sites=sorted(model.labels[n] for n in cuts),
        backward_dependencies=sorted(
            [model.labels[a], model.labels[b]] for a, b in retries
        ),
        ranks={model.labels[n]: ranks[n] for n in range(len(model.labels))},
    )


def contract_native_evaluators(data, native_owners):
    """Substitute one SMT rank for all operations of each indivisible activation.

    A wait starts a new wave. Only operations joined by actual source edges
    share a symbol. Visibility, wake and hard ordering constraints are then
    built on these symbols by the ordinary rank solver.
    """
    if not isinstance(native_owners, (set, list, tuple)) or not all(
        isinstance(name, str) for name in native_owners
    ):
        raise ValueError("native evaluator owners must be a list of process names")
    keep = set(native_owners)
    names = {proc["name"] for proc in data["processes"]}
    if not keep <= names:
        raise ValueError("native evaluator inventory names an unknown process")
    aliases = {}
    processes = []
    for proc in data["processes"]:
        if proc["name"] not in keep:
            processes.append(proc)
            continue
        parent = {n: n for path in proc["paths"] for n in path}

        def root(n):
            while n != parent[n]:
                parent[n] = parent[parent[n]]
                n = parent[n]
            return n

        for path in proc["paths"]:
            for a, b in zip(path, path[1:]):
                parent[root(b)] = root(a)
        if aliases.keys() & parent.keys():
            raise ValueError("operation belongs to two native evaluator owners")
        mapping = {n: root(n) for n in parent}
        aliases.update(mapping)
        processes.append(
            dict(
                name=proc["name"], paths=[[n] for n in dict.fromkeys(mapping.values())]
            )
        )
    for proc in processes:
        if proc["name"] not in keep and any(
            n in aliases for path in proc["paths"] for n in path
        ):
            raise ValueError("native and unprotected processes share an operation")
    projected = dict(processes=processes)
    for field in ("dependencies", "hard_dependencies"):
        projected[field] = sorted(
            {(aliases.get(a, a), aliases.get(b, b)) for a, b in data.get(field, [])}
        )
    return projected, aliases


def solve(
    data,
    solver,
    allow_retries=False,
    max_iterations=1000,
    cut_budget_ms=250,
    rank_first=False,
    native_owners=(),
):
    if cut_budget_ms < 0:
        raise ValueError("cut budget must be nonnegative")
    if native_owners:
        projected, aliases = contract_native_evaluators(data, native_owners)
        plan = solve(
            projected, solver, allow_retries, max_iterations, cut_budget_ms, rank_first
        )
        # Keep quotient cycle witnesses, edge inventories and settle groups in
        # their own coordinate system. They need not be original source edges.
        result = dict(
            status=plan["status"],
            native_eval_owners=len(set(native_owners)),
            contracted_plan=plan,
        )
        for field in (
            "minimum_retry_owners",
            "retry_owner_lower",
            "retry_owner_upper",
            "cut_lower",
            "cut_upper",
        ):
            if field in plan:
                result[field] = plan[field]
        if "ranks" in plan:
            rank = plan["ranks"]
            source = {
                n: rank[aliases.get(n, n)]
                for proc in data["processes"]
                for path in proc["paths"]
                for n in path
            }
            cuts = set()
            for proc in data["processes"]:
                for path in proc["paths"]:
                    for a, b in zip(path, path[1:]):
                        if source[a] > source[b]:
                            raise RuntimeError(
                                "native eval expansion reversed a source edge"
                            )
                        if source[a] < source[b]:
                            cuts.add(b)
            if (
                cuts != set(plan["cut_sites"])
                or cuts.intersection(aliases)
                or any(
                    source[a] >= source[b] for a, b in data.get("hard_dependencies", [])
                )
            ):
                raise RuntimeError("native eval expansion violated a hard constraint")
            result.update(ranks=source, cut_sites=plan["cut_sites"], cuts=len(cuts))
        return result
    model = Model(data, rank_first)
    result = dict(
        processes=len(model.names),
        operations=len(model.labels),
        source_edges=len(model.control),
        required_forward_edges=len(model.required),
    )
    cycle = model.cyclic_witness()
    if cycle:
        edges = list(zip(cycle, cycle[1:]))
        terms = rank_constraints(
            [e for e in edges if e in model.control],
            [e for e in edges if e in model.required],
            sorted(set(cycle)),
        )
        status, _ = solver.check("all-cuts-cycle", terms)
        if status != "unsat":
            raise RuntimeError(f"cycle certificate returned {status}")
        result.update(status="unsat", cycle=[model.labels[n] for n in cycle])
        if allow_retries or rank_first:
            result["zero_reentry"] = "unsat"
            result.update(isolate_retries(model, solver, max_iterations, cut_budget_ms))
        return result

    adj = [set() for _ in model.names]
    for a, b in model.required:
        adj[model.owner[a]].add(model.owner[b])
    groups = components(range(len(adj)), [sorted(v) for v in adj])
    group_of = {p: i for i, group in enumerate(groups) for p in group}
    local = defaultdict(list)
    for a, b in sorted(model.required):
        i = group_of[model.owner[a]]
        if i == group_of[model.owner[b]]:
            local[i].append((a, b))
    control = defaultdict(list)
    for a, b in sorted(model.control):
        control[group_of[model.owner[a]]].append((a, b))
    ranks = {}
    offset = 0
    minima = []
    for i, group in enumerate(groups):
        nodes = [n for p in group for n in model.members[p]]
        if len(group) == 1:
            for n in nodes:
                ranks[n] = offset
            offset += 1
            continue
        assignment, high = minimum_cuts(
            i, nodes, control[i], local[i], solver, max_iterations
        )
        if assignment is None:
            return dict(result, status="unknown", component=i, lower_bound=high)
        for n in nodes:
            ranks[n] = offset + assignment[n]
        actual = {b for a, b in control[i] if ranks[a] < ranks[b]}
        if len(actual) != high:
            raise RuntimeError("cut witness failed minimum-cost check")
        minima.append(dict(processes=[model.names[p] for p in group], cuts=high))
        offset = 1 + max(ranks[n] for n in nodes)
    if any(ranks[a] > ranks[b] for a, b in model.control) or any(
        ranks[a] >= ranks[b] for a, b in model.required
    ):
        raise RuntimeError("whole-design rank verification failed")
    cut_sites = sorted({b for a, b in model.control if ranks[a] < ranks[b]})
    return dict(
        result,
        status="optimal",
        queue_reentries=0,
        cuts=len(cut_sites),
        slices=len(model.names) + len(cut_sites),
        cut_sites=[model.labels[n] for n in cut_sites],
        ranks={model.labels[n]: ranks[n] for n in range(len(model.labels))},
        cyclic_process_components=minima,
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("graph", type=Path)
    ap.add_argument("-o", "--output", type=Path, required=True)
    ap.add_argument(
        "--z3", help="use this external Z3 executable instead of the bundled solver"
    )
    ap.add_argument("--timeout-ms", type=int, default=30_000)
    ap.add_argument("--dump-smt", type=Path)
    ap.add_argument(
        "--native-eval-owners",
        type=Path,
        help="JSON list of certified source process names whose native activations must remain indivisible",
    )
    ap.add_argument(
        "--local-retries",
        action="store_true",
        help="on unsatisfiable forward order, isolate feedback and minimize queue-entry owners, then cuts",
    )
    ap.add_argument("--max-refinements", type=int, default=1000)
    ap.add_argument(
        "--rank-first",
        action="store_true",
        help="minimize retry owners and rank splits before localizing settle groups",
    )
    ap.add_argument(
        "--cut-budget-ms",
        type=int,
        default=250,
        help="wall-time budget for optional cut refinement after a verified minimum-retry plan (default: 250 ms; 0 for unlimited)",
    )
    args = ap.parse_args()
    result = solve(
        json.loads(args.graph.read_text()),
        Z3(args.z3, args.timeout_ms, args.dump_smt),
        args.local_retries,
        args.max_refinements,
        args.cut_budget_ms,
        args.rank_first,
        json.loads(args.native_eval_owners.read_text())
        if args.native_eval_owners
        else (),
    )
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(
        {
            k: v
            for k, v in result.items()
            if k
            not in {
                "ranks",
                "cut_sites",
                "cyclic_process_components",
                "contracted_plan",
                "cycle",
                "retry_groups",
                "backward_dependencies",
            }
        }
    )


if __name__ == "__main__":
    main()
