module Shoals.TestsNeg.TenorSpotOutsideHorizon
import Std.Test (assert_eq)
import Std.Datetime (date)
import Std.Datetime.Business (Following)
import Shoreleave.UsFederal (us_federal)
import Shoals.Tenor (two_calendar_lag, lagged_date)
-- The US federal calendar ends in 2030; spot in 2031 has no answer.
def test_neg_spot_date_rejects_a_trade_outside_the_horizon() -> unit ! { Test } = assert_eq(lagged_date(two_calendar_lag(2i64, us_federal(), us_federal(), Following), date(2031i64, 3i64, 3i64)), date(2031i64, 3i64, 5i64), "a trade outside the horizon must fail")
