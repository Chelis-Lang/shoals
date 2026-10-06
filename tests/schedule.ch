module Shoals.Tests.Schedule
import Std.Test (assert_eq)
import Std.Datetime (Date, date, ClampToMonthEnd, RejectInvalidDay)
import Std.Datetime.Business (Unadjusted, Following)
import Shoreleave.UsFederal (us_federal)
-- `us_federal` is the US federal government calendar, used here as a calendar
-- with known closures; it is not a USD settlement calendar.
import Shoals.Tenor (tenor_months, tenor_years)
import Shoals.Schedule (NoStub, ShortInitial, LongInitial, ShortFinal, LongFinal, schedule, schedule_unadjusted)
import Shoals.Properties.Tenor (schedule_is_increasing_and_bounded)
def d(y: i64, m: i64, day: i64) -> Date = date(y, m, day)
-- Each date is the anchor plus k tenors. Stepping from the previous date
-- would turn 31 January, 28 February into 28 March; from the anchor it is
-- 31 March.
def test_monthly_from_31_january_does_not_drift() -> unit ! { Test } = assert_eq(schedule_unadjusted(d(2025i64, 1i64, 31i64), d(2025i64, 5i64, 31i64), tenor_months(1i64), NoStub, false, ClampToMonthEnd), [d(2025i64, 1i64, 31i64), d(2025i64, 2i64, 28i64), d(2025i64, 3i64, 31i64), d(2025i64, 4i64, 30i64), d(2025i64, 5i64, 31i64)], "monthly from 31 January")
-- The end-of-month flag keeps a month-end anchor on month ends; without it the
-- anchor's day of month stands.
def test_end_of_month_flag_from_28_february() -> unit ! { Test } = {
  _ = assert_eq(schedule_unadjusted(d(2025i64, 2i64, 28i64), d(2026i64, 2i64, 28i64), tenor_months(3i64), NoStub, true, ClampToMonthEnd), [d(2025i64, 2i64, 28i64), d(2025i64, 5i64, 31i64), d(2025i64, 8i64, 31i64), d(2025i64, 11i64, 30i64), d(2026i64, 2i64, 28i64)], "EOM keeps month ends")
  assert_eq(schedule_unadjusted(d(2025i64, 2i64, 28i64), d(2026i64, 2i64, 28i64), tenor_months(3i64), NoStub, false, ClampToMonthEnd), [d(2025i64, 2i64, 28i64), d(2025i64, 5i64, 28i64), d(2025i64, 8i64, 28i64), d(2025i64, 11i64, 28i64), d(2026i64, 2i64, 28i64)], "without EOM the 28th stands")
}
def test_annual_from_29_february_returns_to_29_february() -> unit ! { Test } = assert_eq(schedule_unadjusted(d(2024i64, 2i64, 29i64), d(2028i64, 2i64, 29i64), tenor_years(1i64), NoStub, false, ClampToMonthEnd), [d(2024i64, 2i64, 29i64), d(2025i64, 2i64, 28i64), d(2026i64, 2i64, 28i64), d(2027i64, 2i64, 28i64), d(2028i64, 2i64, 29i64)], "clamped years, back on 29 February in 2028")
def test_stub_conventions() -> unit ! { Test } = {
  start = d(2025i64, 1i64, 15i64)
  end = d(2025i64, 12i64, 31i64)
  q = tenor_months(3i64)
  _ = assert_eq(schedule_unadjusted(start, end, q, ShortFinal, false, ClampToMonthEnd), [start, d(2025i64, 4i64, 15i64), d(2025i64, 7i64, 15i64), d(2025i64, 10i64, 15i64), end], "short final stub")
  _ = assert_eq(schedule_unadjusted(start, end, q, LongFinal, false, ClampToMonthEnd), [start, d(2025i64, 4i64, 15i64), d(2025i64, 7i64, 15i64), end], "long final stub")
  _ = assert_eq(schedule_unadjusted(start, end, q, ShortInitial, false, ClampToMonthEnd), [start, d(2025i64, 3i64, 31i64), d(2025i64, 6i64, 30i64), d(2025i64, 9i64, 30i64), end], "short initial stub, anchored at 31 December")
  assert_eq(schedule_unadjusted(start, end, q, LongInitial, false, ClampToMonthEnd), [start, d(2025i64, 6i64, 30i64), d(2025i64, 9i64, 30i64), end], "long initial stub")
}
def test_adjusted_schedule_rolls_each_date() -> unit ! { Test } = {
  _ = assert_eq(schedule(d(2025i64, 5i64, 4i64), d(2025i64, 8i64, 4i64), tenor_months(1i64), NoStub, false, ClampToMonthEnd, us_federal(), Following), [d(2025i64, 5i64, 5i64), d(2025i64, 6i64, 4i64), d(2025i64, 7i64, 7i64), d(2025i64, 8i64, 4i64)], "Sunday 4 May and the 4 July holiday roll forward")
  assert_eq(schedule(d(2025i64, 5i64, 4i64), d(2025i64, 8i64, 4i64), tenor_months(1i64), NoStub, false, ClampToMonthEnd, us_federal(), Unadjusted), [d(2025i64, 5i64, 4i64), d(2025i64, 6i64, 4i64), d(2025i64, 7i64, 4i64), d(2025i64, 8i64, 4i64)], "Unadjusted leaves them")
}
def test_property_schedule_is_increasing_and_bounded() -> unit ! { Test } = {
  _ = assert_eq(schedule_is_increasing_and_bounded(d(2025i64, 1i64, 31i64), d(2030i64, 3i64, 15i64), 1i64), true, "monthly with a final stub")
  assert_eq(schedule_is_increasing_and_bounded(d(2024i64, 2i64, 29i64), d(2054i64, 2i64, 28i64), 6i64), true, "semi-annual over 30 years")
}
-- RejectInvalidDay applies only to the dates a schedule emits. Locating the
-- end must not step onto a nonexistent day such as 30 February and fail.
def test_reject_ignores_a_step_past_the_end() -> unit ! { Test } = assert_eq(schedule_unadjusted(d(2025i64, 12i64, 30i64), d(2026i64, 1i64, 30i64), tenor_months(1i64), NoStub, false, RejectInvalidDay), [d(2025i64, 12i64, 30i64), d(2026i64, 1i64, 30i64)], "one regular period; 30 February is never emitted")
def test_reject_short_final_from_the_30th() -> unit ! { Test } = assert_eq(schedule_unadjusted(d(2025i64, 10i64, 30i64), d(2026i64, 1i64, 30i64), tenor_months(1i64), ShortFinal, false, RejectInvalidDay), [d(2025i64, 10i64, 30i64), d(2025i64, 11i64, 30i64), d(2025i64, 12i64, 30i64), d(2026i64, 1i64, 30i64)], "every emitted date exists")
-- Under the end-of-month rule the month end is the day, so the overflow
-- policy has nothing to reject.
def test_reject_with_end_of_month() -> unit ! { Test } = assert_eq(schedule_unadjusted(d(2025i64, 1i64, 31i64), d(2025i64, 4i64, 30i64), tenor_months(1i64), NoStub, true, RejectInvalidDay), [d(2025i64, 1i64, 31i64), d(2025i64, 2i64, 28i64), d(2025i64, 3i64, 31i64), d(2025i64, 4i64, 30i64)], "EOM month ends")
-- Regularity follows the caller's policy: 30 December plus two months is 28
-- February when clamped and does not exist when rejected, so the period to 28
-- February is regular under one policy and a stub under the other.
def test_regularity_follows_the_overflow_policy() -> unit ! { Test } = {
  _ = assert_eq(schedule_unadjusted(d(2025i64, 12i64, 30i64), d(2026i64, 2i64, 28i64), tenor_months(1i64), LongFinal, false, ClampToMonthEnd), [d(2025i64, 12i64, 30i64), d(2026i64, 1i64, 30i64), d(2026i64, 2i64, 28i64)], "clamped: two regular periods")
  assert_eq(schedule_unadjusted(d(2025i64, 12i64, 30i64), d(2026i64, 2i64, 28i64), tenor_months(1i64), LongFinal, false, RejectInvalidDay), [d(2025i64, 12i64, 30i64), d(2026i64, 2i64, 28i64)], "rejected: one long final stub")
}
