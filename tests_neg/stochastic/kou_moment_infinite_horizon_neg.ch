module Shoals.TestsNeg.KouMomentInfiniteHorizon
import Std.Test (assert_true)
import Shoals.Stochastic (sto_kou_sampler_log_jump_moment)
def test_neg_kou_moment_infinite_horizon() -> unit ! { Test } = {
  value = sto_kou_sampler_log_jump_moment(0.0, 0.5, 3.0, 4.0, div(1.0, 0.0))
  assert_true(eq(value, value), "invalid jump model must refuse before returning a moment")
}
