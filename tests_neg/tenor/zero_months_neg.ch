module Shoals.TestsNeg.TenorZeroMonths
import Std.Test (assert_eq)
import Std.Datetime (period)
import Shoals.Tenor (tenor_months, tenor_period)
-- A tenor is a positive length; a zero count would make a schedule loop in place.
def test_neg_tenor_months_rejects_zero() -> unit ! { Test } = assert_eq(tenor_period(tenor_months(0i64)), period(0i64, 0i64), "a zero count must fail")
