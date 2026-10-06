module Shoals.TestsNeg.DateReversedInterval
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoals.Date (ActualOver360, year_fraction, year_fraction_to_f64)
-- Every convention measures a forward accrual; a reversed one is a caller error.
def test_neg_year_fraction_rejects_a_reversed_interval() -> unit ! { Test } = assert_eq(year_fraction_to_f64(year_fraction(date(2025i64, 6i64, 1i64), date(2025i64, 1i64, 1i64), ActualOver360)), -0.42f64, "a reversed interval must fail")
