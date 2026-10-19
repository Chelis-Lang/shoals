module Shoals.TestsNeg.IndicatorsZeroRollingMin
import Std.Test (assert_eq)
import Shoals.Indicators (ind_rolling_min)
-- Validation applies even when no input element will be visited.
def test_neg_rolling_min_rejects_zero_period_on_empty_input() -> unit ! { Test } = assert_eq(len(ind_rolling_min(take([1.0f64], 0i64), 0i64)), 0i64, "invalid period must trap before returning an empty list")
