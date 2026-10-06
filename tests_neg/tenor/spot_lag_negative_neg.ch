module Shoals.TestsNeg.TenorSpotLagNegative
import Std.Test (assert_eq)
import Std.Datetime (date)
import Std.Datetime.Business (Following)
import Shoreleave.UsFederal (us_federal)
import Shoals.Tenor (spot_lag, spot_date)
-- Spot lies on or after the trade date.
def test_neg_spot_lag_rejects_a_negative_lag() -> unit ! { Test } = assert_eq(spot_date(spot_lag(-1i64, us_federal(), us_federal(), Following), date(2025i64, 7i64, 2i64)), date(2025i64, 7i64, 1i64), "a negative lag must fail")
