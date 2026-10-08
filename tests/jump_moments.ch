module Shoals.Tests.JumpMoments
import Std.Test (assert_close)
import Shoals.Stochastic (merton_sampler_log_jump_moment, sto_kou_sampler_log_jump_moment)
def test_jump_moments_positive_inputs_unchanged() -> unit ! { Test } = {
  _ = assert_close(merton_sampler_log_jump_moment(4.0, 0.1, 0.2, 1.0), 0.50998753, 2e-6, "Merton positive rate")
  assert_close(sto_kou_sampler_log_jump_moment(4.0, 0.5, 3.0, 4.0, 1.0), 0.6000001, 2e-6, "Kou positive rate")
}
def test_jump_moments_zero_intensity_and_horizon() -> unit ! { Test } = {
  _ = assert_close(merton_sampler_log_jump_moment(0.0, 0.1, 0.2, 1.0), 0.0, 1e-6, "Merton zero intensity")
  _ = assert_close(merton_sampler_log_jump_moment(4.0, 0.1, 0.2, 0.0), 0.0, 1e-6, "Merton zero horizon")
  _ = assert_close(sto_kou_sampler_log_jump_moment(0.0, 0.5, 3.0, 4.0, 1.0), 0.0, 1e-6, "Kou zero intensity")
  assert_close(sto_kou_sampler_log_jump_moment(4.0, 0.5, 3.0, 4.0, 0.0), 0.0, 1e-6, "Kou zero horizon")
}
