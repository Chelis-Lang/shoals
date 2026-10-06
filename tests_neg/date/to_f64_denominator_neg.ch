module Shoals.TestsNeg.DateToF64Denominator
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoals.Date (ActualActualIcma, year_fraction, year_fraction_to_f64)
-- A denominator above 2^53 is not exact in f64, so the quotient would not be
-- one rounding of the true value.
def test_neg_to_f64_rejects_a_large_denominator() -> unit ! { Test } = assert_eq(year_fraction_to_f64(year_fraction(date(2003i64, 11i64, 1i64), date(2003i64, 11i64, 2i64), ActualActualIcma { reference_start: date(2003i64, 11i64, 1i64), reference_end: date(2004i64, 5i64, 1i64), frequency: 100000000000000i64 })), 0.0f64, "a large denominator must fail")
