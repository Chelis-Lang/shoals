module Shoals.TestsNeg.CdsBootstrapUnsortedTenors
import Shoals.Cds (cds_bootstrap_hazards)
def test_neg_cds_bootstrap_rejects_unsorted_tenors() -> unit ! { Test } = {
  _ = cds_bootstrap_hazards(to_tensor([0.01f32, 0.02f32, 0.03f32]), to_tensor([1.0f32, 3.0f32, 2.0f32]), 0.4f32, 0.03f32, 4i64)
  ()
}
