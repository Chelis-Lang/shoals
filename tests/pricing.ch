module Shoals.Tests.Pricing
import Std.Test (assert_close, assert_true)
import Shoals.Pricing (bs_call_scalar, bs_put_scalar, bs_call_f64, bs_call_f64_vector, call_prices, put_prices, call_total, mc_call_price)
def abs_f64_test(x: f64) -> f64 = if lt(x, cast(0.0, f64)) then neg(x) else x
def assert_close_f64(actual: f64, expected: f64, tol: f64, label: string) -> unit ! { Test } = {
  diff = abs_f64_test(sub(actual, expected))
  assert_true(lte(diff, tol), label)
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
  _ = assert_close(index(pl, cast(0, int64)), cast(1.8594, f32), cast(0.001, f32), "OTM call")
  _ = assert_close(index(pl, cast(1, int64)), cast(10.4506, f32), cast(0.001, f32), "ATM call")
  assert_close(index(pl, cast(2, int64)), cast(26.169, f32), cast(0.001, f32), "ITM call")
}
def assert_call_tensor_matches_scalar(s: f32, k: f32, r: f32, sigma: f32, t: f32, label: str) -> unit ! { Test } = {
  prices = to_list(call_prices(to_tensor([s]), k, r, sigma, t))
  tensor_px = index(prices, cast(0, int64))
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
  _ = assert_close(index(prices, cast(0, int64)), bs_call_scalar(index(spot_list, cast(0, int64)), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)), cast(0.0, f32), "lane 0 equals scalar")
  _ = assert_close(index(prices, cast(1, int64)), bs_call_scalar(index(spot_list, cast(1, int64)), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)), cast(0.0, f32), "lane 1 equals scalar")
  assert_close(index(prices, cast(2, int64)), bs_call_scalar(index(spot_list, cast(2, int64)), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)), cast(0.0, f32), "lane 2 equals scalar")
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
  _ = assert_close_f64(index(prices, cast(0, int64)), bs_call_f64(cast(100.0, f64), cast(100.0, f64), cast(0.05, f64), cast(0.2, f64), cast(1.0, f64)), cast(0.0, f64), "f64 vector row 0 equals scalar")
  _ = assert_close_f64(index(prices, cast(1, int64)), bs_call_f64(cast(60.0, f64), cast(130.0, f64), cast(0.01, f64), cast(0.1, f64), cast(0.25, f64)), cast(0.0, f64), "f64 vector row 1 equals scalar")
  _ = assert_close_f64(index(prices, cast(2, int64)), bs_call_f64(cast(140.0, f64), cast(70.0, f64), cast(0.1, f64), cast(0.2, f64), cast(2.0, f64)), cast(0.0, f64), "f64 vector row 2 equals scalar")
  _ = assert_close_f64(index(prices, cast(3, int64)), bs_call_f64(cast(100.0, f64), cast(100.0, f64), cast(0.05, f64), cast(0.4, f64), cast(2.0, f64)), cast(0.0, f64), "f64 vector row 3 equals scalar")
  _ = assert_close_f64(index(prices, cast(4, int64)), bs_call_f64(cast(120.0, f64), cast(100.0, f64), cast(0.01, f64), cast(0.1, f64), cast(0.25, f64)), cast(0.0, f64), "f64 vector row 4 equals scalar")
  _ = assert_close_f64(index(prices, cast(5, int64)), bs_call_f64(cast(50.0, f64), cast(100.0, f64), cast(0.0, f64), cast(0.05, f64), cast(0.01, f64)), cast(0.0, f64), "f64 vector row 5 equals scalar")
  assert_close_f64(index(prices, cast(6, int64)), bs_call_f64(cast(150.0, f64), cast(100.0, f64), cast(0.1, f64), cast(0.8, f64), cast(2.0, f64)), cast(0.0, f64), "f64 vector row 6 equals scalar")
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
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(5000, int64))))
  px1 = with seed(42i64) { mc_call_price(copy(template), cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  px2 = with seed(42i64) { mc_call_price(template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  assert_close(px1, px2, cast(0.0, f32), "same seed, same price")
}
def test_mc_converges_to_bs() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: int64) -> cast(0.0, f32), range(cast(0, int64), cast(20000, int64))))
  mc_px = with seed(42i64) { mc_call_price(template, cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
  bs_px = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  diff = sub(mc_px, bs_px)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  rel = div(abs_diff, bs_px)
  ok = lt(rel, cast(0.02, f32))
  assert_close(if ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "MC within 2% of BS at 20K paths")
}
