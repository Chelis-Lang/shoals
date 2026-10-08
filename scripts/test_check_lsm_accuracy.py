"""Positive and mutation controls for the native LSM accuracy oracle."""

import copy
import json
import unittest

from check_lsm_accuracy import evaluate_output


class LsmAccuracyControls(unittest.TestCase):
    def setUp(self):
        self.values = {
            "atm_prices": [6.08, 6.10] * 4,
            "atm_tree_coarse": 6.089, "atm_tree_fine": 6.090,
            "itm_prices": [12.08, 12.10] * 4,
            "itm_tree_coarse": 12.086, "itm_tree_fine": 12.087,
        }

    def output(self, values=None):
        return "\n".join(f"{k} = {json.dumps(v)}" for k, v in (values or self.values).items())

    def test_positive(self):
        self.assertEqual(evaluate_output(self.output())["verdict"], "pass")

    def test_original_collapse_is_detected(self):
        self.values["atm_prices"] = [2.4734879] * 8
        self.assertEqual(evaluate_output(self.output())["verdict"], "fail")

    def test_high_dispersion_does_not_waive_absolute_accuracy(self):
        self.values["atm_prices"] = [5.5, 7.5] * 4
        self.assertTrue(any("absolute error" in x for x in evaluate_output(self.output())["failures"]))

    def test_small_bias_with_zero_uncertainty_is_detected(self):
        self.values["atm_prices"] = [6.20] * 8
        self.assertTrue(any("4 SE" in x for x in evaluate_output(self.output())["failures"]))

    def test_unconverged_reference_is_detected(self):
        self.values["itm_tree_coarse"] = 11.0
        self.assertTrue(any("tree refinement" in x for x in evaluate_output(self.output())["failures"]))

    def test_missing_truncated_nonfinite_and_duplicate_measurements_fail(self):
        for mutation in ("missing", "truncated", "nonfinite", "duplicate"):
            with self.subTest(mutation=mutation):
                values = copy.deepcopy(self.values)
                if mutation == "missing":
                    del values["atm_prices"]
                elif mutation == "truncated":
                    values["atm_prices"] = values["atm_prices"][:7]
                elif mutation == "nonfinite":
                    values["atm_prices"][0] = float("nan")
                output = self.output(values)
                if mutation == "duplicate":
                    output += "\natm_tree_fine = 6.090"
                with self.assertRaises(ValueError):
                    evaluate_output(output)


if __name__ == "__main__":
    unittest.main()
