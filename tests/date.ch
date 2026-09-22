module Shoals.Tests.Date
import Std.Test (assert_close)
import Std.Time (Date, date, days_between, date_lte)
import Shoals.Date (DayCount, Act360, Act365, ThirtyThreeSixty, year_fraction, is_weekend, date_roll_following, schedule_from_tenor, add_months, days_in_month, schedule_from_tenor_calendar)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def test_act_360_one_year() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2026, i64), cast(1, i64), cast(1, i64))
  yf = year_fraction(start, end, Act360)
  expected = div(cast(365.0, f32), cast(360.0, f32))
  assert_close(yf, expected, cast(0.0001, f32), "Act/360 one year == 365/360")
}
def test_act_365_one_year() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2026, i64), cast(1, i64), cast(1, i64))
  yf = year_fraction(start, end, Act365)
  assert_close(yf, cast(1.0, f32), cast(1e-6, f32), "Act/365 one year == 1.0")
}
def test_thirty_360_half_year() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(15, i64))
  end = date(cast(2025, i64), cast(7, i64), cast(15, i64))
  yf = year_fraction(start, end, ThirtyThreeSixty)
  assert_close(yf, cast(0.5, f32), cast(1e-6, f32), "30/360 six months == 0.5")
}
def test_weekend_saturday() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(1, i64), cast(4, i64))
  assert_close(to01(is_weekend(d)), cast(1.0, f32), cast(0.001, f32), "2025-01-04 is Saturday")
}
def test_weekend_sunday() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(1, i64), cast(5, i64))
  assert_close(to01(is_weekend(d)), cast(1.0, f32), cast(0.001, f32), "2025-01-05 is Sunday")
}
def test_weekend_monday_is_not() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(1, i64), cast(6, i64))
  assert_close(to01(is_weekend(d)), cast(0.0, f32), cast(0.001, f32), "2025-01-06 is Monday, not weekend")
}
def test_date_roll_following_from_saturday() -> unit ! { Test } = {
  sat = date(cast(2025, i64), cast(1, i64), cast(4, i64))
  rolled = date_roll_following(sat, true)
  expected_mon = date(cast(2025, i64), cast(1, i64), cast(6, i64))
  gap = cast(days_between(rolled, expected_mon), f32)
  assert_close(gap, cast(0.0, f32), cast(0.001, f32), "Saturday rolls to following Monday")
}
def test_days_in_month_jan() -> unit ! { Test } = assert_close(cast(days_in_month(cast(2025, i64), cast(1, i64)), f32), cast(31.0, f32), cast(0.001, f32), "Jan = 31")
def test_days_in_month_feb_non_leap() -> unit ! { Test } = assert_close(cast(days_in_month(cast(2025, i64), cast(2, i64)), f32), cast(28.0, f32), cast(0.001, f32), "Feb 2025 = 28")
def test_days_in_month_feb_leap() -> unit ! { Test } = assert_close(cast(days_in_month(cast(2024, i64), cast(2, i64)), f32), cast(29.0, f32), cast(0.001, f32), "Feb 2024 = 29 (leap)")
def test_days_in_month_apr() -> unit ! { Test } = assert_close(cast(days_in_month(cast(2025, i64), cast(4, i64)), f32), cast(30.0, f32), cast(0.001, f32), "Apr = 30")
def test_add_months_within_year() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(3, i64), cast(15, i64))
  d2 = add_months(d, cast(3, i64))
  expected = date(cast(2025, i64), cast(6, i64), cast(15, i64))
  gap = cast(days_between(d2, expected), f32)
  assert_close(gap, cast(0.0, f32), cast(0.001, f32), "add_months 3 stays in 2025")
}
def test_add_months_year_wrap() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(10, i64), cast(15, i64))
  d2 = add_months(d, cast(5, i64))
  expected = date(cast(2026, i64), cast(3, i64), cast(15, i64))
  gap = cast(days_between(d2, expected), f32)
  assert_close(gap, cast(0.0, f32), cast(0.001, f32), "add_months 5 wraps to next year")
}
def test_add_months_day_cap_feb() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(1, i64), cast(31, i64))
  d2 = add_months(d, cast(1, i64))
  expected = date(cast(2025, i64), cast(2, i64), cast(28, i64))
  gap = cast(days_between(d2, expected), f32)
  assert_close(gap, cast(0.0, f32), cast(0.001, f32), "Jan-31 + 1mo caps to Feb-28")
}
def test_add_months_day_cap_feb_leap() -> unit ! { Test } = {
  d = date(cast(2024, i64), cast(1, i64), cast(31, i64))
  d2 = add_months(d, cast(1, i64))
  expected = date(cast(2024, i64), cast(2, i64), cast(29, i64))
  gap = cast(days_between(d2, expected), f32)
  assert_close(gap, cast(0.0, f32), cast(0.001, f32), "Jan-31 + 1mo in leap year caps to Feb-29")
}
def test_add_months_negative() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(2, i64), cast(15, i64))
  d2 = add_months(d, cast(-3, i64))
  expected = date(cast(2024, i64), cast(11, i64), cast(15, i64))
  gap = cast(days_between(d2, expected), f32)
  assert_close(gap, cast(0.0, f32), cast(0.001, f32), "add_months -3 wraps to prior year")
}
def test_schedule_calendar_quarterly() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(15, i64))
  end = date(cast(2025, i64), cast(12, i64), cast(31, i64))
  dates = schedule_from_tenor_calendar(start, end, cast(3, i64))
  n = len(dates)
  fourth = index(dates, cast(3, i64))
  expected = date(cast(2025, i64), cast(10, i64), cast(15, i64))
  gap = cast(days_between(fourth, expected), f32)
  _ = assert_close(cast(n, f32), cast(4.0, f32), cast(0.001, f32), "calendar quarterly schedule across 2025 (Jan-15 start) has 4 stops")
  assert_close(gap, cast(0.0, f32), cast(0.001, f32), "4th stop is Oct-15")
}
def test_schedule_step_quarterly() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2025, i64), cast(12, i64), cast(31, i64))
  dates = schedule_from_tenor(start, end, cast(3, i64))
  n = len(dates)
  first = index(dates, cast(0, i64))
  last = index(dates, sub(n, cast(1, i64)))
  first_gap = cast(days_between(start, first), f32)
  _ = assert_close(cast(n, f32), cast(5.0, f32), cast(0.001, f32), "quarterly schedule across 2025 has 5 stops")
  _ = assert_close(first_gap, cast(0.0, f32), cast(0.001, f32), "schedule starts at start date")
  assert_close(to01(date_lte(last, end)), cast(1.0, f32), cast(0.001, f32), "schedule end <= requested end")
}
