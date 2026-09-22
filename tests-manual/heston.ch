module Shoals.Tests.Heston
import Std.Test (assert_true)
import Shoals.Stochastic (heston_qe_terminal)
import Shoals.Heston (heston_call_carr_madan_panels, heston_put_carr_madan_panels)
def to01(b: bool) -> f32 = if b then cast(1.0, f32) else cast(0.0, f32)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_heston_carr_madan_atm_parity_r_zero() -> unit ! { Test } = {
  call_p = heston_call_carr_madan_panels(cast(100.0, f32), cast(100.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.04, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(1.5, f32), cast(200.0, f32), cast(32, i64))
  put_p = heston_put_carr_madan_panels(cast(100.0, f32), cast(100.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.04, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(1.5, f32), cast(200.0, f32), cast(32, i64))
  diff = if lt(sub(call_p, put_p), cast(0.0, f32)) then neg(sub(call_p, put_p)) else sub(call_p, put_p)
  assert_true(lt(diff, cast(0.001, f32)), "ATM put-call parity at r=0: call ≈ put")
}
def test_heston_charfn_otm_clamps_nonnegative() -> unit ! { Test } = {
  p = heston_call_carr_madan_panels(cast(100.0, f32), cast(120.0, f32), cast(1.0, f32), cast(0.0, f32), cast(0.04, f32), cast(0.5, f32), cast(0.04, f32), cast(1.0, f32), cast(-0.9, f32), cast(1.5, f32), cast(25.0, f32), cast(32, i64))
  assert_true(gte(p, cast(0.0, f32)), "OTM K=120 at low u_max=25 clamped to non-negative (raw quadrature returns ~-0.03 without the clamp)")
}
def test_heston_qe_zero_vol_deterministic_asset() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  mu = cast(0.05, f32)
  big_t = cast(2.0, f32)
  out = with seed(23i64) { heston_qe_terminal(s0, cast(0.0, f32), mu, cast(0.5, f32), cast(0.0, f32), cast(1.0, f32), cast(-0.9, f32), big_t, cast(20, i64)) }
  s_t = out.0
  expected = mul(s0, exp(mul(mu, big_t)))
  rel_err = div(abs_f32(sub(s_t, expected)), expected)
  assert_true(lt(rel_err, cast(0.001, f32)), "with v0=theta=0 the asset degenerates to deterministic S0*exp(mu*T)")
}
