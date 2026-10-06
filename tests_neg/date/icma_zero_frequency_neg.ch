module Shoals.TestsNeg.DateIcmaZeroFrequency
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoals.Date (ActualActualIcma, year_fraction, year_fraction_to_f64)
-- A coupon frequency counts periods per year, so zero has no meaning.
def test_neg_icma_rejects_zero_frequency() -> unit ! { Test } = assert_eq(year_fraction_to_f64(year_fraction(date(2003i64, 11i64, 1i64), date(2004i64, 5i64, 1i64), ActualActualIcma { reference_start: date(2003i64, 11i64, 1i64), reference_end: date(2004i64, 5i64, 1i64), frequency: 0i64 })), 0.5f64, "zero frequency must fail")
