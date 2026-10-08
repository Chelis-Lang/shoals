"""Negative parity and independent sanity checks for the spread reference gate."""

import math
import unittest

from manual_gates.spread_adi_oracle import conditional_price, decode, decode_native, exchange_price, reference_checks


class SpreadReferenceTests(unittest.TestCase):
    def test_reproduces_independent_reference_literals(self):
        observations, failures = reference_checks()
        self.assertEqual(failures, [])
        self.assertEqual(len(observations), 4)

    def test_exchange_with_yields_and_both_correlation_signs(self):
        for rho in (-.9, -.5, .5, .9):
            params = (110, 95, 0, -.03, .04, .02, .2, .3, rho, 2)
            self.assertAlmostEqual(conditional_price(params), exchange_price(params), places=8)

    def test_vanilla_reduction_when_second_asset_is_zero(self):
        params = (100, 0, 100, .05, 0, 0, .2, .3, 0, 1)
        self.assertAlmostEqual(conditional_price(params), 10.450583572185565, places=8)

    def test_zero_horizon_and_negative_strike(self):
        self.assertEqual(conditional_price((100, 95, -5, .05, 0, 0, .2, .3, .5, 0)), 10)
        params = (100, 95, -5, .05, .02, .01, .2, .3, .5, 1)
        reversed_params = (95, 100, 5, .05, .01, .02, .3, .2, .5, 1)
        expected_difference = 100 * math.exp(-.02) - 95 * math.exp(-.01) + 5 * math.exp(-.05)
        self.assertAlmostEqual(conditional_price(params) - conditional_price(reversed_params), expected_difference, places=8)

    def test_invalid_simpson_resolution_rejected(self):
        for intervals in (-2, 0, 1, 3):
            with self.assertRaises(ValueError):
                conditional_price((100, 95, 5, .05, 0, 0, .2, .3, .5, 1), intervals)

    def test_probe_decoder_requires_the_expected_carrier(self):
        self.assertEqual(decode({"type": "scalar", "value": {"dtype": "f32", "bits": "3f800000"}}), 1)
        for value in ({"type": "scalar", "value": {"dtype": "f64", "bits": "3ff0000000000000"}},
                      {"type": "tensor", "value": []}):
            with self.assertRaises(ValueError):
                decode(value)

    def test_native_probe_decoder_accepts_scalar_tuple_and_list(self):
        self.assertEqual(decode_native("pde_zero = 0.0\nprobe = 1.25\n"), 1.25)
        self.assertEqual(decode_native("probe = [1.25, 2.5]\n"), [1.25, 2.5])
        self.assertEqual(decode_native("probe.1 = 2.5\nprobe.0 = 1.25\n"), [1.25, 2.5])
        self.assertEqual(decode_native("probe = (1.25, 2.5)\n"), [1.25, 2.5])

    def test_native_probe_decoder_rejects_missing_duplicate_and_invalid_values(self):
        for text in ("other = 1.0\n", "probe.1 = 1.0\n", "probe = 1.0\nprobe = 2.0\n",
                     "probe = True\n", "probe = 'wrong carrier'\n", "probe = 1e1000\n",
                     "probe = 1.0\nprobe.0 = 2.0\n"):
            with self.assertRaises(ValueError):
                decode_native(text)


if __name__ == "__main__":
    unittest.main()
