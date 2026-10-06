module Shoals.References.Date
import Std.Datetime (Date, date_year, date_month, date_day)
export (naive_days_between, year_fraction_act_360_textbook, year_fraction_act_365_textbook, year_fraction_thirty_360_textbook, year_fraction_act_act_isda_textbook, year_fraction_act_act_icma_textbook)
def min_i64(a: i64, b: i64) -> i64 = if lt(a, b) then a else b
def naive_days_between(start: Date, end: Date) -> i64 = {
  start_ord = add(add(mul(date_year(start), cast(365, i64)), mul(sub(date_month(start), cast(1, i64)), cast(30, i64))), date_day(start))
  end_ord = add(add(mul(date_year(end), cast(365, i64)), mul(sub(date_month(end), cast(1, i64)), cast(30, i64))), date_day(end))
  sub(end_ord, start_ord)
}
def year_fraction_act_360_textbook(start: Date, end: Date) -> f64 = div(cast(naive_days_between(start, end), f64), cast(360.0, f64))
def year_fraction_act_365_textbook(start: Date, end: Date) -> f64 = div(cast(naive_days_between(start, end), f64), cast(365.0, f64))
def year_fraction_thirty_360_textbook(start: Date, end: Date) -> f64 = {
  y1 = date_year(start)
  m1 = date_month(start)
  d1 = min_i64(date_day(start), cast(30, i64))
  y2 = date_year(end)
  m2 = date_month(end)
  d2 = min_i64(date_day(end), cast(30, i64))
  days = add(add(mul(cast(360, i64), sub(y2, y1)), mul(cast(30, i64), sub(m2, m1))), sub(d2, d1))
  days |> fn (__chelis_pipe) -> cast(__chelis_pipe, f64) |> div(cast(360.0, f64))
}
-- An exact proleptic-Gregorian day number, computed here rather than taken from
-- `Std.Datetime.date_days_until`, so the ACT/ACT references below check the subject
-- against an independently derived calendar rather than against itself. The
-- older textbook functions above deliberately keep their crude 30-day-month
-- count; only the ACT/ACT pair needs exactness to be worth comparing.
def civil_ordinal(year: i64, month: i64, day: i64) -> i64 = {
  shifted = if lte(month, cast(2, i64)) then sub(year, cast(1, i64)) else year
  era = floor_div(shifted, cast(400, i64))
  yoe = sub(shifted, mul(era, cast(400, i64)))
  march_month = if gt(month, cast(2, i64)) then sub(month, cast(3, i64)) else add(month, cast(9, i64))
  doy = add(floor_div(add(mul(cast(153, i64), march_month), cast(2, i64)), cast(5, i64)), sub(day, cast(1, i64)))
  doe = add(sub(add(mul(yoe, cast(365, i64)), floor_div(yoe, cast(4, i64))), floor_div(yoe, cast(100, i64))), doy)
  sub(add(mul(era, cast(146097, i64)), doe), cast(719468, i64))
}
def civil_is_leap(year: i64) -> bool = or(and(eq(mod(year, cast(4, i64)), cast(0, i64)), neq(mod(year, cast(100, i64)), cast(0, i64))), eq(mod(year, cast(400, i64)), cast(0, i64)))
def civil_year_length(year: i64) -> f64 = if civil_is_leap(year) then cast(366.0, f64) else cast(365.0, f64)
def civil_ord_of(d: Date) -> i64 = civil_ordinal(date_year(d), date_month(d), date_day(d))
-- ACT/ACT ISDA by per-calendar-year clamp: every year the interval touches is
-- intersected with it and divided by that year's own length. `Shoals.Date`
-- instead counts whole interior years as exactly 1 and divides only the head and
-- tail stubs, which is O(1) in the span. Agreement is therefore a real
-- cross-check of the year-boundary handling rather than a restatement, and the
-- cost of this loop is irrelevant because the reference only runs over
-- test-sized spans.
def year_fraction_act_act_isda_textbook(start: Date, end: Date) -> f64 = {
  ord_start = civil_ord_of(start)
  ord_end = civil_ord_of(end)
  if lt(ord_end, ord_start) then neg(year_fraction_act_act_isda_textbook(end, start)) else {
    years = range(date_year(start), add(date_year(end), cast(1, i64)))
    fold(fn (acc: f64, y: i64) -> {
      year_begin = civil_ordinal(y, cast(1, i64), cast(1, i64))
      year_limit = civil_ordinal(add(y, cast(1, i64)), cast(1, i64), cast(1, i64))
      seg_start = if lt(ord_start, year_begin) then year_begin else ord_start
      seg_end = if lt(ord_end, year_limit) then ord_end else year_limit
      span = sub(seg_end, seg_start)
      if lt(span, cast(1, i64)) then acc else add(acc, div(cast(span, f64), civil_year_length(y)))
    }, cast(0.0, f64), years)
  }
}
def year_fraction_act_act_icma_textbook(start: Date, end: Date, period_start: Date, period_end: Date, frequency: i64) -> f64 = {
  accrued = sub(civil_ord_of(end), civil_ord_of(start))
  period = sub(civil_ord_of(period_end), civil_ord_of(period_start))
  div(cast(accrued, f64), mul(cast(frequency, f64), cast(period, f64)))
}
