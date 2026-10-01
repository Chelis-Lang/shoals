module Shoals.TestsNeg.IndicatorsTensorNegativeWarmup
import Std.Test (assert_eq)
import Shoals.Indicators (tensor_crossover)
-- A negative warm-up used to read silently as 0, because the mask test is
-- `lt(i, warmup)` and no index is below a negative bound. That is the same
-- defect shape `ind_shift` traps ("a negative shift reads the future"), on the
-- one integer the tensor surface accepts that the list surface does not.
--
-- The assertion is the length an UNGUARDED implementation would return, so if
-- the guard is removed this probe PASSES and `--expect neg` flags the file.
def series() -> tensor[3, f64] = to_tensor([cast(1.0, f64), cast(2.0, f64), cast(3.0, f64)])
def test_neg_tensor_crossover_rejects_negative_warmup() -> unit ! { Test } = assert_eq(len(tensor_crossover(series(), cast(-1, i64), series(), cast(0, i64))), cast(3, i64), "a negative warm-up must trap, not read as 0")
