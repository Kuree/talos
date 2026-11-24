"""Cross-check the finite-wave rank optimizer against exhaustive small schedules."""

import os
from pathlib import Path
import random
import shutil
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

import rank_native
from forward_rank import Model, Z3, retry_groups, solve


def schedules(paths, emitted=()):
    if not any(paths):
        yield emitted
        return
    for i, path in enumerate(paths):
        if path:
            yield from schedules(
                paths[:i] + [path[1:]] + paths[i + 1 :], emitted + (path[0],)
            )


def exhaustive_cost(data, rank_first=False):
    model = Model(data)
    kernels, membership = retry_groups(model)
    best = None
    for order in schedules(model.members):
        pos = {n: i for i, n in enumerate(order)}
        if any(pos[a] >= pos[b] for a, b in model.hard):
            continue
        if not rank_first and any(
            max(pos[n] for n in g) - min(pos[n] for n in g) + 1 != len(g)
            for g in kernels
        ):
            continue
        backward = {(a, b) for a, b in model.required if pos[a] > pos[b]}
        if any(
            a not in membership or membership[a] != membership.get(b)
            for a, b in backward
        ):
            continue
        receivers = {model.owner[b] for a, b in backward}
        cuts = {
            b
            for a, b in model.control
            if pos[b] != pos[a] + 1
            or (not rank_first and membership.get(a) != membership.get(b))
        }
        cost = (len(receivers), len(cuts))
        best = cost if best is None else min(best, cost)
    return best


def graph(paths, deps, hard=()):
    return {
        "processes": [{"name": p[0][0], "paths": [p]} for p in paths],
        "dependencies": deps,
        "hard_dependencies": hard,
    }


@unittest.skipUnless(
    os.environ.get("Z3")
    or shutil.which("z3")
    or hasattr(rank_native.lib, "talos_rank_solver"),
    "Z3 executable or embedded solver required",
)
class ForwardRankTests(unittest.TestCase):
    def setUp(self):
        self.solver = Z3(os.environ.get("Z3"), 10000, None)

    def test_budget_keeps_feasible_plan_and_proved_owner_minimum(self):
        g = graph(
            [["a0"], ["b0"], ["c0", "c1"], ["d0"]],
            [["a0", "b0"], ["b0", "a0"], ["c0", "d0"], ["d0", "c1"]],
        )
        with patch("forward_rank.time.monotonic", side_effect=[1.0, 2.0]):
            r = solve(g, self.solver, allow_retries=True, cut_budget_ms=1)
        owners, cuts = exhaustive_cost(g)
        self.assertEqual(
            (r["status"], r["minimum_retry_owners"]), ("bounded-cuts", owners)
        )
        self.assertLessEqual(r["cut_lower"], cuts)
        self.assertEqual(r["cut_upper"], len(r["cut_sites"]))
        self.assertEqual(r["cut_sites"], ["c1"])
        rank = r["ranks"]
        self.assertLess(rank["c0"], rank["d0"])
        self.assertLess(rank["d0"], rank["c1"])
        back = [(a, b) for a, b in g["dependencies"] if rank[a] >= rank[b]]
        self.assertEqual([b[0] for a, b in back], r["retry_owner_witness"])
        exact = solve(g, self.solver, allow_retries=True, cut_budget_ms=0)
        self.assertEqual((exact["cut_lower"], exact["cut_upper"]), (cuts, cuts))

    @unittest.skipUnless(
        hasattr(rank_native.lib, "talos_rank_solver"), "embedded Z3 required"
    )
    def test_embedded_solver_dumps_replayable_queries(self):
        with TemporaryDirectory() as tmp:
            dump = Path(tmp)
            solver = Z3(None, 1000, dump)
            with patch("forward_rank.subprocess.run", side_effect=AssertionError):
                status, values = solver.check(
                    "example", ["(declare-const c1 Bool)", "(assert c1)"], ["c1"]
                )
            self.assertEqual((status, values), ("sat", {"c1": "true"}))
            query = (dump / "example.smt2").read_text()
            self.assertTrue(query.endswith("(check-sat)\n"))
            self.assertEqual(
                (dump / "example-model.smt2").read_text(), query + "(get-value (c1))\n"
            )

    def test_two_sources_must_split(self):
        g = graph(
            [["a0", "a1"], ["b0", "b1"], ["c0"]],
            [["a0", "b0"], ["b0", "c0"], ["c0", "a1"], ["a1", "b1"]],
        )
        r = solve(g, self.solver, allow_retries=True)
        self.assertEqual((r["queue_reentries"], r["cuts"], r["slices"]), (0, 2, 5))
        self.assertEqual(set(r["cut_sites"]), {"a1", "b1"})

    def test_local_cycle_and_forward_neighbors(self):
        g = graph(
            [["a0", "a1"], ["b0", "b1"], ["c0"], ["d0"]],
            [["c0", "b0"], ["b1", "a0"], ["a1", "b0"], ["a1", "d0"]],
        )
        r = solve(g, self.solver, allow_retries=True)
        self.assertEqual(r["zero_reentry"], "unsat")
        self.assertEqual(r["minimum_retry_owners"], 1)
        self.assertEqual(r["operations_outside_local_settle"], 2)
        self.assertEqual(set(r["retry_groups"][0]["members"]), {"a0", "a1", "b0", "b1"})
        self.assertEqual((r["minimum_retry_owners"], r["cuts"]), exhaustive_cost(g))

    def test_hard_cycle(self):
        g = graph([["a0"], ["b0"]], [], [["a0", "b0"], ["b0", "a0"]])
        self.assertEqual(
            solve(g, self.solver, allow_retries=True)["status"],
            "unsat-even-with-retries",
        )

    def test_native_eval_body_cannot_be_split_to_avoid_a_retry(self):
        g = graph([["a0", "a1"], ["b0"]], [["a0", "b0"], ["b0", "a1"]])
        free = solve(g, self.solver, rank_first=True)
        self.assertEqual((free["queue_reentries"], free["cut_sites"]), (0, ["a1"]))
        bound = solve(g, self.solver, rank_first=True, native_owners=["a"])
        self.assertEqual(bound["contracted_plan"]["minimum_retry_owners"], 1)
        self.assertEqual(bound["ranks"]["a0"], bound["ranks"]["a1"])
        self.assertEqual(bound["cut_sites"], [])
        g["hard_dependencies"] = g["dependencies"]
        self.assertEqual(
            solve(g, self.solver, rank_first=True, native_owners=["a"])["status"],
            "unsat-even-with-retries",
        )

    def test_native_eval_owner_does_not_join_distinct_activations(self):
        g = graph([["a0"], ["b0"]], [["a0", "b0"], ["b0", "a1"]])
        g["processes"][0]["paths"].append(["a1"])
        r = solve(g, self.solver, rank_first=True, native_owners=["a"])
        self.assertLess(r["ranks"]["a0"], r["ranks"]["b0"])
        self.assertLess(r["ranks"]["b0"], r["ranks"]["a1"])
        self.assertEqual(r["cuts"], 0)

    def test_rank_first_keeps_whole_process_across_feedback_boundary(self):
        g = graph(
            [["a0", "a1", "a2"], ["b0"], ["c0"], ["d0"]],
            [["a1", "b0"], ["b0", "a1"], ["c0", "a0"], ["a2", "d0"]],
        )
        isolated = solve(g, self.solver, allow_retries=True, cut_budget_ms=0)
        r = solve(g, self.solver, rank_first=True, cut_budget_ms=0)
        self.assertEqual((isolated["minimum_retry_owners"], isolated["cuts"]), (1, 2))
        self.assertEqual((r["minimum_retry_owners"], r["cuts"]), (1, 0))
        self.assertEqual(set(r["retry_groups"][0]["members"]), {"a0", "a1", "a2", "b0"})
        ranks = r["ranks"]
        self.assertEqual(ranks["a0"], ranks["a2"])
        self.assertLess(ranks["c0"], min(ranks["a0"], ranks["b0"]))
        self.assertLess(max(ranks["a2"], ranks["b0"]), ranks["d0"])

    def test_rank_first_still_splits_for_a_required_forward_handoff(self):
        g = graph(
            [["a0", "a1"], ["b0"], ["c0"], ["d0"]],
            [["a0", "b0"], ["b0", "a1"], ["a1", "c0"], ["c0", "d0"], ["d0", "c0"]],
        )
        r = solve(g, self.solver, rank_first=True, cut_budget_ms=0)
        self.assertEqual((r["minimum_retry_owners"], r["cut_sites"]), (1, ["a1"]))
        self.assertTrue(r["cut_sites_irredundant_for_retry_owners"])

    def test_rank_first_keeps_separate_activations_outside_feedback(self):
        g = graph([["a0"], ["b0"], ["c0"]], [["a0", "b0"], ["b0", "a0"], ["a1", "c0"]])
        # a1 is the same process after a true wait; no source edge crosses it.
        g["processes"][0]["paths"].append(["a1"])
        r = solve(g, self.solver, rank_first=True, cut_budget_ms=0)
        self.assertEqual(r["cut_sites"], [])
        self.assertEqual(set(r["retry_groups"][0]["members"]), {"a0", "b0"})
        self.assertLess(r["ranks"]["a1"], r["ranks"]["c0"])

    def test_forward_handoff_between_feedback_groups(self):
        g = graph(
            [["a0", "a1"], ["b0"], ["c0"], ["d0"]],
            [["a1", "b0"], ["b0", "a0"], ["c0", "d0"], ["d0", "c0"]],
            [["b0", "c0"]],
        )
        # The two source paths share both their entry and their join.
        g["processes"][0]["paths"].append(["a0", "a2", "a1"])
        r = solve(g, self.solver, allow_retries=True, cut_budget_ms=0)
        self.assertEqual(r["minimum_retry_owners"], 2)
        self.assertEqual((r["cut_lower"], r["cut_upper"]), (0, 0))
        ranks = r["ranks"]
        finished = max(ranks[n] for n in ("a0", "a1", "a2", "b0"))
        self.assertLess(finished, min(ranks["c0"], ranks["d0"]))

    def test_optimum_against_all_interleavings(self):
        rng = random.Random(935)
        hard_rng = random.Random(491)
        paths = [["a0", "a1"], ["b0", "b1"], ["c0", "c1"]]
        candidates = [
            (a, b)
            for pa in paths
            for pb in paths
            if pa is not pb
            for a in pa
            for b in pb
        ]
        for _ in range(24):
            deps = rng.sample(candidates, rng.randint(1, 8))
            for hard in (
                [],
                hard_rng.sample(deps, hard_rng.randint(1, min(3, len(deps)))),
            ):
                for rank_first in (False, True):
                    with self.subTest(deps=deps, hard=hard, rank_first=rank_first):
                        g = graph(paths, deps, hard)
                        r = solve(
                            g,
                            self.solver,
                            allow_retries=True,
                            cut_budget_ms=0,
                            rank_first=rank_first,
                        )
                        optimal = exhaustive_cost(g, rank_first)
                        if optimal is None:
                            self.assertEqual(r["status"], "unsat-even-with-retries")
                            continue
                        self.assertIn(
                            r["status"], {"optimal", "optimal-with-local-retries"}
                        )
                        self.assertEqual(
                            (r.get("minimum_retry_owners", 0), r["cuts"]), optimal
                        )


if __name__ == "__main__":
    unittest.main()
