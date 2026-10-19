module Shoals.TestsNeg.IndicatorsZeroRollingSum
import Std.Test (assert_eq)
import Shoals.Indicators (ind_rolling_sum)
-- Validation applies even when no input element will be visited.
def test_neg_rolling_sum_rejects_zero_period_on_empty_input() -> unit ! { Test } = assert_eq(len(ind_rolling_sum(take([1.0f64], 0i64), 0i64)), 0i64, "invalid period must trap before returning an empty list")
