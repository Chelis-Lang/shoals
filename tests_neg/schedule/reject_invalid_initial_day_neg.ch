module Shoals.TestsNeg.ScheduleRejectInvalidInitialDay
import Std.Test (assert_eq)
import Std.Datetime (date, RejectInvalidDay)
import Shoals.Tenor (tenor_months)
import Shoals.Schedule (ShortInitial, schedule_unadjusted)
-- Anchored at 31 May, the emitted date one month back is 31 April, which
-- RejectInvalidDay refuses rather than clamp.
def test_neg_schedule_rejects_an_emitted_invalid_day_before_the_end() -> unit ! { Test } = assert_eq(schedule_unadjusted(date(2025i64, 1i64, 15i64), date(2025i64, 5i64, 31i64), tenor_months(1i64), ShortInitial, false, RejectInvalidDay), [], "an emitted invalid day must fail")
