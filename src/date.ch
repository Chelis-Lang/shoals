module Shoals.Date
import Std.Time (Date, date, try_date, is_leap_year, add_days, days_between, day_of_week, DayOfWeek, Saturday, Sunday)
export (DayCount, year_fraction, add_business_days, is_weekend, date_roll_following, date_roll_modified_following, date_roll_preceding, schedule_from_tenor, add_months, days_in_month, schedule_from_tenor_calendar)
type DayCount =
  | Act360
  | Act365
  | ThirtyThreeSixty
  | ActAct
def min_i64(a: int64, b: int64) -> int64 = if lt(a, b) then a else b
def year_fraction(start: Date, end: Date, convention: DayCount) -> f32 = {
  match convention with {
    | Act360 => div(cast(days_between(start, end), f32), cast(360.0, f32))
    | Act365 => div(cast(days_between(start, end), f32), cast(365.0, f32))
    | ThirtyThreeSixty => {
    y1 = start.year
    m1 = start.month
    d1 = min_i64(start.day, cast(30, int64))
    y2 = end.year
    m2 = end.month
    d2 = min_i64(end.day, cast(30, int64))
    days = add(add(mul(cast(360, int64), sub(y2, y1)), mul(cast(30, int64), sub(m2, m1))), sub(d2, d1))
    div(cast(days, f32), cast(360.0, f32))
  }
    | ActAct => div(cast(days_between(start, end), f32), cast(365.25, f32))
  }
}
def is_weekend(d: Date) -> bool = {
  match day_of_week(d) with {
    | Saturday => true
    | Sunday => true
    | _ => false
  }
}
def add_business_days(d: Date, n: int64, weekend_only: bool) -> Date = {
  flag = weekend_only
  idxs = range(cast(0, int64), n)
  fold(fn (acc: Date, _i: int64) -> {
    next = add_days(acc, cast(1, int64))
    if flag then advance_to_business(next) else advance_to_business(next)
  }, d, idxs)
}
def advance_to_business(d: Date) -> Date = { if is_weekend(d) then advance_to_business(add_days(d, cast(1, int64))) else d }
def retreat_to_business(d: Date) -> Date = { if is_weekend(d) then retreat_to_business(add_days(d, cast(-1, int64))) else d }
def date_roll_following(d: Date, weekend_only: bool) -> Date = { if weekend_only then advance_to_business(d) else advance_to_business(d) }
def date_roll_preceding(d: Date, weekend_only: bool) -> Date = { if weekend_only then retreat_to_business(d) else retreat_to_business(d) }
def date_roll_modified_following(d: Date, weekend_only: bool) -> Date = {
  rolled = if weekend_only then advance_to_business(d) else advance_to_business(d)
  if eq(rolled.month, d.month) then rolled else retreat_to_business(d)
}
def schedule_from_tenor(start: Date, end: Date, step_months: int64) -> List[Date] = {
  step_days = mul(step_months, cast(30, int64))
  total = days_between(start, end)
  n_steps = if lt(step_days, cast(1, int64)) then cast(0, int64) else floor_div(total, step_days)
  idxs = range(cast(0, int64), add(n_steps, cast(1, int64)))
  fold(fn (acc: List[Date], i: int64) -> {
    candidate = add_days(start, mul(i, step_days))
    append(acc, candidate)
  }, [], idxs)
}
def days_in_month(year: int64, month: int64) -> int64 = { if or(eq(month, cast(1, int64)), or(eq(month, cast(3, int64)), or(eq(month, cast(5, int64)), or(eq(month, cast(7, int64)), or(eq(month, cast(8, int64)), or(eq(month, cast(10, int64)), eq(month, cast(12, int64)))))))) then cast(31, int64) else if or(eq(month, cast(4, int64)), or(eq(month, cast(6, int64)), or(eq(month, cast(9, int64)), eq(month, cast(11, int64))))) then cast(30, int64) else if is_leap_year(year) then cast(29, int64) else cast(28, int64) }
def normalize_month(year: int64, month: int64) -> (int64, int64) = { if lt(month, cast(1, int64)) then normalize_month(sub(year, cast(1, int64)), add(month, cast(12, int64))) else if gt(month, cast(12, int64)) then normalize_month(add(year, cast(1, int64)), sub(month, cast(12, int64))) else (year, month) }
def add_months(d: Date, n: int64) -> Date = {
  raw_month = add(d.month, n)
  normalized = normalize_month(d.year, raw_month)
  ny = normalized.0
  nm = normalized.1
  cap = days_in_month(ny, nm)
  nd = if gt(d.day, cap) then cap else d.day
  date(ny, nm, nd)
}
def schedule_from_tenor_calendar(start: Date, end: Date, step_months: int64) -> List[Date] = {
  end_ord = days_between(start, end)
  rough = if lt(step_months, cast(1, int64)) then cast(0, int64) else add(floor_div(end_ord, mul(step_months, cast(28, int64))), cast(2, int64))
  idxs = range(cast(0, int64), add(rough, cast(1, int64)))
  fold(fn (acc: List[Date], i: int64) -> {
    candidate = add_months(start, mul(i, step_months))
    if gt(days_between(candidate, end), cast(-1, int64)) then append(acc, candidate) else acc
  }, [], idxs)
}
