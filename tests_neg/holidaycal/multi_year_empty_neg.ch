module Shoals.TestsNeg.HolidayCalMultiYearEmpty
import Std.Test (assert_false)
import Std.Datetime (date)
import Shoals.HolidayCal (is_holiday, hc_ldn_calendar_multi)
-- An empty year list covers no date, so it has no horizon to give.
def test_neg_multi_year_calendar_rejects_no_years() -> unit ! { Test } = assert_false(is_holiday(hc_ldn_calendar_multi([]), date(2025i64, 1i64, 1i64)), "an empty year list must fail")
