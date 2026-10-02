module Shoals.TestsNeg.DateIcmaDegeneratePeriod
import Std.Test (assert_eq)
import Std.Time (date)
import Shoals.Date (ActActIcma, year_fraction)
-- A coupon period that ends where it starts has no day count to measure the
-- accrual against. Admitting it would divide by zero rather than reporting that
-- the period is the thing that is wrong.
def test_neg_icma_rejects_empty_period() -> unit ! { Test } = {
  pivot = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start: pivot, period_end: pivot, frequency: cast(2, i64) }
  assert_eq(year_fraction(pivot, pivot, convention), cast(0.0, f64), "an empty coupon period must trap")
}
