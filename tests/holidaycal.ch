module Shoals.Tests.HolidayCal
import Std.Test (assert_true, assert_false, assert_eq)
import Std.Datetime (date, date_year, date_month, date_day)
import Std.Datetime.Business (try_is_business_day, business_calendar_holidays, business_calendar_valid_from, business_calendar_valid_until)
import Shoals.HolidayCal (Calendar, is_holiday, is_business_day, as_business_calendar, hc_nyc_calendar, hc_ldn_calendar, joint_calendar, weekend_only_calendar, empty_calendar, easter_sunday_gregorian, good_friday, easter_monday, hc_nyc_calendar_multi, hc_ldn_calendar_multi, hc_ldn_calendar_year, hc_us_federal_published, hc_england_wales_published)
import Shoals.Date (date_roll_following_published, date_roll_preceding_published, date_roll_modified_following_published)
def test_published_us_federal_closure_roll() -> unit ! { Test } = {
  day = date(2025i64, 12i64, 24i64)
  landed = date_roll_following_published(day, hc_us_federal_published())
  assert_true(and(eq(date_year(landed), 2025i64), and(eq(date_month(landed), 12i64), eq(date_day(landed), 29i64))), "US federal closure through December 26 rolls to December 29")
}
def test_published_england_wales_bank_holiday_roll() -> unit ! { Test } = {
  day = date(2025i64, 5i64, 5i64)
  landed = date_roll_following_published(day, hc_england_wales_published())
  assert_true(and(eq(date_year(landed), 2025i64), and(eq(date_month(landed), 5i64), eq(date_day(landed), 6i64))), "England and Wales bank holiday rolls to May 6")
}
def test_published_calendar_preceding_and_modified_following() -> unit ! { Test } = {
  cal = hc_england_wales_published()
  may = date(2025i64, 5i64, 5i64)
  preceding = date_roll_preceding_published(may, cal)
  august = date(2025i64, 8i64, 31i64)
  modified = date_roll_modified_following_published(august, cal)
  _ = assert_true(and(eq(date_month(preceding), 5i64), eq(date_day(preceding), 2i64)), "preceding roll reaches May 2")
  assert_true(and(eq(date_month(modified), 8i64), eq(date_day(modified), 29i64)), "modified following stays in August")
}
def test_published_calendar_rejects_outside_horizon() -> unit ! { Test } = {
  result = try_is_business_day(hc_us_federal_published(), date(2031i64, 1i64, 2i64))
  match result with {
    | None => assert_true(true, "published calendar has a finite horizon")
    | Some(_) => assert_true(false, "published calendar must reject a date outside its horizon")
  }
}
def test_local_calendar_business_adapter_preserves_weekday_holidays() -> unit ! { Test } = {
  d = date(2025i64, 7i64, 4i64)
  _ = assert_eq(try_is_business_day(as_business_calendar(hc_nyc_calendar()), d), Some(false), "the local July 4 closure remains non-business")
  assert_eq(try_is_business_day(as_business_calendar(weekend_only_calendar()), d), Some(true), "a weekend-only calendar leaves July 4 open")
}
-- A local list answers business-day queries only for the years it was built
-- for. Outside them the adapted calendar has no data, so the core `try_` form
-- returns None rather than a weekday guess.
def test_adapted_2025_calendar_answers_none_outside_its_year() -> unit ! { Test } = {
  cal = as_business_calendar(hc_nyc_calendar())
  _ = assert_eq(try_is_business_day(cal, date(2030i64, 12i64, 25i64)), None, "a 2025 list does not know 2030-12-25")
  assert_eq(try_is_business_day(cal, date(1900i64, 12i64, 25i64)), None, "a 2025 list does not know 1900-12-25")
}
def test_adapted_2025_calendar_keeps_its_in_horizon_answers() -> unit ! { Test } = {
  cal = as_business_calendar(hc_nyc_calendar())
  _ = assert_eq(try_is_business_day(cal, date(2025i64, 1i64, 1i64)), Some(false), "New Year's Day 2025 is a holiday")
  _ = assert_eq(try_is_business_day(cal, date(2025i64, 12i64, 24i64)), Some(true), "Wednesday 2025-12-24 is open")
  _ = assert_eq(try_is_business_day(cal, date(2025i64, 12i64, 25i64)), Some(false), "Christmas 2025 is a holiday")
  _ = assert_eq(try_is_business_day(cal, date(2025i64, 12i64, 27i64)), Some(false), "Saturday 2025-12-27 is a weekend day")
  assert_eq(try_is_business_day(cal, date(2025i64, 12i64, 31i64)), Some(true), "Wednesday 2025-12-31 is open")
}
def test_year_constructor_covers_its_year() -> unit ! { Test } = {
  cal = as_business_calendar(hc_ldn_calendar_year(2027i64))
  _ = assert_eq(business_calendar_valid_from(cal), date(2027i64, 1i64, 1i64), "a one-year list starts on 1 January")
  _ = assert_eq(business_calendar_valid_until(cal), date(2027i64, 12i64, 31i64), "a one-year list ends on 31 December")
  assert_eq(try_is_business_day(cal, date(2028i64, 1i64, 3i64)), None, "the 2027 list does not know 2028")
}
def test_multi_year_constructor_covers_its_years_in_any_order() -> unit ! { Test } = {
  cal = as_business_calendar(hc_nyc_calendar_multi([2026i64, 2025i64, 2027i64]))
  _ = assert_eq(business_calendar_valid_from(cal), date(2025i64, 1i64, 1i64), "the multi-year list starts with its first year")
  assert_eq(business_calendar_valid_until(cal), date(2027i64, 12i64, 31i64), "the multi-year list ends with its last year")
}
-- A joint calendar knows a day only when both inputs do, so its business-day
-- horizon is the intersection; its holiday membership stays the union.
def test_joint_calendar_covers_the_intersection() -> unit ! { Test } = {
  joint = joint_calendar(hc_nyc_calendar_multi([2025i64, 2026i64]), hc_ldn_calendar_year(2026i64))
  cal = as_business_calendar(joint)
  _ = assert_eq(business_calendar_valid_from(cal), date(2026i64, 1i64, 1i64), "the joint horizon starts where both lists start")
  _ = assert_eq(business_calendar_valid_until(cal), date(2026i64, 12i64, 31i64), "the joint horizon ends where both lists end")
  _ = assert_true(is_holiday(joint, date(2025i64, 7i64, 4i64)), "holiday membership keeps the New York 2025 date")
  assert_eq(try_is_business_day(cal, date(2025i64, 7i64, 7i64)), None, "London 2026 data cannot answer for 2025")
}
-- `weekend_only_calendar()` and `empty_calendar` state that no date is a
-- holiday, so their claim holds over the whole `Std.Datetime.Date` range.
def test_holiday_free_calendars_cover_the_full_date_range() -> unit ! { Test } = {
  cal = as_business_calendar(weekend_only_calendar())
  _ = assert_eq(business_calendar_valid_from(cal), date(-9999i64, 1i64, 1i64), "a holiday-free calendar starts at the first date")
  _ = assert_eq(business_calendar_valid_until(cal), date(9999i64, 12i64, 31i64), "a holiday-free calendar ends at the last date")
  assert_eq(try_is_business_day(as_business_calendar(empty_calendar("none")), date(1900i64, 12i64, 25i64)), Some(true), "an empty calendar answers for 1900")
}
def test_local_calendar_keeps_explicit_weekend_holiday_membership() -> unit ! { Test } = {
  saturday = date(2025i64, 7i64, 5i64)
  cal = Calendar { name: "weekend-listed", holidays: [saturday], valid_from: date(2025i64, 1i64, 1i64), valid_until: date(2025i64, 12i64, 31i64) }
  _ = assert_true(is_holiday(cal, saturday), "the local holiday query retains a listed Saturday")
  _ = assert_eq(business_calendar_holidays(as_business_calendar(cal)), [], "the business calendar normalizes Saturday out of its holiday list")
  assert_false(is_business_day(cal, saturday), "Saturday stays non-business through the weekmask")
}
def test_nyc_new_year_is_holiday() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  assert_true(is_holiday(cal, d), "NYC: 2025-01-01 New Year is a holiday")
}
def test_nyc_independence_day_is_holiday() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, i64), cast(7, i64), cast(4, i64))
  assert_true(is_holiday(cal, d), "NYC: 2025-07-04 is a holiday")
}
def test_nyc_random_wednesday_is_not_holiday() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, i64), cast(8, i64), cast(13, i64))
  assert_false(is_holiday(cal, d), "NYC: 2025-08-13 (a Wednesday) is not a holiday")
}
def test_ldn_christmas_is_holiday() -> unit ! { Test } = {
  cal = hc_ldn_calendar()
  d = date(cast(2025, i64), cast(12, i64), cast(25, i64))
  assert_true(is_holiday(cal, d), "LDN: 2025-12-25 is a holiday")
}
def test_ldn_boxing_day_is_holiday() -> unit ! { Test } = {
  cal = hc_ldn_calendar()
  d = date(cast(2025, i64), cast(12, i64), cast(26, i64))
  assert_true(is_holiday(cal, d), "LDN: 2025-12-26 is a holiday")
}
def test_ldn_does_not_observe_july_4() -> unit ! { Test } = {
  cal = hc_ldn_calendar()
  d = date(cast(2025, i64), cast(7, i64), cast(4, i64))
  assert_false(is_holiday(cal, d), "LDN: 2025-07-04 is not a holiday")
}
def test_business_day_wednesday() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, i64), cast(8, i64), cast(13, i64))
  assert_true(is_business_day(cal, d), "NYC: 2025-08-13 (Wed, non-holiday) is a business day")
}
def test_business_day_saturday() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, i64), cast(8, i64), cast(16, i64))
  assert_false(is_business_day(cal, d), "NYC: 2025-08-16 (Sat) is not a business day")
}
def test_business_day_new_year_2025() -> unit ! { Test } = {
  cal = hc_nyc_calendar()
  d = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  assert_false(is_business_day(cal, d), "NYC: 2025-01-01 (holiday Wed) is not a business day")
}
def test_joint_calendar_us_july_4() -> unit ! { Test } = {
  cal = joint_calendar(hc_nyc_calendar(), hc_ldn_calendar())
  d_us = date(cast(2025, i64), cast(7, i64), cast(4, i64))
  assert_true(is_holiday(cal, d_us), "joint cal: US July 4 still a holiday")
}
def test_joint_calendar_uk_boxing_day() -> unit ! { Test } = {
  cal = joint_calendar(hc_nyc_calendar(), hc_ldn_calendar())
  d_uk = date(cast(2025, i64), cast(12, i64), cast(26, i64))
  assert_true(is_holiday(cal, d_uk), "joint cal: UK Boxing Day a holiday")
}
def test_empty_calendar_has_no_holidays() -> unit ! { Test } = {
  cal = empty_calendar("test")
  d = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  assert_false(is_holiday(cal, d), "empty calendar has no holidays")
}
def test_weekend_only_calendar_treats_weekday_as_business() -> unit ! { Test } = {
  cal = weekend_only_calendar()
  d = date(cast(2025, i64), cast(8, i64), cast(13, i64))
  assert_true(is_business_day(cal, d), "weekend-only: Wed is a business day")
}
def test_easter_2024() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(2024, i64))
  assert_true(and(eq(date_year(e), cast(2024, i64)), and(eq(date_month(e), cast(3, i64)), eq(date_day(e), cast(31, i64)))), "Easter 2024 = 2024-03-31")
}
def test_easter_2025() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(2025, i64))
  assert_true(and(eq(date_year(e), cast(2025, i64)), and(eq(date_month(e), cast(4, i64)), eq(date_day(e), cast(20, i64)))), "Easter 2025 = 2025-04-20")
}
def test_easter_2026() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(2026, i64))
  assert_true(and(eq(date_year(e), cast(2026, i64)), and(eq(date_month(e), cast(4, i64)), eq(date_day(e), cast(5, i64)))), "Easter 2026 = 2026-04-05")
}
def test_easter_2030() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(2030, i64))
  assert_true(and(eq(date_year(e), cast(2030, i64)), and(eq(date_month(e), cast(4, i64)), eq(date_day(e), cast(21, i64)))), "Easter 2030 = 2030-04-21")
}
def test_easter_2050() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(2050, i64))
  assert_true(and(eq(date_year(e), cast(2050, i64)), and(eq(date_month(e), cast(4, i64)), eq(date_day(e), cast(10, i64)))), "Easter 2050 = 2050-04-10")
}
def test_easter_9999() -> unit ! { Test } = {
  e = easter_sunday_gregorian(cast(9999, i64))
  assert_true(eq(date_year(e), cast(9999, i64)), "Easter 9999 returns a valid date in year 9999")
}
def test_good_friday_2025() -> unit ! { Test } = {
  gf = good_friday(cast(2025, i64))
  assert_true(and(eq(date_year(gf), cast(2025, i64)), and(eq(date_month(gf), cast(4, i64)), eq(date_day(gf), cast(18, i64)))), "Good Friday 2025 = 2025-04-18")
}
def test_easter_monday_2025() -> unit ! { Test } = {
  em = easter_monday(cast(2025, i64))
  assert_true(and(eq(date_year(em), cast(2025, i64)), and(eq(date_month(em), cast(4, i64)), eq(date_day(em), cast(21, i64)))), "Easter Monday 2025 = 2025-04-21")
}
def test_ldn_multi_2029_christmas() -> unit ! { Test } = {
  cal = hc_ldn_calendar_multi([cast(2025, i64), cast(2026, i64), cast(2027, i64), cast(2028, i64), cast(2029, i64), cast(2030, i64)])
  d = date(cast(2029, i64), cast(12, i64), cast(25, i64))
  assert_true(is_holiday(cal, d), "ldn multi-year contains 2029 Christmas")
}
def test_nyc_multi_2026_independence_day() -> unit ! { Test } = {
  cal = hc_nyc_calendar_multi([cast(2025, i64), cast(2026, i64), cast(2027, i64)])
  d = date(cast(2026, i64), cast(7, i64), cast(4, i64))
  assert_true(is_holiday(cal, d), "nyc multi-year contains 2026 July 4")
}
def test_ldn_multi_easter_2027() -> unit ! { Test } = {
  cal = hc_ldn_calendar_multi([cast(2027, i64)])
  assert_true(is_holiday(cal, easter_monday(cast(2027, i64))), "ldn 2027 contains Easter Monday")
}
