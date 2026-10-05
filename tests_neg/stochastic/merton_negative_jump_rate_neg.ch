module Shoals.TestsNeg.MertonNegativeJumpRate
import Std.Test (assert_true)
import Nautilus.Stats (mean_vec)
import Shoals.Stochastic (merton_jump_terminal)
-- Negative: a negative jump intensity has no Poisson law, so there is no jump
-- count to draw and no exponential moment to compensate. Before shoals#98 the
-- aggregate log jump was a Gaussian whose variance was lambda*t*(b^2 + a^2),
-- which is NEGATIVE here, so `sqrt` of it gave NaN and every terminal value
-- came back NaN -- a wrong answer dressed as an answer. The enumerated
-- sampler refuses instead.
--
-- This is the negative-parity case for the `gte(rate, zero)` guard in
-- merton_jump_slots. The assertion is deliberately one that NaN also fails, so
-- removing the guard does not make this file pass by accident: it would then
-- fail on the assertion rather than on the refusal, and `--expect neg` checks
-- the diagnostic text, not merely that something failed.
def test_neg_merton_rejects_negative_jump_rate() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  paths = merton_jump_terminal(key_from_seed(3i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(-1.0, f32), cast(0.1, f32), cast(0.2, f32), cast(1.0, f32))
  assert_true(gt(mean_vec(paths), cast(0.0, f32)), "should not reach here: unguarded this returned NaN terminal values from a negative aggregate jump variance")
}
