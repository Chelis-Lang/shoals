module Shoals.TestsNeg.DateIcmaAccrualOutsidePeriod
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoals.Date (ActualActualIcma, year_fraction, year_fraction_to_f64)
-- An accrual past the reference period belongs to the next coupon period.
def test_neg_icma_rejects_an_accrual_past_the_period() -> unit ! { Test } = assert_eq(year_fraction_to_f64(year_fraction(date(2003i64, 11i64, 1i64), date(2004i64, 11i64, 1i64), ActualActualIcma { reference_start: date(2003i64, 11i64, 1i64), reference_end: date(2004i64, 5i64, 1i64), frequency: 2i64 })), 1.0f64, "an accrual outside the period must fail")
