module Shoals.Tests.CompositesBinding
import Std.Test (assert_close)
import Shoals.Pricing (bs_call_scalar)
import Std.Contracts (normal_cdf)
-- S7 binding cross-check for the S8 composite corpus
-- (`properties/composites.ch`) -- FAST SMOKE.
--
-- The composites in Shoals.Properties.Composites are PROVEN about
-- `Std.Contracts.normal_cdf` -- the certified f32 Abramowitz-Stegun normal CDF.
-- The shipped pricer `bs_call_scalar` does not call that f32 symbol. Its
-- `n_cdf64` evaluates Chelis's `standard_normal_cdf` in f64 and downcasts;
-- the Greeks differentiate that same f64 price body.
--
-- So the binding is MEASURED AGREEMENT, not identity of model. Before shoals#61
-- the two sides were the same A&S coefficients at two widths and this comment
-- claimed identity; that claim is now false and the cross-check below is what
-- carries the binding on its own. Each cell here
-- rebuilds a Black-Scholes call price from `Std.Contracts.normal_cdf` (f32) and
-- asserts agreement with `bs_call_scalar` within a stated f32 bound. Without this
-- cross-check the composite proofs would be about a function the shipped pricer
-- does not use.
--
-- This file is the fast CI smoke: a handful of representative cells (ATM, deep
-- OTM/ITM, high-vol, short maturity). The full 405-cell grid sweep lives in
-- `tests-manual/composites_binding_heavy.ch` (nightly), where the measured max
-- abs diff was 2.67e-5 in an earlier measurement; the grid retains its 1e-4
-- bound. The smoke cells retain a 5e-5 f32 bound and compare the current
-- native-CDF pricer to the certified f32 contract CDF at representative points.
def d1_f32(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  num = add(log(div(s, k)), mul(add(r, mul(cast(0.5, f32), mul(sigma, sigma))), t))
  div(num, mul(sigma, sqrt(t)))
}
def d2_f32(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = sub(d1_f32(s, k, r, sigma, t), mul(sigma, sqrt(t)))
-- Black-Scholes call rebuilt from the CERTIFIED f32 contract normal CDF.
def bs_call_contract(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  nd1 = normal_cdf(d1_f32(s, k, r, sigma, t))
  nd2 = normal_cdf(d2_f32(s, k, r, sigma, t))
  disc = exp(neg(mul(r, t)))
  sub(mul(s, nd1), mul(k, mul(disc, nd2)))
}
-- One cell of the binding: shipped f64-CDF pricer == contract-CDF BS within 5e-5.
def test_binding_atm() -> unit ! { Test } = {
  shipped = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  contract = bs_call_contract(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(shipped, contract, cast(0.00005, f32), "ATM: shipped pricer == contract-CDF BS within 5e-5")
}
def test_binding_deep_otm() -> unit ! { Test } = {
  shipped = bs_call_scalar(cast(60.0, f32), cast(130.0, f32), cast(0.01, f32), cast(0.1, f32), cast(0.25, f32))
  contract = bs_call_contract(cast(60.0, f32), cast(130.0, f32), cast(0.01, f32), cast(0.1, f32), cast(0.25, f32))
  assert_close(shipped, contract, cast(0.00005, f32), "deep OTM: shipped == contract within 5e-5")
}
def test_binding_deep_itm() -> unit ! { Test } = {
  shipped = bs_call_scalar(cast(140.0, f32), cast(70.0, f32), cast(0.1, f32), cast(0.2, f32), cast(2.0, f32))
  contract = bs_call_contract(cast(140.0, f32), cast(70.0, f32), cast(0.1, f32), cast(0.2, f32), cast(2.0, f32))
  assert_close(shipped, contract, cast(0.00005, f32), "deep ITM: shipped == contract within 5e-5")
}
def test_binding_high_vol() -> unit ! { Test } = {
  shipped = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.4, f32), cast(2.0, f32))
  contract = bs_call_contract(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.4, f32), cast(2.0, f32))
  assert_close(shipped, contract, cast(0.00005, f32), "high vol: shipped == contract within 5e-5")
}
def test_binding_short_maturity() -> unit ! { Test } = {
  shipped = bs_call_scalar(cast(120.0, f32), cast(100.0, f32), cast(0.01, f32), cast(0.1, f32), cast(0.25, f32))
  contract = bs_call_contract(cast(120.0, f32), cast(100.0, f32), cast(0.01, f32), cast(0.1, f32), cast(0.25, f32))
  assert_close(shipped, contract, cast(0.00005, f32), "short maturity: shipped == contract within 5e-5")
}
