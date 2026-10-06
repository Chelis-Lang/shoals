module Shoals.Properties.Date
import Std.Datetime (Date, date)
import Shoals.Date (DayCount, Act360, Act365, ThirtyThreeSixty, ActActIsda, ActActIcma, year_fraction)
import Shoals.References.Date (year_fraction_act_360_textbook, year_fraction_act_365_textbook, year_fraction_thirty_360_textbook, year_fraction_act_act_isda_textbook, year_fraction_act_act_icma_textbook)
export (year_fraction_matches_textbook, whole_isda_year_is_exactly_one, isda_reverses_under_swap)
def abs_f64(x: f64) -> f64 = if lt(x, cast(0.0, f64)) then neg(x) else x
-- The ACT/ACT legs compare two exact calendars against each other, so they hold
-- to floating-point agreement. The other three compare against the crude
-- 30-day-month textbook count in `Shoals.References.Date` and keep its loose
-- tolerance; tightening those is a separate change to the reference, not to the
-- subject.
def year_fraction_matches_textbook(start: Date, end: Date, convention: DayCount) -> bool = {
  observed = year_fraction(start, end, convention)
  reference = match convention with {
    | Act360 => year_fraction_act_360_textbook(start, end)
    | Act365 => year_fraction_act_365_textbook(start, end)
    | ThirtyThreeSixty => year_fraction_thirty_360_textbook(start, end)
    | ActActIsda => year_fraction_act_act_isda_textbook(start, end)
    | ActActIcma { period_start: ps, period_end: pe, frequency: f } => year_fraction_act_act_icma_textbook(start, end, ps, pe, f)
  }
  tol = match convention with {
    | ThirtyThreeSixty => cast(1e-9, f64)
    | Act360 => cast(0.05, f64)
    | Act365 => cast(0.05, f64)
    | ActActIsda => cast(1e-9, f64)
    | ActActIcma { period_start: _, period_end: _, frequency: _ } => cast(1e-9, f64)
  }
  diff = sub(observed, reference)
  lt(abs_f64(diff), tol)
}
-- A calendar year is exactly one ACT/ACT ISDA year whether or not it is a leap
-- year: that is the whole point of the per-year denominator, and the 365.25
-- approximation this replaced failed it in both directions.
def whole_isda_year_is_exactly_one(year: i64) -> bool = {
  jan_first = date(year, cast(1, i64), cast(1, i64))
  next_jan = date(add(year, cast(1, i64)), cast(1, i64), cast(1, i64))
  observed = year_fraction(jan_first, next_jan, ActActIsda)
  lt(abs_f64(sub(observed, cast(1.0, f64))), cast(1e-12, f64))
}
def isda_reverses_under_swap(start: Date, end: Date) -> bool = {
  forward = year_fraction(start, end, ActActIsda)
  backward = year_fraction(end, start, ActActIsda)
  lt(abs_f64(add(forward, backward)), cast(1e-12, f64))
}
