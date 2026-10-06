module Shoals.Date
import Std.Datetime (Date, date, try_date, is_leap_year, date_add_days, date_add_months, ClampToMonthEnd, date_days_until, date_weekday, date_year, date_month, date_day, Weekday, Saturday, Sunday, date_lt, date_lte)
import Std.Datetime.Business (BusinessCalendar, Following, Preceding, ModifiedFollowing, RollStartForward, RollStartBackward, RejectNonBusinessStart, business_day_roll, business_day_offset)
import Shoals.HolidayCal (Calendar, as_business_calendar, weekend_only_calendar)
export (DayCount, year_fraction, add_business_days, is_weekend, date_roll_following, date_roll_modified_following, date_roll_preceding, date_roll_following_published, date_roll_modified_following_published, date_roll_preceding_published, schedule_from_tenor, add_months, days_in_month, schedule_from_tenor_calendar)
-- `ActActIcma` carries the enclosing coupon period and the coupon frequency
-- because ACT/ACT ICMA is not computable from (start, end) alone. Holding them
-- in the variant rather than in an optional parameter makes an ICMA request
-- without a period unrepresentable instead of a runtime guard.
type DayCount =
  | Act360
  | Act365
  | ThirtyThreeSixty
  | ActActIsda
  | ActActIcma { period_start: Date, period_end: Date, frequency: i64 }
def min_i64(a: i64, b: i64) -> i64 = if lt(a, b) then a else b
def date_require_positive_period(period_start: Date, period_end: Date) -> i64 = {
  span = date_days_until(period_start, period_end)
  if lt(span, cast(1, i64)) then fail("Shoals.Date: ACT/ACT ICMA coupon period must end after it starts") else span
}
def date_require_frequency(n: i64) -> i64 = if lt(n, cast(1, i64)) then fail("Shoals.Date: ACT/ACT ICMA coupon frequency must be >= 1") else n
-- ACT/ACT ISDA weights a day by the length of the calendar year it falls in, so
-- a leap day counts 1/366 and an ordinary day 1/365. Stated the way a textbook
-- does: a whole interior year is exactly 1, and only the head and tail stubs are
-- divided. The formulation matters, and the reason is not where it first looks.
-- This form makes a bounded number of date calls whatever the span. The
-- `Std.Datetime` date operations use closed-form Gregorian arithmetic, so
-- intervals distant from 1970 do not add a per-year traversal cost.
-- `Shoals.References.Date` carries the per-year-clamp formulation instead, where
-- the span is always test-sized and the differing shape is what makes the
-- cross-check worth running. A reversed interval returns the negated fraction.
def length_of_year(year: i64) -> f64 = if is_leap_year(year) then cast(366.0, f64) else cast(365.0, f64)
def isda_fraction(start: Date, end: Date) -> f64 = {
  forward = date_lte(start, end)
  lo = if forward then start else end
  hi = if forward then end else start
  span = date_days_until(lo, hi)
  total = if lt(span, cast(1, i64)) then cast(0.0, f64) else {
    y_lo = date_year(lo)
    y_hi = date_year(hi)
    if eq(y_lo, y_hi) then div(cast(span, f64), length_of_year(y_lo)) else {
      head_days = date_days_until(lo, date(add(y_lo, cast(1, i64)), cast(1, i64), cast(1, i64)))
      tail_days = date_days_until(date(y_hi, cast(1, i64), cast(1, i64)), hi)
      head = div(cast(head_days, f64), length_of_year(y_lo))
      tail = div(cast(tail_days, f64), length_of_year(y_hi))
      interior = cast(sub(sub(y_hi, y_lo), cast(1, i64)), f64)
      add(add(head, interior), tail)
    }
  }
  if forward then total else neg(total)
}
-- ACT/ACT ICMA measures the accrued days against the full coupon period, scaled
-- by the number of coupon periods in a year, so a regular full period is exactly
-- 1/frequency whatever its actual day count.
def icma_fraction(start: Date, end: Date, period_start: Date, period_end: Date, frequency: i64) -> f64 = {
  span = date_require_positive_period(period_start, period_end)
  freq = date_require_frequency(frequency)
  accrued = date_days_until(start, end)
  div(cast(accrued, f64), mul(cast(freq, f64), cast(span, f64)))
}
def year_fraction(start: Date, end: Date, convention: DayCount) -> f64 =
  match convention with {
    | Act360 => div(cast(date_days_until(start, end), f64), cast(360.0, f64))
    | Act365 => div(cast(date_days_until(start, end), f64), cast(365.0, f64))
    | ThirtyThreeSixty => {
    y1 = date_year(start)
    m1 = date_month(start)
    d1 = min_i64(date_day(start), cast(30, i64))
    y2 = date_year(end)
    m2 = date_month(end)
    d2 = min_i64(date_day(end), cast(30, i64))
    days = add(add(mul(cast(360, i64), sub(y2, y1)), mul(cast(30, i64), sub(m2, m1))), sub(d2, d1))
    div(cast(days, f64), cast(360.0, f64))
  }
    | ActActIsda => isda_fraction(start, end)
    | ActActIcma { period_start: ps, period_end: pe, frequency: f } => icma_fraction(start, end, ps, pe, f)
  }
def is_weekend(d: Date) -> bool =
  match date_weekday(d) with {
    | Saturday => true
    | Sunday => true
    | _ => false
  }
-- Every roll takes its calendar. `weekend_only_calendar()` applies a
-- Monday-to-Friday business week without holiday dates.
-- A non-business start sits between two business days. A positive count
-- starts from the following one, so its first step lands there; a negative
-- count starts from the preceding one, so its first step lands there. Zero
-- business days from a non-business start is the following business day, the
-- core offset of 0 under `RollStartForward`; from a business day it is the
-- start. Each case is one `business_day_offset` call, so the calendar's
-- horizon bounds every answer.
def add_business_days(d: Date, n: i64, cal: Calendar) -> Date = {
  core = as_business_calendar(cal)
  if Std.Datetime.Business.is_business_day(core, d) then business_day_offset(core, d, n, RejectNonBusinessStart) else if gt(n, 0i64) then business_day_offset(core, d, sub(n, 1i64), RollStartForward) else if lt(n, 0i64) then business_day_offset(core, d, add(n, 1i64), RollStartBackward) else business_day_offset(core, d, 0i64, RollStartForward)
}
def date_roll_following(d: Date, cal: Calendar) -> Date = business_day_roll(as_business_calendar(cal), d, Following)
def date_roll_preceding(d: Date, cal: Calendar) -> Date = business_day_roll(as_business_calendar(cal), d, Preceding)
def date_roll_modified_following(d: Date, cal: Calendar) -> Date = business_day_roll(as_business_calendar(cal), d, ModifiedFollowing)
def date_roll_following_published(d: Date, cal: BusinessCalendar) -> Date = business_day_roll(cal, d, Following)
def date_roll_preceding_published(d: Date, cal: BusinessCalendar) -> Date = business_day_roll(cal, d, Preceding)
def date_roll_modified_following_published(d: Date, cal: BusinessCalendar) -> Date = business_day_roll(cal, d, ModifiedFollowing)
def schedule_from_tenor(start: Date, end: Date, step_months: i64) -> List[Date] = {
  step_days = mul(step_months, cast(30, i64))
  total = date_days_until(start, end)
  n_steps = if lt(step_days, cast(1, i64)) then cast(0, i64) else floor_div(total, step_days)
  idxs = range(cast(0, i64), add(n_steps, cast(1, i64)))
  fold(fn (acc: List[Date], i: i64) -> {
    candidate = date_add_days(start, mul(i, step_days))
    append(acc, candidate)
  }, [], idxs)
}
def days_in_month(year: i64, month: i64) -> i64 = Std.Datetime.days_in_month(year, month)
def add_months(d: Date, n: i64) -> Date = date_add_months(d, n, ClampToMonthEnd)
def schedule_from_tenor_calendar(start: Date, end: Date, step_months: i64) -> List[Date] = {
  end_ord = date_days_until(start, end)
  rough = if lt(step_months, cast(1, i64)) then cast(0, i64) else add(floor_div(end_ord, mul(step_months, cast(28, i64))), cast(2, i64))
  idxs = range(cast(0, i64), add(rough, cast(1, i64)))
  fold(fn (acc: List[Date], i: i64) -> {
    candidate = add_months(start, mul(i, step_months))
    if gt(date_days_until(candidate, end), cast(-1, i64)) then append(acc, candidate) else acc
  }, [], idxs)
}
