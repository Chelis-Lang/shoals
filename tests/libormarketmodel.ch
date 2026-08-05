module Shoals.Tests.LiborMarketModel
import Std.Test (assert_close, assert_true)
import Nautilus.Stats (mean_vec, std_vec)
import Shoals.LiborMarketModel (lmm_step, lmm_path, hjm_no_arb_drift, step_hjm)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def lmm_identity_corr_4() -> tensor[4, 4, f32] = {
  flat = to_tensor([cast(1.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(1.0, f32)])
  reshape(flat, [cast(4, int64), cast(4, int64)])
}
def lmm_const_vec_4(v: f32) -> tensor[4, f32] = to_tensor([v, v, v, v])
def test_lmm_zero_vol_deterministic() -> unit ! { Test } = {
  forwards0 = to_tensor([cast(0.03, f32), cast(0.035, f32), cast(0.04, f32), cast(0.045, f32)])
  taus = lmm_const_vec_4(cast(0.25, f32))
  sigmas = lmm_const_vec_4(cast(0.0, f32))
  corr = lmm_identity_corr_4()
  paths_template = to_tensor([cast(0.0, f32)])
  r0 = with seed(1i64) { lmm_path(copy(paths_template), copy(forwards0), copy(taus), copy(sigmas), copy(corr), cast(1.0, f32), cast(10, int64), cast(0, int64)) }
  r3 = with seed(1i64) { lmm_path(paths_template, forwards0, taus, sigmas, corr, cast(1.0, f32), cast(10, int64), cast(3, int64)) }
  v0 = index(to_list(r0), cast(0, int64))
  v3 = index(to_list(r3), cast(0, int64))
  _ = assert_close(v0, cast(0.03, f32), cast(0.00001, f32), "L_0(T) == L_0(0) when vol=0")
  assert_close(v3, cast(0.045, f32), cast(0.00001, f32), "L_3(T) == L_3(0) when vol=0")
}
def test_lmm_martingale_at_zero_drift() -> unit ! { Test } = {
  n_paths = cast(128, int64)
  forwards0 = to_tensor([cast(0.03, f32), cast(0.035, f32), cast(0.04, f32), cast(0.045, f32)])
  taus = lmm_const_vec_4(cast(0.25, f32))
  sigmas = lmm_const_vec_4(cast(0.2, f32))
  corr = lmm_identity_corr_4()
  paths_template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), n_paths)))
  l_last = with seed(42i64) { lmm_path(paths_template, forwards0, taus, sigmas, corr, cast(1.0, f32), cast(50, int64), cast(3, int64)) }
  e_l_last = mean_vec(copy(l_last))
  s_l_last = std_vec(l_last, cast(1, int64))
  se_mc = div(s_l_last, sqrt(cast(n_paths, f32)))
  diff = sub(e_l_last, cast(0.045, f32))
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  tol = mul(cast(3.0, f32), se_mc)
  ok = lt(abs_diff, tol)
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "|E[L_N(T)] - L_N(0)| < 3*SE_mc under terminal measure (L_N is martingale at 128 paths)")
}
def test_lmm_forward_positivity() -> unit ! { Test } = {
  n_paths = cast(32, int64)
  forwards0 = to_tensor([cast(0.03, f32), cast(0.035, f32), cast(0.04, f32), cast(0.045, f32)])
  taus = lmm_const_vec_4(cast(0.25, f32))
  sigmas = lmm_const_vec_4(cast(0.5, f32))
  corr = lmm_identity_corr_4()
  paths_template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), n_paths)))
  l3 = with seed(7i64) { lmm_path(paths_template, forwards0, taus, sigmas, corr, cast(5.0, f32), cast(60, int64), cast(3, int64)) }
  l3_list = to_list(l3)
  all_pos = fold(fn (acc: bool, v: f32) -> and(acc, gt(v, cast(0.0, f32))), true, l3_list)
  assert_true(all_pos, "longest-tenor forward L_3 stays strictly positive over 32 paths x 60 steps at sigma=0.5, T=5y (shifted-lognormal positivity is structural)")
}
def test_hjm_no_arb_drift_zero_at_zero_vol() -> unit ! { Test } = {
  sigmas = to_tensor([cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32)])
  taus = to_tensor([cast(0.25, f32), cast(0.25, f32), cast(0.25, f32), cast(0.25, f32)])
  drift = hjm_no_arb_drift(sigmas, taus)
  drift_l = to_list(drift)
  all_zero = fold(fn (acc: bool, v: f32) -> and(acc, eq(v, cast(0.0, f32))), true, drift_l)
  assert_true(all_zero, "hjm_no_arb_drift is identically zero when all sigmas are zero")
}
def test_hjm_drift_positive_for_positive_vol() -> unit ! { Test } = {
  sigmas = to_tensor([cast(0.01, f32), cast(0.012, f32), cast(0.015, f32), cast(0.02, f32)])
  taus = to_tensor([cast(0.25, f32), cast(0.25, f32), cast(0.25, f32), cast(0.25, f32)])
  drift = hjm_no_arb_drift(sigmas, taus)
  drift_l = to_list(drift)
  all_pos = fold(fn (acc: bool, v: f32) -> and(acc, gt(v, cast(0.0, f32))), true, drift_l)
  assert_true(all_pos, "hjm_no_arb_drift is strictly positive for strictly positive sigmas (canonical HJM upward bias)")
}
def test_lmm_step_zero_drift_last_forward() -> unit ! { Test } = {
  forwards = to_tensor([cast(0.03, f32), cast(0.04, f32), cast(0.05, f32), cast(0.06, f32)])
  taus = lmm_const_vec_4(cast(0.25, f32))
  sigmas = lmm_const_vec_4(cast(0.1, f32))
  corr = lmm_identity_corr_4()
  normals = to_tensor([cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32)])
  out = lmm_step(forwards, taus, sigmas, corr, cast(0.01, f32), normals)
  out_l = to_list(out)
  v3 = index(out_l, cast(3, int64))
  expected_v3 = mul(cast(0.06, f32), exp(mul(neg(cast(0.5, f32)), mul(cast(0.1, f32), mul(cast(0.1, f32), cast(0.01, f32))))))
  assert_close(v3, expected_v3, cast(1e-6, f32), "L_3 with z=0 evolves by drift -0.5*sigma^2*dt (zero terminal-measure drift for last forward)")
}
def test_hjm_step_zero_normal_pure_drift() -> unit ! { Test } = {
  forwards = to_tensor([cast(0.03, f32), cast(0.035, f32), cast(0.04, f32), cast(0.045, f32)])
  drifts = to_tensor([cast(0.001, f32), cast(0.002, f32), cast(0.003, f32), cast(0.004, f32)])
  sigmas = lmm_const_vec_4(cast(0.01, f32))
  normals = to_tensor([cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32)])
  out = step_hjm(forwards, drifts, sigmas, cast(0.5, f32), normals)
  out_l = to_list(out)
  v0 = index(out_l, cast(0, int64))
  v3 = index(out_l, cast(3, int64))
  _ = assert_close(v0, add(cast(0.03, f32), mul(cast(0.001, f32), cast(0.5, f32))), cast(1e-6, f32), "HJM step with z=0 advances f by drift*dt only (f_0)")
  assert_close(v3, add(cast(0.045, f32), mul(cast(0.004, f32), cast(0.5, f32))), cast(1e-6, f32), "HJM step with z=0 advances f by drift*dt only (f_3)")
}
