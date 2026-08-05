module Shoals.Tests.StochasticExtended
import Std.Test (assert_close, assert_true)
import Nautilus.Stats (mean_vec, std_vec)
import Shoals.Stochastic (merton_compensated_drift, merton_jump_terminal, cholesky_2x2_lower, correlated_gbm_terminal_2d)
def test_merton_compensated_drift_zero_lambda_equals_gbm() -> unit ! { Test } = {
  d = merton_compensated_drift(cast(0.05, f32), cast(0.2, f32), cast(0.0, f32), cast(-0.1, f32), cast(0.1, f32))
  expected = sub(cast(0.05, f32), mul(cast(0.5, f32), mul(cast(0.2, f32), cast(0.2, f32))))
  assert_close(d, expected, cast(1e-6, f32), "lambda=0 reduces Merton drift to GBM drift")
}
def test_merton_compensated_drift_subtracts_expected_jump_contribution() -> unit ! { Test } = {
  d = merton_compensated_drift(cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.0, f32), cast(0.1, f32))
  half_sigma_sq = mul(cast(0.5, f32), mul(cast(0.2, f32), cast(0.2, f32)))
  half_jump_vol_sq = mul(cast(0.5, f32), mul(cast(0.1, f32), cast(0.1, f32)))
  expected_jump = sub(exp(add(cast(0.0, f32), half_jump_vol_sq)), cast(1.0, f32))
  expected_d = sub(sub(cast(0.05, f32), half_sigma_sq), mul(cast(1.0, f32), expected_jump))
  assert_close(d, expected_d, cast(1e-6, f32), "lambda=1 subtracts E[exp(J)-1]")
}
def test_cholesky_2x2_identity() -> unit ! { Test } = {
  out = cholesky_2x2_lower(cast(1.0, f32), cast(0.0, f32), cast(1.0, f32))
  _ = assert_close(out.0, cast(1.0, f32), cast(1e-6, f32), "L11 = 1")
  _ = assert_close(out.1, cast(0.0, f32), cast(1e-6, f32), "L21 = 0")
  assert_close(out.2, cast(1.0, f32), cast(1e-6, f32), "L22 = 1")
}
def test_cholesky_2x2_correlated() -> unit ! { Test } = {
  out = cholesky_2x2_lower(cast(4.0, f32), cast(2.0, f32), cast(3.0, f32))
  _ = assert_close(out.0, cast(2.0, f32), cast(1e-6, f32), "L11 = sqrt(4) = 2")
  _ = assert_close(out.1, cast(1.0, f32), cast(1e-6, f32), "L21 = 2/2 = 1")
  assert_close(out.2, sqrt(cast(2.0, f32)), cast(1e-6, f32), "L22 = sqrt(3 - 1) = sqrt(2)")
}
def test_cholesky_round_trip_recovers_covariance() -> unit ! { Test } = {
  sigma_xx = cast(0.04, f32)
  sigma_xy = cast(0.012, f32)
  sigma_yy = cast(0.09, f32)
  out = cholesky_2x2_lower(sigma_xx, sigma_xy, sigma_yy)
  recon_xx = mul(out.0, out.0)
  recon_xy = mul(out.0, out.1)
  recon_yy = add(mul(out.1, out.1), mul(out.2, out.2))
  _ = assert_close(recon_xx, sigma_xx, cast(1e-6, f32), "L L^T [0,0] = Sigma_xx")
  _ = assert_close(recon_xy, sigma_xy, cast(1e-6, f32), "L L^T [1,0] = Sigma_xy")
  assert_close(recon_yy, sigma_yy, cast(1e-6, f32), "L L^T [1,1] = Sigma_yy")
}
def test_merton_terminal_positive_paths() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(2000, int64))))
  jumps_template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(2000, int64))))
  paths = with seed(11i64) { merton_jump_terminal(template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.3, f32), cast(-0.1, f32), cast(0.15, f32), cast(1.0, f32)) }
  paths_l = to_list(paths)
  init = true
  all_pos = fold(fn (acc: bool, p: f32) -> and(acc, gt(p, cast(0.0, f32))), init, paths_l)
  assert_true(all_pos, "all Merton-jump terminal values are positive")
}
def test_merton_terminal_mean_near_s0_exp_mu_t() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(5000, int64))))
  jumps_template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(5000, int64))))
  paths = with seed(7i64) { merton_jump_terminal(template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.3, f32), cast(-0.1, f32), cast(0.15, f32), cast(1.0, f32)) }
  m = mean_vec(paths)
  expected = mul(cast(100.0, f32), exp(cast(0.05, f32)))
  rel_err = div(sub(m, expected), expected)
  abs_err = if lt(rel_err, cast(0.0, f32)) then neg(rel_err) else rel_err
  assert_true(lt(abs_err, cast(0.05, f32)), "Merton terminal mean within 5% of S0*exp(mu*t) for compensated drift")
}
def test_correlated_gbm_2d_marginals() -> unit ! { Test } = {
  template_x = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(5000, int64))))
  template_y = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(5000, int64))))
  out = with seed(13i64) { correlated_gbm_terminal_2d(template_x, template_y, cast(100.0, f32), cast(50.0, f32), cast(0.04, f32), cast(0.06, f32), cast(0.2, f32), cast(0.3, f32), cast(0.5, f32), cast(1.0, f32)) }
  m_x = mean_vec(out.0)
  m_y = mean_vec(out.1)
  exp_x = mul(cast(100.0, f32), exp(cast(0.04, f32)))
  exp_y = mul(cast(50.0, f32), exp(cast(0.06, f32)))
  rel_err_x = div(sub(m_x, exp_x), exp_x)
  rel_err_y = div(sub(m_y, exp_y), exp_y)
  abs_x = if lt(rel_err_x, cast(0.0, f32)) then neg(rel_err_x) else rel_err_x
  abs_y = if lt(rel_err_y, cast(0.0, f32)) then neg(rel_err_y) else rel_err_y
  _ = assert_true(lt(abs_x, cast(0.05, f32)), "X marginal mean within 5%")
  assert_true(lt(abs_y, cast(0.05, f32)), "Y marginal mean within 5%")
}
def test_correlated_gbm_2d_rho_zero_positive_dispersion() -> unit ! { Test } = {
  template_x = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(100, int64))))
  template_y = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(100, int64))))
  out = with seed(17i64) { correlated_gbm_terminal_2d(template_x, template_y, cast(100.0, f32), cast(100.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.2, f32), cast(0.2, f32), cast(0.0, f32), cast(1.0, f32)) }
  s_x = std_vec(out.0, cast(1, int64))
  assert_true(gt(s_x, cast(0.0, f32)), "X has positive dispersion under rho=0")
}
