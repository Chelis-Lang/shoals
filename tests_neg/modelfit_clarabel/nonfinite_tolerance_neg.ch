module Shoals.TestsNeg.ModelFitClarabelNonfiniteTolerance
import Clarabel.Qp (Settings)
import Shoals.ModelFitClarabel (lm_bounded_nparam)
def zero_model[n, m](theta: &tensor[n, f64], features: &tensor[m, f64]) -> tensor[m, f64] = to_tensor(map(fn (value: f64) -> 0.0f64, to_list(features)))
def test_neg_rejects_nonfinite_tolerance() -> unit ! { Test } = {
  huge = 1e308f64
  nonfinite_tolerance = mul(huge, huge)
  result = lm_bounded_nparam(zero_model, to_tensor([0.0f64]), to_tensor([1.0f64]), to_tensor([1.0f64]), to_tensor([0.0f64]), to_tensor([-2.0f64]), to_tensor([2.0f64]), 0.01f64, nonfinite_tolerance, 0i64, 0.00001f64, 1e-6f64, Settings { max_iterations: 200i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 })
  fail("should not reach here")
}
