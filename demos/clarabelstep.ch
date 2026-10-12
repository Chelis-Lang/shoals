module Shoals.Demos.ClarabelStep
import Clarabel.Qp (Settings, Solved, Stopped, MaxIterationsStatus)
import Shoals.ModelFitClarabel (solve_bounded_step)
def main() -> bool = {
  p = to_tensor([[2.0f64, 1.0f64], [1.0f64, 2.0f64]])
  g = to_tensor([-1.0f64, 1.0f64])
  theta = to_tensor([0.0f64, 0.0f64])
  lo = to_tensor([0.0f64, 0.0f64])
  hi = to_tensor([2.0f64, 2.0f64])
  settings = Settings { max_iterations: 200i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 }
  coupled = match solve_bounded_step(p, g, theta, lo, hi, settings) with {
    | Solved { primal, dual, slack, iterations, primal_residual, dual_residual } => {
    values = to_list(primal)
    and(lt(abs(index(values, 0i64)), 1e-6f64), lt(abs(sub(index(values, 1i64), 0.5f64)), 1e-6f64))
  }
    | _ => false
  }
  interior = match solve_bounded_step(to_tensor([[2.0f64]]), to_tensor([2.0f64]), to_tensor([0.0f64]), to_tensor([-10.0f64]), to_tensor([10.0f64]), Settings { max_iterations: 200i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 }) with {
    | Solved { primal, dual, slack, iterations, primal_residual, dual_residual } => lt(abs(sub(index(to_list(primal), 0i64), 1.0f64)), 1e-6f64)
    | _ => false
  }
  lower = match solve_bounded_step(to_tensor([[2.0f64]]), to_tensor([-2.0f64]), to_tensor([0.0f64]), to_tensor([0.0f64]), to_tensor([1.0f64]), Settings { max_iterations: 200i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 }) with {
    | Solved { primal, dual, slack, iterations, primal_residual, dual_residual } => lt(abs(index(to_list(primal), 0i64)), 1e-6f64)
    | _ => false
  }
  upper = match solve_bounded_step(to_tensor([[2.0f64]]), to_tensor([4.0f64]), to_tensor([0.0f64]), to_tensor([-2.0f64]), to_tensor([1.0f64]), Settings { max_iterations: 200i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 }) with {
    | Solved { primal, dual, slack, iterations, primal_residual, dual_residual } => lt(abs(sub(index(to_list(primal), 0i64), 1.0f64)), 1e-6f64)
    | _ => false
  }
  stopped = match solve_bounded_step(to_tensor([[2.0f64]]), to_tensor([2.0f64]), to_tensor([0.0f64]), to_tensor([-10.0f64]), to_tensor([10.0f64]), Settings { max_iterations: 0i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 }) with {
    | Stopped { status: MaxIterationsStatus } => true
    | _ => false
  }
  and(coupled, and(interior, and(lower, and(upper, stopped))))
}
