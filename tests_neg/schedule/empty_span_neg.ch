module Shoals.TestsNeg.ScheduleEmptySpan
import Std.Test (assert_eq)
import Std.Datetime (date, ClampToMonthEnd)
import Shoals.Tenor (tenor_months)
import Shoals.Schedule (ShortFinal, schedule_unadjusted)
-- A schedule needs a start before its end.
def test_neg_schedule_rejects_an_empty_span() -> unit ! { Test } = assert_eq(schedule_unadjusted(date(2025i64, 6i64, 1i64), date(2025i64, 6i64, 1i64), tenor_months(1i64), ShortFinal, false, ClampToMonthEnd), [], "an empty span must fail")
