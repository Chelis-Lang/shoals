module Shoals.TestsNeg.KouMomentNegativeHorizonZeroIntensity
import Std.Test (assert_true)
import Shoals.Stochastic (sto_kou_sampler_log_jump_moment)
def test_neg_kou_moment_negative_horizon_zero_intensity() -> unit ! { Test } = {
  value = sto_kou_sampler_log_jump_moment(0.0, 0.5, 3.0, 4.0, -1.0)
  assert_true(eq(value, value), "invalid jump model must refuse before returning a moment")
}
