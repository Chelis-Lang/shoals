module Shoals.Date
import Std.Time (Date, add_days, days_between, day_of_week, DayOfWeek)
export (DayCount, year_fraction, add_business_days, is_weekend, roll_following, roll_modified_following, roll_preceding, schedule_from_tenor)
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
def roll_following(d: Date, weekend_only: bool) -> Date = { if weekend_only then advance_to_business(d) else advance_to_business(d) }
def roll_preceding(d: Date, weekend_only: bool) -> Date = { if weekend_only then retreat_to_business(d) else retreat_to_business(d) }
def roll_modified_following(d: Date, weekend_only: bool) -> Date = {
  rolled = if weekend_only then advance_to_business(d) else advance_to_business(d)
  if eq(rolled.month, d.month) then rolled else retreat_to_business(d)
}
def schedule_from_tenor(start: Date, end: Date, step_months: int64) -> List[Date] = {
  step_days = mul(step_months, cast(30, int64))
  total = days_between(start, end)
  n_steps = if lt(step_days, cast(1, int64)) then cast(0, int64) else div(total, step_days)
  idxs = range(cast(0, int64), add(n_steps, cast(1, int64)))
  fold(fn (acc: List[Date], i: int64) -> {
    candidate = add_days(start, mul(i, step_days))
    append(acc, candidate)
  }, [], idxs)
}
