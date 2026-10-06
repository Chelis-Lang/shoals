module Shoals.References.Date
import Std.Datetime (Date, date_year, date_month, date_day)
export (actual_days_reference, isda_reference, icma_reference)
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
def civil_is_leap(year: i64) -> bool = or(and(eq(mod(year, 4i64), 0i64), neq(mod(year, 100i64), 0i64)), eq(mod(year, 400i64), 0i64))
def civil_year_length(year: i64) -> i64 = if civil_is_leap(year) then 366i64 else 365i64
def civil_ord_of(d: Date) -> i64 = civil_ordinal(date_year(d), date_month(d), date_day(d))
def ref_gcd(a: i64, b: i64) -> i64 = if eq(b, 0i64) then a else ref_gcd(b, mod(a, b))
-- A rational as (numerator, denominator) in lowest terms, denominator positive.
def ref_reduce(n: i64, d: i64) -> (i64, i64) = {
  g = ref_gcd(if lt(n, 0i64) then neg(n) else n, d)
  (floor_div(n, g), floor_div(d, g))
}
def ref_add(a: (i64, i64), b: (i64, i64)) -> (i64, i64) = ref_reduce(add(mul(a.0, b.1), mul(b.0, a.1)), mul(a.1, b.1))
-- Actual days by the independent ordinal, for ACT/360 and ACT/365 Fixed.
def actual_days_reference(start: Date, end: Date) -> i64 = sub(civil_ord_of(end), civil_ord_of(start))
-- ACT/ACT ISDA by per-calendar-year clamp: every year the interval touches is
-- intersected with it and divided by that year's own length, and the pieces
-- are summed as exact rationals. `Shoals.Date` instead counts whole interior
-- years as exactly 1 and divides only the head and tail stubs, which is O(1)
-- in the span. Agreement is therefore a real cross-check of the year-boundary
-- handling rather than a restatement, and the cost of this loop is irrelevant
-- because the reference only runs over test-sized spans.
def isda_reference(start: Date, end: Date) -> (i64, i64) = {
  ord_start = civil_ord_of(start)
  ord_end = civil_ord_of(end)
  years = range(date_year(start), add(date_year(end), 1i64))
  fold(fn (acc: (i64, i64), y: i64) -> {
    year_begin = civil_ordinal(y, 1i64, 1i64)
    year_limit = civil_ordinal(add(y, 1i64), 1i64, 1i64)
    seg_start = if lt(ord_start, year_begin) then year_begin else ord_start
    seg_end = if lt(ord_end, year_limit) then ord_end else year_limit
    span = sub(seg_end, seg_start)
    if lt(span, 1i64) then acc else ref_add(acc, ref_reduce(span, civil_year_length(y)))
  }, (0i64, 1i64), years)
}
def icma_reference(start: Date, end: Date, period_start: Date, period_end: Date, frequency: i64) -> (i64, i64) = ref_reduce(sub(civil_ord_of(end), civil_ord_of(start)), mul(frequency, sub(civil_ord_of(period_end), civil_ord_of(period_start))))
