module Shoals.TestsNeg.IndicatorsZeroRollingMean
import Std.Test (assert_eq)
import Shoals.Indicators (ind_rolling_mean)
def test_neg_rolling_mean_rejects_zero_period_on_empty_input() -> unit ! { Test } = assert_eq(len(ind_rolling_mean(take([1.0f64], 0i64), 0i64)), 0i64, "invalid period must trap even on empty input")
