module Shoals.TestsNeg.MertonNegativeJumpRate
import Std.Test (assert_true)
import Nautilus.Stats (mean_vec)
import Shoals.Stochastic (merton_jump_terminal)
-- A negative intensity must refuse before constructing the jump-count table.
-- The sidecar requires its diagnostic rather than an incidental NaN failure.
def test_neg_merton_rejects_negative_jump_rate() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  paths = merton_jump_terminal(key_from_seed(3i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(-1.0, f32), cast(0.1, f32), cast(0.2, f32), cast(1.0, f32))
  assert_true(gt(mean_vec(paths), cast(0.0, f32)), "should not reach here: unguarded this returned NaN terminal values from a negative aggregate jump variance")
}
