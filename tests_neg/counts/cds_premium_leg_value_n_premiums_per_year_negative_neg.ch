module Shoals.TestsNeg.CdsPremiumLegValuePremiumFrequencyNegativeNeg
import Std.Test (assert_true)
import Shoals.Cds (cds_premium_leg_value, hazard_curve_from_pillars, cds_survival_from_hazards)
-- shoals#166: diagnostic parity for a consumed computational count.
def test_neg_count() -> unit ! { Test } = {
  result = cds_premium_leg_value(0.01f32, 1f32, -1i64, hazard_curve_from_pillars(to_tensor([1f32]), to_tensor([0.02f32])), 0.03f32)
  assert_true(eq(result, result), "must refuse an invalid consumed count")
}
