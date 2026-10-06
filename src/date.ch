module Shoals.Date
import Std.Datetime (Date, is_leap_year, days_in_month, date, date_days_until, date_year, date_month, date_day, date_lte, date_lt, date_to_string)
import Std.Datetime.Business (BusinessCalendar, business_day_count)
export (DayCount, ActualOver360, ActualOver365Fixed, ActualActualIsda, ActualActualIcma, ThirtyEOver360, ThirtyEOver360Isda, ThirtyOver360Us, Business252, YearFraction, year_fraction, year_fraction_numerator, year_fraction_denominator, year_fraction_to_f64, year_fraction_to_f32)
-- Each convention has one published definition, and its name says which.
-- ACT/365 and "30/360 ISDA" are not names here, because libraries disagree on
-- what they mean. Inputs beyond the two dates are fields of the variant, so a
-- convention that needs them cannot be requested without them:
--   ActualOver360        ACT/360: actual days / 360.
--   ActualOver365Fixed   ACT/365 Fixed: actual days / 365.
--   ActualActualIsda     ACT/ACT ISDA (ISDA 2006 4.16(b)): days in each
--                        calendar year over that year's length.
--   ActualActualIcma     ACT/ACT ICMA (ICMA Rule 251): accrued days over
--                        frequency x days of the reference coupon period
--                        that contains the accrual.
--   ThirtyEOver360       30E/360, the Eurobond basis (ISDA 2006 4.16(g)).
--   ThirtyEOver360Isda   30E/360 ISDA (ISDA 2006 4.16(h)); the maturity date
--                        decides the February end-of-month case.
--   ThirtyOver360Us      30/360 US (SIFMA); `end_of_month` applies the
--                        last-day-of-February rules.
--   Business252          BUS/252: business days of the calendar in
--                        [start, end) / 252.
type DayCount =
  | ActualOver360
  | ActualOver365Fixed
  | ActualActualIsda
  | ActualActualIcma { reference_start: Date, reference_end: Date, frequency: i64 }
  | ThirtyEOver360
  | ThirtyEOver360Isda { maturity: Date }
  | ThirtyOver360Us { end_of_month: bool }
  | Business252 { calendar: BusinessCalendar }
-- A year fraction is an exact rational in lowest terms with a positive
-- denominator. The representation is closed so that every value went through
-- `reduced`.
@opaque
type YearFraction =
  | YearFraction { numerator: i64, denominator: i64 }
def joined(parts: List[string]) -> string = fold(fn (acc: string, part: string) -> string_concat(acc, part), "", parts)
def domain_failure(detail: string) -> string = string_concat("Shoals.Date.year_fraction: domain: ", detail)
def gcd(a: i64, b: i64) -> i64 = if eq(b, 0i64) then a else gcd(b, mod(a, b))
def abs_i64(x: i64) -> i64 = if lt(x, 0i64) then neg(x) else x
def reduced(numerator: i64, denominator: i64) -> YearFraction = {
  g = gcd(abs_i64(numerator), denominator)
  YearFraction { numerator: floor_div(numerator, g), denominator: floor_div(denominator, g) }
}
def year_fraction_numerator(f: YearFraction) -> i64 = f.numerator
def year_fraction_denominator(f: YearFraction) -> i64 = f.denominator
-- Correct rounding. A cast of an integer of magnitude at most 2^53 to f64 is
-- exact, and f64 division of two exact operands is one IEEE round-to-nearest-
-- even of the true quotient ([04-NUM-2]), so the f64 result is the correctly
-- rounded p/q.
--
-- For f32 the f64 quotient is rounded a second time, which is correct unless
-- the first rounding lands exactly on an f32 midpoint the true quotient is not
-- on. Take p/q in [2^E, 2^(E+1)) with E <= 23. The f32 midpoints there are
-- multiples of 2^(E-24), so a quotient off a midpoint m is at least
-- |p 2^(24-E) - M q| / (q 2^(24-E)) >= 2^(E-24) / q away from it, while the
-- f64 rounding moves it at most 2^(E-53). With q < 2^29 the first exceeds the
-- second, so the f64 result is never on a midpoint the quotient is not on,
-- and the second rounding is the correct one. Every convention here stays far
-- inside both bounds; a value outside them fails rather than round twice.
def two_pow_53() -> i64 = 9007199254740992i64
def two_pow_29() -> i64 = 536870912i64
def two_pow_24() -> i64 = 16777216i64
def year_fraction_to_f64(f: YearFraction) -> f64 = if gt(abs_i64(f.numerator), two_pow_53()) then fail("Shoals.Date.year_fraction_to_f64: domain: the numerator exceeds 2^53 in magnitude") else if gt(f.denominator, two_pow_53()) then fail("Shoals.Date.year_fraction_to_f64: domain: the denominator exceeds 2^53") else div(cast(f.numerator, f64), cast(f.denominator, f64))
def year_fraction_to_f32(f: YearFraction) -> f32 = if gte(f.denominator, two_pow_29()) then fail("Shoals.Date.year_fraction_to_f32: domain: the denominator is not below 2^29") else if gte(abs_i64(f.numerator), mul(f.denominator, two_pow_24())) then fail("Shoals.Date.year_fraction_to_f32: domain: the magnitude is not below 2^24") else cast(year_fraction_to_f64(f), f32)
def days(start: Date, end: Date) -> i64 = date_days_until(start, end)
def year_length(year: i64) -> i64 = if is_leap_year(year) then 366i64 else 365i64
-- ACT/ACT ISDA: a whole interior year counts exactly 1, and only the head and
-- tail stubs are divided, each by its own year's length.
def isda(start: Date, end: Date) -> YearFraction = {
  y_lo = date_year(start)
  y_hi = date_year(end)
  if eq(y_lo, y_hi) then reduced(days(start, end), year_length(y_lo)) else {
    head = days(start, date(add(y_lo, 1i64), 1i64, 1i64))
    tail = days(date(y_hi, 1i64, 1i64), end)
    l_lo = year_length(y_lo)
    l_hi = year_length(y_hi)
    interior = sub(sub(y_hi, y_lo), 1i64)
    reduced(add(add(mul(head, l_hi), mul(tail, l_lo)), mul(interior, mul(l_lo, l_hi))), mul(l_lo, l_hi))
  }
}
-- ACT/ACT ICMA for an accrual inside one reference coupon period. An accrual
-- that leaves the period belongs to a different period, so it fails rather
-- than be scaled by the wrong one.
def icma(start: Date, end: Date, reference_start: Date, reference_end: Date, frequency: i64) -> YearFraction = if lt(frequency, 1i64) then fail(domain_failure(joined(["ACT/ACT ICMA frequency ", to_string(frequency), " is below 1"]))) else if date_lte(reference_end, reference_start) then fail(domain_failure(joined(["ACT/ACT ICMA reference period ", date_to_string(reference_start), "..", date_to_string(reference_end), " is empty"]))) else if or(date_lt(start, reference_start), date_lt(reference_end, end)) then fail(domain_failure(joined(["accrual ", date_to_string(start), "..", date_to_string(end), " is outside the ACT/ACT ICMA reference period ", date_to_string(reference_start), "..", date_to_string(reference_end)]))) else reduced(days(start, end), mul(frequency, days(reference_start, reference_end)))
def thirty_360(start: Date, end: Date, d1: i64, d2: i64) -> YearFraction = reduced(add(add(mul(360i64, sub(date_year(end), date_year(start))), mul(30i64, sub(date_month(end), date_month(start)))), sub(d2, d1)), 360i64)
def is_month_end(d: Date) -> bool = eq(date_day(d), days_in_month(date_year(d), date_month(d)))
def is_february_end(d: Date) -> bool = and(eq(date_month(d), 2i64), is_month_end(d))
def thirty_e(start: Date, end: Date) -> YearFraction = thirty_360(start, end, if eq(date_day(start), 31i64) then 30i64 else date_day(start), if eq(date_day(end), 31i64) then 30i64 else date_day(end))
-- 30E/360 ISDA: a month-end day counts as 30, except an end date that is the
-- last day of February and also the maturity date.
def thirty_e_isda(start: Date, end: Date, maturity: Date) -> YearFraction = {
  d1 = if is_month_end(start) then 30i64 else date_day(start)
  end_is_maturity_february = and(is_february_end(end), and(date_lte(end, maturity), date_lte(maturity, end)))
  d2 = if and(is_month_end(end), not(end_is_maturity_february)) then 30i64 else date_day(end)
  thirty_360(start, end, d1, d2)
}
-- 30/360 US, rules applied in order: with the end-of-month flag, a February
-- month-end end date after a February month-end start counts 30, and a
-- February month-end start counts 30; then an end day of 31 after a start day
-- of 30 or 31 counts 30; then a start day of 31 counts 30.
def thirty_us(start: Date, end: Date, end_of_month: bool) -> YearFraction = {
  feb_start = and(end_of_month, is_february_end(start))
  d2_feb = if and(feb_start, is_february_end(end)) then 30i64 else date_day(end)
  d1_feb = if feb_start then 30i64 else date_day(start)
  d2 = if and(eq(d2_feb, 31i64), gte(d1_feb, 30i64)) then 30i64 else d2_feb
  d1 = if eq(d1_feb, 31i64) then 30i64 else d1_feb
  thirty_360(start, end, d1, d2)
}
def bus_252(start: Date, end: Date, calendar: BusinessCalendar) -> YearFraction = reduced(business_day_count(calendar, start, end), 252i64)
-- Every convention measures a forward accrual: an end before the start fails
-- instead of returning a negated fraction.
def year_fraction(start: Date, end: Date, convention: DayCount) -> YearFraction =
  if date_lt(end, start) then fail(domain_failure(joined(["end ", date_to_string(end), " is before start ", date_to_string(start)]))) else match convention with {
    | ActualOver360 => reduced(days(start, end), 360i64)
    | ActualOver365Fixed => reduced(days(start, end), 365i64)
    | ActualActualIsda => isda(start, end)
    | ActualActualIcma { reference_start: rs, reference_end: re, frequency: f } => icma(start, end, rs, re, f)
    | ThirtyEOver360 => thirty_e(start, end)
    | ThirtyEOver360Isda { maturity: m } => thirty_e_isda(start, end, m)
    | ThirtyOver360Us { end_of_month: eom } => thirty_us(start, end, eom)
    | Business252 { calendar: c } => bus_252(start, end, c)
  }
