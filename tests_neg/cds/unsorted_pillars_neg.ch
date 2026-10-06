module Shoals.TestsNeg.CdsUnsortedPillars
import Shoals.Cds (hazard_curve_from_pillars, cds_survival_from_hazards)
def test_neg_cds_rejects_unsorted_pillars() -> unit ! { Test } = {
  curve = hazard_curve_from_pillars(to_tensor([1.0f32, 3.0f32, 2.0f32]), to_tensor([0.01f32, 0.2f32, 0.05f32]))
  _ = cds_survival_from_hazards(curve, 2.5f32)
  ()
}
