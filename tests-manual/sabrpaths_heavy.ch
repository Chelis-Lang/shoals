module Shoals.Tests.SabrpathsHeavy
import Std.Test (assert_true)
import Nautilus.Stats (mean_vec, correlation_scalar)
import Shoals.SabrPaths (sabr_paths_terminal)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_sabr_zero_volvol_deterministic() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(64, i64))))
  f0 = cast(100.0, f32)
  alpha0 = cast(0.2, f32)
  beta = cast(0.5, f32)
  rho = cast(-0.3, f32)
  nu = cast(0.0, f32)
  big_t = cast(0.1, f32)
  n_steps = cast(50, i64)
  out = with seed(7i64) { sabr_paths_terminal(template, f0, alpha0, beta, rho, nu, big_t, n_steps) }
  mean_f = mean_vec(out.0)
  diff = abs_f32(sub(mean_f, f0))
  rel = div(diff, f0)
  log_f0 = log(f0)
  beta_minus_one = sub(beta, cast(1.0, f32))
  f0_pow_bm1 = exp(mul(beta_minus_one, log_f0))
  sigma_eff = mul(alpha0, mul(f0_pow_bm1, sqrt(big_t)))
  std_per_path = mul(f0, sigma_eff)
  se_mc = div(std_per_path, sqrt(cast(64.0, f32)))
  tol = div(mul(cast(3.0, f32), se_mc), f0)
  assert_true(lt(rel, tol), "with nu=0, F follows CEV with constant alpha; martingale E[F_T] approx F_0 at 64 paths within 3*SE_mc")
}
def test_sabr_alpha_lognormal_marginal() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(100, i64))))
  f0 = cast(100.0, f32)
  alpha0 = cast(0.2, f32)
  beta = cast(0.5, f32)
  rho = cast(-0.3, f32)
  nu = cast(0.5, f32)
  big_t = cast(1.0, f32)
  n_steps = cast(100, i64)
  out = with seed(11i64) { sabr_paths_terminal(template, f0, alpha0, beta, rho, nu, big_t, n_steps) }
  mean_alpha = mean_vec(out.1)
  diff = abs_f32(sub(mean_alpha, alpha0))
  var_factor = sub(exp(mul(mul(nu, nu), big_t)), cast(1.0, f32))
  std_per_path = mul(alpha0, sqrt(var_factor))
  se_mc = div(std_per_path, sqrt(cast(100.0, f32)))
  tol = mul(cast(3.0, f32), se_mc)
  assert_true(lt(diff, tol), "alpha is exact log-Euler martingale: E[alpha_T] approx alpha_0 at 100 paths within 3*SE_mc")
}
def test_sabr_f_nonneg() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(64, i64))))
  f0 = cast(100.0, f32)
  alpha0 = cast(0.2, f32)
  beta = cast(0.3, f32)
  rho = cast(-0.95, f32)
  nu = cast(2.0, f32)
  big_t = cast(2.0, f32)
  n_steps = cast(100, i64)
  out = with seed(13i64) { sabr_paths_terminal(template, f0, alpha0, beta, rho, nu, big_t, n_steps) }
  f_l = to_list(out.0)
  init = true
  all_nonneg = fold(fn (acc: bool, fv: f32) -> and(acc, gte(fv, cast(0.0, f32))), init, f_l)
  assert_true(all_nonneg, "under extreme SABR params (beta=0.3, rho=-0.95, nu=2.0, T=2y), all 64 terminal F values stay non-negative thanks to clamp")
}
def test_sabr_zero_correlation_independence() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(256, i64))))
  f0 = cast(100.0, f32)
  alpha0 = cast(0.2, f32)
  beta = cast(0.5, f32)
  rho = cast(0.0, f32)
  nu = cast(0.5, f32)
  big_t = cast(1.0, f32)
  n_steps = cast(50, i64)
  out = with seed(17i64) { sabr_paths_terminal(template, f0, alpha0, beta, rho, nu, big_t, n_steps) }
  f_l = to_list(out.0)
  alpha_l = to_list(out.1)
  log_f = to_tensor(map(fn (fv: f32) -> log(fv), f_l))
  log_alpha = to_tensor(map(fn (av: f32) -> log(av), alpha_l))
  corr = correlation_scalar(copy(log_f), log_alpha)
  abs_corr = abs_f32(corr)
  assert_true(lt(abs_corr, cast(0.2, f32)), "with rho=0 the F-driving and alpha-driving Brownians are independent; sample corr(log F_T, log alpha_T) stays within +/- 0.2 across 256 paths (3*SE under H0 is 0.187)")
}
