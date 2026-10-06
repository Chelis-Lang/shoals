module Shoals.Tests.GreeksSecondOrder
import Std.Test (assert_close, assert_true)
import Shoals.Pricing (gammas_call, volgas_call, vannas_call)
-- Nested gradients of the f64 Black-Scholes body provide gamma, volga,
-- and vanna. The targets are textbook second derivatives checked against
-- independent formulas and finite differences in scripts/oracle_greeks_gate.py.
-- This tensor-lane suite is manual because nested vmap/grad is expensive.
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
-- One vector call exercises the full moneyness fold (OTM/ATM/ITM/deep-OTM with
-- negative d1) in a single lane sweep. K=100, r=0.05, sigma=0.2, t=1.
-- d1 at s=80 is -0.766 and at s=60 is -2.204, so the negative-d1 side
-- of the standard-normal CDF is exercised inside the nested derivative.
-- gamma is the SECOND derivative of the displayed price wrt S (correctness invariant).
def test_gammas_call_matches_displayed_2nd_deriv() -> unit ! { Test } = {
  spots = to_tensor([cast(60.0, f32), cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
  g = to_list(gammas_call(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)))
  _ = assert_close(index(g, cast(0, i64)), cast(0.00292946, f32), cast(5e-6, f32), "gamma neg-d1 s=60")
  _ = assert_close(index(g, cast(1, i64)), cast(0.01859823, f32), cast(5e-6, f32), "gamma s=80")
  _ = assert_close(index(g, cast(2, i64)), cast(0.01876202, f32), cast(5e-6, f32), "gamma ATM s=100")
  assert_close(index(g, cast(3, i64)), cast(0.00750025, f32), cast(5e-6, f32), "gamma ITM s=120")
}
-- gamma of a vanilla call is strictly positive everywhere (price convex in S).
def test_gammas_call_strictly_positive() -> unit ! { Test } = {
  spots = to_tensor([cast(60.0, f32), cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
  g = to_list(gammas_call(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)))
  _ = assert_true(gt(index(g, cast(0, i64)), cast(0.0, f32)), "gamma>0 s=60")
  _ = assert_true(gt(index(g, cast(1, i64)), cast(0.0, f32)), "gamma>0 s=80")
  _ = assert_true(gt(index(g, cast(2, i64)), cast(0.0, f32)), "gamma>0 s=100")
  assert_true(gt(index(g, cast(3, i64)), cast(0.0, f32)), "gamma>0 s=120")
}
def test_volgas_call_matches_displayed_2nd_deriv() -> unit ! { Test } = {
  spots = to_tensor([cast(60.0, f32), cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
  v = to_list(volgas_call(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)))
  _ = assert_close(index(v, cast(0, i64)), cast(55.883708, f32), cast(0.0015, f32), "volga neg-d1 s=60")
  _ = assert_close(index(v, cast(1, i64)), cast(88.017782, f32), cast(0.0015, f32), "volga s=80")
  _ = assert_close(index(v, cast(2, i64)), cast(9.850059, f32), cast(0.0015, f32), "volga ATM s=100")
  assert_close(index(v, cast(3, i64)), cast(144.65267, f32), cast(0.007, f32), "volga ITM s=120")
}
-- vanna sign folds across moneyness: positive below the d1=0 spot, negative above.
def test_vannas_call_matches_displayed_2nd_deriv() -> unit ! { Test } = {
  spots = to_tensor([cast(60.0, f32), cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
  v = to_list(vannas_call(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)))
  _ = assert_close(index(v, cast(0, i64)), cast(0.42256851, f32), cast(0.00004, f32), "vanna neg-d1 s=60")
  _ = assert_close(index(v, cast(1, i64)), cast(1.43685094, f32), cast(0.00008, f32), "vanna s=80")
  _ = assert_close(index(v, cast(2, i64)), cast(-0.28143026, f32), cast(0.00004, f32), "vanna ATM s=100")
  assert_close(index(v, cast(3, i64)), cast(-0.95547831, f32), cast(0.00006, f32), "vanna ITM s=120")
}
