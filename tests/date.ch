module Shoals.Tests.Date
import Std.Test (assert_close)
import Std.Time (Date, date, days_between, date_lte)
import Shoals.Date (DayCount, Act360, Act365, ThirtyThreeSixty, ActActIsda, ActActIcma, year_fraction, is_weekend, date_roll_following, date_roll_preceding, date_roll_modified_following, add_business_days, schedule_from_tenor, add_months, days_in_month, schedule_from_tenor_calendar)
import Shoals.HolidayCal (Calendar, hc_nyc_calendar, weekend_only_calendar)
import Shoals.Properties.Date (year_fraction_matches_textbook, whole_isda_year_is_exactly_one, isda_reverses_under_swap, date_roll_following_idempotent_on_weekday)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def to01_f64(b: bool) -> f64 = if b then cast(1.0, f64) else cast(0.0, f64)
def tight64() -> f64 = cast(1e-12, f64)
-- Every roll test below comes in a pair: one against a calendar that contains
-- the date, and one against `weekend_only_calendar()` that does not. The pair is
-- the point. The defect this file now pins (shoals#87) was three roll functions
-- and `add_business_days` written as `if weekend_only then X else X`, so a test
-- that only asserted the calendar-aware direction would have passed against a
-- weekend-only implementation for every WEEKEND date. A weekday holiday is the
-- only input that separates them.
def nyc_cal() -> Calendar = hc_nyc_calendar()
def eom_holiday_cal() -> Calendar = Calendar { name: "eom-test", holidays: [date(cast(2025, i64), cast(7, i64), cast(31, i64))] }
def independence_day() -> Date = date(cast(2025, i64), cast(7, i64), cast(4, i64))
def same_date(actual: Date, expected: Date) -> f32 = cast(days_between(actual, expected), f32)
def test_act_360_one_year() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2026, i64), cast(1, i64), cast(1, i64))
  yf = year_fraction(start, end, Act360)
  expected = div(cast(365.0, f64), cast(360.0, f64))
  assert_close(yf, expected, cast(0.0001, f64), "Act/360 one year == 365/360")
}
def test_act_365_one_year() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2026, i64), cast(1, i64), cast(1, i64))
  yf = year_fraction(start, end, Act365)
  assert_close(yf, cast(1.0, f64), cast(1e-9, f64), "Act/365 one year == 1.0")
}
def test_thirty_360_half_year() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(15, i64))
  end = date(cast(2025, i64), cast(7, i64), cast(15, i64))
  yf = year_fraction(start, end, ThirtyThreeSixty)
  assert_close(yf, cast(0.5, f64), cast(1e-9, f64), "30/360 six months == 0.5")
}
-- The ISDA 2006 worked example: 2003-11-01 to 2004-05-01 is 61 days of a
-- 365-day year plus 121 days of a 366-day year, so 61/365 + 121/366.
def test_act_act_isda_worked_example() -> unit ! { Test } = {
  start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  yf = year_fraction(start, end, ActActIsda)
  expected = add(div(cast(61.0, f64), cast(365.0, f64)), div(cast(121.0, f64), cast(366.0, f64)))
  assert_close(yf, expected, tight64(), "ACT/ACT ISDA 2003-11-01..2004-05-01 == 61/365 + 121/366")
}
-- The regression test for the defect itself: the replaced implementation was
-- days/365.25, which on this interval gives 182/365.25 = 0.49829. ISDA gives
-- 0.49772. Asserting only the ISDA value would also pass if someone reinstated
-- a slightly different approximation, so assert the distance from the old one.
def test_act_act_isda_is_not_the_365_25_approximation() -> unit ! { Test } = {
  start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  yf = year_fraction(start, end, ActActIsda)
  approximation = div(cast(182.0, f64), cast(365.25, f64))
  gap = if lt(yf, approximation) then sub(approximation, yf) else sub(yf, approximation)
  assert_close(to01_f64(gt(gap, cast(0.0001, f64))), cast(1.0, f64), tight64(), "ACT/ACT ISDA differs measurably from the days/365.25 approximation it replaced")
}
-- Red-team F2/X4. A calendar-year segment of exactly ONE day is the boundary of
-- the per-year split, and the suite's shortest interval was two days inside a
-- single year, so a mutation widening the "skip empty segment" guard from
-- `span < 1` to `span < 2` silently returned 0.0 here and nothing caught it.
def test_act_act_isda_one_day_segment_at_a_year_boundary() -> unit ! { Test } = {
  start = date(cast(2024, i64), cast(12, i64), cast(31, i64))
  end = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  expected = div(cast(1.0, f64), cast(366.0, f64))
  assert_close(year_fraction(start, end, ActActIsda), expected, tight64(), "2024-12-31..2025-01-01 is one leap-year day == 1/366")
}
def test_act_act_isda_one_day_segment_each_side_of_a_boundary() -> unit ! { Test } = {
  start = date(cast(2023, i64), cast(12, i64), cast(31, i64))
  end = date(cast(2024, i64), cast(1, i64), cast(2, i64))
  expected = add(div(cast(1.0, f64), cast(365.0, f64)), div(cast(1.0, f64), cast(366.0, f64)))
  assert_close(year_fraction(start, end, ActActIsda), expected, tight64(), "2023-12-31..2024-01-02 is 1/365 + 1/366, one day in each year")
}
def test_act_act_isda_whole_non_leap_year_is_one() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2026, i64), cast(1, i64), cast(1, i64))
  assert_close(year_fraction(start, end, ActActIsda), cast(1.0, f64), tight64(), "ACT/ACT ISDA over 2025 == exactly 1.0")
}
-- The leap year is where days/365.25 was visibly wrong: 366/365.25 = 1.00205.
def test_act_act_isda_whole_leap_year_is_one() -> unit ! { Test } = {
  start = date(cast(2024, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  assert_close(year_fraction(start, end, ActActIsda), cast(1.0, f64), tight64(), "ACT/ACT ISDA over leap year 2024 == exactly 1.0, not 366/365.25")
}
def test_act_act_isda_five_years_spanning_a_leap() -> unit ! { Test } = {
  start = date(cast(2020, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  assert_close(year_fraction(start, end, ActActIsda), cast(5.0, f64), tight64(), "ACT/ACT ISDA over 2020..2025 == exactly 5.0")
}
def test_act_act_isda_weights_the_leap_day_by_366() -> unit ! { Test } = {
  start = date(cast(2024, i64), cast(2, i64), cast(28, i64))
  end = date(cast(2024, i64), cast(3, i64), cast(1, i64))
  expected = div(cast(2.0, f64), cast(366.0, f64))
  assert_close(year_fraction(start, end, ActActIsda), expected, tight64(), "Feb-28..Mar-01 in 2024 is 2 days weighted 1/366")
}
def test_act_act_isda_reversed_interval_negates() -> unit ! { Test } = {
  start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  forward = year_fraction(start, end, ActActIsda)
  backward = year_fraction(end, start, ActActIsda)
  assert_close(add(forward, backward), cast(0.0, f64), tight64(), "ACT/ACT ISDA reversed interval is the negation")
}
def test_act_act_isda_zero_interval_is_zero() -> unit ! { Test } = {
  d = date(cast(2024, i64), cast(2, i64), cast(29, i64))
  assert_close(year_fraction(d, d, ActActIsda), cast(0.0, f64), tight64(), "ACT/ACT ISDA of an empty interval is 0")
}
-- ACT/ACT ICMA: a regular full coupon period is exactly 1/frequency whatever its
-- actual day count, which is the property that distinguishes it from ISDA.
def test_act_act_icma_full_semi_annual_period_is_half() -> unit ! { Test } = {
  period_start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  period_end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(2, i64) }
  assert_close(year_fraction(period_start, period_end, convention), cast(0.5, f64), tight64(), "a full semi-annual ICMA period is exactly 0.5")
}
def test_act_act_icma_full_annual_period_is_one() -> unit ! { Test } = {
  period_start = date(cast(2024, i64), cast(3, i64), cast(15, i64))
  period_end = date(cast(2025, i64), cast(3, i64), cast(15, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(1, i64) }
  assert_close(year_fraction(period_start, period_end, convention), cast(1.0, f64), tight64(), "a full annual ICMA period is exactly 1.0")
}
def test_act_act_icma_short_first_period() -> unit ! { Test } = {
  period_start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  period_end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(2, i64) }
  settle = date(cast(2004, i64), cast(2, i64), cast(1, i64))
  expected = div(cast(92.0, f64), mul(cast(2.0, f64), cast(182.0, f64)))
  assert_close(year_fraction(period_start, settle, convention), expected, tight64(), "92 of 182 days at semi-annual frequency == 92/364")
}
-- ISDA and ICMA must not agree on this interval, or the ICMA leg could be
-- satisfied by an implementation that silently routed to ISDA.
def test_act_act_icma_differs_from_isda_on_the_same_interval() -> unit ! { Test } = {
  period_start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  period_end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(2, i64) }
  icma = year_fraction(period_start, period_end, convention)
  isda = year_fraction(period_start, period_end, ActActIsda)
  gap = if lt(icma, isda) then sub(isda, icma) else sub(icma, isda)
  assert_close(to01_f64(gt(gap, cast(0.0001, f64))), cast(1.0, f64), tight64(), "ICMA and ISDA disagree on 2003-11-01..2004-05-01")
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
  rolled = date_roll_following(sat, weekend_only_calendar())
  expected_mon = date(cast(2025, i64), cast(1, i64), cast(6, i64))
  assert_close(same_date(rolled, expected_mon), cast(0.0, f32), cast(0.001, f32), "Saturday rolls to following Monday")
}
-- shoals#87 UB-8. 2025-07-04 is a FRIDAY and a NYC holiday, so it is a business
-- day to a weekend-only roll and a non-business day to a calendar-aware one.
def test_roll_following_consults_the_holiday_calendar() -> unit ! { Test } = {
  rolled = date_roll_following(independence_day(), nyc_cal())
  expected_mon = date(cast(2025, i64), cast(7, i64), cast(7, i64))
  assert_close(same_date(rolled, expected_mon), cast(0.0, f32), cast(0.001, f32), "July 4 2025 (Friday, NYC holiday) rolls forward to Monday July 7")
}
def test_roll_following_weekend_only_leaves_a_weekday_holiday() -> unit ! { Test } = {
  rolled = date_roll_following(independence_day(), weekend_only_calendar())
  assert_close(same_date(rolled, independence_day()), cast(0.0, f32), cast(0.001, f32), "a weekend-only calendar does not roll July 4 2025")
}
def test_roll_preceding_consults_the_holiday_calendar() -> unit ! { Test } = {
  rolled = date_roll_preceding(independence_day(), nyc_cal())
  expected_thu = date(cast(2025, i64), cast(7, i64), cast(3, i64))
  assert_close(same_date(rolled, expected_thu), cast(0.0, f32), cast(0.001, f32), "July 4 2025 rolls back to Thursday July 3")
}
def test_roll_preceding_weekend_only_leaves_a_weekday_holiday() -> unit ! { Test } = {
  rolled = date_roll_preceding(independence_day(), weekend_only_calendar())
  assert_close(same_date(rolled, independence_day()), cast(0.0, f32), cast(0.001, f32), "a weekend-only calendar does not roll July 4 2025 backwards")
}
-- 2025-07-31 is a Thursday. Held as a holiday, the following roll leaves July,
-- so modified-following must retreat instead, and the retreat must itself skip
-- the holiday.
def test_roll_modified_following_retreats_across_a_month_end_holiday() -> unit ! { Test } = {
  eom = date(cast(2025, i64), cast(7, i64), cast(31, i64))
  rolled = date_roll_modified_following(eom, eom_holiday_cal())
  expected_wed = date(cast(2025, i64), cast(7, i64), cast(30, i64))
  assert_close(same_date(rolled, expected_wed), cast(0.0, f32), cast(0.001, f32), "a month-end holiday rolls back to July 30 rather than forward into August")
}
def test_roll_modified_following_weekend_only_leaves_the_month_end() -> unit ! { Test } = {
  eom = date(cast(2025, i64), cast(7, i64), cast(31, i64))
  rolled = date_roll_modified_following(eom, weekend_only_calendar())
  assert_close(same_date(rolled, eom), cast(0.0, f32), cast(0.001, f32), "a weekend-only calendar leaves Thursday July 31 alone")
}
-- shoals#87 UB-8, fourth site. `add_business_days` carried the same dead flag
-- and the issue does not name it.
def test_add_business_days_skips_a_weekday_holiday() -> unit ! { Test } = {
  thu = date(cast(2025, i64), cast(7, i64), cast(3, i64))
  landed = add_business_days(thu, cast(1, i64), nyc_cal())
  expected_mon = date(cast(2025, i64), cast(7, i64), cast(7, i64))
  assert_close(same_date(landed, expected_mon), cast(0.0, f32), cast(0.001, f32), "one business day after Thursday July 3 2025 is Monday July 7 on a NYC calendar")
}
-- Red-team F2/X2. `add_business_days` was only ever started from a business day,
-- so a mutation rolling its STARTING date to a business day before stepping
-- survived. Starting on a holiday must not consume a step: one business day after
-- July 4 is July 7, the same answer as from July 3, and the two must agree.
def test_add_business_days_from_a_non_business_start() -> unit ! { Test } = {
  landed = add_business_days(independence_day(), cast(1, i64), nyc_cal())
  expected_mon = date(cast(2025, i64), cast(7, i64), cast(7, i64))
  assert_close(same_date(landed, expected_mon), cast(0.0, f32), cast(0.001, f32), "one business day from Friday July 4 2025 (a NYC holiday) is Monday July 7")
}
def test_add_business_days_zero_is_the_identity_even_on_a_holiday() -> unit ! { Test } = {
  landed = add_business_days(independence_day(), cast(0, i64), nyc_cal())
  assert_close(same_date(landed, independence_day()), cast(0.0, f32), cast(0.001, f32), "zero business days does not roll, even from a holiday")
}
def test_add_business_days_negative_does_not_step_backward() -> unit ! { Test } = {
  landed = add_business_days(independence_day(), cast(-5, i64), nyc_cal())
  assert_close(same_date(landed, independence_day()), cast(0.0, f32), cast(0.001, f32), "a negative count does not step backward, as docs/src/scope.md states")
}
def test_add_business_days_weekend_only_lands_on_the_holiday() -> unit ! { Test } = {
  thu = date(cast(2025, i64), cast(7, i64), cast(3, i64))
  landed = add_business_days(thu, cast(1, i64), weekend_only_calendar())
  expected_fri = date(cast(2025, i64), cast(7, i64), cast(4, i64))
  assert_close(same_date(landed, expected_fri), cast(0.0, f32), cast(0.001, f32), "a weekend-only calendar lands on Friday July 4")
}
def test_days_in_month_jan() -> unit ! { Test } = assert_close(cast(days_in_month(cast(2025, i64), cast(1, i64)), f32), cast(31.0, f32), cast(0.001, f32), "Jan = 31")
def test_days_in_month_feb_non_leap() -> unit ! { Test } = assert_close(cast(days_in_month(cast(2025, i64), cast(2, i64)), f32), cast(28.0, f32), cast(0.001, f32), "Feb 2025 = 28")
def test_days_in_month_feb_leap() -> unit ! { Test } = assert_close(cast(days_in_month(cast(2024, i64), cast(2, i64)), f32), cast(29.0, f32), cast(0.001, f32), "Feb 2024 = 29 (leap)")
def test_days_in_month_apr() -> unit ! { Test } = assert_close(cast(days_in_month(cast(2025, i64), cast(4, i64)), f32), cast(30.0, f32), cast(0.001, f32), "Apr = 30")
def test_add_months_within_year() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(3, i64), cast(15, i64))
  d2 = add_months(d, cast(3, i64))
  expected = date(cast(2025, i64), cast(6, i64), cast(15, i64))
  assert_close(same_date(d2, expected), cast(0.0, f32), cast(0.001, f32), "add_months 3 stays in 2025")
}
def test_add_months_year_wrap() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(10, i64), cast(15, i64))
  d2 = add_months(d, cast(5, i64))
  expected = date(cast(2026, i64), cast(3, i64), cast(15, i64))
  assert_close(same_date(d2, expected), cast(0.0, f32), cast(0.001, f32), "add_months 5 wraps to next year")
}
def test_add_months_day_cap_feb() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(1, i64), cast(31, i64))
  d2 = add_months(d, cast(1, i64))
  expected = date(cast(2025, i64), cast(2, i64), cast(28, i64))
  assert_close(same_date(d2, expected), cast(0.0, f32), cast(0.001, f32), "Jan-31 + 1mo caps to Feb-28")
}
def test_add_months_day_cap_feb_leap() -> unit ! { Test } = {
  d = date(cast(2024, i64), cast(1, i64), cast(31, i64))
  d2 = add_months(d, cast(1, i64))
  expected = date(cast(2024, i64), cast(2, i64), cast(29, i64))
  assert_close(same_date(d2, expected), cast(0.0, f32), cast(0.001, f32), "Jan-31 + 1mo in leap year caps to Feb-29")
}
def test_add_months_negative() -> unit ! { Test } = {
  d = date(cast(2025, i64), cast(2, i64), cast(15, i64))
  d2 = add_months(d, cast(-3, i64))
  expected = date(cast(2024, i64), cast(11, i64), cast(15, i64))
  assert_close(same_date(d2, expected), cast(0.0, f32), cast(0.001, f32), "add_months -3 wraps to prior year")
}
def test_schedule_calendar_quarterly() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(15, i64))
  end = date(cast(2025, i64), cast(12, i64), cast(31, i64))
  dates = schedule_from_tenor_calendar(start, end, cast(3, i64))
  n = len(dates)
  fourth = index(dates, cast(3, i64))
  expected = date(cast(2025, i64), cast(10, i64), cast(15, i64))
  _ = assert_close(cast(n, f32), cast(4.0, f32), cast(0.001, f32), "calendar quarterly schedule across 2025 (Jan-15 start) has 4 stops")
  assert_close(same_date(fourth, expected), cast(0.0, f32), cast(0.001, f32), "4th stop is Oct-15")
}
def test_schedule_step_quarterly() -> unit ! { Test } = {
  start = date(cast(2025, i64), cast(1, i64), cast(1, i64))
  end = date(cast(2025, i64), cast(12, i64), cast(31, i64))
  dates = schedule_from_tenor(start, end, cast(3, i64))
  n = len(dates)
  first = index(dates, cast(0, i64))
  last = index(dates, sub(n, cast(1, i64)))
  _ = assert_close(cast(n, f32), cast(5.0, f32), cast(0.001, f32), "quarterly schedule across 2025 has 5 stops")
  _ = assert_close(same_date(start, first), cast(0.0, f32), cast(0.001, f32), "schedule starts at start date")
  assert_close(to01(date_lte(last, end)), cast(1.0, f32), cast(0.001, f32), "schedule end <= requested end")
}
-- The property surface in `properties/` is compiled but called by nothing, so
-- these drive it at concrete inputs. An uncalled property is not coverage.
def test_property_isda_matches_independent_calendar() -> unit ! { Test } = {
  start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  assert_close(to01_f64(year_fraction_matches_textbook(start, end, ActActIsda)), cast(1.0, f64), tight64(), "ACT/ACT ISDA agrees with the independent ordinal reference")
}
def test_property_icma_matches_independent_calendar() -> unit ! { Test } = {
  period_start = date(cast(2003, i64), cast(11, i64), cast(1, i64))
  period_end = date(cast(2004, i64), cast(5, i64), cast(1, i64))
  convention = ActActIcma { period_start, period_end, frequency: cast(2, i64) }
  settle = date(cast(2004, i64), cast(2, i64), cast(1, i64))
  assert_close(to01_f64(year_fraction_matches_textbook(period_start, settle, convention)), cast(1.0, f64), tight64(), "ACT/ACT ICMA agrees with the independent ordinal reference")
}
-- 1899-11-01 to 1900-05-01 is 61 days of 1899 plus 120 days of 1900, both
-- ordinary years, so 181/365. Two things make this case load-bearing rather
-- than decorative. It is the only subject-vs-reference comparison here that
-- reaches a nonzero century term in the reference's ordinal: for every year in
-- 2000..2099 that term is identically zero, so a reference with the Gregorian
-- century rule deleted agrees with a correct one everywhere else in this file.
-- And 1900 is the century non-leap, so a denominator of 366 would also show up.
def test_act_act_isda_across_a_century_non_leap() -> unit ! { Test } = {
  start = date(cast(1899, i64), cast(11, i64), cast(1, i64))
  end = date(cast(1900, i64), cast(5, i64), cast(1, i64))
  expected = div(cast(181.0, f64), cast(365.0, f64))
  assert_close(year_fraction(start, end, ActActIsda), expected, tight64(), "1899-11-01..1900-05-01 == 181/365 (1900 is not a leap year)")
}
def test_property_isda_matches_independent_calendar_across_a_century() -> unit ! { Test } = {
  start = date(cast(1899, i64), cast(11, i64), cast(1, i64))
  end = date(cast(1900, i64), cast(5, i64), cast(1, i64))
  assert_close(to01_f64(year_fraction_matches_textbook(start, end, ActActIsda)), cast(1.0, f64), tight64(), "subject and independent reference agree where the ordinal's century term is live")
}
def test_property_whole_isda_year_non_leap() -> unit ! { Test } = assert_close(to01_f64(whole_isda_year_is_exactly_one(cast(2025, i64))), cast(1.0, f64), tight64(), "2025 is exactly one ISDA year")
def test_property_whole_isda_year_leap() -> unit ! { Test } = assert_close(to01_f64(whole_isda_year_is_exactly_one(cast(2024, i64))), cast(1.0, f64), tight64(), "2024 is exactly one ISDA year")
def test_property_whole_isda_year_century_non_leap() -> unit ! { Test } = assert_close(to01_f64(whole_isda_year_is_exactly_one(cast(1900, i64))), cast(1.0, f64), tight64(), "1900 is exactly one ISDA year (century non-leap)")
def test_property_whole_isda_year_quadricentennial() -> unit ! { Test } = assert_close(to01_f64(whole_isda_year_is_exactly_one(cast(2000, i64))), cast(1.0, f64), tight64(), "2000 is exactly one ISDA year (quadricentennial leap)")
def test_property_isda_reverses_under_swap() -> unit ! { Test } = {
  start = date(cast(2019, i64), cast(6, i64), cast(10, i64))
  end = date(cast(2024, i64), cast(3, i64), cast(2, i64))
  assert_close(to01_f64(isda_reverses_under_swap(start, end)), cast(1.0, f64), tight64(), "ISDA negates under argument swap across a leap year")
}
def test_property_roll_idempotent_on_weekday() -> unit ! { Test } = assert_close(to01_f64(date_roll_following_idempotent_on_weekday(date(cast(2025, i64), cast(7, i64), cast(8, i64)))), cast(1.0, f64), tight64(), "a weekend-only following roll fixes an ordinary Tuesday")
