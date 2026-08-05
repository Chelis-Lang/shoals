module Shoals.Tests.ModelfitSabrInit
import Std.Test (assert_close, assert_true)
import Shoals.ModelFit (mf_sabr_smart_initializer, mf_sabr_multi_start_initializer)
import Shoals.VolSurface (SABR, vs_sabr_implied_vol)
def msi_abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def msi_is_finite(x: f32) -> bool = if neq(x, x) then false else lt(msi_abs_f32(x), cast(1000000000.0, f32))
def msi_build_smile_5(alpha: f32, beta: f32, rho: f32, nu: f32, forward: f32, t: f32) -> (tensor[5, f32], tensor[5, f32]) = {
  params = SABR { alpha, beta, rho, nu }
  ks = to_tensor([mul(cast(0.8, f32), forward), mul(cast(0.9, f32), forward), forward, mul(cast(1.1, f32), forward), mul(cast(1.2, f32), forward)])
  k_l = to_list(copy(ks))
  ivs = to_tensor(map(fn (k: f32) -> vs_sabr_implied_vol(params, forward, k, t), k_l))
  (ks, ivs)
}
def test_sabr_init_atm_alpha_recovery() -> unit ! { Test } = {
  forward = cast(100.0, f32)
  t = cast(1.0, f32)
  alpha_true = cast(0.4, f32)
  beta_smart = cast(0.5, f32)
  rho_true = cast(-0.3, f32)
  nu_true = cast(0.5, f32)
  smile = msi_build_smile_5(alpha_true, beta_smart, rho_true, nu_true, forward, t)
  ks = smile.0
  ivs = smile.1
  theta0 = mf_sabr_smart_initializer(copy(ks), copy(ivs), forward, t)
  th_l = to_list(theta0)
  alpha_0 = index(th_l, cast(0, int64))
  rel_err = div(msi_abs_f32(sub(alpha_0, alpha_true)), alpha_true)
  assert_true(lt(rel_err, cast(0.2, f32)), "alpha_0 within 20% relative of true alpha when beta matches smart-init convention 0.5 (heuristic ATM recovery)")
}
def test_sabr_init_skew_sign_recovers_rho_sign() -> unit ! { Test } = {
  forward = cast(100.0, f32)
  t = cast(1.0, f32)
  alpha = cast(0.3, f32)
  beta = cast(0.5, f32)
  nu = cast(0.5, f32)
  neg_smile = msi_build_smile_5(alpha, beta, cast(-0.5, f32), nu, forward, t)
  neg_theta = mf_sabr_smart_initializer(copy(neg_smile.0), copy(neg_smile.1), forward, t)
  neg_th_l = to_list(neg_theta)
  rho_neg = index(neg_th_l, cast(2, int64))
  pos_smile = msi_build_smile_5(alpha, beta, cast(0.5, f32), nu, forward, t)
  pos_theta = mf_sabr_smart_initializer(copy(pos_smile.0), copy(pos_smile.1), forward, t)
  pos_th_l = to_list(pos_theta)
  rho_pos = index(pos_th_l, cast(2, int64))
  _ = assert_true(lt(rho_neg, cast(0.0, f32)), "negative-skew smile yields rho_0 < 0")
  assert_true(gt(rho_pos, cast(0.0, f32)), "positive-skew smile yields rho_0 > 0")
}
def test_sabr_init_convexity_recovers_nu_positive() -> unit ! { Test } = {
  forward = cast(100.0, f32)
  t = cast(1.0, f32)
  smile = msi_build_smile_5(cast(0.3, f32), cast(0.5, f32), cast(-0.2, f32), cast(0.6, f32), forward, t)
  theta0 = mf_sabr_smart_initializer(copy(smile.0), copy(smile.1), forward, t)
  th_l = to_list(theta0)
  nu_0 = index(th_l, cast(3, int64))
  assert_true(gt(nu_0, cast(0.0, f32)), "non-degenerate convex smile -> nu_0 > 0")
}
def test_sabr_init_clipping() -> unit ! { Test } = {
  forward = cast(100.0, f32)
  t = cast(1.0, f32)
  ks = to_tensor([cast(80.0, f32), cast(90.0, f32), cast(100.0, f32), cast(110.0, f32), cast(120.0, f32)])
  ivs_extreme = to_tensor([cast(0.5, f32), cast(0.4, f32), cast(0.2, f32), cast(0.7, f32), cast(0.9, f32)])
  theta0 = mf_sabr_smart_initializer(copy(ks), copy(ivs_extreme), forward, t)
  th_l = to_list(theta0)
  rho_0 = index(th_l, cast(2, int64))
  nu_0 = index(th_l, cast(3, int64))
  _ = assert_true(if gte(rho_0, cast(-0.9, f32)) then lte(rho_0, cast(0.9, f32)) else false, "rho_0 clipped to [-0.9, 0.9]")
  assert_true(if gte(nu_0, cast(0.1, f32)) then lte(nu_0, cast(3.0, f32)) else false, "nu_0 clipped to [0.1, 3.0]")
}
def test_sabr_multi_start_returns_5_candidates() -> unit ! { Test } = {
  forward = cast(100.0, f32)
  t = cast(1.0, f32)
  smile = msi_build_smile_5(cast(0.3, f32), cast(0.5, f32), cast(-0.2, f32), cast(0.4, f32), forward, t)
  multi = mf_sabr_multi_start_initializer(copy(smile.0), copy(smile.1), forward, t)
  flat = to_list(reshape(multi, [cast(20, int64)]))
  rho_targets = [cast(-0.7, f32), cast(-0.3, f32), cast(0.0, f32), cast(0.3, f32), cast(0.7, f32)]
  idxs = range(cast(0, int64), cast(5, int64))
  rho_pairs = zip(idxs, rho_targets)
  all_finite = fold(fn (acc: bool, x: f32) -> if acc then msi_is_finite(x) else false, true, flat)
  rho_check = fold(fn (acc: bool, pair: (int64, f32)) -> {
    i = pair.0
    expected = pair.1
    flat_idx = add(mul(i, cast(4, int64)), cast(2, int64))
    actual = index(flat, flat_idx)
    diff = msi_abs_f32(sub(actual, expected))
    if acc then lt(diff, cast(1e-6, f32)) else false
  }, true, rho_pairs)
  _ = assert_true(all_finite, "all 20 entries of the 5x4 multi-start tensor are finite")
  assert_true(rho_check, "rho component sweeps {-0.7, -0.3, 0, 0.3, 0.7} across the 5 candidates")
}
