module Shoals.Tests.CountContracts
import Std.Test (assert_close, assert_true)
import Shoals.Pde (pde_european_call_cn, pde_european_put_cn, pde_american_put_cn, pde_spread_option_adi, pde_thomas_solve)
import Shoals.Heston (heston_call_carr_madan, heston_call_carr_madan_panels)
import Shoals.Cds (hazard_curve_from_pillars, hazard_curve_pillars, cds_premium_leg_value, cds_pv, cds_bootstrap_hazards)
import Shoals.Xva (xva_cva_wwr_constant_hazard)
import Nautilus.Distributions (normal_sample, normal_cdf)
-- With three log-grid points and one initial implicit step, there is only
-- one interior equation: (1-T*b)V = payoff + T*(a*lower + c*upper).
-- Derive its coefficients independently in f64 rather than using PDE helpers.
def test_vanilla_count_minimum_one_interior_oracle() -> unit ! { Test } = {
  dx = log(2f64)
  diffusion = div(0.02f64, mul(dx, dx))
  advection = div(0.01f64, mul(2f64, dx))
  a = sub(diffusion, advection)
  c = add(diffusion, advection)
  denominator = add(1f64, mul(0.25f64, add(div(0.04f64, mul(dx, dx)), 0.05f64)))
  upper = sub(mul(200f64, exp(-0.005f64)), mul(100f64, exp(-0.0125f64)))
  call_oracle = cast(div(mul(0.25f64, mul(c, upper)), denominator), f32)
  put_oracle = cast(div(mul(0.25f64, mul(a, mul(100f64, exp(-0.0125f64)))), denominator), f32)
  american_oracle = cast(div(mul(0.25f64, mul(a, 100f64)), denominator), f32)
  _ = assert_close(pde_european_call_cn(100f32, 100f32, 0.05f32, 0.02f32, 0.2f32, 0.25f32, 3i64, 1i64, 2f32), call_oracle, 0.0001f32, "call accepts 3 spatial points and one step; single implicit equation agrees")
  _ = assert_close(pde_european_put_cn(100f32, 100f32, 0.05f32, 0.02f32, 0.2f32, 0.25f32, 3i64, 1i64, 2f32), put_oracle, 0.0001f32, "put delegates to the same count contract")
  assert_close(pde_american_put_cn(100f32, 100f32, 0.05f32, 0.02f32, 0.2f32, 0.25f32, 3i64, 1i64, 2f32), american_oracle, 0.0001f32, "American put uses its undiscounted lower boundary at the accepted minimum")
}
def test_thomas_small_systems_remain_valid() -> unit ! { Test } = {
  one = pde_thomas_solve([0f32], [2f32], [0f32], [6f32], 1i64)
  two = pde_thomas_solve([0f32, -1f32], [2f32, 2f32], [-1f32, 0f32], [3f32, 3f32], 2i64)
  _ = assert_close(index(one, 0i64), 3f32, 1e-6f32, "one-equation Thomas solve is independent of the PDE grid minimum")
  _ = assert_close(index(two, 0i64), 3f32, 1e-6f32, "two-equation Thomas solve first coordinate")
  assert_close(index(two, 1i64), 3f32, 1e-6f32, "two-equation Thomas solve second coordinate")
}
def test_spread_count_minimum_and_expiry_shortcut() -> unit ! { Test } = {
  _ = assert_close(pde_spread_option_adi(100f32, 90f32, 5f32, 0f32, 0f32, 0f32, 0f32, 0f32, 0.3f32, 0.25f32, 3i64, 3i64, 1i64), 5f32, 0.0001f32, "3x3/one-step ADI with zero generator retains intrinsic")
  assert_true(eq(pde_spread_option_adi(100f32, 90f32, 5f32, 0.05f32, 0f32, 0f32, 0.2f32, 0.3f32, 0.3f32, 0f32, -1i64, 0i64, -2i64), 5f32), "expiry never consumes invalid grid or step counts")
}
def test_heston_single_panel_matches_single_rule() -> unit ! { Test } = {
  rule = heston_call_carr_madan(100f32, 100f32, 1f32, 0.05f32, 0.04f32, 2f32, 0.04f32, 0.3f32, -0.7f32, 1.5f32, 10f32)
  panel = heston_call_carr_madan_panels(100f32, 100f32, 1f32, 0.05f32, 0.04f32, 2f32, 0.04f32, 0.3f32, -0.7f32, 1.5f32, 10f32, 1i64)
  _ = assert_true(gt(rule, 0f32), "single-rule comparison has a nonzero positive control")
  assert_close(panel, rule, 0.00001f32, "one panel is the same ten-point Carr-Madan quadrature rule")
}
def test_cds_annual_premium_identity() -> unit ! { Test } = {
  curve = hazard_curve_from_pillars(to_tensor([2f32]), to_tensor([0.02f32]))
  annual = cds_premium_leg_value(0.01f32, 2f32, 1i64, curve, 0.03f32)
  oracle = mul(0.01f32, add(exp(-0.05f32), exp(-0.1f32)))
  assert_close(annual, oracle, 1e-7f32, "annual premium minimum discounts both year-end survival-weighted payments")
}
def test_cds_one_pillar_annual_bootstrap() -> unit ! { Test } = {
  -- At zero rates the monthly protection increments telescope. One annual
  -- premium gives the independent par spread (1-R)*(exp(h)-1).
  spread = mul(0.6f32, sub(exp(0.02f32), 1f32))
  curve = cds_bootstrap_hazards(to_tensor([spread]), to_tensor([1f32]), 0.4f32, 0f32, 1i64)
  hazard = index(to_list(hazard_curve_pillars(curve).1), 0i64)
  _ = assert_close(cds_pv(spread, 1f32, 1i64, 0.4f32, hazard_curve_from_pillars(to_tensor([1f32]), to_tensor([0.02f32])), 0f32), 0f32, 1e-6f32, "annual CDS PV vanishes at the independent synthetic spread")
  assert_close(hazard, 0.02f32, 0.00001f32, "one-pillar annual-frequency bootstrap recovers the synthetic hazard")
}
def test_cds_empty_bootstrap_does_not_consume_frequency() -> unit ! { Test } = {
  empty = to_tensor(map(fn (i: i64) -> 0f32, range(0i64, 0i64)))
  pillars = hazard_curve_pillars(cds_bootstrap_hazards(empty, empty, 0.4f32, 0.03f32, 0i64))
  assert_true(and(eq(numel(pillars.0), 0i64), eq(numel(pillars.1), 0i64)), "empty bootstrap has no premium grid to validate")
}
def test_xva_one_path_replay_and_zero_epe() -> unit ! { Test } = {
  (exposure_key, default_key) = split_key(key_from_seed(21i64))
  ze = index(to_list(normal_sample(exposure_key, to_tensor([0f32]), 0f32, 1f32)), 0i64)
  zd = index(to_list(normal_sample(default_key, to_tensor([0f32]), 0f32, 1f32)), 0i64)
  xd = add(mul(-0.3f32, ze), mul(sqrt(sub(1f32, mul(0.3f32, 0.3f32))), zd))
  survival_draw = sub(1f32, normal_cdf(xd, 0f32, 1f32))
  tau = div(neg(log(if lt(survival_draw, 1e-12f32) then 1e-12f32 else survival_draw)), 10f32)
  shock = exp(sub(mul(0.5f32, ze), 0.125f32))
  oracle = if lt(tau, 1f32) then mul(0.6f32, mul(mul(100f32, shock), exp(mul(-0.03f32, tau)))) else 0f32
  actual = xva_cva_wwr_constant_hazard(key_from_seed(21i64), to_tensor([0f32, 1f32]), to_tensor([100f32, 100f32]), 10f32, 0.4f32, 0.03f32, 0.3f32, 1i64)
  zero = xva_cva_wwr_constant_hazard(key_from_seed(21i64), to_tensor([0f32, 1f32]), to_tensor([0f32, 0f32]), 10f32, 0.4f32, 0.03f32, 0.3f32, 1i64)
  _ = assert_true(gt(oracle, 0f32), "one-path replay actually realizes a default contribution")
  _ = assert_close(actual, oracle, 0.0001f32, "one path is accepted and agrees with its keyed default/exposure replay")
  assert_true(eq(zero, 0f32), "one path with zero EPE returns zero")
}
