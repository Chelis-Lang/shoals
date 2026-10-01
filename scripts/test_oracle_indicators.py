#!/usr/bin/env python3
"""Self-checks for `scripts/oracle_indicators.py` (shoals#83).

WHY THIS EXISTS. `oracle_indicators.py` produces the decimals that
`tests/indicators.ch` asserts, so if the oracle is wrong the Chelis tests
are wrong in exactly the same direction and nothing notices. The 45 Chelis
tests do cross-check it -- they are an independent implementation agreeing
on 40-odd values -- but that agreement is symmetric: it cannot tell which
side is right.

So this file checks the oracle against things that are true by derivation,
independently of either implementation: a constant series' exponential
average is that constant, a strictly monotone series pins RSI to 100 or 0,
an SMA over an arithmetic ramp is the window midpoint, the two ddof
deviations differ by exactly sqrt(n/(n-1)), and the Wilder and span alphas
differ for every n > 1. These are the same identities
`properties/indicators.ch` asserts on the Chelis side, deliberately: the
pair brackets the oracle and the module with one set of derivable facts.

MANUAL GATE. Not part of `scripts/run_local_gate.py` and not in CI -- it
guards an evidence-producing script rather than shipped behaviour.

    Command:   python3 scripts/test_oracle_indicators.py
    Success:   exit 0 and a final `ORACLE SELF-CHECK: PASS` line
    Owner:     shoals#83 / spec/shoals_quant_surface.md §2.15
    Run it:    whenever oracle_indicators.py changes, before re-transcribing
               any decimal into tests/indicators.ch

Re-run `oracle_indicators.py` itself and diff its output against the
transcribed values in `tests/indicators.ch` as the companion step; nothing
checks that transcription automatically.
"""

from __future__ import annotations

import sys
import unittest

sys.path.insert(0, "scripts")

import oracle_indicators as o  # noqa: E402

TOL = 1e-12


def defined(series):
    """The non-None tail, with its first index."""
    first = next((i for i, v in enumerate(series) if v is not None), len(series))
    return first, [v for v in series[first:]]


class AlphaConventions(unittest.TestCase):
    def test_wilder_and_span_differ_for_every_n_above_one(self):
        # The conflation shoals#83 measured in ~105 programs. If these ever
        # coincide the whole module's premise is wrong.
        for n in range(2, 40):
            self.assertNotAlmostEqual(
                o.alpha_wilder(n), o.alpha_span(n), delta=1e-9, msg=f"n={n}"
            )
        self.assertAlmostEqual(o.alpha_span(1), o.alpha_wilder(1), delta=TOL)

    def test_exact_values(self):
        self.assertAlmostEqual(o.alpha_span(14), 2 / 15, delta=TOL)
        self.assertAlmostEqual(o.alpha_wilder(14), 1 / 14, delta=TOL)


class AnalyticIdentities(unittest.TestCase):
    def test_constant_series_is_a_fixed_point_of_every_ema_convention(self):
        xs = [7.25] * 12
        for seed in ("first", "sma"):
            for a in (o.alpha_span(4), o.alpha_wilder(4)):
                _, vals = defined(o.ema(xs, 4, seed, a))
                for v in vals:
                    self.assertAlmostEqual(v, 7.25, delta=TOL)

    def test_monotone_up_rsi_is_exactly_one_hundred(self):
        xs = [100.0 + i for i in range(20)]
        for kind in ("wilder", "ema", "simple"):
            _, vals = defined(o.rsi(xs, 5, kind))
            for v in vals:
                self.assertAlmostEqual(v, 100.0, delta=TOL, msg=kind)

    def test_monotone_down_rsi_is_exactly_zero(self):
        xs = [100.0 - i for i in range(20)]
        for kind in ("wilder", "ema", "simple"):
            _, vals = defined(o.rsi(xs, 5, kind))
            for v in vals:
                self.assertAlmostEqual(v, 0.0, delta=TOL, msg=kind)

    def test_ramp_sma_is_the_window_midpoint(self):
        start, step, n = 5.0, 2.0, 4
        xs = [start + step * i for i in range(14)]
        out = o.rolling(xs, n, o.mean)
        offset = step * (n - 1) / 2
        self.assertEqual(sum(v is None for v in out), n - 1)
        for i in range(n - 1, len(xs)):
            self.assertAlmostEqual(out[i], xs[i] - offset, delta=TOL)

    def test_ddof_ratio_is_exactly_sqrt_n_over_n_minus_one(self):
        xs = [10.0, 11.0, 12.0, 11.0, 10.0, 11.0, 13.0, 14.0, 13.0, 12.0]
        for n in (3, 4, 5):
            expected = (n / (n - 1)) ** 0.5
            pop = o.rolling(xs, n, lambda w: o.var(w, 0) ** 0.5)
            samp = o.rolling(xs, n, lambda w: o.var(w, 1) ** 0.5)
            for p, s in zip(pop, samp):
                if p is None or p < 1e-12:
                    continue
                self.assertAlmostEqual(s / p, expected, delta=1e-10, msg=f"n={n}")

    def test_constant_bar_range_recovers_the_range(self):
        base, r, n, m = 50.0, 1.5, 4, 12
        high, low, close = [base + r / 2] * m, [base - r / 2] * m, [base] * m
        _, vals = defined(o.smooth(o.true_range(high, low, close), n, "wilder"))
        for v in vals:
            self.assertAlmostEqual(v, r, delta=TOL)


class WarmupLengths(unittest.TestCase):
    """The lengths docs/src/indicators.md and §2.15.4 publish, across many n
    rather than the single period the fixture happens to use."""

    def setUp(self):
        self.high = [10.0 + i * 0.7 + (i % 3) * 0.4 for i in range(40)]
        self.low = [h - 1.1 for h in self.high]
        self.close = [h - 0.5 for h in self.high]

    def test_sma_warms_up_for_n_minus_one(self):
        for n in (1, 2, 3, 5, 14, 20):
            out = o.rolling(self.close, n, o.mean)
            self.assertEqual(sum(v is None for v in out), n - 1, f"n={n}")

    def test_first_value_seeding_has_no_warmup_and_sma_seeding_has_n_minus_one(self):
        for n in (2, 3, 5, 14):
            self.assertEqual(sum(v is None for v in o.ema(self.close, n, "first", o.alpha_span(n))), 0, f"n={n}")
            self.assertEqual(sum(v is None for v in o.ema(self.close, n, "sma", o.alpha_span(n))), n - 1, f"n={n}")

    def test_wilder_rsi_and_atr_warm_up_for_n(self):
        for n in (2, 3, 5, 14):
            self.assertEqual(sum(v is None for v in o.rsi(self.close, n, "wilder")), n, f"rsi n={n}")
            atr = o.smooth(o.true_range(self.high, self.low, self.close), n, "wilder")
            self.assertEqual(sum(v is None for v in atr), n, f"atr n={n}")

    def test_adx_warms_up_for_two_n_minus_one(self):
        for n in (2, 3, 4, 5, 7, 14):
            _, _, adx = o.adx(self.high, self.low, self.close, n)
            self.assertEqual(sum(v is None for v in adx), 2 * n - 1, f"n={n}")

    def test_true_range_warms_up_for_exactly_one_bar(self):
        tr = o.true_range(self.high, self.low, self.close)
        self.assertEqual(sum(v is None for v in tr), 1)
        self.assertIsNone(tr[0])


class DegenerateCases(unittest.TestCase):
    """The documented reference behaviours, which are silent fallbacks in the
    module and would otherwise be untested on the Python side."""

    def test_flat_series_rsi_reads_zero(self):
        # TA-Lib guards the SUM: `if (prevGain + prevLoss > 0.0) ... else 0.0`.
        # A dead-flat window has both at zero, so it reads 0 -- not 100, not
        # 50, not NaN. This is the case an earlier revision got backwards.
        _, vals = defined(o.rsi([5.0] * 10, 3, "wilder"))
        for v in vals:
            self.assertEqual(v, 0.0)

    def test_monotone_rise_still_reads_one_hundred(self):
        # The sibling of the above, and the reason the guard must be on the
        # SUM rather than on the loss: a zero loss with a POSITIVE gain is an
        # ordinary division and still reads exactly 100.
        _, vals = defined(o.rsi([100.0 + i for i in range(12)], 3, "wilder"))
        for v in vals:
            self.assertEqual(v, 100.0)

    def test_true_range_takes_the_gap_term_when_it_dominates(self):
        # A gap up: |h - prev_c| exceeds h - l, so the gap must win.
        high, low, close = [10.0, 20.0], [9.0, 19.0], [9.5, 19.5]
        tr = o.true_range(high, low, close)
        self.assertAlmostEqual(tr[1], abs(20.0 - 9.5), delta=TOL)
        self.assertGreater(tr[1], 20.0 - 19.0)

    def test_closed_form_matches_the_recursion(self):
        # The same cross-check references/indicators.ch makes in Chelis.
        xs = [10.0, 11.0, 12.0, 11.0, 10.0, 11.0, 13.0, 14.0]
        n = 3
        a = o.alpha_span(n)
        recursive = o.ema(xs, n, "first", a)
        for i in range(len(xs)):
            closed = (1 - a) ** i * xs[0] + sum(a * (1 - a) ** (i - j) * xs[j] for j in range(1, i + 1))
            self.assertAlmostEqual(recursive[i], closed, delta=1e-12, msg=f"i={i}")


if __name__ == "__main__":
    result = unittest.main(exit=False, verbosity=2).result
    if result.wasSuccessful():
        print("\nORACLE SELF-CHECK: PASS")
        sys.exit(0)
    print("\nORACLE SELF-CHECK: FAIL")
    sys.exit(1)
