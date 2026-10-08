module Shoals.TestsNeg.KouSmallProbabilityDivergentTerminal
import Std.Test (assert_true)
import Shoals.Stochastic (sto_kou_jump_terminal)
-- shoals#146: only exact zero probability with a finite placeholder relaxes the upward-rate bound.
def test_neg_kou_small_probability_divergent_terminal() -> unit ! { Test } = {
  template = to_tensor([0.0f32])
  paths = sto_kou_jump_terminal(key_from_seed(3i64), copy(template), template, 100.0f32, 0.05f32, 0.2f32, 1.0f32, 1e-6f32, 0.0f32, 3.0f32, 1.0f32)
  value = index(to_list(paths), 0i64)
  assert_true(gt(value, 0.0f32), "The invalid terminal law must be refused before returning a price")
}
