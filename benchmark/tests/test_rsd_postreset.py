import contextlib
import io
import json
import os
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from scheduler import rsd_postreset


@unittest.skipUnless(hasattr(os, "sched_getaffinity"), "requires Linux CPU affinity")
class PostResetMeasurementTest(unittest.TestCase):
    def report(self, guest_counts, event="instructions:u"):
        # Supply the simulator's cap results directly so these tests need no PMU.
        states = [(host, (cap, guest, b"registers", b"", False))
                  for host, cap, guest in zip((10000, 10700), (20, 30), guest_counts)]
        args = ["rsd_postreset", "--sim", f"test={__file__}", "--image", __file__,
                "--source-root", ".", "--caps", "20", "30", "--repeats", "1", "--event", event]
        output = io.StringIO()
        with mock.patch.object(sys, "argv", args), mock.patch.object(
                rsd_postreset, "measure", side_effect=states), contextlib.redirect_stdout(output):
            rsd_postreset.main()
        return json.loads(output.getvalue())

    def test_reports_host_cost_and_guest_progress(self):
        result = self.report([3, 7])
        self.assertEqual(result["committed_riscv_ops_per_window"], {"20-30": 4})
        self.assertEqual(result["insns_per_simulated_cycle"]["test"], {"20-30": 70})

    def test_rejects_window_without_guest_progress(self):
        with self.assertRaisesRegex(RuntimeError, "no RISC-V retirement progress"):
            self.report([3, 3])

    def test_rejects_cycle_counts_as_instructions(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr), self.assertRaises(SystemExit) as error:
            self.report([3, 7], event="cycles:u")
        self.assertEqual(error.exception.code, 2)
        self.assertIn("retired user-space instructions", stderr.getvalue())
