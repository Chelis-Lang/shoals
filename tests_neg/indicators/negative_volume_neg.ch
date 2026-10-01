module Shoals.TestsNeg.IndicatorsNegativeVolume
import Std.Test (assert_eq)
import Shoals.Indicators (cumulative_vwap)
-- Negative volume is a data error, not a weighting. Admitting it would let a
-- VWAP fall outside the range of its own prices, which no caller could
-- detect from the result.
def test_neg_vwap_rejects_negative_volume() -> unit ! { Test } = assert_eq(len(cumulative_vwap([cast(10.0, f64), cast(11.0, f64)], [cast(5.0, f64), cast(-1.0, f64)])), cast(2, i64), "negative volume must trap")
