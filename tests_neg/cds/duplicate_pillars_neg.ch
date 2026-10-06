module Shoals.TestsNeg.CdsDuplicatePillars
import Shoals.Cds (hazard_curve_from_pillars)
def test_neg_cds_rejects_duplicate_pillars() -> unit ! { Test } = {
  _ = hazard_curve_from_pillars(to_tensor([1.0f32, 1.0f32]), to_tensor([0.01f32, 0.05f32]))
  ()
}
