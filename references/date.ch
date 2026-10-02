module Shoals.References.Date
import Std.Time (Date)
export (naive_days_between, year_fraction_act_360_textbook, year_fraction_act_365_textbook, year_fraction_thirty_360_textbook, year_fraction_act_act_isda_textbook, year_fraction_act_act_icma_textbook)
def min_i64(a: i64, b: i64) -> i64 = if lt(a, b) then a else b
def naive_days_between(start: Date, end: Date) -> i64 = {
  start_ord = add(add(mul(start.year, cast(365, i64)), mul(sub(start.month, cast(1, i64)), cast(30, i64))), start.day)
  end_ord = add(add(mul(end.year, cast(365, i64)), mul(sub(end.month, cast(1, i64)), cast(30, i64))), end.day)
  sub(end_ord, start_ord)
}
def year_fraction_act_360_textbook(start: Date, end: Date) -> f64 = div(cast(naive_days_between(start, end), f64), cast(360.0, f64))
def year_fraction_act_365_textbook(start: Date, end: Date) -> f64 = div(cast(naive_days_between(start, end), f64), cast(365.0, f64))
def year_fraction_thirty_360_textbook(start: Date, end: Date) -> f64 = {
  y1 = start.year
  m1 = start.month
  d1 = min_i64(start.day, cast(30, i64))
  y2 = end.year
  m2 = end.month
  d2 = min_i64(end.day, cast(30, i64))
  days = add(add(mul(cast(360, i64), sub(y2, y1)), mul(cast(30, i64), sub(m2, m1))), sub(d2, d1))
  days |> fn (__chelis_pipe) -> cast(__chelis_pipe, f64) |> div(cast(360.0, f64))
}
-- An exact proleptic-Gregorian day number, computed here rather than taken from
-- `Std.Time.days_between`, so the ACT/ACT references below check the subject
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
def civil_ord_of(d: Date) -> i64 = civil_ordinal(d.year, d.month, d.day)
-- ACT/ACT ISDA written the way a textbook states it: a whole interior year
-- counts as exactly 1, and only the head and tail stubs are divided. The subject
-- in `Shoals.Date` instead clamps every calendar year to the interval and divides
-- each segment, so agreement is a real cross-check of the year-boundary handling.
def year_fraction_act_act_isda_textbook(start: Date, end: Date) -> f64 = {
  ord_start = civil_ord_of(start)
  ord_end = civil_ord_of(end)
  if lt(ord_end, ord_start) then neg(year_fraction_act_act_isda_textbook(end, start)) else if eq(ord_end, ord_start) then cast(0.0, f64) else {
    y_start = start.year
    y_end = end.year
    if eq(y_start, y_end) then div(cast(sub(ord_end, ord_start), f64), civil_year_length(y_start)) else {
      head_days = sub(civil_ordinal(add(y_start, cast(1, i64)), cast(1, i64), cast(1, i64)), ord_start)
      tail_days = sub(ord_end, civil_ordinal(y_end, cast(1, i64), cast(1, i64)))
      head = div(cast(head_days, f64), civil_year_length(y_start))
      tail = div(cast(tail_days, f64), civil_year_length(y_end))
      interior = cast(sub(sub(y_end, y_start), cast(1, i64)), f64)
      add(add(head, interior), tail)
    }
  }
}
def year_fraction_act_act_icma_textbook(start: Date, end: Date, period_start: Date, period_end: Date, frequency: i64) -> f64 = {
  accrued = sub(civil_ord_of(end), civil_ord_of(start))
  period = sub(civil_ord_of(period_end), civil_ord_of(period_start))
  div(cast(accrued, f64), mul(cast(frequency, f64), cast(period, f64)))
}
