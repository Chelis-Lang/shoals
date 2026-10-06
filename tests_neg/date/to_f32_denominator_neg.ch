module Shoals.TestsNeg.DateToF32Denominator
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoals.Date (ActualActualIcma, year_fraction, year_fraction_to_f32)
-- A denominator of 2^29 or more could round twice through f64, so the f32
-- conversion refuses it. One day at 10^7 periods a year over a
-- 182-day period is 1/1.82e9.
def test_neg_to_f32_rejects_a_large_denominator() -> unit ! { Test } = assert_eq(year_fraction_to_f32(year_fraction(date(2003i64, 11i64, 1i64), date(2003i64, 11i64, 2i64), ActualActualIcma { reference_start: date(2003i64, 11i64, 1i64), reference_end: date(2004i64, 5i64, 1i64), frequency: 10000000i64 })), 0.0f32, "a large denominator must fail")
