module Shoals.Tests.CompositesBinding
import Std.Test (assert_close)
import Shoals.Pricing (bs_call_scalar)
import Std.Contracts (normal_cdf)
-- S7 binding cross-check for the S8 composite corpus
-- (`properties/composites.ch`) -- FAST SMOKE.
--
-- The composites in Shoals.Properties.Composites are PROVEN about
-- `Std.Contracts.normal_cdf` -- the certified f32 Abramowitz-Stegun normal CDF.
-- The shipped pricer `bs_call_scalar` does NOT call that f32 symbol: it computes
-- the SAME A&S model in an f64 body (`Shoals.Pricing.erf64`/`n_cdf64`, the
-- byte-identical 7.1.26 coefficients) and downcasts, because the Greeks need f64
-- precision and the single-body correctness invariant forbids a second CDF path.
--
-- This is the honest binding between the two: the shipped pricer's f64-lifted A&S
-- normal CDF realizes the same model the contract certifies. Each cell here
-- rebuilds a Black-Scholes call price from `Std.Contracts.normal_cdf` (f32) and
-- asserts agreement with `bs_call_scalar` within a stated f32 bound. Without this
-- cross-check the composite proofs would be about a function the shipped pricer
-- does not use.
--
-- This file is the fast CI smoke: a handful of representative cells (ATM, deep
-- OTM/ITM, high-vol, short maturity). The full 405-cell grid sweep lives in
-- `tests-manual/composites_binding_heavy.ch` (nightly), where the measured max
-- abs diff is 2.67e-5. The asserted f32 bound here and there is 1e-4.
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
-- One cell of the binding: shipped f64-erf pricer == contract-CDF BS within 1e-4.
def test_binding_atm() -> unit ! { Test } = {
  shipped = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  contract = bs_call_contract(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
  assert_close(shipped, contract, cast(0.0001, f32), "ATM: shipped pricer == contract-CDF BS within 1e-4")
}
def test_binding_deep_otm() -> unit ! { Test } = {
  shipped = bs_call_scalar(cast(60.0, f32), cast(130.0, f32), cast(0.01, f32), cast(0.1, f32), cast(0.25, f32))
  contract = bs_call_contract(cast(60.0, f32), cast(130.0, f32), cast(0.01, f32), cast(0.1, f32), cast(0.25, f32))
  assert_close(shipped, contract, cast(0.0001, f32), "deep OTM: shipped == contract within 1e-4")
}
def test_binding_deep_itm() -> unit ! { Test } = {
  shipped = bs_call_scalar(cast(140.0, f32), cast(70.0, f32), cast(0.1, f32), cast(0.2, f32), cast(2.0, f32))
  contract = bs_call_contract(cast(140.0, f32), cast(70.0, f32), cast(0.1, f32), cast(0.2, f32), cast(2.0, f32))
  assert_close(shipped, contract, cast(0.0001, f32), "deep ITM: shipped == contract within 1e-4")
}
def test_binding_high_vol() -> unit ! { Test } = {
  shipped = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.4, f32), cast(2.0, f32))
  contract = bs_call_contract(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.4, f32), cast(2.0, f32))
  assert_close(shipped, contract, cast(0.0001, f32), "high vol: shipped == contract within 1e-4")
}
def test_binding_short_maturity() -> unit ! { Test } = {
  shipped = bs_call_scalar(cast(120.0, f32), cast(100.0, f32), cast(0.01, f32), cast(0.1, f32), cast(0.25, f32))
  contract = bs_call_contract(cast(120.0, f32), cast(100.0, f32), cast(0.01, f32), cast(0.1, f32), cast(0.25, f32))
  assert_close(shipped, contract, cast(0.0001, f32), "short maturity: shipped == contract within 1e-4")
}
