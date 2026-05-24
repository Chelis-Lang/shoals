module Shoals.Tests.Calendar
import Std.Test (assert_true, assert_false, assert_eq_bool)
import Std.Time (date)
import Shoals.Calendar (Calendar, is_holiday, is_business_day, nyc_calendar, ldn_calendar, joint_calendar, weekend_only_calendar, empty_calendar)
def test_nyc_new_year_is_holiday() -> unit ! { Test } = {
  cal = nyc_calendar()
  d = date(cast(2025, int64), cast(1, int64), cast(1, int64))
  assert_true(is_holiday(cal, d), "NYC: 2025-01-01 New Year is a holiday")
}
def test_nyc_independence_day_is_holiday() -> unit ! { Test } = {
  cal = nyc_calendar()
  d = date(cast(2025, int64), cast(7, int64), cast(4, int64))
  assert_true(is_holiday(cal, d), "NYC: 2025-07-04 is a holiday")
}
def test_nyc_random_wednesday_is_not_holiday() -> unit ! { Test } = {
  cal = nyc_calendar()
  d = date(cast(2025, int64), cast(8, int64), cast(13, int64))
  assert_false(is_holiday(cal, d), "NYC: 2025-08-13 (a Wednesday) is not a holiday")
}
def test_ldn_christmas_is_holiday() -> unit ! { Test } = {
  cal = ldn_calendar()
  d = date(cast(2025, int64), cast(12, int64), cast(25, int64))
  assert_true(is_holiday(cal, d), "LDN: 2025-12-25 is a holiday")
}
def test_ldn_boxing_day_is_holiday() -> unit ! { Test } = {
  cal = ldn_calendar()
  d = date(cast(2025, int64), cast(12, int64), cast(26, int64))
  assert_true(is_holiday(cal, d), "LDN: 2025-12-26 is a holiday")
}
def test_ldn_does_not_observe_july_4() -> unit ! { Test } = {
  cal = ldn_calendar()
  d = date(cast(2025, int64), cast(7, int64), cast(4, int64))
  assert_false(is_holiday(cal, d), "LDN: 2025-07-04 is not a holiday")
}
def test_business_day_wednesday() -> unit ! { Test } = {
  cal = nyc_calendar()
  d = date(cast(2025, int64), cast(8, int64), cast(13, int64))
  assert_true(is_business_day(cal, d), "NYC: 2025-08-13 (Wed, non-holiday) is a business day")
}
def test_business_day_saturday() -> unit ! { Test } = {
  cal = nyc_calendar()
  d = date(cast(2025, int64), cast(8, int64), cast(16, int64))
  assert_false(is_business_day(cal, d), "NYC: 2025-08-16 (Sat) is not a business day")
}
def test_business_day_new_year_2025() -> unit ! { Test } = {
  cal = nyc_calendar()
  d = date(cast(2025, int64), cast(1, int64), cast(1, int64))
  assert_false(is_business_day(cal, d), "NYC: 2025-01-01 (holiday Wed) is not a business day")
}
def test_joint_calendar_us_july_4() -> unit ! { Test } = {
  cal = joint_calendar(nyc_calendar(), ldn_calendar())
  d_us = date(cast(2025, int64), cast(7, int64), cast(4, int64))
  assert_true(is_holiday(cal, d_us), "joint cal: US July 4 still a holiday")
}
def test_joint_calendar_uk_boxing_day() -> unit ! { Test } = {
  cal = joint_calendar(nyc_calendar(), ldn_calendar())
  d_uk = date(cast(2025, int64), cast(12, int64), cast(26, int64))
  assert_true(is_holiday(cal, d_uk), "joint cal: UK Boxing Day a holiday")
}
def test_empty_calendar_has_no_holidays() -> unit ! { Test } = {
  cal = empty_calendar("test")
  d = date(cast(2025, int64), cast(1, int64), cast(1, int64))
  assert_false(is_holiday(cal, d), "empty calendar has no holidays")
}
def test_weekend_only_calendar_treats_weekday_as_business() -> unit ! { Test } = {
  cal = weekend_only_calendar()
  d = date(cast(2025, int64), cast(8, int64), cast(13, int64))
  assert_true(is_business_day(cal, d), "weekend-only: Wed is a business day")
}
