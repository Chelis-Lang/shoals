module Shoals.TestsNeg.DateRetiredAct365
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoals.Date (Act365, year_fraction, year_fraction_to_f64)
-- "ACT/365" is ambiguous between ACT/365 Fixed and ACT/ACT variants, so it is not a name.
def test_neg_act_365_is_not_a_convention() -> unit ! { Test } = assert_eq(year_fraction_to_f64(year_fraction(date(2025i64, 1i64, 1i64), date(2026i64, 1i64, 1i64), Act365)), 1.0f64, "an ambiguous name must not compile")
