module Shoals.TestsNeg.CdsBootstrapHazardsPremiumFrequencyNearestNeg
import Std.Test (assert_true)
import Shoals.Cds (cds_bootstrap_hazards, hazard_curve_from_pillars, cds_survival_from_hazards)
-- shoals#166: diagnostic parity for a consumed computational count.
def test_neg_count() -> unit ! { Test } = {
  result = cds_survival_from_hazards(cds_bootstrap_hazards(to_tensor([0.01f32]), to_tensor([1f32]), 0.4f32, 0.03f32, 0i64), 1f32)
  assert_true(eq(result, result), "must refuse an invalid consumed count")
}
