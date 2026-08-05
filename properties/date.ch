module Shoals.Properties.Date
import Std.Time (Date, date_lt, date_lte)
import Shoals.Date (DayCount, Act360, Act365, ThirtyThreeSixty, ActAct, year_fraction, schedule_from_tenor, schedule_from_tenor_calendar, date_roll_following, is_weekend, add_months)
import Shoals.References.Date (year_fraction_act_360_textbook, year_fraction_act_365_textbook, year_fraction_thirty_360_textbook, year_fraction_act_act_textbook)
export (year_fraction_matches_textbook, schedule_monotone_increasing, date_roll_following_idempotent_on_weekday, add_months_then_neg_is_identity, schedule_calendar_monotone_increasing)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def date_eq(a: Date, b: Date) -> bool = and(date_lte(a, b), date_lte(b, a))
def year_fraction_matches_textbook(start: Date, end: Date, convention: DayCount) -> bool = {
  observed = year_fraction(start, end, convention)
  reference = match convention with {
    | Act360 => year_fraction_act_360_textbook(start, end)
    | Act365 => year_fraction_act_365_textbook(start, end)
    | ThirtyThreeSixty => year_fraction_thirty_360_textbook(start, end)
    | ActAct => year_fraction_act_act_textbook(start, end)
  }
  diff = sub(observed, reference)
  tol = match convention with {
    | ThirtyThreeSixty => cast(1e-6, f32)
    | Act360 => cast(0.05, f32)
    | Act365 => cast(0.05, f32)
    | ActAct => cast(0.05, f32)
  }
  lt(abs_f32(diff), tol)
}
def schedule_monotone_increasing(start: Date, end: Date, step_months: int64) -> bool = {
  dates = schedule_from_tenor(start, end, step_months)
  n = len(dates)
  if lte(n, cast(1, int64)) then true else {
    idxs = range(cast(1, int64), n)
    fold(fn (acc: bool, i: int64) -> {
      prev = index(dates, sub(i, cast(1, int64)))
      curr = index(dates, i)
      and(acc, date_lt(prev, curr))
    }, true, idxs)
  }
}
def date_roll_following_idempotent_on_weekday(d: Date) -> bool = if is_weekend(d) then true else date_eq(date_roll_following(d, true), d)
def add_months_then_neg_is_identity(d: Date, n: int64) -> bool = if gt(d.day, cast(28, int64)) then true else date_eq(add_months(add_months(d, n), neg(n)), d)
def schedule_calendar_monotone_increasing(start: Date, end: Date, step_months: int64) -> bool = {
  dates = schedule_from_tenor_calendar(start, end, step_months)
  n = len(dates)
  if lte(n, cast(1, int64)) then true else {
    idxs = range(cast(1, int64), n)
    fold(fn (acc: bool, i: int64) -> {
      prev = index(dates, sub(i, cast(1, int64)))
      curr = index(dates, i)
      and(acc, date_lt(prev, curr))
    }, true, idxs)
  }
}
