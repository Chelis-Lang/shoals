module Shoals.Tests.Csa
import Std.Test (assert_close, assert_true)
import Shoals.Csa (csa_collateralized_exposure, csa_collateralized_exposure_path)
def test_csa_exposure_below_threshold_no_collateral() -> unit ! { Test } = {
  eff = csa_collateralized_exposure(cast(50.0, f32), cast(100.0, f32), cast(10.0, f32), cast(0.0, f32), cast(0.0, f32))
  assert_close(eff, cast(50.0, f32), cast(0.000001, f32), "exposure 50 below threshold 100 -> effective 50 (no collateral demanded)")
}
def test_csa_exposure_above_threshold_mta_satisfied() -> unit ! { Test } = {
  eff = csa_collateralized_exposure(cast(200.0, f32), cast(100.0, f32), cast(10.0, f32), cast(0.0, f32), cast(0.0, f32))
  assert_close(eff, cast(100.0, f32), cast(0.000001, f32), "exposure 200 over threshold 100, MTA satisfied -> effective 100")
}
def test_csa_exposure_above_threshold_mta_blocks() -> unit ! { Test } = {
  eff = csa_collateralized_exposure(cast(105.0, f32), cast(100.0, f32), cast(10.0, f32), cast(0.0, f32), cast(0.0, f32))
  assert_close(eff, cast(105.0, f32), cast(0.000001, f32), "required 5 < MTA 10 -> no transfer, effective 105")
}
def test_csa_monotone_in_threshold() -> unit ! { Test } = {
  exposures = to_tensor([cast(50.0, f32), cast(150.0, f32), cast(300.0, f32), cast(500.0, f32)])
  effs_low = csa_collateralized_exposure_path(copy(exposures), cast(50.0, f32), cast(5.0, f32), cast(0.0, f32), cast(0.0, f32))
  effs_high = csa_collateralized_exposure_path(exposures, cast(200.0, f32), cast(5.0, f32), cast(0.0, f32), cast(0.0, f32))
  el_low = to_list(effs_low)
  el_high = to_list(effs_high)
  sum_low = fold(fn (a: f32, x: f32) -> add(a, x), cast(0.0, f32), el_low)
  sum_high = fold(fn (a: f32, x: f32) -> add(a, x), cast(0.0, f32), el_high)
  assert_true(gt(sum_high, sum_low), "increasing threshold -> increasing effective exposure (more uncollateralized)")
}
def test_csa_negative_exposure_clipped_to_zero() -> unit ! { Test } = {
  out = csa_collateralized_exposure(cast(-50.0, f32), cast(100.0, f32), cast(10.0, f32), cast(0.0, f32), cast(0.0, f32))
  assert_close(out, cast(0.0, f32), cast(0.0001, f32), "negative exposure (we owe counterparty) yields zero collateralized exposure")
}
