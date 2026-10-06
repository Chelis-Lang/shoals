module Shoals.Tenor
import Std.Datetime (Date, Period, DayOverflow, period, period_months, period_days, date_add_period)
import Std.Datetime.Business (BusinessCalendar, BusinessDayRoll, NonBusinessStart, RejectNonBusinessStart, RollStartForward, is_business_day, business_day_offset, business_day_roll)
export (Tenor, tenor_days, tenor_weeks, tenor_months, tenor_years, tenor_period, tenor_apply, parse_tenor, try_parse_tenor, BusinessDayTenor, overnight, tomorrow_next, spot_next, business_day_tenor_lag, business_day_tenor_length, business_day_tenor_dates, SpotLag, two_calendar_lag, lagged_date)
-- A tenor is a positive `Std.Datetime.Period`: a month is a calendar month and
-- a year is twelve of them, never a fixed number of days. Applying one takes
-- the caller's `DayOverflow` policy, because a month step from the 31st has
-- no day-31 answer in a 30-day month.
@opaque
type Tenor =
  | Tenor { period: Period }
def tenor_failure(function: string, detail: string) -> string = string_concat(string_concat("Shoals.Tenor.", function), string_concat(": domain: ", detail))
def positive_count(function: string, n: i64) -> i64 = if lt(n, 1i64) then fail(tenor_failure(function, string_concat(string_concat("count ", to_string(n)), " is below 1"))) else n
def tenor_days(n: i64) -> Tenor = Tenor { period: period(0i64, positive_count("tenor_days", n)) }
def tenor_weeks(n: i64) -> Tenor = Tenor { period: period(0i64, mul(7i64, positive_count("tenor_weeks", n))) }
def tenor_months(n: i64) -> Tenor = Tenor { period: period(positive_count("tenor_months", n), 0i64) }
def tenor_years(n: i64) -> Tenor = Tenor { period: period(mul(12i64, positive_count("tenor_years", n)), 0i64) }
def tenor_period(t: Tenor) -> Period = t.period
def tenor_apply(t: Tenor, reference: Date, overflow: DayOverflow) -> Date = date_add_period(reference, t.period, overflow)
-- The grammar is exactly: one or more ASCII digits with a value of at least 1,
-- then one of D, W, M, Y. No sign, space, or other unit is accepted.
def is_digit(c: string) -> bool = fold(fn (acc: bool, digit: string) -> or(acc, eq(c, digit)), false, ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
def all_digits(text: string) -> bool = fold(fn (acc: bool, i: i64) -> and(acc, is_digit(string_slice(text, i, 1i64))), true, range(0i64, string_len(text)))
def try_parse_tenor(text: string) -> Option[Tenor] = {
  n = string_len(text)
  if lt(n, 2i64) then None else {
    digits = string_slice(text, 0i64, sub(n, 1i64))
    unit = string_slice(text, sub(n, 1i64), 1i64)
    if not(all_digits(digits)) then None else match to_int(digits) with {
      | None => None
      | Some(count) => if lt(count, 1i64) then None else if eq(unit, "D") then Some(tenor_days(count)) else if eq(unit, "W") then Some(tenor_weeks(count)) else if eq(unit, "M") then Some(tenor_months(count)) else if eq(unit, "Y") then Some(tenor_years(count)) else None
    }
  }
}
def parse_tenor(text: string) -> Tenor =
  match try_parse_tenor(text) with {
    | Some(t) => t
    | None => fail(tenor_failure("parse_tenor", string_concat(string_concat("\"", text), "\" is not a count of at least 1 followed by D, W, M or Y")))
  }
-- ON, TN and SN are money-market tenors measured in business days: the start
-- lies `lag` business days after the trade date and the end `length` business
-- days after the start. Spot-next starts at spot, whose lag the caller states.
type BusinessDayTenor =
  | BusinessDayTenor { lag: i64, length: i64 }
def overnight() -> BusinessDayTenor = BusinessDayTenor { lag: 0i64, length: 1i64 }
def tomorrow_next() -> BusinessDayTenor = BusinessDayTenor { lag: 1i64, length: 1i64 }
def spot_next(spot_days: i64) -> BusinessDayTenor = if lt(spot_days, 0i64) then fail(tenor_failure("spot_next", string_concat(string_concat("spot lag ", to_string(spot_days)), " is negative"))) else BusinessDayTenor { lag: spot_days, length: 1i64 }
def business_day_tenor_lag(t: BusinessDayTenor) -> i64 = t.lag
def business_day_tenor_length(t: BusinessDayTenor) -> i64 = t.length
def business_day_tenor_dates(t: BusinessDayTenor, trade: Date, calendar: BusinessCalendar, start: NonBusinessStart) -> (Date, Date) = {
  first = business_day_offset(calendar, trade, t.lag, start)
  (first, business_day_offset(calendar, first, t.length, RejectNonBusinessStart))
}
-- Spot lag in the two-calendar form of OpenGamma Strata's DaysAdjustment:
-- count `days` business days in `count_calendar`, then roll the result in
-- `adjust_calendar`. Counting from a non-business trade date, the first step
-- lands on the next business day.
type SpotLag =
  | SpotLag { days: i64, count_calendar: BusinessCalendar, adjust_calendar: BusinessCalendar, roll: BusinessDayRoll }
def two_calendar_lag(days: i64, count_calendar: BusinessCalendar, adjust_calendar: BusinessCalendar, roll: BusinessDayRoll) -> SpotLag = if lt(days, 0i64) then fail(tenor_failure("two_calendar_lag", string_concat(string_concat("lag ", to_string(days)), " is negative"))) else SpotLag { days, count_calendar, adjust_calendar, roll }
def counted(lag: SpotLag, trade: Date) -> Date = if eq(lag.days, 0i64) then trade else if is_business_day(lag.count_calendar, trade) then business_day_offset(lag.count_calendar, trade, lag.days, RejectNonBusinessStart) else business_day_offset(lag.count_calendar, trade, sub(lag.days, 1i64), RollStartForward)
def lagged_date(lag: SpotLag, trade: Date) -> Date = business_day_roll(lag.adjust_calendar, counted(lag, trade), lag.roll)
