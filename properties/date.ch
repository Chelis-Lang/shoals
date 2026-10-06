module Shoals.Properties.Date
import Std.Datetime (Date, date)
import Shoals.Date (DayCount, ActualOver360, ActualOver365Fixed, ActualActualIsda, ActualActualIcma, YearFraction, year_fraction, year_fraction_numerator, year_fraction_denominator)
import Shoals.References.Date (actual_days_reference, isda_reference, icma_reference)
export (actual_matches_reference, isda_matches_reference, icma_matches_reference, whole_isda_year_is_exactly_one, additive_under_isda)
-- Year fractions are exact rationals in lowest terms, so every property here
-- is an equality, not a tolerance.
def is_exactly(f: YearFraction, n: i64, d: i64) -> bool = {
  g = act_gcd(if lt(n, 0i64) then neg(n) else n, d)
  and(eq(year_fraction_numerator(f), floor_div(n, g)), eq(year_fraction_denominator(f), floor_div(d, g)))
}
def act_gcd(a: i64, b: i64) -> i64 = if eq(b, 0i64) then a else act_gcd(b, mod(a, b))
def actual_matches_reference(start: Date, end: Date) -> bool = {
  n = actual_days_reference(start, end)
  and(is_exactly(year_fraction(start, end, ActualOver360), n, 360i64), is_exactly(year_fraction(start, end, ActualOver365Fixed), n, 365i64))
}
def isda_matches_reference(start: Date, end: Date) -> bool = {
  r = isda_reference(start, end)
  is_exactly(year_fraction(start, end, ActualActualIsda), r.0, r.1)
}
def icma_matches_reference(start: Date, end: Date, period_start: Date, period_end: Date, frequency: i64) -> bool = {
  r = icma_reference(start, end, period_start, period_end, frequency)
  is_exactly(year_fraction(start, end, ActualActualIcma { reference_start: period_start, reference_end: period_end, frequency }), r.0, r.1)
}
-- A calendar year is exactly one ACT/ACT ISDA year whether or not it is a leap
-- year: that is the whole point of the per-year denominator.
def whole_isda_year_is_exactly_one(year: i64) -> bool = is_exactly(year_fraction(date(year, 1i64, 1i64), date(add(year, 1i64), 1i64, 1i64), ActualActualIsda), 1i64, 1i64)
-- ACT/ACT ISDA is additive over a split point, exactly.
def additive_under_isda(a: Date, b: Date, c: Date) -> bool = {
  left = year_fraction(a, b, ActualActualIsda)
  right = year_fraction(b, c, ActualActualIsda)
  n = add(mul(year_fraction_numerator(left), year_fraction_denominator(right)), mul(year_fraction_numerator(right), year_fraction_denominator(left)))
  is_exactly(year_fraction(a, c, ActualActualIsda), n, mul(year_fraction_denominator(left), year_fraction_denominator(right)))
}
