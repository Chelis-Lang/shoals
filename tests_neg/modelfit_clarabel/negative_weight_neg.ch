module Shoals.TestsNeg.ModelFitClarabelNegativeWeight
import Clarabel.Qp (Settings)
import Shoals.ModelFitClarabel (lm_bounded_nparam)
def identity_model[n, m](theta: &tensor[n, f64], features: &tensor[m, f64]) -> tensor[m, f64] = copy(features)
def test_neg_rejects_negative_weight() -> unit ! { Test } = {
  result = lm_bounded_nparam(identity_model, to_tensor([0.0f64]), to_tensor([1.0f64]), to_tensor([-1.0f64]), to_tensor([0.0f64]), to_tensor([-2.0f64]), to_tensor([2.0f64]), 0.01f64, 1e-6f64, 3i64, 0.00001f64, 1e-6f64, Settings { max_iterations: 200i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 })
  fail("should not reach here")
}
