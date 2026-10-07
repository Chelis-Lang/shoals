module Shoals.TestsNeg.GbmTerminalInfiniteHorizon
import Std.Test (assert_true)
import Shoals.Stochastic (gbm_terminal)
-- Negative: the non-finite branch of checked_horizon. A horizon of +inf makes
-- both the log drift and `sigma * sqrt(t)` non-finite, so no path value was
-- usable before shoals#139 -- MEASURED as 3 NaN and 5 `+inf` of 8, not NaN at
-- every path: `inf - inf` is NaN for a negative draw and `+inf` for a positive
-- one, and seed 7 gives 5 positive draws of 8. The all-NaN case is a NEGATIVE
-- horizon, which is a different fixture. This file pins the FINITENESS
-- diagnostic, deliberately distinct from the non-negativity one:
-- `gte(nan, 0.0)` is false, so one ordering check alone would blame the wrong
-- cause.
--
-- The assertion is one that NaN also fails, so deleting the finiteness clause
-- makes this file report WRONG-DIAGNOSTIC rather than pass.
def template() -> tensor[8, f32] = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
def non_nan_count[n](xs: tensor[n, f32]) -> f32 = tensor_to_scalar(sum(cast(eq(copy(xs), xs), f32), 0))
def test_neg_gbm_terminal_infinite_horizon() -> unit ! { Test } = {
  paths = gbm_terminal(key_from_seed(7i64), template(), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), div(cast(1.0, f32), cast(0.0, f32)))
  assert_true(eq(non_nan_count(paths), cast(8.0, f32)), "should not reach here: unguarded a +inf horizon left no usable path value, measured 3 NaN and 5 +inf of 8")
}
