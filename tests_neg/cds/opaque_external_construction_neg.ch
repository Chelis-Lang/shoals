module Shoals.TestsNeg.CdsOpaqueExternalConstruction
import Shoals.Cds (HazardCurve, cds_survival_from_hazards)
def test_neg_cds_rejects_external_construction() -> unit ! { Test } = {
  curve = HazardCurve { times: to_tensor([1.0f32, 3.0f32, 2.0f32]), hazards: to_tensor([0.01f32, 0.2f32, 0.05f32]) }
  _ = cds_survival_from_hazards(curve, 2.5f32)
  ()
}
