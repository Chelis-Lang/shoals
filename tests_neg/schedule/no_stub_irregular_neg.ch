module Shoals.TestsNeg.ScheduleNoStubIrregular
import Std.Test (assert_eq)
import Std.Datetime (date, ClampToMonthEnd)
import Shoals.Tenor (tenor_months)
import Shoals.Schedule (NoStub, schedule_unadjusted)
-- NoStub states the tenor divides the span; 15 January to 31 December is not whole quarters.
def test_neg_no_stub_rejects_an_irregular_span() -> unit ! { Test } = assert_eq(schedule_unadjusted(date(2025i64, 1i64, 15i64), date(2025i64, 12i64, 31i64), tenor_months(3i64), NoStub, false, ClampToMonthEnd), [], "an irregular span must fail")
