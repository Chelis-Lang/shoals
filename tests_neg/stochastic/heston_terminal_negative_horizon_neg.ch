module Shoals.TestsNeg.HestonTerminalNegativeHorizon
import Std.Test (assert_true)
import Shoals.Stochastic (heston_qe_terminal)
-- Negative: a negative time horizon has no path to sample. `sqrt(t)` is NaN,
-- so before shoals#139 this sampler returned NaN for every value with no
-- diagnostic. checked_horizon refuses at the sampler's entry instead.
--
-- The assertion below is deliberately one that NaN also fails, so removing the
-- guard does not make this file pass by accident: it would then fail on the
-- assertion rather than on the refusal, and `--expect neg` checks the
-- diagnostic text, not merely that something failed.
def test_neg_heston_terminal_negative_horizon() -> unit ! { Test } = {
  out = heston_qe_terminal(key_from_seed(7i64), cast(100.0, f32), cast(0.04, f32), cast(0.05, f32), cast(1.5, f32), cast(0.04, f32), cast(0.3, f32), cast(-0.5, f32), cast(-1.0, f32), cast(8, i64))
  assert_true(eq(out.0, out.0), "should not reach here: unguarded this returned a NaN terminal spot, via dt = t / n_steps")
}
