module Shoals.Schedule
import Std.Datetime (Date, DayOverflow, ClampToMonthEnd, Period, days_in_month, date, date_year, date_month, date_day, date_days_until, date_lt, date_lte, date_add_period, try_date_add_period, period_mul, period_months, period_days, date_to_string)
import Std.Datetime.Business (BusinessCalendar, BusinessDayRoll, business_day_roll)
import Shoals.Tenor (Tenor, tenor_period)
export (StubConvention, NoStub, ShortInitial, LongInitial, ShortFinal, LongFinal, schedule, schedule_unadjusted)
-- Where an irregular period goes when the tenor does not divide the span.
-- `NoStub` requires an exact division and fails otherwise. A final stub
-- anchors the dates at the start, an initial stub at the end; a long stub
-- merges the irregular piece into its neighbouring regular period.
type StubConvention =
  | NoStub
  | ShortInitial
  | LongInitial
  | ShortFinal
  | LongFinal
def schedule_failure(detail: string) -> string = string_concat("Shoals.Schedule.schedule: domain: ", detail)
def same_date(a: Date, b: Date) -> bool = and(date_lte(a, b), date_lte(b, a))
def is_month_end(d: Date) -> bool = eq(date_day(d), days_in_month(date_year(d), date_month(d)))
def month_end_of(d: Date) -> Date = date(date_year(d), date_month(d), days_in_month(date_year(d), date_month(d)))
-- Every date is the anchor plus k whole tenors, never the previous date plus
-- one, so a clamped day of month cannot drift. With `end_of_month` and a
-- month-end anchor, a whole-month tenor keeps every date on its month end.
--
-- The caller's overflow policy applies only to dates the schedule emits.
-- Finding where the schedule stops uses clamped dates, which never fail, so
-- a step past the end that lands on a nonexistent day (30 February) cannot
-- fail the call. Under the end-of-month rule the month end is the day, so the
-- overflow policy has nothing to decide.
def located(anchor: Date, p: Period, k: i64, eom: bool) -> Date = {
  base = date_add_period(anchor, period_mul(p, k), ClampToMonthEnd)
  if eom then month_end_of(base) else base
}
def emitted(anchor: Date, p: Period, k: i64, eom: bool, overflow: DayOverflow) -> Date = if eom then located(anchor, p, k, true) else date_add_period(anchor, period_mul(p, k), overflow)
-- Whether anchor plus k tenors is exactly `target` under the caller's policy;
-- a step that does not exist under that policy lands nowhere.
def lands_on(anchor: Date, p: Period, k: i64, eom: bool, overflow: DayOverflow, target: Date) -> bool =
  if eom then same_date(located(anchor, p, k, true), target) else match try_date_add_period(anchor, period_mul(p, k), overflow) with {
    | Some(x) => same_date(x, target)
    | None => false
  }
def step_bound(start: Date, end: Date, p: Period) -> i64 = {
  span = date_days_until(start, end)
  if gt(period_months(p), 0i64) then add(floor_div(span, mul(28i64, period_months(p))), 2i64) else add(floor_div(span, period_days(p)), 2i64)
}
def is_final(stub: StubConvention) -> bool =
  match stub with {
    | ShortInitial => false
    | LongInitial => false
    | _ => true
  }
def is_long(stub: StubConvention) -> bool =
  match stub with {
    | LongInitial => true
    | LongFinal => true
    | _ => false
  }
def is_none(stub: StubConvention) -> bool =
  match stub with {
    | NoStub => true
    | _ => false
  }
def drop_last(xs: List[Date]) -> List[Date] = map(fn (i: i64) -> index(xs, i), range(0i64, sub(len(xs), 1i64)))
def drop_first(xs: List[Date]) -> List[Date] = map(fn (i: i64) -> index(xs, i), range(1i64, len(xs)))
def reversed(xs: List[Date]) -> List[Date] = map(fn (i: i64) -> index(xs, sub(sub(len(xs), 1i64), i)), range(0i64, len(xs)))
def schedule_unadjusted(start: Date, end: Date, tenor: Tenor, stub: StubConvention, end_of_month: bool, overflow: DayOverflow) -> List[Date] =
  if not(date_lt(start, end)) then fail(schedule_failure(string_concat(string_concat(string_concat("start ", date_to_string(start)), " is not before end "), date_to_string(end)))) else {
    p = tenor_period(tenor)
    forward = is_final(stub)
    anchor = if forward then start else end
    sign = if forward then 1i64 else -1i64
    eom = and(end_of_month, and(is_month_end(anchor), eq(period_days(p), 0i64)))
    candidates = map(fn (k: i64) -> located(anchor, p, mul(sign, k), eom), range(0i64, step_bound(start, end, p)))
    count = len(filter(fn (x: Date) -> if forward then date_lt(x, end) else date_lt(start, x), candidates))
    inside = map(fn (k: i64) -> emitted(anchor, p, mul(sign, k), eom, overflow), range(0i64, count))
    regular = lands_on(anchor, p, mul(sign, count), eom, overflow, if forward then end else start)
    if and(is_none(stub), not(regular)) then fail(schedule_failure(joined_text(["the tenor does not divide ", date_to_string(start), "..", date_to_string(end), " and the stub convention is NoStub"]))) else {
      merged = if and(is_long(stub), and(not(regular), gte(len(inside), 2i64))) then drop_last(inside) else inside
      if forward then append(merged, end) else concat([start], reversed(merged))
    }
  }
def joined_text(parts: List[string]) -> string = fold(fn (acc: string, part: string) -> string_concat(acc, part), "", parts)
-- Each date rolled in the calendar. Rolling must keep the dates strictly
-- increasing; two dates that roll onto the same business day fail.
def schedule(start: Date, end: Date, tenor: Tenor, stub: StubConvention, end_of_month: bool, overflow: DayOverflow, calendar: BusinessCalendar, roll: BusinessDayRoll) -> List[Date] = {
  rolled = map(fn (x: Date) -> business_day_roll(calendar, x, roll), schedule_unadjusted(start, end, tenor, stub, end_of_month, overflow))
  increasing = fold(fn (acc: bool, i: i64) -> and(acc, date_lt(index(rolled, sub(i, 1i64)), index(rolled, i))), true, range(1i64, len(rolled)))
  if increasing then rolled else fail(schedule_failure("two schedule dates roll onto the same business day"))
}
