module Shoals.TestsNeg.IndicatorsNegativeDiff
import Std.Test (assert_eq)
import Shoals.Indicators (ind_diff)
def test_neg_diff_rejects_negative_diff_lag() -> unit ! { Test } = assert_eq(len(ind_diff(take([1.0f64], 0i64), -1i64)), 0i64, "invalid difference lag must trap even on empty input")
