module Shoals.Tests.HestonLewis
import Std.Test (assert_close, assert_true)
import Shoals.Heston (heston_call_lewis_panels, heston_put_lewis_panels, heston_call_carr_madan_panels, heston_call_lipton_panels)
-- shoals#151: independent double-precision complex-CF / Simpson goldens,
-- checked against numerical integration of the Heston Riccati equations.
-- Model: S=100, T=1, v0=theta=0.04, kappa=1.5, sigma=0.5, rho=-0.7.
-- U=200 and 100 panels keep quadrature error below the 0.001 f32 allowance.
def lewis_call(k: f32, r: f32) -> f32 = heston_call_lewis_panels(100.0, k, 1.0, r, 0.04, 1.5, 0.04, 0.5, -0.7, 200.0, 100i64)
def lewis_put(k: f32, r: f32) -> f32 = heston_put_lewis_panels(100.0, k, 1.0, r, 0.04, 1.5, 0.04, 0.5, -0.7, 200.0, 100i64)
def test_lewis_itm_call_and_put_reference() -> unit ! { Test } = {
  _ = assert_close(lewis_call(80.0, 0.05), 25.29168764, 0.001, "ITM Lewis call matches independent reference away from forward")
  assert_close(lewis_put(80.0, 0.05), 1.3900416, 0.001, "ITM Lewis put matches independent reference")
}
def test_lewis_atm_nonzero_rate_call_and_put_reference() -> unit ! { Test } = {
  _ = assert_close(lewis_call(100.0, 0.05), 10.05548297, 0.001, "shoals#151 reproducer: spot-ATM is away from forward at r=5%")
  assert_close(lewis_put(100.0, 0.05), 5.17842542, 0.001, "spot-ATM Lewis put inherits corrected normalization")
}
def test_lewis_otm_call_and_put_reference() -> unit ! { Test } = {
  call_price = lewis_call(120.0, 0.05)
  _ = assert_close(call_price, 1.54914123, 0.001, "OTM call must not hide normalization error behind zero clamp")
  _ = assert_true(gt(call_price, 1.0), "OTM call is materially positive")
  assert_close(lewis_put(120.0, 0.05), 15.69667217, 0.001, "OTM Lewis put matches independent reference")
}
def test_lewis_negative_rate_reference() -> unit ! { Test } = {
  _ = assert_close(lewis_call(100.0, -0.03), 5.40206059, 0.001, "negative rate changes forward without restricting Lewis normalization")
  assert_close(lewis_put(100.0, -0.03), 8.44751398, 0.001, "negative-rate put matches independent reference")
}
def test_lewis_zero_rate_off_forward_reference() -> unit ! { Test } = {
  _ = assert_close(lewis_call(120.0, 0.0), 0.69140851, 0.001, "zero rate alone does not hide off-forward normalization defect")
  assert_close(lewis_put(120.0, 0.0), 20.69140851, 0.001, "zero-rate off-forward put reference")
}
def test_lewis_agrees_with_other_inversions_across_strikes() -> unit ! { Test } = {
  strikes = [80.0, 100.0, 120.0]
  pairs = map(fn (k: f32) -> {
    lw = lewis_call(k, 0.05)
    cm = heston_call_carr_madan_panels(100.0, k, 1.0, 0.05, 0.04, 1.5, 0.04, 0.5, -0.7, 1.5, 200.0, 100i64)
    lp = heston_call_lipton_panels(100.0, k, 1.0, 0.05, 0.04, 1.5, 0.04, 0.5, -0.7, 200.0, 100i64)
    and(lt(abs(sub(lw, cm)), 0.001), lt(abs(sub(lw, lp)), 0.001))
  }, strikes)
  assert_true(fold(fn (acc: bool, ok: bool) -> and(acc, ok), true, pairs), "Lewis / Carr-Madan / Lipton agree ITM, spot-ATM, and OTM at nonzero rate")
}
def test_lewis_nonzero_rate_parity() -> unit ! { Test } = {
  call_price = lewis_call(80.0, 0.05)
  put_price = lewis_put(80.0, 0.05)
  assert_close(sub(call_price, put_price), sub(100.0, mul(80.0, exp(-0.05))), 0.0001, "put-call parity holds away from forward at nonzero rate")
}
def test_lewis_panel_refinement() -> unit ! { Test } = {
  fine = heston_call_lewis_panels(100.0, 120.0, 1.0, 0.05, 0.04, 1.5, 0.04, 0.5, -0.7, 200.0, 200i64)
  assert_close(lewis_call(120.0, 0.05), fine, 0.001, "doubling panel resolution preserves independent OTM benchmark")
}
