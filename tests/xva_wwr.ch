module Shoals.Tests.XvaWwr
import Std.Test (assert_close, assert_true)
import Nautilus.Stats (mean_vec, std_vec)
import Shoals.Xva (cva_constant_hazard, xva_cva_wwr_constant_hazard)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def xvaw_time_grid() -> tensor[5, f32] = to_tensor([cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(3.0, f32), cast(5.0, f32)])
def xvaw_epe() -> tensor[5, f32] = to_tensor([cast(0.0, f32), cast(10.0, f32), cast(15.0, f32), cast(12.0, f32), cast(8.0, f32)])
def test_wwr_at_zero_correlation_reduces_to_cva() -> unit ! { Test } = {
  hazard = cast(0.05, f32)
  recovery = cast(0.4, f32)
  rate = cast(0.03, f32)
  n_paths = cast(256, int64)
  cva_bare = cva_constant_hazard(xvaw_time_grid(), xvaw_epe(), hazard, recovery, rate)
  k_outer = cast(16, int64)
  k_idxs = range(cast(0, int64), k_outer)
  wwr_means = with seed(101) { map(fn (k: int64) -> xva_cva_wwr_constant_hazard(xvaw_time_grid(), xvaw_epe(), hazard, recovery, rate, cast(0.0, f32), n_paths), k_idxs) }
  wwr_mean_tensor = to_tensor(wwr_means)
  est_mean = mean_vec(copy(wwr_mean_tensor))
  est_sd_across_runs = std_vec(wwr_mean_tensor, cast(1, int64))
  se_mc = div(est_sd_across_runs, sqrt(cast(k_outer, f32)))
  diff = sub(est_mean, cva_bare)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  tol = mul(cast(3.0, f32), se_mc)
  ok = lt(abs_diff, tol)
  assert_close(to01(ok), cast(1.0, f32), cast(0.001, f32), "rho=0 WWR-CVA agrees with cva_constant_hazard within 3*SE_mc across 16 batches of 256 paths")
}
def test_wwr_positive_correlation_increases_cva() -> unit ! { Test } = {
  hazard = cast(0.05, f32)
  recovery = cast(0.4, f32)
  rate = cast(0.03, f32)
  n_paths = cast(2048, int64)
  cva_zero = with seed(11) { xva_cva_wwr_constant_hazard(xvaw_time_grid(), xvaw_epe(), hazard, recovery, rate, cast(0.0, f32), n_paths) }
  cva_pos = with seed(11) { xva_cva_wwr_constant_hazard(xvaw_time_grid(), xvaw_epe(), hazard, recovery, rate, cast(0.7, f32), n_paths) }
  assert_true(gt(cva_pos, cva_zero), "rho=0.7 WWR-CVA strictly exceeds rho=0 (sign-of-effect probe for WWR coupling)")
}
def test_wwr_negative_correlation_reduces_cva() -> unit ! { Test } = {
  hazard = cast(0.05, f32)
  recovery = cast(0.4, f32)
  rate = cast(0.03, f32)
  n_paths = cast(2048, int64)
  cva_zero = with seed(13) { xva_cva_wwr_constant_hazard(xvaw_time_grid(), xvaw_epe(), hazard, recovery, rate, cast(0.0, f32), n_paths) }
  cva_neg = with seed(13) { xva_cva_wwr_constant_hazard(xvaw_time_grid(), xvaw_epe(), hazard, recovery, rate, cast(-0.5, f32), n_paths) }
  assert_true(lt(cva_neg, cva_zero), "rho=-0.5 WWR-CVA strictly less than rho=0 (right-way-risk sign-of-effect probe)")
}
def test_wwr_finite_at_extreme_correlation() -> unit ! { Test } = {
  hazard = cast(0.05, f32)
  recovery = cast(0.4, f32)
  rate = cast(0.03, f32)
  n_paths = cast(256, int64)
  cva_extreme = with seed(17) { xva_cva_wwr_constant_hazard(xvaw_time_grid(), xvaw_epe(), hazard, recovery, rate, cast(0.99, f32), n_paths) }
  is_finite = and(gt(cva_extreme, cast(0.0, f32)), lt(cva_extreme, cast(1000000000.0, f32)))
  assert_close(to01(is_finite), cast(1.0, f32), cast(0.001, f32), "rho=0.99 WWR-CVA is finite and strictly positive (no NaN/Inf at extreme correlation)")
}
