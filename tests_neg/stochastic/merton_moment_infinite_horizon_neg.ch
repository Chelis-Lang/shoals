module Shoals.TestsNeg.MertonMomentInfiniteHorizon
import Std.Test (assert_true)
import Shoals.Stochastic (merton_sampler_log_jump_moment)
def test_neg_merton_moment_infinite_horizon() -> unit ! { Test } = {
  value = merton_sampler_log_jump_moment(0.0, 0.1, 0.2, div(1.0, 0.0))
  assert_true(eq(value, value), "invalid jump model must refuse before returning a moment")
}
