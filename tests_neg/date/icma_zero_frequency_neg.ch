module Shoals.TestsNeg.DateIcmaZeroFrequency
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoals.Date (ActActIcma, year_fraction)
-- A coupon frequency of zero would divide by zero and hand back an infinity
-- that reads as a year fraction. ACT/ACT ICMA scales by the number of coupon
-- periods per year, so there is no meaningful zero.
def test_neg_icma_rejects_zero_frequency() -> unit ! { Test } = {
  period_start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  period_end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(0, i64) }
  assert_eq(year_fraction(period_start, period_end, convention), cast(0.5, f64), "zero coupon frequency must trap")
}
