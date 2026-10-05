module Shoals.TestsNeg.DateIcmaNegativeFrequency
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoals.Date (ActActIcma, year_fraction)
-- Red-team F2/X1. The zero-frequency case alone left `lt(n, 1)` indistinguishable
-- from `eq(n, 0)`: with the guard narrowed to equality a negative frequency
-- passed and returned a NEGATIVE year fraction, which no caller could read as an
-- error. The docs say "a frequency below 1 traps", so below 1 is what is pinned.
def test_neg_icma_rejects_negative_frequency() -> unit ! { Test } = {
  period_start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  period_end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(-2, i64) }
  assert_eq(year_fraction(period_start, period_end, convention), cast(-0.5, f64), "a negative coupon frequency must trap")
}
