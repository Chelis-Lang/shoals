module Shoals.Properties.Tenor
import Std.Datetime (Date, ClampToMonthEnd, date_lt, date_lte)
import Shoals.Tenor (tenor_months)
import Shoals.Schedule (ShortFinal, schedule_unadjusted)
export (schedule_is_increasing_and_bounded)
-- A short-final monthly schedule starts at the start, ends at the end, and is
-- strictly increasing, whatever the day of month.
def schedule_is_increasing_and_bounded(start: Date, end: Date, months: i64) -> bool = {
  xs = schedule_unadjusted(start, end, tenor_months(months), ShortFinal, false, ClampToMonthEnd)
  n = len(xs)
  bounds = and(and(date_lte(index(xs, 0i64), start), date_lte(start, index(xs, 0i64))), and(date_lte(index(xs, sub(n, 1i64)), end), date_lte(end, index(xs, sub(n, 1i64)))))
  and(bounds, fold(fn (acc: bool, i: i64) -> and(acc, date_lt(index(xs, sub(i, 1i64)), index(xs, i))), true, range(1i64, n)))
}
