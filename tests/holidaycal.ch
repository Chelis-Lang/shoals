module Shoals.Tests.HolidayCal
import Std.Test (assert_true, assert_false, assert_eq_bool)
import Std.Time (date)
import Shoals.HolidayCal (Calendar, is_holiday, is_business_day, hc_nyc_calendar, hc_ldn_calendar, joint_calendar, weekend_only_calendar, empty_calendar, easter_sunday_gregorian, good_friday, easter_monday, hc_nyc_calendar_multi, hc_ldn_calendar_multi)
def test_nyc_new_year_is_holiday() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, int64), cast(1, int64), cast(1, int64))
  assert_true(is_holiday(cal, d), "NYC: 2025-01-01 New Year is a holiday")
}
def test_nyc_independence_day_is_holiday() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, int64), cast(7, int64), cast(4, int64))
  assert_true(is_holiday(cal, d), "NYC: 2025-07-04 is a holiday")
}
def test_nyc_random_wednesday_is_not_holiday() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, int64), cast(8, int64), cast(13, int64))
  assert_false(is_holiday(cal, d), "NYC: 2025-08-13 (a Wednesday) is not a holiday")
}
def test_ldn_christmas_is_holiday() -> unit ! { Test } = {
  cal = hc_ldn_calendar()
  d = date(cast(2025, int64), cast(12, int64), cast(25, int64))
  assert_true(is_holiday(cal, d), "LDN: 2025-12-25 is a holiday")
}
def test_ldn_boxing_day_is_holiday() -> unit ! { Test } = {
  cal = hc_ldn_calendar()
  d = date(cast(2025, int64), cast(12, int64), cast(26, int64))
  assert_true(is_holiday(cal, d), "LDN: 2025-12-26 is a holiday")
}
def test_ldn_does_not_observe_july_4() -> unit ! { Test } = {
  cal = hc_ldn_calendar()
  d = date(cast(2025, int64), cast(7, int64), cast(4, int64))
  assert_false(is_holiday(cal, d), "LDN: 2025-07-04 is not a holiday")
}
def test_business_day_wednesday() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, int64), cast(8, int64), cast(13, int64))
  assert_true(is_business_day(cal, d), "NYC: 2025-08-13 (Wed, non-holiday) is a business day")
}
def test_business_day_saturday() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, int64), cast(8, int64), cast(16, int64))
  assert_false(is_business_day(cal, d), "NYC: 2025-08-16 (Sat) is not a business day")
}
def test_business_day_new_year_2025() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, int64), cast(1, int64), cast(1, int64))
  assert_false(is_business_day(cal, d), "NYC: 2025-01-01 (holiday Wed) is not a business day")
}
def test_joint_calendar_us_july_4() -> unit ! { Test } = {
  cal = joint_calendar(hc_nyc_calendar(), hc_ldn_calendar())
  d_us = date(cast(2025, int64), cast(7, int64), cast(4, int64))
  assert_true(is_holiday(cal, d_us), "joint cal: US July 4 still a holiday")
}
def test_joint_calendar_uk_boxing_day() -> unit ! { Test } = {
  cal = joint_calendar(hc_nyc_calendar(), hc_ldn_calendar())
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
def test_easter_2024() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(2024, int64))
  assert_true(and(eq(e.year, cast(2024, int64)), and(eq(e.month, cast(3, int64)), eq(e.day, cast(31, int64)))), "Easter 2024 = 2024-03-31")
}
def test_easter_2025() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(2025, int64))
  assert_true(and(eq(e.year, cast(2025, int64)), and(eq(e.month, cast(4, int64)), eq(e.day, cast(20, int64)))), "Easter 2025 = 2025-04-20")
}
def test_easter_2026() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(2026, int64))
  assert_true(and(eq(e.year, cast(2026, int64)), and(eq(e.month, cast(4, int64)), eq(e.day, cast(5, int64)))), "Easter 2026 = 2026-04-05")
}
def test_easter_2030() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(2030, int64))
  assert_true(and(eq(e.year, cast(2030, int64)), and(eq(e.month, cast(4, int64)), eq(e.day, cast(21, int64)))), "Easter 2030 = 2030-04-21")
}
def test_easter_2050() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(2050, int64))
  assert_true(and(eq(e.year, cast(2050, int64)), and(eq(e.month, cast(4, int64)), eq(e.day, cast(10, int64)))), "Easter 2050 = 2050-04-10")
}
def test_easter_9999() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(9999, int64))
  assert_true(eq(e.year, cast(9999, int64)), "Easter 9999 returns a valid date in year 9999")
}
def test_good_friday_2025() -> unit ! { Test } = {
  gf = good_friday(cast(2025, int64))
  assert_true(and(eq(gf.year, cast(2025, int64)), and(eq(gf.month, cast(4, int64)), eq(gf.day, cast(18, int64)))), "Good Friday 2025 = 2025-04-18")
}
def test_easter_monday_2025() -> unit ! { Test } = {
  em = easter_monday(cast(2025, int64))
  assert_true(and(eq(em.year, cast(2025, int64)), and(eq(em.month, cast(4, int64)), eq(em.day, cast(21, int64)))), "Easter Monday 2025 = 2025-04-21")
}
def test_ldn_multi_2029_christmas() -> unit ! { Test } = {
  cal = hc_ldn_calendar_multi([cast(2025, int64), cast(2026, int64), cast(2027, int64), cast(2028, int64), cast(2029, int64), cast(2030, int64)])
  d = date(cast(2029, int64), cast(12, int64), cast(25, int64))
  assert_true(is_holiday(cal, d), "ldn multi-year contains 2029 Christmas")
}
def test_nyc_multi_2026_independence_day() -> unit ! { Test } = {
  cal = hc_nyc_calendar_multi([cast(2025, int64), cast(2026, int64), cast(2027, int64)])
  d = date(cast(2026, int64), cast(7, int64), cast(4, int64))
  assert_true(is_holiday(cal, d), "nyc multi-year contains 2026 July 4")
}
def test_ldn_multi_easter_2027() -> unit ! { Test } = {
  cal = hc_ldn_calendar_multi([cast(2027, int64)])
  assert_true(is_holiday(cal, easter_monday(cast(2027, int64))), "ldn 2027 contains Easter Monday")
}
