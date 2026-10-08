#!/usr/bin/env python3
"""Adversarial tests for bounded pricing property-result classification."""

import copy
import json
import unittest
import contextlib
import io
import subprocess
import tempfile
from pathlib import Path
from unittest import mock

import check_pricing_fix_properties as runner

from check_pricing_fix_properties import FAMILIES, validate_run


def valid_records():
    rows = []
    for name in FAMILIES["jumpmoments"]:
        for corrupt in (False, True):
            row = {
                "kind": "property", "name": name + ("_corrupted" if corrupt else ""),
                "proof_tier": "fuzz", "seed": 0,
                "source": {"file": "properties/jumpmoments.ch"},
                "status": "failed" if corrupt else "passed",
                "accepted_samples": 1 if corrupt else 25,
                "attempted_samples": 1 if corrupt else 25,
            }
            if corrupt:
                row["counterexample"] = {"lambda_jump": 0.0}
            rows.append(row)
    count = len(FAMILIES["jumpmoments"])
    rows.append({"kind": "summary", "total": 2 * count, "passed": count, "failed": count,
                 "errors": 0, "unsupported": 0})
    return rows


def output(rows):
    return "\n".join(json.dumps(row) for row in rows)


class ResultClassificationTests(unittest.TestCase):
    def test_valid_bounded_evidence_accepts_expected_nonzero_exit(self):
        validate_run(output(valid_records()), 1, "jumpmoments", 0)

    def test_rejected_samples_do_not_reduce_accepted_count(self):
        rows = valid_records()
        rows[0]["attempted_samples"] = 31
        validate_run(output(rows), 1, "jumpmoments", 0)

    def test_missing_duplicate_and_unexpected_records_fail(self):
        cases = [valid_records()[1:], valid_records() + [valid_records()[0]],
                 valid_records() + [{"kind": "error"}], [], [{}], [None]]
        for rows in cases:
            with self.subTest(rows=rows):
                with self.assertRaises(ValueError):
                    validate_run(output(rows), 1, "jumpmoments", 0)

    def test_wrong_method_status_source_and_counts_fail(self):
        mutations = {"proof_tier": ("smt", None), "seed": (1, False),
                     "source": (None, {}, {"file": "properties/other.ch"}),
                     "status": ("unsupported", "error", "failed"),
                     "accepted_samples": (0, 24, 26, True, 25.0),
                     "attempted_samples": (0, 24, True),
                     "counterexample": ({"x": 1},)}
        for key, values in mutations.items():
            for value in values:
                rows = valid_records()
                rows[0][key] = value
                with self.subTest(key=key, value=value):
                    with self.assertRaises(ValueError):
                        validate_run(output(rows), 1, "jumpmoments", 0)

    def test_surviving_or_witnessless_control_fails(self):
        for mutation in ({"status": "passed"}, {"counterexample": None},
                         {"counterexample": {}}, {"counterexample": []},
                         {"accepted_samples": 0}):
            rows = valid_records()
            rows[1].update(mutation)
            with self.subTest(mutation=mutation):
                with self.assertRaises(ValueError):
                    validate_run(output(rows), 1, "jumpmoments", 0)

    def test_summary_mismatch_and_duplicate_fail(self):
        for key in ("total", "passed", "failed", "errors", "unsupported"):
            for value in (None, False, -1, 99):
                rows = valid_records()
                rows[-1][key] = value
                with self.subTest(key=key, value=value):
                    with self.assertRaises(ValueError):
                        validate_run(output(rows), 1, "jumpmoments", 0)
        rows = valid_records()
        rows.append(copy.deepcopy(rows[-1]))
        with self.assertRaises(ValueError):
            validate_run(output(rows), 1, "jumpmoments", 0)

    def test_malformed_output_and_wrong_exit_fail(self):
        for value in ("compiler crashed", "{", output(valid_records()) + "\nwarning"):
            with self.assertRaises(ValueError):
                validate_run(value, 1, "jumpmoments", 0)
        for code in (0, 2, -9):
            with self.assertRaises(ValueError):
                validate_run(output(valid_records()), code, "jumpmoments", 0)


class SmokeSelectionTests(unittest.TestCase):
    @staticmethod
    def records(family, name):
        rows = valid_records()[:2]
        for row, suffix in zip(rows, ("", "_corrupted")):
            row["name"] = name + suffix
            row["source"]["file"] = f"properties/{family}.ch"
        rows.append({"kind": "summary", "total": 2, "passed": 1, "failed": 1,
                     "errors": 0, "unsupported": 0})
        return rows

    def test_expiry_subset_retains_sample_and_false_control_requirements(self):
        name = "lsm_expiry_intrinsic"
        rows = self.records("canonlsm", name)
        validate_run(output(rows), 1, "canonlsm", 0, property_names=(name,))
        for mutation in ({"accepted_samples": 24}, {"seed": 1}, {"proof_tier": "smt"}):
            bad = copy.deepcopy(rows)
            bad[0].update(mutation)
            with self.assertRaises(ValueError):
                validate_run(output(bad), 1, "canonlsm", 0, property_names=(name,))
        for mutation in ({"status": "passed"}, {"counterexample": {}}):
            bad = copy.deepcopy(rows)
            bad[1].update(mutation)
            with self.assertRaises(ValueError):
                validate_run(output(bad), 1, "canonlsm", 0, property_names=(name,))
        with self.assertRaises(ValueError):
            validate_run(output(rows), 0, "canonlsm", 0, property_names=(name,))
        with self.assertRaises(ValueError):
            validate_run(output(rows), 1, "canonlsm", 0)
        for selection in ((), ("invented",)):
            with self.assertRaises(ValueError):
                validate_run(output(rows), 1, "canonlsm", 0, property_names=selection)

    def test_smoke_runs_only_two_expiry_pairs_at_seed_zero_with_short_ceiling(self):
        calls = []
        def fake_run(command, **kwargs):
            family = Path(command[2]).stem
            name = command[command.index("--only") + 1]
            calls.append((command, kwargs["timeout"]))
            return subprocess.CompletedProcess(command, 1, output(self.records(family, name)), "")
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(runner, "ROOT", Path(directory)), \
                mock.patch.object(runner.subprocess, "run", side_effect=fake_run), \
                mock.patch("sys.argv", ["check_pricing_fix_properties.py", "--smoke"]), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(runner.main(), 0)
        self.assertEqual(len(calls), 2)
        self.assertEqual({command[command.index("--only") + 1] for command, _ in calls},
                         {"lsm_expiry_intrinsic", "spread_expiry_matches_intrinsic"})
        for command, timeout in calls:
            self.assertEqual(command[command.index("--samples") + 1], "25")
            self.assertEqual(command[command.index("--seed") + 1], "0")
            self.assertLessEqual(timeout, 60)

    def test_smoke_timeout_fails_without_reporting_pass(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(runner, "ROOT", Path(directory)), \
                mock.patch.object(runner.subprocess, "run", side_effect=subprocess.TimeoutExpired("prove", 60)), \
                mock.patch("sys.argv", ["check_pricing_fix_properties.py", "--smoke"]), \
                contextlib.redirect_stdout(io.StringIO()) as stdout, \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(runner.main(), 1)
            self.assertNotIn("PASS", stdout.getvalue())


if __name__ == "__main__":
    unittest.main()
