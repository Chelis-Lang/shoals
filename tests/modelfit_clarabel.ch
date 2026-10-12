module Shoals.Tests.ModelFitClarabel
import Std.Test (assert_close, assert_true)
import Clarabel.Qp (Settings, Solved, Stopped, MaxIterationsStatus)
import Shoals.ModelFitClarabel (solve_bounded_step, lm_bounded_nparam, FitConverged, FitIterationLimit, FitSolverStopped, FitNumericalFailure)
def affine_model[n, m](theta: &tensor[n, f64], features: &tensor[m, f64]) -> tensor[m, f64] = {
  parameters = to_list(theta)
  slope = index(parameters, 0i64)
  intercept = index(parameters, 1i64)
  to_tensor(map(fn (x: f64) -> add(mul(slope, x), intercept), to_list(features)))
}
def zero_model[n, m](theta: &tensor[n, f64], features: &tensor[m, f64]) -> tensor[m, f64] = to_tensor(map(fn (value: f64) -> 0.0f64, to_list(features)))
def sum_model[n, m](theta: &tensor[n, f64], features: &tensor[m, f64]) -> tensor[m, f64] = {
  parameters = to_list(theta)
  total = add(index(parameters, 0i64), index(parameters, 1i64))
  to_tensor(map(fn (x: f64) -> mul(total, x), to_list(features)))
}
def quadratic_model[n, m](theta: &tensor[n, f64], features: &tensor[m, f64]) -> tensor[m, f64] = {
  parameter = index(to_list(theta), 0i64)
  to_tensor(map(fn (x: f64) -> mul(mul(parameter, parameter), x), to_list(features)))
}
def settings() -> Settings = Settings { max_iterations: 200i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 }
def test_coupled_lower_bound_differs_from_clamping() -> unit ! { Test } = {
  p = to_tensor([[2.0f64, 1.0f64], [1.0f64, 2.0f64]])
  g = to_tensor([-1.0f64, 1.0f64])
  theta = to_tensor([0.0f64, 0.0f64])
  lo = to_tensor([0.0f64, 0.0f64])
  hi = to_tensor([2.0f64, 2.0f64])
  match solve_bounded_step(p, g, theta, lo, hi, settings()) with {
    | Solved { primal, dual, slack, iterations, primal_residual, dual_residual } => {
    values = to_list(primal)
    _ = assert_close(index(values, 0i64), 0.0f64, 1e-6f64, "active lower bound")
    assert_close(index(values, 1i64), 0.5f64, 1e-6f64, "coupled constrained optimum")
  }
    | _ => assert_true(false, "QP must solve")
  }
}
def test_unconstrained_interior_step() -> unit ! { Test } = {
  p = to_tensor([[2.0f64]])
  g = to_tensor([2.0f64])
  theta = to_tensor([0.0f64])
  lo = to_tensor([-10.0f64])
  hi = to_tensor([10.0f64])
  match solve_bounded_step(p, g, theta, lo, hi, settings()) with {
    | Solved { primal, dual, slack, iterations, primal_residual, dual_residual } => assert_close(index(to_list(primal), 0i64), 1.0f64, 1e-6f64, "interior optimum")
    | _ => assert_true(false, "QP must solve")
  }
}
def test_active_upper_bound_step() -> unit ! { Test } = {
  p = to_tensor([[2.0f64]])
  g = to_tensor([4.0f64])
  theta = to_tensor([0.0f64])
  lo = to_tensor([-2.0f64])
  hi = to_tensor([1.0f64])
  match solve_bounded_step(p, g, theta, lo, hi, settings()) with {
    | Solved { primal, dual, slack, iterations, primal_residual, dual_residual } => assert_close(index(to_list(primal), 0i64), 1.0f64, 1e-6f64, "active upper bound")
    | _ => assert_true(false, "QP must solve")
  }
}
def test_stopped_is_distinct_from_solved() -> unit ! { Test } = {
  p = to_tensor([[2.0f64]])
  g = to_tensor([2.0f64])
  theta = to_tensor([0.0f64])
  lo = to_tensor([-10.0f64])
  hi = to_tensor([10.0f64])
  match solve_bounded_step(p, g, theta, lo, hi, Settings { max_iterations: 0i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 }) with {
    | Stopped { status: MaxIterationsStatus } => assert_true(true, "iteration limit preserves stopped status")
    | _ => assert_true(false, "zero iterations must stop")
  }
}
def test_f64_fit_recovers_affine_model() -> unit ! { Test } = {
  features = to_tensor([0.0f64, 1.0f64, 2.0f64, 3.0f64])
  observed = to_tensor([1.0f64, 3.0f64, 5.0f64, 7.0f64])
  weights = to_tensor([1.0f64, 1.0f64, 1.0f64, 1.0f64])
  theta0 = to_tensor([0.5f64, 0.5f64])
  lo = to_tensor([0.0f64, 0.0f64])
  hi = to_tensor([3.0f64, 3.0f64])
  match lm_bounded_nparam(affine_model, features, observed, weights, theta0, lo, hi, 0.01f64, 1e-6f64, 20i64, 0.00001f64, 1e-6f64, settings()) with {
    | FitConverged { parameters, loss, iterations, projection_size } => {
    values = to_list(parameters)
    _ = assert_close(index(values, 0i64), 2.0f64, 0.01f64, "f64 fitted slope")
    _ = assert_close(index(values, 1i64), 1.0f64, 0.01f64, "f64 fitted intercept")
    _ = assert_true(lte(projection_size, 1e-6f64), "bounded numerical projection")
    assert_true(lt(loss, 1e-6f64), "f64 weighted loss")
  }
    | _ => assert_true(false, "affine fit should converge")
  }
}
def test_f64_fit_preserves_solver_stop() -> unit ! { Test } = {
  features = to_tensor([0.0f64, 1.0f64])
  observed = to_tensor([1.0f64, 3.0f64])
  weights = to_tensor([1.0f64, 1.0f64])
  theta0 = to_tensor([0.5f64, 0.5f64])
  lo = to_tensor([0.0f64, 0.0f64])
  hi = to_tensor([3.0f64, 3.0f64])
  stopped_settings = Settings { max_iterations: 0i64, absolute_gap_tolerance: 1e-9f64, relative_gap_tolerance: 1e-9f64, feasibility_tolerance: 1e-9f64 }
  match lm_bounded_nparam(affine_model, features, observed, weights, theta0, lo, hi, 0.01f64, 1e-6f64, 5i64, 0.00001f64, 1e-6f64, stopped_settings) with {
    | FitSolverStopped { parameters, loss, iterations, projection_size, status: MaxIterationsStatus } => assert_true(eq(iterations, 0i64), "solver status is distinct from fit convergence")
    | _ => assert_true(false, "solver must stop")
  }
}
def test_f64_fit_iteration_limit_is_distinct_from_solver_stop() -> unit ! { Test } = {
  features = to_tensor([0.0f64, 1.0f64])
  observed = to_tensor([1.0f64, 3.0f64])
  weights = to_tensor([1.0f64, 1.0f64])
  theta0 = to_tensor([0.5f64, 0.5f64])
  lo = to_tensor([0.0f64, 0.0f64])
  hi = to_tensor([3.0f64, 3.0f64])
  match lm_bounded_nparam(affine_model, features, observed, weights, theta0, lo, hi, 0.01f64, 1e-6f64, 0i64, 0.00001f64, 1e-6f64, settings()) with {
    | FitIterationLimit { parameters, loss, iterations, projection_size } => {
    _ = assert_true(eq(iterations, 0i64), "outer iteration limit is zero")
    assert_true(gt(loss, 1e-6f64), "initial fit is not converged")
  }
    | _ => assert_true(false, "outer iteration limit must be distinct from solver stop")
  }
}
def test_f64_fit_rejects_overflowed_initial_loss() -> unit ! { Test } = {
  features = to_tensor([0.0f64])
  observed = to_tensor([1e308f64])
  weights = to_tensor([1.0f64])
  theta0 = to_tensor([0.0f64])
  bounds_lo = to_tensor([-1.0f64])
  bounds_hi = to_tensor([1.0f64])
  match lm_bounded_nparam(zero_model, features, observed, weights, theta0, bounds_lo, bounds_hi, 0.01f64, 1e-6f64, 0i64, 0.00001f64, 1e-6f64, settings()) with {
    | FitNumericalFailure { parameters, loss, iterations, projection_size, reason } => assert_true(eq(reason, "nonfinite initial loss"), "overflow must be reported")
    | _ => assert_true(false, "overflowed loss must not become an iteration limit")
  }
}
def test_f64_fit_rank_deficient_model() -> unit ! { Test } = {
  features = to_tensor([1.0f64, 2.0f64])
  observed = to_tensor([2.0f64, 4.0f64])
  weights = to_tensor([1.0f64, 1.0f64])
  theta0 = to_tensor([0.0f64, 0.0f64])
  lo = to_tensor([-3.0f64, -3.0f64])
  hi = to_tensor([3.0f64, 3.0f64])
  match lm_bounded_nparam(sum_model, features, observed, weights, theta0, lo, hi, 0.01f64, 1e-6f64, 20i64, 0.00001f64, 1e-6f64, settings()) with {
    | FitConverged { parameters, loss, iterations, projection_size } => {
    values = to_list(parameters)
    _ = assert_close(add(index(values, 0i64), index(values, 1i64)), 2.0f64, 0.01f64, "rank-deficient fitted sum")
    assert_true(lt(loss, 1e-6f64), "rank-deficient weighted loss")
  }
    | _ => assert_true(false, "rank-deficient fit should converge")
  }
}
def test_f64_fit_nonlinear_model() -> unit ! { Test } = {
  features = to_tensor([1.0f64, 2.0f64])
  observed = to_tensor([4.0f64, 8.0f64])
  weights = to_tensor([1.0f64, 1.0f64])
  theta0 = to_tensor([1.0f64])
  lo = to_tensor([0.0f64])
  hi = to_tensor([3.0f64])
  match lm_bounded_nparam(quadratic_model, features, observed, weights, theta0, lo, hi, 0.01f64, 1e-6f64, 20i64, 0.00001f64, 1e-6f64, settings()) with {
    | FitConverged { parameters, loss, iterations, projection_size } => {
    _ = assert_close(index(to_list(parameters), 0i64), 2.0f64, 0.01f64, "nonlinear fitted parameter")
    assert_true(lt(loss, 1e-6f64), "nonlinear weighted loss")
  }
    | _ => assert_true(false, "nonlinear fit should converge")
  }
}
def test_f64_fit_ill_conditioned_affine_model() -> unit ! { Test } = {
  features = to_tensor([0.0f64, 0.001f64, 0.002f64, 0.003f64])
  observed = to_tensor([1.0f64, 1.002f64, 1.004f64, 1.006f64])
  weights = to_tensor([1.0f64, 1.0f64, 1.0f64, 1.0f64])
  theta0 = to_tensor([0.0f64, 0.0f64])
  lo = to_tensor([-10.0f64, 0.0f64])
  hi = to_tensor([10.0f64, 2.0f64])
  match lm_bounded_nparam(affine_model, features, observed, weights, theta0, lo, hi, 0.01f64, 1e-10f64, 30i64, 1e-6f64, 1e-6f64, settings()) with {
    | FitConverged { parameters, loss, iterations, projection_size } => {
    values = to_list(parameters)
    _ = assert_close(index(values, 0i64), 2.0f64, 0.05f64, "ill-conditioned fitted slope")
    _ = assert_close(index(values, 1i64), 1.0f64, 0.001f64, "ill-conditioned fitted intercept")
    assert_true(lt(loss, 1e-8f64), "ill-conditioned weighted loss")
  }
    | _ => assert_true(false, "ill-conditioned affine fit should converge")
  }
}
