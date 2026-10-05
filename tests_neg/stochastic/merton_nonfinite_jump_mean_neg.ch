module Shoals.TestsNeg.MertonNonfiniteJumpMean
import Std.Test (assert_true)
import Nautilus.Stats (mean_vec)
import Shoals.Stochastic (merton_jump_terminal)
-- Negative: a non-finite jump_mean. This is the case that slipped BOTH of the
-- other guards. `exp(-inf)` is zero, and the slot bound takes `max(1, tilt)`,
-- so the tilted mean came out as plain `lambda * t` and passed the rate check
-- and the cap check alike. The jump-count table then formed
-- `mul(cast(0, f32), -inf)` in its k=0 term, which is NaN, and every terminal
-- value came back NaN.
--
-- This is the negative-parity case for the `all_finite` guard, which tests
-- `sub(x, x) == 0` on both `lambda * t` and `jump_mean + 0.5 * jump_vol^2`.
-- That predicate is NaN-and-infinity aware in a way an ordering comparison is
-- not: `gte(nan, 0.0)` and `lte(nan, 4096.0)` are both false, which is why the
-- two ordering guards could not reject this and reported the wrong cause for
-- the inputs they did reject.
def test_neg_merton_rejects_nonfinite_jump_mean() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  paths = with seed(3i64) { merton_jump_terminal(template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(4.0, f32), log(cast(0.0, f32)), cast(0.2, f32), cast(1.0, f32)) }
  assert_true(gt(mean_vec(paths), cast(0.0, f32)), "should not reach here: unguarded this returned NaN for every path")
}
