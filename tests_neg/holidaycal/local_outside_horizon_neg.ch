module Shoals.TestsNeg.HolidayCalLocalOutsideHorizon
import Std.Test (assert_true)
import Std.Datetime (date)
import Shoals.HolidayCal (is_business_day, hc_nyc_calendar)
-- The local predicate answers through the same horizon, so a 1900 query
-- against the 2025 list fails instead of reporting a weekday as open.
def test_neg_local_2025_calendar_rejects_1900() -> unit ! { Test } = assert_true(is_business_day(hc_nyc_calendar(), date(1900i64, 12i64, 25i64)), "a 2025 list must not answer for 1900")
