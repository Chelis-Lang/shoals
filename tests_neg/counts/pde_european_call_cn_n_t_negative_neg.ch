module Shoals.TestsNeg.PdeEuropeanCallCnTimeCountNegativeNeg
import Std.Test (assert_true)
import Shoals.Pde (pde_european_call_cn)
-- shoals#166: diagnostic parity for a consumed computational count.
def test_neg_count() -> unit ! { Test } = {
  result = pde_european_call_cn(100f32, 100f32, 0.05f32, 0f32, 0.2f32, 1f32, 3i64, -1i64, 2f32)
  assert_true(eq(result, result), "must refuse an invalid consumed count")
}
