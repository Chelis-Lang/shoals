module Shoals.TestsNeg.DateBus252OutsideHorizon
import Std.Test (assert_eq)
import Std.Datetime (date)
import Shoreleave.UsFederal (us_federal)
import Shoals.Date (Business252, year_fraction, year_fraction_to_f64)
-- BUS/252 counts only inside the calendar horizon (US federal 2021-2030).
def test_neg_bus_252_rejects_a_date_outside_the_horizon() -> unit ! { Test } = assert_eq(year_fraction_to_f64(year_fraction(date(2030i64, 6i64, 1i64), date(2031i64, 6i64, 1i64), Business252 { calendar: us_federal() })), 1.0f64, "a date outside the horizon must fail")
