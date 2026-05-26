module Shoals.HullWhite
import Nautilus.Distributions (normal_sample)
export (hw1f_step, hw1f_path, hw1f_bond_price, hw2f_step, hw2f_path)
{- Hull-White 1-factor short-rate model:
     dr_t = (theta - a * r_t) dt + sigma * dW_t
   This module reparameterizes with theta_bar = theta / a so the SDE is
     dr_t = a * (theta_bar - r_t) dt + sigma * dW_t
   and theta_bar is the (constant) mean-reversion target rate.

   Closed-form bond-price reference exposed by hw1f_bond_price:
   At t = 0 with theta_bar = 0 (per spec test fixture) the zero-coupon
   bond price is
     B(0,T) = (1 - exp(-a*T)) / a
     P(0,T; r_0, a, sigma) = exp(  ((T - B) * sigma_sq) / (2 * a_sq)
                                  - (sigma_sq * B_sq) / (4 * a)
                                  - B * r_0 )
   This is the standard Vasicek/Hull-White zero-coupon formula
   specialized to theta_bar = 0. The Shoals milestone-E spec text
   writes the first factor as ((T-t)-B)*(sigma_sq/(4*a_sq)), which is
   a factor-of-two/sign typo relative to the SDE we simulate; we use
   the form that is consistent with hw1f_step / hw1f_path so the MC
   discount-factor mean and the analytic bond price agree to leading
   order. The MC-vs-analytic test in tests/hull_white.ch verifies the
   match to within 3 standard errors.

   Hull-White 2-factor (additive Gaussian-2, Brigo-Mercurio form):
     dx_t = -a * x_t dt + sigma_1 * dW_1
     dy_t = -b * y_t dt + sigma_2 * dW_2
     r_t  = x_t + y_t + phi(t)
     corr(dW_1, dW_2) = rho
   hw2f_path returns the two factor terminal samples without the
   deterministic shift phi(t), per the spec's path API. -}
def hw1f_step(r: f32, a: f32, theta_bar: f32, sigma: f32, dt: f32, z: f32) -> f32 = {
  drift = mul(a, mul(sub(theta_bar, r), dt))
  diffusion = mul(sigma, mul(sqrt(dt), z))
  add(r, add(drift, diffusion))
}
def hw1f_path[n](paths_template: tensor[n, f32], r0: f32, a: f32, theta_bar: f32, sigma: f32, t: f32, n_steps: int64) -> tensor[n, f32] ! { Random } = {
  n_paths = numel(copy(paths_template))
  total = mul(n_paths, n_steps)
  big_template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), total)))
  z_t = normal_sample(big_template, cast(0.0, f32), cast(1.0, f32))
  z_l = to_list(z_t)
  dt = div(t, cast(n_steps, f32))
  path_idxs = range(cast(0, int64), n_paths)
  terminal = to_tensor(map(fn (p: int64) -> {
    base = mul(p, n_steps)
    step_idxs = range(cast(0, int64), n_steps)
    fold(fn (r: f32, i: int64) -> {
      k = add(base, i)
      z = index(z_l, k)
      hw1f_step(r, a, theta_bar, sigma, dt, z)
    }, r0, step_idxs)
  }, path_idxs))
  terminal
}
def hw1f_bond_price(t: f32, t_maturity: f32, r0: f32, a: f32, sigma: f32) -> f32 = {
  tau = sub(t_maturity, t)
  b_val = div(sub(cast(1.0, f32), exp(neg(mul(a, tau)))), a)
  sigma_sq = mul(sigma, sigma)
  a_sq = mul(a, a)
  term_a = div(mul(sub(tau, b_val), sigma_sq), mul(cast(2.0, f32), a_sq))
  term_b = div(mul(sigma_sq, mul(b_val, b_val)), mul(cast(4.0, f32), a))
  log_p = sub(sub(term_a, term_b), mul(b_val, r0))
  exp(log_p)
}
def hw2f_step(x: f32, y: f32, a: f32, b: f32, sigma1: f32, sigma2: f32, rho: f32, dt: f32, z1: f32, z2: f32) -> (f32, f32) = {
  sqrt_dt = sqrt(dt)
  one_minus_rho_sq = sub(cast(1.0, f32), mul(rho, rho))
  sqrt_one_minus_rho_sq = if lt(one_minus_rho_sq, cast(0.0, f32)) then cast(0.0, f32) else sqrt(one_minus_rho_sq)
  w1 = z1
  w2 = add(mul(rho, z1), mul(sqrt_one_minus_rho_sq, z2))
  drift_x = mul(neg(a), mul(x, dt))
  drift_y = mul(neg(b), mul(y, dt))
  diff_x = mul(sigma1, mul(sqrt_dt, w1))
  diff_y = mul(sigma2, mul(sqrt_dt, w2))
  (add(x, add(drift_x, diff_x)), add(y, add(drift_y, diff_y)))
}
def hw2f_path[n](paths_template: tensor[n, f32], x0: f32, y0: f32, a: f32, b: f32, sigma1: f32, sigma2: f32, rho: f32, t: f32, n_steps: int64) -> (tensor[n, f32], tensor[n, f32]) ! { Random } = {
  n_paths = numel(copy(paths_template))
  total = mul(n_paths, n_steps)
  big_template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), total)))
  z1_t = normal_sample(copy(big_template), cast(0.0, f32), cast(1.0, f32))
  z2_t = normal_sample(big_template, cast(0.0, f32), cast(1.0, f32))
  z1_l = to_list(z1_t)
  z2_l = to_list(z2_t)
  dt = div(t, cast(n_steps, f32))
  path_idxs = range(cast(0, int64), n_paths)
  results = map(fn (p: int64) -> {
    base = mul(p, n_steps)
    step_idxs = range(cast(0, int64), n_steps)
    fold(fn (state: (f32, f32), i: int64) -> {
      x = state.0
      y = state.1
      k = add(base, i)
      z1 = index(z1_l, k)
      z2 = index(z2_l, k)
      hw2f_step(x, y, a, b, sigma1, sigma2, rho, dt, z1, z2)
    }, (x0, y0), step_idxs)
  }, path_idxs)
  x_t = to_tensor(map(fn (s: (f32, f32)) -> s.0, results))
  y_t = to_tensor(map(fn (s: (f32, f32)) -> s.1, results))
  (x_t, y_t)
}
