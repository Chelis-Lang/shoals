module Shoals.TestsNeg.LsmNonpositiveStrike
import Shoals.Lsm (lsm_american_put)
import Std.Test (assert_true)
-- shoals#152: this input has no finite numerical answer under the contract.
-- The sidecar pins the refusal diagnostic, not merely any failed assertion.
def test_neg_nonpositive_strike() -> unit ! { Test } = {
  result = lsm_american_put(key_from_seed(1i64), to_tensor([0f32]), 100f32, 0f32, 0.05f32, 0.2f32, 1f32, 1i64)
  assert_true(eq(result, result), "should refuse the invalid input before computing a price or fit")
}
