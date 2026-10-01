module Shoals.Tests.Pricing
import Std.Test (assert_close, assert_true)
import Shoals.Pricing (bs_call_scalar, bs_put_scalar, bs_call_f64, bs_call_f64_vector, bs_call_wire_f64, call_prices, put_prices, call_total, mc_call_price, deltas_call, gammas_call)
def abs_f64_test(x: f64) -> f64 = if lt(x, cast(0.0, f64)) then neg(x) else x
def assert_close_f64(actual: f64, expected: f64, tol: f64, label: string) -> unit ! { Test } = {
  diff = abs_f64_test(sub(actual, expected))
  assert_true(lte(diff, tol), label)
}
def assert_close_f64_scaled(actual: f64, expected: f64, label: string) -> unit ! { Test } = {
  tol = add(cast(0.00001, f64), mul(cast(1e-8, f64), abs_f64_test(expected)))
  assert_close_f64(actual, expected, tol, label)
}
def test_bs_call_atm() -> unit ! { Test } = {
  px = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(px, cast(10.4506, f32), cast(0.001, f32), "ATM call ~ 10.4506")
}
def test_bs_put_atm() -> unit ! { Test } = {
  px = bs_put_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(px, cast(5.5735, f32), cast(0.001, f32), "ATM put ~ 5.5735")
}
def test_put_call_parity() -> unit ! { Test } = {
  c_px = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  p_px = bs_put_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  diff = sub(c_px, p_px)
  parity = sub(cast(100.0, f32), mul(cast(100.0, f32), exp(neg(mul(cast(0.05, f32), cast(1.0, f32))))))
  assert_close(diff, parity, cast(0.001, f32), "C - P == S - K*exp(-rT)")
}
def test_call_prices_vector() -> unit ! { Test } = {
  spots = to_tensor([cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
  prices = call_prices(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  pl = to_list(prices)
  _ = assert_close(index(pl, cast(0, i64)), cast(1.8594, f32), cast(0.001, f32), "OTM call")
  _ = assert_close(index(pl, cast(1, i64)), cast(10.4506, f32), cast(0.001, f32), "ATM call")
  assert_close(index(pl, cast(2, i64)), cast(26.169, f32), cast(0.001, f32), "ITM call")
}
def assert_call_tensor_matches_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32, label: string) -> unit ! { Test } = {
  prices = to_list(call_prices(to_tensor([s]), k, r, sigma, t))
  tensor_px = index(prices, cast(0, i64))
  scalar_px = bs_call_scalar(s, k, r, sigma, t)
  assert_close(tensor_px, scalar_px, cast(0.0, f32), label)
}
def test_call_prices_tensor_scalar_equivalence_representative_rows() -> unit ! { Test } = {
  _ = assert_call_tensor_matches_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), "ATM tensor lane equals scalar")
  _ = assert_call_tensor_matches_scalar(cast(60.0, f32), cast(130.0, f32), cast(0.01, f32), cast(0.1, f32), cast(0.25, f32), "deep OTM tensor lane equals scalar")
  _ = assert_call_tensor_matches_scalar(cast(140.0, f32), cast(70.0, f32), cast(0.1, f32), cast(0.2, f32), cast(2.0, f32), "deep ITM tensor lane equals scalar")
  _ = assert_call_tensor_matches_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.4, f32), cast(2.0, f32), "high vol tensor lane equals scalar")
  assert_call_tensor_matches_scalar(cast(120.0, f32), cast(100.0, f32), cast(0.01, f32), cast(0.1, f32), cast(0.25, f32), "short maturity tensor lane equals scalar")
}
def test_call_prices_vector_lanes_match_scalar_pricer() -> unit ! { Test } = {
  spots = to_tensor([cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
  prices = to_list(call_prices(copy(spots), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)))
  spot_list = to_list(spots)
  _ = assert_close(index(prices, cast(0, i64)), bs_call_scalar(index(spot_list, cast(0, i64)), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)), cast(0.0, f32), "lane 0 equals scalar")
  _ = assert_close(index(prices, cast(1, i64)), bs_call_scalar(index(spot_list, cast(1, i64)), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)), cast(0.0, f32), "lane 1 equals scalar")
  assert_close(index(prices, cast(2, i64)), bs_call_scalar(index(spot_list, cast(2, i64)), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)), cast(0.0, f32), "lane 2 equals scalar")
}
def test_call_total_sums_prices() -> unit ! { Test } = {
  spots = to_tensor([cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
  total = call_total(copy(spots), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  prices = to_list(call_prices(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)))
  expected = fold(fn (acc: f32, p: f32) -> add(acc, p), cast(0.0, f32), prices)
  assert_close(total, expected, cast(0.001, f32), "call_total == sum(call_prices)")
}
def test_bs_call_f64_vector_matches_scalar_desk_rows() -> unit ! { Test } = {
  spots = to_tensor([cast(100.0, f64), cast(60.0, f64), cast(140.0, f64), cast(100.0, f64), cast(120.0, f64), cast(50.0, f64), cast(150.0, f64)])
  strikes = to_tensor([cast(100.0, f64), cast(130.0, f64), cast(70.0, f64), cast(100.0, f64), cast(100.0, f64), cast(100.0, f64), cast(100.0, f64)])
  rates = to_tensor([cast(0.05, f64), cast(0.01, f64), cast(0.1, f64), cast(0.05, f64), cast(0.01, f64), cast(0.0, f64), cast(0.1, f64)])
  sigmas = to_tensor([cast(0.2, f64), cast(0.1, f64), cast(0.2, f64), cast(0.4, f64), cast(0.1, f64), cast(0.05, f64), cast(0.8, f64)])
  times = to_tensor([cast(1.0, f64), cast(0.25, f64), cast(2.0, f64), cast(2.0, f64), cast(0.25, f64), cast(0.01, f64), cast(2.0, f64)])
  prices = to_list(bs_call_f64_vector(spots, strikes, rates, sigmas, times))
  _ = assert_close_f64(index(prices, cast(0, i64)), bs_call_f64(cast(100.0, f64), cast(100.0, f64), cast(0.05, f64), cast(0.2, f64), cast(1.0, f64)), cast(0.0, f64), "f64 vector row 0 equals scalar")
  _ = assert_close_f64(index(prices, cast(1, i64)), bs_call_f64(cast(60.0, f64), cast(130.0, f64), cast(0.01, f64), cast(0.1, f64), cast(0.25, f64)), cast(0.0, f64), "f64 vector row 1 equals scalar")
  _ = assert_close_f64(index(prices, cast(2, i64)), bs_call_f64(cast(140.0, f64), cast(70.0, f64), cast(0.1, f64), cast(0.2, f64), cast(2.0, f64)), cast(0.0, f64), "f64 vector row 2 equals scalar")
  _ = assert_close_f64(index(prices, cast(3, i64)), bs_call_f64(cast(100.0, f64), cast(100.0, f64), cast(0.05, f64), cast(0.4, f64), cast(2.0, f64)), cast(0.0, f64), "f64 vector row 3 equals scalar")
  _ = assert_close_f64(index(prices, cast(4, i64)), bs_call_f64(cast(120.0, f64), cast(100.0, f64), cast(0.01, f64), cast(0.1, f64), cast(0.25, f64)), cast(0.0, f64), "f64 vector row 4 equals scalar")
  _ = assert_close_f64(index(prices, cast(5, i64)), bs_call_f64(cast(50.0, f64), cast(100.0, f64), cast(0.0, f64), cast(0.05, f64), cast(0.01, f64)), cast(0.0, f64), "f64 vector row 5 equals scalar")
  assert_close_f64(index(prices, cast(6, i64)), bs_call_f64(cast(150.0, f64), cast(100.0, f64), cast(0.1, f64), cast(0.8, f64), cast(2.0, f64)), cast(0.0, f64), "f64 vector row 6 equals scalar")
}
def constant_3(v: f64) -> tensor[3, f64] = to_tensor([v, v, v])
def constant_1(v: f64) -> tensor[1, f64] = to_tensor([v])
-- These rows were written to lock STRUCTURAL AGREEMENT, when both sides
-- evaluated one kernel and agreed exactly. `bs_call_f64` now evaluates Cody
-- while `bs_call_wire_f64` still evaluates A&S from caller-supplied
-- coefficients, so they pass on ~19-78% headroom and would survive a real
-- divergence: a smoke test until the wire path migrates.
def test_bs_call_wire_f64_matches_real_scalar_pricer() -> unit ! { Test } = {
  spots = to_tensor([cast(60.0, f64), cast(100.0, f64), cast(140.0, f64)])
  strikes = to_tensor([cast(130.0, f64), cast(100.0, f64), cast(70.0, f64)])
  rates = to_tensor([cast(0.01, f64), cast(0.05, f64), cast(0.1, f64)])
  sigmas = to_tensor([cast(0.1, f64), cast(0.2, f64), cast(0.8, f64)])
  times = to_tensor([cast(0.25, f64), cast(1.0, f64), cast(2.0, f64)])
  prices = to_list(bs_call_wire_f64(spots, strikes, rates, sigmas, times, constant_3(cast(0.5, f64)), constant_3(cast(0.7071067811865476, f64)), constant_3(cast(0.254829592, f64)), constant_3(cast(-0.284496736, f64)), constant_3(cast(1.421413741, f64)), constant_3(cast(-1.453152027, f64)), constant_3(cast(1.061405429, f64)), constant_3(cast(0.3275911, f64)), constant_3(cast(1.1283791670955126, f64)), constant_3(cast(0.00001, f64))))
  _ = assert_close_f64_scaled(index(prices, cast(0, i64)), bs_call_f64(cast(60.0, f64), cast(130.0, f64), cast(0.01, f64), cast(0.1, f64), cast(0.25, f64)), "WireDag OTM row matches scalar")
  _ = assert_close_f64_scaled(index(prices, cast(1, i64)), bs_call_f64(cast(100.0, f64), cast(100.0, f64), cast(0.05, f64), cast(0.2, f64), cast(1.0, f64)), "WireDag ATM row matches scalar")
  assert_close_f64_scaled(index(prices, cast(2, i64)), bs_call_f64(cast(140.0, f64), cast(70.0, f64), cast(0.1, f64), cast(0.8, f64), cast(2.0, f64)), "WireDag ITM row matches scalar")
}
def test_bs_call_wire_f64_scale_robust_extreme_itm_shape_one() -> unit ! { Test } = {
  prices = to_list(bs_call_wire_f64(to_tensor([cast(1000.0, f64)]), to_tensor([cast(1.0, f64)]), to_tensor([cast(0.2, f64)]), to_tensor([cast(1.0, f64)]), to_tensor([cast(10.0, f64)]), constant_1(cast(0.5, f64)), constant_1(cast(0.7071067811865476, f64)), constant_1(cast(0.254829592, f64)), constant_1(cast(-0.284496736, f64)), constant_1(cast(1.421413741, f64)), constant_1(cast(-1.453152027, f64)), constant_1(cast(1.061405429, f64)), constant_1(cast(0.3275911, f64)), constant_1(cast(1.1283791670955126, f64)), constant_1(cast(0.00001, f64))))
  expected = bs_call_f64(cast(1000.0, f64), cast(1.0, f64), cast(0.2, f64), cast(1.0, f64), cast(10.0, f64))
  assert_close_f64_scaled(index(prices, cast(0, i64)), expected, "WireDag extreme ITM shape-one row matches scalar with abs+relative tolerance")
}
def test_fd_delta_matches_analytic() -> unit ! { Test } = {
  s_v = cast(100.0, f32)
  k_v = cast(100.0, f32)
  r_v = cast(0.05, f32)
  sigma_v = cast(0.2, f32)
  t_v = cast(1.0, f32)
  h_v = cast(0.01, f32)
  up = bs_call_scalar(add(s_v, h_v), k_v, r_v, sigma_v, t_v)
  dn = bs_call_scalar(sub(s_v, h_v), k_v, r_v, sigma_v, t_v)
  fd = div(sub(up, dn), mul(cast(2.0, f32), h_v))
  assert_close(fd, cast(0.6368, f32), cast(0.001, f32), "FD delta ~ 0.6368")
}
def test_mc_reproducible() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
  px1 = with seed(42i64) { mc_call_price(copy(template), cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  px2 = with seed(42i64) { mc_call_price(template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  assert_close(px1, px2, cast(0.0, f32), "same seed, same price")
}
def test_mc_converges_to_bs() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(20000, i64))))
  mc_px = with seed(42i64) { mc_call_price(template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  bs_px = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  diff = sub(mc_px, bs_px)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  rel = div(abs_diff, bs_px)
  ok = lt(rel, cast(0.02, f32))
  assert_close(if ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "MC within 2% of BS at 20K paths")
}
-- chelis#2640-adjacent hazard: under `grad` an untaken arm with an unbounded
-- DERIVATIVE poisons the result, so every core must be total over the region the
-- dispatcher can hand it. The untaken arm's VALUE does not propagate at this pin;
-- an earlier revision of this comment said it did. Two distinct mechanisms, both
-- pinned below:
--
--   * region 3 (tail) divides by its operand twice; at ax = 0 an unclamped
--     divisor is +inf. Reached when d1 or d2 is exactly zero -- 0.5*0.25^2
--     = 0.03125 is exact in binary, so r = +3.125% makes d2 exactly 0 and
--     r = -3.125% makes d1 exactly 0.
--   * regions 1 and 2 do not divide at all -- both are P(y)/Q(y) Horner chains
--     with positive coefficients, so numerator AND denominator overflow to
--     +inf at large argument and inf/inf = NaN. Reached when sigma is tiny
--     enough to make |d| enormous; 1e-40 is a representable f32 subnormal, so
--     this is reachable from f32 callers, and the AD lane trips first.
def test_zero_d2_prices_are_not_nan() -> unit ! { Test } = {
  spots = to_tensor([cast(100.0, f32)])
  p = to_list(call_prices(spots, cast(100.0, f32), cast(0.03125, f32), cast(0.25, f32), cast(1.0, f32)))
  assert_close(index(p, cast(0, i64)), cast(11.408971, f32), cast(0.0001, f32), "call_prices at d2=0")
}
def test_zero_d2_delta_is_not_nan() -> unit ! { Test } = {
  spots = to_tensor([cast(100.0, f32)])
  d = to_list(deltas_call(spots, cast(100.0, f32), cast(0.03125, f32), cast(0.25, f32), cast(1.0, f32)))
  assert_close(index(d, cast(0, i64)), cast(0.5987063, f32), cast(0.00001, f32), "deltas_call at d2=0")
}
def test_zero_d1_gamma_is_not_nan() -> unit ! { Test } = {
  spots = to_tensor([cast(100.0, f32)])
  g = to_list(gammas_call(spots, cast(100.0, f32), cast(-0.03125, f32), cast(0.25, f32), cast(1.0, f32)))
  assert_close(index(g, cast(0, i64)), cast(0.01595769, f32), cast(1e-6, f32), "gammas_call at d1=0")
}
def test_tiny_sigma_price_is_not_nan() -> unit ! { Test } = {
  spots = to_tensor([cast(100.0, f64)])
  strikes = to_tensor([cast(100.0, f64)])
  rates = to_tensor([cast(0.05, f64)])
  sigmas = to_tensor([cast(1e-60, f64)])
  times = to_tensor([cast(1.0, f64)])
  prices = to_list(bs_call_f64_vector(spots, strikes, rates, sigmas, times))
  assert_close_f64(index(prices, cast(0, i64)), cast(4.877057549928594, f64), cast(1e-9, f64), "f64 vector price at sigma=1e-60")
}
def test_subnormal_sigma_price_is_not_nan() -> unit ! { Test } = {
  spots = to_tensor([cast(100.0, f64)])
  strikes = to_tensor([cast(100.0, f64)])
  rates = to_tensor([cast(0.05, f64)])
  sigmas = to_tensor([cast(1e-41, f64)])
  times = to_tensor([cast(1.0, f64)])
  prices = to_list(bs_call_f64_vector(spots, strikes, rates, sigmas, times))
  assert_close_f64(index(prices, cast(0, i64)), cast(4.877057549928594, f64), cast(1e-9, f64), "f64 vector price at sigma=1e-41")
}
def test_non_finite_input_propagates_rather_than_saturating() -> unit ! { Test } = {
  -- Every `lt` against NaN is false, so without an explicit guard the
  -- dispatcher falls through to its saturation arm and returns 1.0 -- pricing
  -- a negative spot to a silent 0.0 where the pre-Cody kernel returned NaN,
  -- and diverging from the vmap lane, which still gave NaN. Answering zero is
  -- worse than answering NaN for a pricing kernel.
  neg_spot = bs_call_f64(cast(-100.0, f64), cast(100.0, f64), cast(0.05, f64), cast(0.2, f64), cast(1.0, f64))
  _ = assert_true(neq(neg_spot, neg_spot), "a negative spot must not price to a finite 0.0")
  inf_sigma = bs_call_f64(cast(100.0, f64), cast(100.0, f64), cast(0.05, f64), div(cast(1.0, f64), cast(0.0, f64)), cast(1.0, f64))
  assert_true(neq(inf_sigma, inf_sigma), "an infinite sigma must not price to a finite 0.0")
}
def test_subnormal_sigma_gamma_is_not_nan() -> unit ! { Test } = {
  spots = to_tensor([cast(100.0, f32)])
  g = to_list(gammas_call(spots, cast(100.0, f32), cast(0.05, f32), cast(1e-40, f32), cast(1.0, f32)))
  gv = index(g, cast(0, i64))
  assert_close(sub(gv, gv), cast(0.0, f32), cast(0.0, f32), "AD gamma at sigma=1e-40 is finite")
}
