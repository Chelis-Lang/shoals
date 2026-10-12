module Shoals.TestsNeg.ModelFitClarabelF32Precision
import Clarabel.Qp (Settings)
import Shoals.ModelFitClarabel (solve_bounded_step)
def main() = solve_bounded_step(to_tensor([[1.0f32]]), to_tensor([1.0f64]), to_tensor([0.0f64]), to_tensor([-1.0f64]), to_tensor([1.0f64]), Settings { max_iterations: 20i64, absolute_gap_tolerance: 1e-8f64, relative_gap_tolerance: 1e-8f64, feasibility_tolerance: 1e-8f64 })
