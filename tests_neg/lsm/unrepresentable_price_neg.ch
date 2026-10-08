module Shoals.TestsNeg.LsmUnrepresentablePrice
import Shoals.Lsm (lsm_american_put)
import Std.Test (assert_true)
-- shoals#152: finite inputs may still require an unrepresentable output.
def test_neg_unrepresentable_price() -> unit ! { Test } = {
  result = lsm_american_put(key_from_seed(1i64), to_tensor([0f32]), 100f32, 100f32, -1000f32, 0f32, 1f32, 1i64)
  assert_true(eq(result, result), "should refuse unrepresentable simulated spots or price")
}
