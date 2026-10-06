module Shoals.TestsNeg.HolidayCalMultiYearGap
import Std.Test (assert_true)
import Std.Datetime (date)
import Shoals.HolidayCal (is_holiday, hc_nyc_calendar_multi)
-- A calendar covers one unbroken run of years. Building 2024 and 2026 without
-- 2025 would leave a year inside its range with no data.
def test_neg_multi_year_calendar_rejects_a_gap() -> unit ! { Test } = assert_true(is_holiday(hc_nyc_calendar_multi([2024i64, 2026i64]), date(2024i64, 1i64, 1i64)), "a gap in the years must fail")
