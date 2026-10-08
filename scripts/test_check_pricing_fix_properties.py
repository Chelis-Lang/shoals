#!/usr/bin/env python3
"""Adversarial tests for bounded pricing property-result classification."""

import copy
import json
import unittest

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
    rows.append({"kind": "summary", "total": 8, "passed": 4, "failed": 4,
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


if __name__ == "__main__":
    unittest.main()
