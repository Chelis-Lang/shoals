module Shoals.TestsNeg.IndicatorsUnequalLengths
import Std.Test (assert_eq)
import Shoals.Indicators (true_range)
-- Multi-series indicators index high, low and close at the same i. Unequal
-- lengths would silently truncate under `zip`, so the length is checked.
--
-- Asserting the unguarded length keeps the probe non-vacuous; see
-- `zero_period_neg.ch`.
def test_neg_true_range_rejects_unequal_lengths() -> unit ! { Test } = assert_eq(len(true_range([cast(2.0, f64), cast(3.0, f64)], [cast(1.0, f64)], [cast(1.5, f64), cast(2.5, f64)])), cast(2, i64), "true_range over unequal-length bars must trap")
