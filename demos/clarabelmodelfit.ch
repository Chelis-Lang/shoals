module Shoals.Demos.ClarabelModelFit
import Clarabel.Qp (Settings, Solved)
import Shoals.ModelFitClarabel (solve_bounded_step, lm_bounded_nparam, FitConverged)
def affine_model[n, m](theta: &tensor[n, f64], features: &tensor[m, f64]) -> tensor[m, f64] = {
  parameters = to_list(theta)
  slope = index(parameters, 0i64)
  intercept = index(parameters, 1i64)
  to_tensor(map(fn (x: f64) -> add(mul(slope, x), intercept), to_list(features)))
}
def settings() -> Settings = Settings { max_iterations: 200i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 }
def main() -> bool = {
  p = to_tensor([[2.0f64, 1.0f64], [1.0f64, 2.0f64]])
  g = to_tensor([-1.0f64, 1.0f64])
  theta = to_tensor([0.0f64, 0.0f64])
  lo = to_tensor([0.0f64, 0.0f64])
  hi = to_tensor([2.0f64, 2.0f64])
  step_ok = match solve_bounded_step(p, g, theta, lo, hi, settings()) with {
    | Solved { primal, dual, slack, iterations, primal_residual, dual_residual } => {
    values = to_list(primal)
    and(lt(abs(index(values, 0i64)), 1e-6f64), lt(abs(sub(index(values, 1i64), 0.5f64)), 1e-6f64))
  }
    | _ => false
  }
  features = to_tensor([0.0f64, 1.0f64, 2.0f64, 3.0f64])
  observed = to_tensor([1.0f64, 3.0f64, 5.0f64, 7.0f64])
  weights = to_tensor([1.0f64, 1.0f64, 1.0f64, 1.0f64])
  fitted = lm_bounded_nparam(affine_model, features, observed, weights, to_tensor([0.5f64, 0.5f64]), to_tensor([0.0f64, 0.0f64]), to_tensor([3.0f64, 3.0f64]), 0.01f64, 1e-6f64, 20i64, 0.00001f64, 1e-6f64, settings())
  fit_ok = match fitted with {
    | FitConverged { parameters, loss, iterations, projection_size } => {
    values = to_list(parameters)
    and(lt(abs(sub(index(values, 0i64), 2.0f64)), 0.01f64), and(lt(abs(sub(index(values, 1i64), 1.0f64)), 0.01f64), lt(loss, 1e-6f64)))
  }
    | _ => false
  }
  and(step_ok, fit_ok)
}
