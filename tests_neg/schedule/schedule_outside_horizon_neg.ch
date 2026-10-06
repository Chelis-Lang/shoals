module Shoals.TestsNeg.ScheduleOutsideHorizon
import Std.Test (assert_eq)
import Std.Datetime (date, ClampToMonthEnd)
import Std.Datetime.Business (Following)
import Shoreleave.UsFederal (us_federal)
import Shoals.Tenor (tenor_years)
import Shoals.Schedule (NoStub, schedule)
-- Rolling a 2031 date needs calendar data the US federal horizon (2021-2030) lacks.
def test_neg_schedule_rejects_dates_outside_the_horizon() -> unit ! { Test } = assert_eq(schedule(date(2029i64, 6i64, 3i64), date(2031i64, 6i64, 3i64), tenor_years(1i64), NoStub, false, ClampToMonthEnd, us_federal(), Following), [], "a date outside the horizon must fail")
