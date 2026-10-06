module Shoals.TestsNeg.DateIcmaEmptyPeriod
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoals.Date (ActualActualIcma, year_fraction, year_fraction_to_f64)
-- A reference period that ends where it starts has no length to divide by.
def test_neg_icma_rejects_an_empty_period() -> unit ! { Test } = assert_eq(year_fraction_to_f64(year_fraction(date(2004i64, 5i64, 1i64), date(2004i64, 5i64, 1i64), ActualActualIcma { reference_start: date(2004i64, 5i64, 1i64), reference_end: date(2004i64, 5i64, 1i64), frequency: 2i64 })), 0.0f64, "an empty reference period must fail")
