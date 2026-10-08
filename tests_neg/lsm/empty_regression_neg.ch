module Shoals.TestsNeg.LsmEmptyRegression
import Shoals.Lsm (lsm_polynomial_regression)
import Std.Test (assert_true)
-- shoals#152: this input has no finite numerical answer under the contract.
-- The sidecar pins the refusal diagnostic, not merely any failed assertion.
def test_neg_empty_regression() -> unit ! { Test } = {
  result = lsm_polynomial_regression(to_tensor([], f32), to_tensor([], f32)).0
  assert_true(eq(result, result), "should refuse the invalid input before computing a price or fit")
}
