module Shoals.Tests.PdeHeavy
import Std.Test (assert_close, assert_true)
import Shoals.Pde (pde_european_call_cn, pde_european_put_cn, pde_american_put_cn, pde_spread_option_adi)
import Shoals.Pricing (bs_call_scalar, bs_put_scalar)
def test_pde_european_call_cn_converges_to_bs() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  q = cast(0.0, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  px_pde = pde_european_call_cn(s0, k, r, q, sigma, t, cast(200, i64), cast(50, i64), cast(4.0, f32))
  px_bs = bs_call_scalar(s0, k, r, sigma, t)
  assert_close(px_pde, px_bs, cast(0.01, f32), "PDE European call within 0.01 of Black-Scholes")
}
def test_pde_european_put_cn_converges_to_bs() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  q = cast(0.0, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  px_pde = pde_european_put_cn(s0, k, r, q, sigma, t, cast(200, i64), cast(50, i64), cast(4.0, f32))
  px_bs = bs_put_scalar(s0, k, r, sigma, t)
  assert_close(px_pde, px_bs, cast(0.01, f32), "PDE European put within 0.01 of Black-Scholes")
}
def test_pde_american_put_ge_european() -> unit ! { Test } = {
  s0 = cast(90.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  q = cast(0.0, f32)
  sigma = cast(0.3, f32)
  t = cast(1.0, f32)
  px_amer = pde_american_put_cn(s0, k, r, q, sigma, t, cast(200, i64), cast(50, i64), cast(4.0, f32))
  px_eur = pde_european_put_cn(s0, k, r, q, sigma, t, cast(200, i64), cast(50, i64), cast(4.0, f32))
  assert_true(gte(px_amer, sub(px_eur, cast(0.001, f32))), "American put >= European put (ITM)")
}
def test_pde_european_put_call_parity() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  q = cast(0.0, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  px_call = pde_european_call_cn(s0, k, r, q, sigma, t, cast(200, i64), cast(50, i64), cast(4.0, f32))
  px_put = pde_european_put_cn(s0, k, r, q, sigma, t, cast(200, i64), cast(50, i64), cast(4.0, f32))
  lhs = sub(px_call, px_put)
  rhs = sub(s0, mul(k, exp(neg(mul(r, t)))))
  assert_close(lhs, rhs, cast(0.02, f32), "Put-call parity: C - P = S - K*exp(-rT)")
}
def test_pde_spread_option_atm_zero_correl() -> unit ! { Test } = {
  s1 = cast(100.0, f32)
  s2 = cast(100.0, f32)
  k = cast(0.0, f32)
  r = cast(0.0, f32)
  q1 = cast(0.0, f32)
  q2 = cast(0.0, f32)
  sigma1 = cast(0.2, f32)
  sigma2 = cast(0.2, f32)
  rho = cast(0.0, f32)
  t = cast(1.0, f32)
  px = pde_spread_option_adi(s1, s2, k, r, q1, q2, sigma1, sigma2, rho, t, cast(41, i64), cast(41, i64), cast(40, i64))
  -- Independent Margrabe value; the automatic wider domain requires a finer mesh.
  px_margrabe = cast(11.2462916018285, f32)
  diff_raw = sub(px, px_margrabe)
  diff_abs = if lt(diff_raw, cast(0.0, f32)) then neg(diff_raw) else diff_raw
  assert_true(lt(diff_abs, cast(0.1, f32)), "ADI spread option within 0.10 of Margrabe at coarse grid")
}
def spread_issue_price(n_x: i64, n_t: i64) -> f32 = pde_spread_option_adi(100.0f32, 95.0f32, 5.0f32, 0.05f32, 0.0f32, 0.0f32, 0.2f32, 0.3f32, 0.5f32, 1.0f32, n_x, n_x, n_t)
-- Reference is conditional-normal integration, independently reproduced by
-- scripts/manual_gates/spread_adi_oracle.py. Its native matrix also runs
-- 41/81/161 mesh refinement and its error ratios, separate time/domain
-- refinements, rectangular
-- stress, and near-endpoint correlations outside the optional evaluator
-- budget. A 20,000-path estimate is not a
-- sufficiently precise regression target for this example (shoals#153).
def test_spread_adi_coarse_conditional_normal_reference() -> unit ! { Test } = {
  exact = 10.211500827214f32
  coarse = spread_issue_price(41i64, 50i64)
  assert_close(coarse, exact, 0.1f32, "41x41 spread price versus independent conditional-normal integration")
}
