module Shoals.Tests.Date
import Std.Test (assert_close)
import Std.Time (Date, date, days_between, date_lte)
import Shoals.Date (DayCount, year_fraction, is_weekend, roll_following, schedule_from_tenor)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def test_act_360_one_year() -> unit ! { Test } = {
  start = date(cast(2025, int64), cast(1, int64), cast(1, int64))
  end = date(cast(2026, int64), cast(1, int64), cast(1, int64))
  yf = year_fraction(start, end, Act360)
  expected = div(cast(365.0, f32), cast(360.0, f32))
  assert_close(yf, expected, cast(0.0001, f32), "Act/360 one year == 365/360")
}
def test_act_365_one_year() -> unit ! { Test } = {
  start = date(cast(2025, int64), cast(1, int64), cast(1, int64))
  end = date(cast(2026, int64), cast(1, int64), cast(1, int64))
  yf = year_fraction(start, end, Act365)
  assert_close(yf, cast(1.0, f32), cast(0.000001, f32), "Act/365 one year == 1.0")
}
def test_thirty_360_half_year() -> unit ! { Test } = {
  start = date(cast(2025, int64), cast(1, int64), cast(15, int64))
  end = date(cast(2025, int64), cast(7, int64), cast(15, int64))
  yf = year_fraction(start, end, ThirtyThreeSixty)
  assert_close(yf, cast(0.5, f32), cast(0.000001, f32), "30/360 six months == 0.5")
}
def test_weekend_saturday() -> unit ! { Test } = {
  d = date(cast(2025, int64), cast(1, int64), cast(4, int64))
  assert_close(to01(is_weekend(d)), cast(1.0, f32), cast(0.001, f32), "2025-01-04 is Saturday")
}
def test_weekend_sunday() -> unit ! { Test } = {
  d = date(cast(2025, int64), cast(1, int64), cast(5, int64))
  assert_close(to01(is_weekend(d)), cast(1.0, f32), cast(0.001, f32), "2025-01-05 is Sunday")
}
def test_weekend_monday_is_not() -> unit ! { Test } = {
  d = date(cast(2025, int64), cast(1, int64), cast(6, int64))
  assert_close(to01(is_weekend(d)), cast(0.0, f32), cast(0.001, f32), "2025-01-06 is Monday, not weekend")
}
def test_roll_following_from_saturday() -> unit ! { Test } = {
  sat = date(cast(2025, int64), cast(1, int64), cast(4, int64))
  rolled = roll_following(sat, true)
  expected_mon = date(cast(2025, int64), cast(1, int64), cast(6, int64))
  gap = cast(days_between(rolled, expected_mon), f32)
  assert_close(gap, cast(0.0, f32), cast(0.001, f32), "Saturday rolls to following Monday")
}
def test_schedule_step_quarterly() -> unit ! { Test } = {
  start = date(cast(2025, int64), cast(1, int64), cast(1, int64))
  end = date(cast(2025, int64), cast(12, int64), cast(31, int64))
  dates = schedule_from_tenor(start, end, cast(3, int64))
  n = len(dates)
  first = index(dates, cast(0, int64))
  last = index(dates, sub(n, cast(1, int64)))
  first_gap = cast(days_between(start, first), f32)
  _ = assert_close(cast(n, f32), cast(5.0, f32), cast(0.001, f32), "quarterly schedule across 2025 has 5 stops")
  _ = assert_close(first_gap, cast(0.0, f32), cast(0.001, f32), "schedule starts at start date")
  assert_close(to01(date_lte(last, end)), cast(1.0, f32), cast(0.001, f32), "schedule end <= requested end")
}
