module Shoals.Tests.HullWhiteHeavy
import Std.Test (assert_true)
import Nautilus.Distributions (normal_sample)
import Nautilus.Stats (mean_vec, correlation_scalar)
import Shoals.HullWhite (hw1f_step, hw1f_path, hw1f_bond_price, hw2f_path)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_hw1f_path_mean_reversion() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(64, i64))))
  r0 = cast(0.05, f32)
  theta_bar = cast(0.02, f32)
  a = cast(0.5, f32)
  sigma = cast(0.001, f32)
  big_t = cast(20.0, f32)
  n_steps = cast(200, i64)
  paths = hw1f_path(key_from_seed(7i64), template, r0, a, theta_bar, sigma, big_t, n_steps)
  m = mean_vec(paths)
  diff = abs_f32(sub(m, theta_bar))
  assert_true(lt(diff, cast(0.005, f32)), "HW1F low-noise long-horizon E[r_T] converges to theta_bar=0.02 within 0.005 at 64 paths x 200 steps over T=20y")
}
def test_hw1f_path_vs_bond_analytic() -> unit ! { Test } = {
  n_paths = cast(64, i64)
  n_steps = cast(200, i64)
  r0 = cast(0.03, f32)
  a = cast(0.3, f32)
  sigma = cast(0.01, f32)
  big_t = cast(5.0, f32)
  dt = div(big_t, cast(n_steps, f32))
  total = mul(n_paths, n_steps)
  big_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), total)))
  z_t = normal_sample(key_from_seed(11i64), big_template, cast(0.0, f32), cast(1.0, f32))
  z_l = to_list(z_t)
  path_idxs = range(cast(0, i64), n_paths)
  disc_factors = to_tensor(map(fn (p: i64) -> {
    base = mul(p, n_steps)
    step_idxs = range(cast(0, i64), n_steps)
    final_state = fold(fn (state: (f32, f32), i: i64) -> {
      r = state.0
      disc = state.1
      k = add(base, i)
      z = index(z_l, k)
      r_next = hw1f_step(r, a, cast(0.0, f32), sigma, dt, z)
      r_avg = mul(cast(0.5, f32), add(r, r_next))
      disc_next = mul(disc, exp(neg(mul(r_avg, dt))))
      (r_next, disc_next)
    }, (r0, cast(1.0, f32)), step_idxs)
    final_state.1
  }, path_idxs))
  n_f = cast(n_paths, f32)
  disc_l = to_list(disc_factors)
  moments = fold(fn (acc: (f32, f32), v: f32) -> (add(acc.0, v), add(acc.1, mul(v, v))), (cast(0.0, f32), cast(0.0, f32)), disc_l)
  mc_price = div(moments.0, n_f)
  mean_sq = div(moments.1, n_f)
  variance = mul(div(n_f, sub(n_f, cast(1.0, f32))), sub(mean_sq, mul(mc_price, mc_price)))
  se = sqrt(div(variance, n_f))
  analytic = hw1f_bond_price(cast(0.0, f32), big_t, r0, a, sigma)
  diff = abs_f32(sub(mc_price, analytic))
  tol = mul(cast(3.0, f32), se)
  assert_true(lt(diff, tol), "HW1F MC discount-factor mean matches analytic bond price within 3 standard errors at 64 paths x 200 steps over T=5y")
}
def test_hw1f_zero_vol_deterministic() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(1, i64))))
  r0 = cast(0.05, f32)
  theta_bar = cast(0.02, f32)
  a = cast(0.4, f32)
  sigma = cast(0.0, f32)
  big_t = cast(3.0, f32)
  n_steps = cast(4000, i64)
  paths = hw1f_path(key_from_seed(19i64), template, r0, a, theta_bar, sigma, big_t, n_steps)
  r_terminal = index(to_list(paths), cast(0, i64))
  expected = add(theta_bar, mul(sub(r0, theta_bar), exp(neg(mul(a, big_t)))))
  rel_err = div(abs_f32(sub(r_terminal, expected)), abs_f32(expected))
  assert_true(lt(rel_err, cast(0.0001, f32)), "HW1F sigma=0 reduces to deterministic ODE r_T = theta_bar + (r_0 - theta_bar) * exp(-a*T) within 1e-4 relative error")
}
def test_hw2f_correlation_recovery() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(128, i64))))
  rho = cast(0.7, f32)
  out = hw2f_path(key_from_seed(23i64), template, cast(0.0, f32), cast(0.0, f32), cast(0.5, f32), cast(0.3, f32), cast(0.01, f32), cast(0.015, f32), rho, cast(2.0, f32), cast(50, i64))
  corr = correlation_scalar(out.0, out.1)
  diff = abs_f32(sub(corr, rho))
  assert_true(lt(diff, cast(0.15, f32)), "HW2F sample corr(x_T, y_T) at 128 paths x 50 steps recovers target rho=0.7 within 0.15 (~3 sigma at N=128 for rho=0.7)")
}
def test_hw2f_zero_correlation_independence() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(128, i64))))
  rho = cast(0.0, f32)
  out = hw2f_path(key_from_seed(29i64), template, cast(0.0, f32), cast(0.0, f32), cast(0.5, f32), cast(0.3, f32), cast(0.01, f32), cast(0.015, f32), rho, cast(2.0, f32), cast(50, i64))
  corr = correlation_scalar(out.0, out.1)
  assert_true(lt(abs_f32(corr), cast(0.25, f32)), "HW2F sample |corr(x_T, y_T)| at 128 paths x 50 steps under rho=0 stays below 0.25 (~3 sigma at N=128)")
}
