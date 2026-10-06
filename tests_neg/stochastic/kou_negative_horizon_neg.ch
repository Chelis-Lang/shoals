module Shoals.TestsNeg.KouNegativeHorizon
import Std.Test (assert_true)
import Shoals.Stochastic (sto_kou_jump_terminal)
-- Negative: a negative time horizon has no path to sample. `sqrt(t)` is NaN,
-- so before shoals#139 this sampler returned NaN for every value with no
-- diagnostic. checked_horizon refuses at the sampler's entry instead.
--
-- The assertion below is deliberately one that NaN also fails, so removing the
-- guard does not make this file pass by accident: it would then fail on the
-- assertion rather than on the refusal, and `--expect neg` checks the
-- diagnostic text, not merely that something failed.
def template() -> tensor[8, f32] = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
def finite_count[n](xs: tensor[n, f32]) -> f32 = tensor_to_scalar(sum(cast(eq(copy(xs), xs), f32), 0))
def test_neg_kou_negative_horizon() -> unit ! { Test } = {
  paths = sto_kou_jump_terminal(key_from_seed(7i64), template(), template(), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.0, f32), cast(0.5, f32), cast(3.0, f32), cast(4.0, f32), cast(-1.0, f32))
  assert_true(eq(finite_count(paths), cast(8.0, f32)), "should not reach here: unguarded this returned NaN for every one of the eight paths, because lambda_jump = 0 makes lambda_jump * t equal -0.0 and the rate guard admits it")
}
