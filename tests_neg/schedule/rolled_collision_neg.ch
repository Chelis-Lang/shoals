module Shoals.TestsNeg.ScheduleRolledCollision
import Std.Test (assert_eq)
import Std.Datetime (date, ClampToMonthEnd)
import Std.Datetime.Business (Following)
import Shoreleave.UsFederal (us_federal)
import Shoals.Tenor (tenor_days)
import Shoals.Schedule (NoStub, schedule)
-- Daily dates over a weekend roll onto the same Monday.
def test_neg_schedule_rejects_colliding_rolled_dates() -> unit ! { Test } = assert_eq(schedule(date(2025i64, 7i64, 4i64), date(2025i64, 7i64, 7i64), tenor_days(1i64), NoStub, false, ClampToMonthEnd, us_federal(), Following), [], "colliding dates must fail")
