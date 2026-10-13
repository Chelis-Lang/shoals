module Shoals.ModelFitClarabel
import Clarabel.Qp (NonnegativeCone, Settings, SolveStatus, Solved, Stopped, solve)
export (solve_bounded_step, apply_step, apply_two_parameter_step, FitResult, FitConverged, FitIterationLimit, FitSolverStopped, FitNumericalFailure, lm_bounded_nparam)
type FitResult[n] =
  | FitConverged { parameters: tensor[n, f64], loss: f64, iterations: i64, projection_size: f64 }
  | FitIterationLimit { parameters: tensor[n, f64], loss: f64, iterations: i64, projection_size: f64 }
  | FitSolverStopped { parameters: tensor[n, f64], loss: f64, iterations: i64, projection_size: f64, status: SolveStatus }
  | FitNumericalFailure { parameters: tensor[n, f64], loss: f64, iterations: i64, projection_size: f64, reason: string }
def vector_add[n](a: &tensor[n, f64], b: &tensor[n, f64]) -> tensor[n, f64] = add(a, b)
def apply_step[n](parameters: &tensor[n, f64], step: &tensor[n, f64]) -> tensor[n, f64] = add(parameters, step)
def apply_two_parameter_step(parameters: tensor[2, f64], step: tensor[2, f64]) -> tensor[2, f64] = {
  updated = add(parameters, step)
  updated
}
def vector_sub[n](a: &tensor[n, f64], b: &tensor[n, f64]) -> tensor[n, f64] = sub(a, b)
def vector_scale[n](a: &tensor[n, f64], factor: f64) -> tensor[n, f64] = to_tensor(map(fn (value: f64) -> mul(value, factor), to_list(a)))
def vector_dot[n](a: &tensor[n, f64], b: &tensor[n, f64]) -> f64 = tensor_to_scalar(sum(mul(a, b), 0i32))
def basis_vector[n](template: &tensor[n, f64], position: i64, value: f64) -> tensor[n, f64] = to_tensor(map(fn (index: i64) -> if eq(index, position) then value else 0.0f64, range(0i64, len(to_list(template)))))
def weighted_loss[m](residual: &tensor[m, f64], weights: &tensor[m, f64]) -> f64 = fold(fn (acc: f64, entry: (f64, f64)) -> add(acc, mul(entry.1, mul(entry.0, entry.0))), 0.0f64, zip(to_list(residual), to_list(weights)))
def clamp_parameters[n](theta: &tensor[n, f64], lo: &tensor[n, f64], hi: &tensor[n, f64]) -> tensor[n, f64] = {
  pairs = zip(to_list(theta), to_list(lo))
  to_tensor(map(fn (entry: ((f64, f64), f64)) -> {
    pair = entry.0
    if lt(pair.0, pair.1) then pair.1 else if gt(pair.0, entry.1) then entry.1 else pair.0
  }, zip(pairs, to_list(hi))))
}
def bounds_ordered[n](lo: &tensor[n, f64], hi: &tensor[n, f64]) -> bool = fold(fn (ok: bool, entry: (f64, f64)) -> and(ok, lte(entry.0, entry.1)), true, zip(to_list(lo), to_list(hi)))
def finite_values[n](values: &tensor[n, f64]) -> bool = fold(fn (ok: bool, value: f64) -> and(ok, eq(sub(value, value), 0.0f64)), true, to_list(values))
def finite_scalar(value: f64) -> bool = eq(sub(value, value), 0.0f64)
def finite_bound_distances[n](theta: &tensor[n, f64], lo: &tensor[n, f64], hi: &tensor[n, f64]) -> bool = and(finite_values(sub(hi, theta)), finite_values(sub(theta, lo)))
def ordered_bounds[n](theta: &tensor[n, f64], lo: &tensor[n, f64], hi: &tensor[n, f64]) -> bool = {
  lower_pairs = zip(to_list(theta), to_list(lo))
  triples = zip(lower_pairs, to_list(hi))
  fold(fn (ok: bool, entry: ((f64, f64), f64)) -> {
    pair = entry.0
    current = pair.0
    lower = pair.1
    upper = entry.1
    and(ok, and(lte(lower, current), and(lte(current, upper), lte(lower, upper))))
  }, true, triples)
}
def identity[n](template: &tensor[n, f64]) -> tensor[n, n, f64] = {
  indices = range(0i64, len(to_list(template)))
  rows = map(fn (row: i64) -> map(fn (column: i64) -> if eq(row, column) then 1.0f64 else 0.0f64, indices), indices)
  to_tensor(rows)
}
def solve_bounded_step[n](p: &tensor[n, n, f64], g: &tensor[n, f64], theta: &tensor[n, f64], lo: &tensor[n, f64], hi: &tensor[n, f64], settings: Settings) = {
  n_params = len(to_list(theta))
  flat_p = reshape(p, [mul(n_params, n_params)])
  p_finite = finite_values(flat_p)
  valid = and(gt(n_params, 0i64), and(p_finite, and(finite_values(g), and(finite_values(theta), and(finite_values(lo), and(finite_values(hi), ordered_bounds(theta, lo, hi)))))))
  if not(valid) then fail("Shoals.ModelFitClarabel: empty, nonfinite, or out-of-bounds QP input") else if not(finite_bound_distances(theta, lo, hi)) then fail("Shoals.ModelFitClarabel: nonfinite QP bound distance") else {
    unit = identity(theta)
    a = concat([copy(unit), neg(unit)], 0i32)
    b = concat([sub(hi, theta), sub(theta, lo)], 0i32)
    solve(p, neg(g), a, b, [NonnegativeCone(mul(2i64, n_params))], settings)
  }
}
def jacobian_column[n, m](model: &tensor[n, f64] -> &tensor[m, f64] -> tensor[m, f64], features: &tensor[m, f64], theta: &tensor[n, f64], prediction: &tensor[m, f64], template: &tensor[n, f64], column: i64, fd_eps: f64) -> tensor[m, f64] = {
  perturbed = vector_add(theta, basis_vector(template, column, fd_eps))
  changed = model(perturbed, features)
  vector_scale(vector_sub(changed, prediction), div(1.0f64, fd_eps))
}
def gradient_acc[n, m](model: &tensor[n, f64] -> &tensor[m, f64] -> tensor[m, f64], features: &tensor[m, f64], theta: &tensor[n, f64], prediction: &tensor[m, f64], weighted_residual: &tensor[m, f64], template: &tensor[n, f64], column: i64, n_params: i64, fd_eps: f64) -> tensor[n, f64] =
  if gte(column, n_params) then vector_scale(template, 0.0f64) else {
    j_column = jacobian_column(model, features, theta, prediction, template, column, fd_eps)
    component = vector_dot(j_column, weighted_residual)
    rest = gradient_acc(model, features, theta, prediction, weighted_residual, template, add(column, 1i64), n_params, fd_eps)
    vector_add(basis_vector(template, column, component), rest)
  }
def normal_row[n, m](model: &tensor[n, f64] -> &tensor[m, f64] -> tensor[m, f64], features: &tensor[m, f64], theta: &tensor[n, f64], prediction: &tensor[m, f64], weights: &tensor[m, f64], template: &tensor[n, f64], row_column: &tensor[m, f64], row_basis: &tensor[n, f64], column: i64, n_params: i64, fd_eps: f64) -> tensor[n, n, f64] =
  if gte(column, n_params) then {
    zero = vector_scale(template, 0.0f64)
    einsum("i,j->ij", copy(zero), zero)
  } else {
    j_column = jacobian_column(model, features, theta, prediction, template, column, fd_eps)
    weighted_column = mul(weights, j_column)
    component = vector_dot(row_column, weighted_column)
    column_basis = basis_vector(template, column, 1.0f64)
    entry = einsum("i,j->ij", vector_scale(row_basis, component), column_basis)
    rest = normal_row(model, features, theta, prediction, weights, template, row_column, row_basis, add(column, 1i64), n_params, fd_eps)
    add(entry, rest)
  }
def normal_matrix_acc[n, m](model: &tensor[n, f64] -> &tensor[m, f64] -> tensor[m, f64], features: &tensor[m, f64], theta: &tensor[n, f64], prediction: &tensor[m, f64], weights: &tensor[m, f64], template: &tensor[n, f64], row: i64, n_params: i64, fd_eps: f64) -> tensor[n, n, f64] =
  if gte(row, n_params) then {
    zero = vector_scale(template, 0.0f64)
    einsum("i,j->ij", copy(zero), zero)
  } else {
    j_row = jacobian_column(model, features, theta, prediction, template, row, fd_eps)
    row_basis = basis_vector(template, row, 1.0f64)
    matrix_row = normal_row(model, features, theta, prediction, weights, template, j_row, row_basis, 0i64, n_params, fd_eps)
    rest = normal_matrix_acc(model, features, theta, prediction, weights, template, add(row, 1i64), n_params, fd_eps)
    add(matrix_row, rest)
  }
def matrix_scale[n](matrix: &tensor[n, n, f64], factor: f64, n_params: i64) -> tensor[n, n, f64] = {
  flat = reshape(matrix, [mul(n_params, n_params)])
  changed = to_tensor(map(fn (value: f64) -> mul(value, factor), to_list(flat)))
  reshape(changed, [n_params, n_params])
}
def damped_normal[n](normal: &tensor[n, n, f64], lambda: f64, template: &tensor[n, f64], n_params: i64) -> tensor[n, n, f64] = {
  symmetric = matrix_scale(add(normal, permute(normal, 1i32, 0i32)), 0.5f64, n_params)
  diagonal = to_list(reshape(symmetric, [mul(n_params, n_params)]))
  fold(fn (acc: tensor[n, n, f64], index_value: i64) -> {
    entry = index(diagonal, add(mul(index_value, n_params), index_value))
    safe_entry = if lt(entry, 1e-7f64) then 1e-7f64 else entry
    scale = mul(lambda, safe_entry)
    basis = basis_vector(template, index_value, 1.0f64)
    add(acc, einsum("i,j->ij", vector_scale(copy(basis), scale), basis))
  }, symmetric, range(0i64, n_params))
}
def max_abs_difference[n](a: &tensor[n, f64], b: &tensor[n, f64]) -> f64 =
  fold(fn (largest: f64, entry: (f64, f64)) -> {
    difference = abs(sub(entry.0, entry.1))
    if gt(difference, largest) then difference else largest
  }, 0.0f64, zip(to_list(a), to_list(b)))
def fit_rec[n, m](model: &tensor[n, f64] -> &tensor[m, f64] -> tensor[m, f64], features: &tensor[m, f64], observed: &tensor[m, f64], weights: &tensor[m, f64], lo: &tensor[n, f64], hi: &tensor[n, f64], theta: tensor[n, f64], loss: f64, lambda: f64, tolerance: f64, steps_left: i64, steps_used: i64, fd_eps: f64, bound_tolerance: f64, projection_size: f64, settings: Settings) -> FitResult[n] =
  if lte(loss, tolerance) then FitConverged { parameters: theta, loss, iterations: steps_used, projection_size } else if lte(steps_left, 0i64) then FitIterationLimit { parameters: theta, loss, iterations: steps_used, projection_size } else {
    prediction = model(copy(theta), features)
    if not(finite_values(prediction)) then FitNumericalFailure { parameters: theta, loss, iterations: steps_used, projection_size, reason: "nonfinite model prediction" } else {
      residual = vector_sub(observed, prediction)
      weighted_residual = mul(weights, residual)
      template = vector_scale(theta, 0.0f64)
      n_params = len(to_list(copy(theta)))
      gradient = gradient_acc(model, features, theta, prediction, weighted_residual, template, 0i64, n_params, fd_eps)
      normal = normal_matrix_acc(model, features, theta, prediction, weights, template, 0i64, n_params, fd_eps)
      p = damped_normal(normal, lambda, template, n_params)
      if not(and(finite_values(gradient), finite_values(reshape(p, [mul(n_params, n_params)])))) then FitNumericalFailure { parameters: theta, loss, iterations: steps_used, projection_size, reason: "nonfinite QP construction" } else if not(finite_bound_distances(theta, lo, hi)) then FitNumericalFailure { parameters: theta, loss, iterations: steps_used, projection_size, reason: "nonfinite QP bound distance" } else {
        result = match solve_bounded_step(p, gradient, theta, lo, hi, settings) with {
          | Stopped { status } => FitSolverStopped { parameters: theta, loss, iterations: steps_used, projection_size, status }
          | Solved { primal, dual, slack, iterations, primal_residual, dual_residual } => {
          raw = vector_add(theta, primal)
          candidate = clamp_parameters(raw, lo, hi)
          correction = max_abs_difference(raw, candidate)
          diagnostics_ok = and(eq(sub(primal_residual, primal_residual), 0.0f64), eq(sub(dual_residual, dual_residual), 0.0f64))
          if not(and(diagnostics_ok, and(finite_values(primal), and(finite_values(candidate), lte(correction, bound_tolerance))))) then FitNumericalFailure { parameters: theta, loss, iterations: steps_used, projection_size, reason: "invalid solved QP step or bound violation" } else {
            updated_projection = if gt(correction, projection_size) then correction else projection_size
            next_prediction = model(copy(candidate), features)
            next_residual = vector_sub(observed, next_prediction)
            next_loss = weighted_loss(next_residual, weights)
            if not(and(finite_values(next_prediction), finite_scalar(next_loss))) then FitNumericalFailure { parameters: theta, loss, iterations: steps_used, projection_size: updated_projection, reason: "nonfinite candidate loss" } else {
              accepted = lt(next_loss, loss)
              new_theta = if accepted then candidate else theta
              new_loss = if accepted then next_loss else loss
              raw_lambda = if accepted then div(lambda, 3.0f64) else mul(lambda, 3.0f64)
              new_lambda = if lt(raw_lambda, 1e-10f64) then 1e-10f64 else if gt(raw_lambda, 10000000000.0f64) then 10000000000.0f64 else raw_lambda
              relative_drop = if eq(loss, 0.0f64) then 0.0f64 else div(sub(loss, new_loss), loss)
              used = add(steps_used, 1i64)
              if and(accepted, lte(relative_drop, tolerance)) then FitConverged { parameters: new_theta, loss: new_loss, iterations: used, projection_size: updated_projection } else fit_rec(model, features, observed, weights, lo, hi, new_theta, new_loss, new_lambda, tolerance, sub(steps_left, 1i64), used, fd_eps, bound_tolerance, updated_projection, settings)
            }
          }
        }
        }
        result
      }
    }
  }
def lm_bounded_nparam[n, m](model: &tensor[n, f64] -> &tensor[m, f64] -> tensor[m, f64], features: &tensor[m, f64], observed: &tensor[m, f64], weights: &tensor[m, f64], theta0: tensor[n, f64], lo: &tensor[n, f64], hi: &tensor[n, f64], lambda0: f64, tolerance: f64, max_iters: i64, fd_eps: f64, bound_tolerance: f64, settings: Settings) -> FitResult[n] = {
  weights_valid = fold(fn (ok: bool, weight: f64) -> and(ok, and(finite_scalar(weight), gte(weight, 0.0f64))), true, to_list(weights))
  data_valid = and(gt(len(to_list(theta0)), 0i64), and(bounds_ordered(lo, hi), and(finite_values(features), and(finite_values(observed), and(weights_valid, and(finite_values(theta0), and(finite_values(lo), finite_values(hi))))))))
  settings_valid = and(finite_scalar(lambda0), and(gt(lambda0, 0.0f64), and(finite_scalar(tolerance), and(gt(tolerance, 0.0f64), and(finite_scalar(fd_eps), and(gt(fd_eps, 0.0f64), and(finite_scalar(bound_tolerance), and(gte(bound_tolerance, 0.0f64), gte(max_iters, 0i64)))))))))
  valid = and(data_valid, settings_valid)
  if not(valid) then fail("Shoals.ModelFitClarabel: invalid fit inputs") else {
    theta = clamp_parameters(theta0, lo, hi)
    prediction = model(copy(theta), features)
    if not(finite_values(prediction)) then FitNumericalFailure { parameters: theta, loss: 0.0f64, iterations: 0i64, projection_size: 0.0f64, reason: "nonfinite initial model prediction" } else {
      residual = vector_sub(observed, prediction)
      loss = weighted_loss(residual, weights)
      if not(finite_scalar(loss)) then FitNumericalFailure { parameters: theta, loss, iterations: 0i64, projection_size: 0.0f64, reason: "nonfinite initial loss" } else fit_rec(model, features, observed, weights, lo, hi, theta, loss, lambda0, tolerance, max_iters, 0i64, fd_eps, bound_tolerance, 0.0f64, settings)
    }
  }
}
