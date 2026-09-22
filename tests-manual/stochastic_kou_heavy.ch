module Shoals.Tests.StochasticKouHeavy
import Std.Test (assert_close, assert_true)
import Nautilus.Stats (mean_vec, std_vec, skewness_vec)
import Shoals.Stochastic (sto_kou_compensator, sto_kou_jump_terminal)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def is_nan_f32(x: f32) -> bool = if eq(x, x) then false else true
def test_kou_zero_jump_rate_reduces_to_gbm() -> unit ! { Test } = {
  n_paths = cast(256, i64)
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), n_paths)))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), n_paths)))
  s0 = cast(100.0, f32)
  mu = cast(0.05, f32)
  sigma = cast(0.2, f32)
  big_t = cast(1.0, f32)
  paths = with seed(7i64) { sto_kou_jump_terminal(template, jumps_template, s0, mu, sigma, cast(0.0, f32), cast(0.5, f32), cast(3.0, f32), cast(3.0, f32), big_t) }
  paths_l = to_list(paths)
  log_returns = to_tensor(map(fn (s: f32) -> log(div(s, s0)), paths_l))
  m = mean_vec(copy(log_returns))
  s = std_vec(log_returns, cast(1, i64))
  expected = mul(sub(mu, mul(cast(0.5, f32), mul(sigma, sigma))), big_t)
  n_f = cast(n_paths, f32)
  se_mc = div(s, sqrt(n_f))
  diff = abs_f32(sub(m, expected))
  tol = mul(cast(3.0, f32), se_mc)
  assert_true(lt(diff, tol), "lambda=0 reduces to GBM: MC mean of log(S_T/S0) within 3*SE_mc of (mu-sigma^2/2)*T")
}
def test_kou_compensator_at_unit_up_rate() -> unit ! { Test } = {
  z = sto_kou_compensator(cast(0.5, f32), cast(2.0, f32), cast(2.0, f32))
  expected = sub(add(mul(cast(0.5, f32), div(cast(2.0, f32), sub(cast(2.0, f32), cast(1.0, f32)))), mul(cast(0.5, f32), div(cast(2.0, f32), add(cast(2.0, f32), cast(1.0, f32))))), cast(1.0, f32))
  assert_close(z, expected, cast(0.00001, f32), "compensator at p=0.5 eta_up=2 eta_dn=2 = 0.5*2/1 + 0.5*2/3 - 1 = 0.3333")
}
def test_kou_compensator_requires_eta_up_greater_than_1() -> unit ! { Test } = {
  z = sto_kou_compensator(cast(0.5, f32), cast(0.5, f32), cast(2.0, f32))
  assert_true(is_nan_f32(z), "eta_up <= 1 produces NaN sentinel since the moment integral diverges")
}
def test_kou_jump_density_check() -> unit ! { Test } = {
  n_paths = cast(256, i64)
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), n_paths)))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), n_paths)))
  s0 = cast(100.0, f32)
  mu = cast(0.02, f32)
  sigma = cast(0.1, f32)
  lambda_jump = cast(10.0, f32)
  p = cast(0.5, f32)
  eta_up = cast(10.0, f32)
  eta_dn = cast(10.0, f32)
  big_t = cast(1.0, f32)
  paths = with seed(11i64) { sto_kou_jump_terminal(template, jumps_template, s0, mu, sigma, lambda_jump, p, eta_up, eta_dn, big_t) }
  paths_l = to_list(paths)
  log_returns = to_tensor(map(fn (s: f32) -> log(div(s, s0)), paths_l))
  m = mean_vec(copy(log_returns))
  s = std_vec(log_returns, cast(1, i64))
  zeta = sto_kou_compensator(p, eta_up, eta_dn)
  half_sigma_sq = mul(cast(0.5, f32), mul(sigma, sigma))
  expected = mul(sub(sub(mu, half_sigma_sq), mul(lambda_jump, zeta)), big_t)
  n_f = cast(n_paths, f32)
  se_mc = div(s, sqrt(n_f))
  diff = abs_f32(sub(m, expected))
  tol = mul(cast(3.0, f32), se_mc)
  assert_true(lt(diff, tol), "compensated drift: MC mean of log(S_T/S0) at 256 paths within 3*SE_mc of (mu-sigma^2/2-lambda*zeta)*T")
}
def test_kou_skewness_sign() -> unit ! { Test } = {
  n_paths = cast(512, i64)
  template_neg = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), n_paths)))
  jumps_template_neg = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), n_paths)))
  template_pos = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), n_paths)))
  jumps_template_pos = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), n_paths)))
  s0 = cast(100.0, f32)
  mu = cast(0.0, f32)
  sigma = cast(0.05, f32)
  lambda_jump = cast(5.0, f32)
  eta_up = cast(5.0, f32)
  eta_dn = cast(5.0, f32)
  big_t = cast(1.0, f32)
  paths_neg = with seed(13i64) { sto_kou_jump_terminal(template_neg, jumps_template_neg, s0, mu, sigma, lambda_jump, cast(0.05, f32), eta_up, eta_dn, big_t) }
  paths_pos = with seed(17i64) { sto_kou_jump_terminal(template_pos, jumps_template_pos, s0, mu, sigma, lambda_jump, cast(0.95, f32), eta_up, eta_dn, big_t) }
  lr_neg = to_tensor(map(fn (s: f32) -> log(div(s, s0)), to_list(paths_neg)))
  lr_pos = to_tensor(map(fn (s: f32) -> log(div(s, s0)), to_list(paths_pos)))
  skew_neg = skewness_vec(copy(lr_neg))
  skew_pos = skewness_vec(copy(lr_pos))
  _ = assert_true(lt(skew_neg, cast(0.0, f32)), "p=0.05 (mostly downward jumps): sample skewness of log(S_T/S0) negative across 512 paths")
  assert_true(gt(skew_pos, cast(0.0, f32)), "p=0.95 (mostly upward jumps): sample skewness of log(S_T/S0) positive across 512 paths")
}
