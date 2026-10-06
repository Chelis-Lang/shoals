module Shoals.TestsNeg.HolidayCalAdaptedOutsideHorizon
import Std.Test (assert_true)
import Std.Datetime (date)
import Std.Datetime.Business (is_business_day)
import Shoals.HolidayCal (as_business_calendar, hc_nyc_calendar)
-- `hc_nyc_calendar()` lists 2025 dates only, so its adapted business calendar
-- has no answer for 2030; the trapping query must fail rather than guess.
def test_neg_adapted_2025_calendar_rejects_2030() -> unit ! { Test } = assert_true(is_business_day(as_business_calendar(hc_nyc_calendar()), date(2030i64, 12i64, 25i64)), "a 2025 list must not answer for 2030")
