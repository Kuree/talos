"""Small exhaustive checks for the contract used by the native eval ranker."""

from itertools import permutations
import os
import shutil
import unittest

from eval_rank import Node, certify, chain_domains, solve
from forward_rank import Z3
import rank_native
from verify_heuristic import better_instance


@unittest.skipUnless(
    os.environ.get("Z3")
    or shutil.which("z3")
    or hasattr(rank_native.lib, "talos_rank_solver"),
    "Z3 required",
)
class EvalRankTests(unittest.TestCase):
    def setUp(self):
        self.solver = Z3(os.getenv("Z3"), 5000, None)
        self.nodes = [
            Node(i, i, 0, 0, 1, 0, 0, 1, 1, 0, 0, 0, f"w{i}", f"b{i}") for i in range(3)
        ]
        self.groups = {n.wrapper: "g" for n in self.nodes}
        self.edges = [(0, 1), (0, 2), (2, 1), (1, 0)]

    def test_optimum_and_indivisible_native_body(self):
        order, report = solve(self.nodes, self.edges, self.groups, self.solver)

        def cost(order):
            back = [b for a, b in self.edges if order.index(a) >= order.index(b)]
            return len(set(back)), len(back)

        self.assertEqual(cost(order), min(map(cost, permutations(order))))
        self.assertEqual(cost(order), (1, 1))
        self.assertTrue(report["optimal"])
        ranks = {n: i for i, n in enumerate(order)}
        self.assertEqual(
            certify(
                self.nodes, self.edges, self.groups, set(), self.solver, ranks, False
            ),
            "sat",
        )
        self.assertEqual(
            certify(
                self.nodes,
                self.edges,
                self.groups,
                set(),
                self.solver,
                ranks,
                False,
                forced_cut=1,
            ),
            "unsat",
        )

    def test_forwarding_chain_proof_changes_the_optimum(self):
        fixed, chains = chain_domains(
            self.nodes, self.groups, [["w0", "w1", "w2"]], False
        )
        order, report = solve(
            self.nodes, self.edges, self.groups, self.solver, False, fixed, chains
        )
        self.assertEqual(order, [0, 1, 2])
        self.assertEqual((report["backward_owners"], report["backward_edges"]), (2, 2))
        self.assertEqual(
            certify(
                self.nodes,
                self.edges,
                self.groups,
                fixed,
                self.solver,
                {0: 0, 2: 1, 1: 2},
                False,
                chains=chains,
            ),
            "unsat",
        )

    def test_checkpoint_stays_between_its_neighbours(self):
        from dataclasses import replace

        nodes = list(self.nodes)
        nodes[1] = replace(nodes[1], checkpoint=1)
        order, report = solve(nodes, self.edges, self.groups, self.solver)
        self.assertEqual(order, [0, 1, 2])
        self.assertEqual(report["movable_slots"], 0)
        self.assertEqual(
            certify(
                nodes,
                self.edges,
                self.groups,
                set(),
                self.solver,
                {0: 2, 1: 1, 2: 0},
                False,
            ),
            "unsat",
        )

    def test_paper_query_against_all_three_node_graphs(self):
        edges = list(permutations(range(3), 2))
        for mask in range(1 << len(edges)):
            selected = [edge for i, edge in enumerate(edges) if mask & (1 << i)]
            # A self wake has a constant cost. Multiple incoming backward
            # edges to one node must still count as one destination.
            selected.append((1, 1))

            def cost(order):
                back = [b for a, b in selected if order.index(a) >= order.index(b)]
                return len(set(back)), len(back)

            base = cost([0, 1, 2])
            best = min(cost(order) for order in permutations(range(3)))
            witness, better, pair = better_instance(
                self.nodes, selected, self.groups, []
            )
            self.assertEqual(pair, base)
            self.assertEqual(self.solver.check("baseline", witness)[0], "sat")
            self.assertEqual(
                self.solver.check("better", better)[0],
                "sat" if best < base else "unsat",
                mask,
            )

    def test_paper_query_constraints_do_not_pin_every_rank(self):
        from dataclasses import replace

        for nodes, chains in (
            (self.nodes, [["w0", "w1", "w2"]]),
            ([self.nodes[0], replace(self.nodes[1], checkpoint=1), self.nodes[2]], []),
        ):
            witness, better, _ = better_instance(nodes, self.edges, self.groups, chains)
            self.assertEqual(self.solver.check("baseline", witness)[0], "sat")
            self.assertEqual(self.solver.check("native", better)[0], "unsat")
            _, relaxed, _ = better_instance(
                nodes, self.edges, self.groups, chains, "graph-only"
            )
            self.assertEqual(self.solver.check("relaxed", relaxed)[0], "sat")


if __name__ == "__main__":
    unittest.main()
