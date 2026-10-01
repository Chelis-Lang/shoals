module Shoals.TestsNeg.IndicatorsTensorOverlongWarmup
import Std.Test (assert_eq)
import Shoals.Indicators (tensor_crossover)
-- A warm-up past the end of the series used to return an all-`None` series.
-- spec/shoals_quant_surface.md §2.15.6 names that in so many words as the wrong
-- answer to a caller bug: it reports "no data" for what is a bad call. A
-- warm-up EQUAL to the length stays legal -- a producing indicator whose window
-- exceeded the series legitimately warms up for all of it -- so only strictly
-- greater traps.
def series() -> tensor[3, f64] = to_tensor([cast(1.0, f64), cast(2.0, f64), cast(3.0, f64)])
def test_neg_tensor_crossover_rejects_overlong_warmup() -> unit ! { Test } = assert_eq(len(tensor_crossover(series(), cast(99, i64), series(), cast(0, i64))), cast(3, i64), "a warm-up past the end must trap, not return all-None")
