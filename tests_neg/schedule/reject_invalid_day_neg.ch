module Shoals.TestsNeg.ScheduleRejectInvalidDay
import Std.Test (assert_eq)
import Std.Datetime (date, RejectInvalidDay)
import Shoals.Tenor (tenor_months)
import Shoals.Schedule (ShortFinal, schedule_unadjusted)
-- RejectInvalidDay refuses 31 January + 1M rather than clamp it.
def test_neg_schedule_rejects_an_invalid_day() -> unit ! { Test } = assert_eq(schedule_unadjusted(date(2025i64, 1i64, 31i64), date(2025i64, 6i64, 30i64), tenor_months(1i64), ShortFinal, false, RejectInvalidDay), [], "an invalid day must fail")
