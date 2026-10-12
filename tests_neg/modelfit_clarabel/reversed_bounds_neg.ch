module Shoals.TestsNeg.ModelFitClarabelReversedBounds
import Clarabel.Qp (Settings)
import Shoals.ModelFitClarabel (solve_bounded_step)
def test_neg_rejects_reversed_bounds() -> unit ! { Test } = {
  result = solve_bounded_step(to_tensor([[2.0f64]]), to_tensor([1.0f64]), to_tensor([0.0f64]), to_tensor([1.0f64]), to_tensor([0.0f64]), Settings { max_iterations: 200i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 })
  fail("should not reach here")
}
