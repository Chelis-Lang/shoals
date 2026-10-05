module Shoals.TestsNeg.DateIcmaReversedPeriod
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoals.Date (ActActIcma, year_fraction)
-- Red-team F2/X3. The empty-period case alone left `lt(span, 1)`
-- indistinguishable from `eq(span, 0)`: with the guard narrowed to equality a
-- REVERSED coupon period passed and gave a negative denominator. The .expect text
-- says "must end after it starts", so a reversed period is what pins it.
def test_neg_icma_rejects_reversed_period() -> unit ! { Test } = {
  earlier = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  later = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start: later, period_end: earlier, frequency: cast(2, i64) }
  assert_eq(year_fraction(earlier, later, convention), cast(-0.5, f64), "a reversed coupon period must trap")
}
