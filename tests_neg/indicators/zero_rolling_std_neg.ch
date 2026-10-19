module Shoals.TestsNeg.IndicatorsZeroRollingStd
import Std.Test (assert_eq)
import Shoals.Indicators (ind_rolling_std, DdofPopulation)
-- Validation applies even when no input element will be visited.
def test_neg_rolling_std_rejects_zero_period_on_empty_input() -> unit ! { Test } = assert_eq(len(ind_rolling_std(take([1.0f64], 0i64), 0i64, DdofPopulation)), 0i64, "invalid period must trap before returning an empty list")
