module Shoals.TestsNeg.IndicatorsNegativeShift
import Std.Test (assert_eq)
import Shoals.Indicators (ind_shift)
-- A negative shift is a look-ahead, not a lag: it would read an input index
-- greater than the output index, which is the defect the whole module is
-- built to make impossible.
def test_neg_shift_rejects_negative_lag() -> unit ! { Test } = assert_eq(len(ind_shift([cast(1.0, f64), cast(2.0, f64), cast(3.0, f64)], cast(-1, i64))), cast(3, i64), "a negative shift must trap rather than read the future")
