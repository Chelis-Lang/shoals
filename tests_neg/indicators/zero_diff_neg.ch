module Shoals.TestsNeg.IndicatorsZeroDiff
import Std.Test (assert_eq)
import Shoals.Indicators (ind_diff)
def test_neg_diff_rejects_zero_diff_lag() -> unit ! { Test } = assert_eq(len(ind_diff(take([1.0f64], 0i64), 0i64)), 0i64, "invalid difference lag must trap even on empty input")
