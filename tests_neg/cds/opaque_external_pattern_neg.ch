module Shoals.TestsNeg.CdsOpaqueExternalPattern
import Shoals.Cds (HazardCurve, hazard_curve_from_pillars)
def test_neg_cds_rejects_external_pattern() -> unit ! { Test } = {
  curve = hazard_curve_from_pillars(to_tensor([1.0f32, 2.0f32]), to_tensor([0.01f32, 0.05f32]))
  _ = match curve with {
    | HazardCurve { times: _, hazards: hs } => hs
  }
  ()
}
