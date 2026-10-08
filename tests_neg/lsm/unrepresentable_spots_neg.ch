module Shoals.TestsNeg.LsmUnrepresentableSpots
import Shoals.Lsm (lsm_american_put)
import Std.Test (assert_true)
-- shoals#163: the log is finite but its simulated spot exceeds f32 range.
def test_neg_unrepresentable_spots() -> unit ! { Test } = {
  result = lsm_american_put(key_from_seed(17i64), to_tensor([0f32]), 100f32, 100f32, 100f32, 0f32, 1f32, 1i64)
  assert_true(eq(result, result), "should refuse an unrepresentable simulated spot before payoff hides it")
}
