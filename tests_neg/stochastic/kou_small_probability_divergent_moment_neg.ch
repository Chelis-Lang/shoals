module Shoals.TestsNeg.KouSmallProbabilityDivergentMoment
import Std.Test (assert_true)
import Shoals.Stochastic (sto_kou_sampler_log_jump_moment)
-- shoals#146: only exact zero probability with a finite placeholder relaxes the upward-rate bound.
def test_neg_kou_small_probability_divergent_moment() -> unit ! { Test } = {
  value = sto_kou_sampler_log_jump_moment(1.0f32, 1e-6f32, 1.0f32, 3.0f32, 1.0f32)
  assert_true(eq(value, value), "The invalid moment must be refused before returning a value")
}
