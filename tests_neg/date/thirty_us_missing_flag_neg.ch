module Shoals.TestsNeg.DateThirtyUsMissingFlag
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoals.Date (ThirtyOver360Us, year_fraction, year_fraction_to_f64)
-- 30/360 US cannot be requested without its end-of-month flag.
def test_neg_thirty_us_requires_the_flag() -> unit ! { Test } = assert_eq(year_fraction_to_f64(year_fraction(date(2025i64, 1i64, 1i64), date(2025i64, 7i64, 1i64), ThirtyOver360Us)), 0.5f64, "a missing flag must not compile")
