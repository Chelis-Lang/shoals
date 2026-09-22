module Shoals.References.Date
import Std.Time (Date)
export (naive_days_between, year_fraction_act_360_textbook, year_fraction_act_365_textbook, year_fraction_thirty_360_textbook, year_fraction_act_act_textbook)
def min_i64(a: i64, b: i64) -> i64 = if lt(a, b) then a else b
def naive_days_between(start: Date, end: Date) -> i64 = {
  start_ord = add(add(mul(start.year, cast(365, i64)), mul(sub(start.month, cast(1, i64)), cast(30, i64))), start.day)
  end_ord = add(add(mul(end.year, cast(365, i64)), mul(sub(end.month, cast(1, i64)), cast(30, i64))), end.day)
  sub(end_ord, start_ord)
}
def year_fraction_act_360_textbook(start: Date, end: Date) -> f32 = div(cast(naive_days_between(start, end), f32), cast(360.0, f32))
def year_fraction_act_365_textbook(start: Date, end: Date) -> f32 = div(cast(naive_days_between(start, end), f32), cast(365.0, f32))
def year_fraction_thirty_360_textbook(start: Date, end: Date) -> f32 = {
  y1 = start.year
  m1 = start.month
  d1 = min_i64(start.day, cast(30, i64))
  y2 = end.year
  m2 = end.month
  d2 = min_i64(end.day, cast(30, i64))
  days = add(add(mul(cast(360, i64), sub(y2, y1)), mul(cast(30, i64), sub(m2, m1))), sub(d2, d1))
  days |> fn (__chelis_pipe) -> cast(__chelis_pipe, f32) |> div(cast(360.0, f32))
}
def year_fraction_act_act_textbook(start: Date, end: Date) -> f32 = div(cast(naive_days_between(start, end), f32), cast(365.25, f32))
