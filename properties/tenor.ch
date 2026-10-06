module Shoals.Properties.Tenor
import Std.Datetime (Date, ClampToMonthEnd, RejectInvalidDay, date_lt, date_lte, date_year, date_month, date_day, days_in_month)
import Shoals.Tenor (tenor_months)
import Shoals.Schedule (StubConvention, ShortFinal, schedule_unadjusted)
export (schedule_is_increasing_and_bounded, reject_agrees_with_clamp)
-- A short-final monthly schedule starts at the start, ends at the end, and is
-- strictly increasing, whatever the day of month.
def schedule_is_increasing_and_bounded(start: Date, end: Date, months: i64) -> bool = {
  xs = schedule_unadjusted(start, end, tenor_months(months), ShortFinal, false, ClampToMonthEnd)
  n = len(xs)
  bounds = and(and(date_lte(index(xs, 0i64), start), date_lte(start, index(xs, 0i64))), and(date_lte(index(xs, sub(n, 1i64)), end), date_lte(end, index(xs, sub(n, 1i64)))))
  and(bounds, fold(fn (acc: bool, i: i64) -> and(acc, date_lt(index(xs, sub(i, 1i64)), index(xs, i))), true, range(1i64, n)))
}
-- RejectInvalidDay judges only the dates a schedule emits. When the clamped
-- schedule emits no step whose day was clamped, every emitted date exists, so
-- the rejecting schedule is the same list; a spurious failure on a step that
-- is not emitted fails this property by trapping. `anchor` is the date the
-- steps count from: the start for a final stub, the end for an initial one.
-- The far boundary must not be a date a clamped step lands on exactly, where
-- regularity depends on the policy by design.
def reject_agrees_with_clamp(start: Date, end: Date, months: i64, stub: StubConvention, end_of_month: bool, anchor: Date) -> bool = {
  clamped = schedule_unadjusted(start, end, tenor_months(months), stub, end_of_month, ClampToMonthEnd)
  anchor_is_month_end = eq(date_day(anchor), days_in_month(date_year(anchor), date_month(anchor)))
  by_rule = and(end_of_month, anchor_is_month_end)
  steps = map(fn (i: i64) -> index(clamped, i), range(1i64, sub(len(clamped), 1i64)))
  was_clamped = fold(fn (acc: bool, d: Date) -> or(acc, gt(date_day(anchor), days_in_month(date_year(d), date_month(d)))), false, steps)
  if or(by_rule, not(was_clamped)) then eq(schedule_unadjusted(start, end, tenor_months(months), stub, end_of_month, RejectInvalidDay), clamped) else true
}
