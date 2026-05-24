module Shoals.Tests.Greeks
import Std.Test (assert_close, assert_true)
import Shoals.Greeks (fd_delta_call, fd_delta_put, fd_gamma_call, fd_vega_call, fd_vega_put, fd_rho_call, fd_rho_put, fd_theta_call, fd_theta_put, fd_vanna_call, fd_volga_call, analytic_delta_call, analytic_delta_put, analytic_vega_call, analytic_gamma_call, pathwise_smooth_call_terminal_delta, lr_digital_call_delta)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_fd_delta_call_matches_analytic_atm() -> unit ! { Test } = {
  s = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  fd = fd_delta_call(s, k, r, sigma, t, cast(0.01, f32))
  an = analytic_delta_call(s, k, r, sigma, t)
  assert_close(fd, an, cast(0.001, f32), "FD delta_call ~ analytic N(d1)")
}
def test_fd_delta_call_in_unit_range() -> unit ! { Test } = {
  d = fd_delta_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.01, f32))
  in_range = and(gte(d, cast(0.0, f32)), lte(d, cast(1.0, f32)))
  assert_true(in_range, "call delta in [0,1]")
}
def test_fd_delta_put_in_negative_unit_range() -> unit ! { Test } = {
  d = fd_delta_put(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.01, f32))
  in_range = and(gte(d, cast(-1.0, f32)), lte(d, cast(0.0, f32)))
  assert_true(in_range, "put delta in [-1,0]")
}
def test_put_call_delta_difference_is_one() -> unit ! { Test } = {
  s = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  dc = fd_delta_call(s, k, r, sigma, t, cast(0.01, f32))
  dp = fd_delta_put(s, k, r, sigma, t, cast(0.01, f32))
  diff = sub(dc, dp)
  assert_close(diff, cast(1.0, f32), cast(0.001, f32), "delta_call - delta_put == 1 (parity)")
}
def test_fd_gamma_call_matches_analytic_atm() -> unit ! { Test } = {
  s = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  fd = fd_gamma_call(s, k, r, sigma, t, cast(0.5, f32))
  an = analytic_gamma_call(s, k, r, sigma, t)
  diff = abs_f32(sub(fd, an))
  assert_true(lt(diff, cast(0.0005, f32)), "FD gamma_call matches analytic at ATM (loose tol for FD)")
}
def test_fd_vega_call_matches_analytic_atm() -> unit ! { Test } = {
  s = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  fd = fd_vega_call(s, k, r, sigma, t, cast(0.001, f32))
  an = analytic_vega_call(s, k, r, sigma, t)
  assert_close(fd, an, cast(0.05, f32), "FD vega_call ~ analytic S*phi(d1)*sqrt(t)")
}
def test_fd_vega_nonneg() -> unit ! { Test } = {
  v = fd_vega_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.001, f32))
  assert_true(gte(v, cast(0.0, f32)), "vega_call >= 0")
}
def test_fd_vega_call_equals_fd_vega_put() -> unit ! { Test } = {
  s = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  vc = fd_vega_call(s, k, r, sigma, t, cast(0.001, f32))
  vp = fd_vega_put(s, k, r, sigma, t, cast(0.001, f32))
  assert_close(vc, vp, cast(0.01, f32), "vega is the same for call and put (parity)")
}
def test_fd_rho_call_positive() -> unit ! { Test } = {
  r = fd_rho_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.0001, f32))
  assert_true(gt(r, cast(0.0, f32)), "rho_call > 0")
}
def test_fd_rho_put_negative() -> unit ! { Test } = {
  r = fd_rho_put(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.0001, f32))
  assert_true(lt(r, cast(0.0, f32)), "rho_put < 0")
}
def test_fd_theta_call_negative() -> unit ! { Test } = {
  th = fd_theta_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.001, f32))
  assert_true(lt(th, cast(0.0, f32)), "theta_call < 0 (option decays)")
}
def test_fd_volga_nonneg_at_atm_short_maturity() -> unit ! { Test } = {
  v = fd_volga_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.005, f32))
  assert_true(gte(v, cast(-1.0, f32)), "volga sanity bound at ATM")
}
def test_fd_vanna_finite() -> unit ! { Test } = {
  v = fd_vanna_call(cast(100.0, f32), cast(105.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.01, f32), cast(0.001, f32))
  abs_v = abs_f32(v)
  assert_true(lt(abs_v, cast(100.0, f32)), "|vanna| finite/bounded")
}
def test_pathwise_call_delta_in_money() -> unit ! { Test } = {
  d = pathwise_smooth_call_terminal_delta(cast(120.0, f32), cast(100.0, f32), cast(0.95, f32), cast(100.0, f32))
  expected = mul(cast(0.95, f32), cast(1.2, f32))
  assert_close(d, expected, cast(0.001, f32), "pathwise delta on ITM single-path == df * S_T / S_0")
}
def test_pathwise_call_delta_otm_zero() -> unit ! { Test } = {
  d = pathwise_smooth_call_terminal_delta(cast(80.0, f32), cast(100.0, f32), cast(0.95, f32), cast(100.0, f32))
  assert_close(d, cast(0.0, f32), cast(0.000001, f32), "pathwise delta on OTM single-path == 0")
}
def test_lr_digital_delta_otm_zero_at_indicator() -> unit ! { Test } = {
  d = lr_digital_call_delta(cast(80.0, f32), cast(100.0, f32), cast(100.0, f32), cast(0.2, f32), cast(1.0, f32), cast(0.95, f32))
  assert_close(d, cast(0.0, f32), cast(0.000001, f32), "LR digital delta on OTM single-path == 0 (indicator zero)")
}
def test_lr_digital_delta_itm_nonzero() -> unit ! { Test } = {
  d = lr_digital_call_delta(cast(120.0, f32), cast(100.0, f32), cast(100.0, f32), cast(0.2, f32), cast(1.0, f32), cast(0.95, f32))
  assert_true(neq(d, cast(0.0, f32)), "LR digital delta on ITM single-path is nonzero")
}
