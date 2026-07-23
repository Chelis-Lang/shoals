module Shoals.Properties.Pricing
import Shoals.Pricing (bs_call_scalar, bs_put_scalar, mc_call_price)
import Shoals.References.BlackScholes (call_textbook, put_textbook)
import Shoals.References.MonteCarlo (vanilla_call_textbook)
def put_call_parity_holds(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool = {
  c_px = bs_call_scalar(s, k, r, sigma, t)
  p_px = bs_put_scalar(s, k, r, sigma, t)
  lhs = sub(c_px, p_px)
  rhs = sub(s, mul(k, exp(neg(mul(r, t)))))
  diff = sub(lhs, rhs)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  lt(abs_diff, cast(0.001, f32))
}
def call_price_nonneg(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool = {
  c_px = bs_call_scalar(s, k, r, sigma, t)
  gte(c_px, cast(0.0, f32))
}
def put_price_nonneg(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool = {
  p_px = bs_put_scalar(s, k, r, sigma, t)
  gte(p_px, cast(0.0, f32))
}
def call_bounded_by_spot(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool = {
  c_px = bs_call_scalar(s, k, r, sigma, t)
  lte(c_px, s)
}
-- Tolerance note (graduation, sanctioned single re-baseline): bs_call_scalar /
-- bs_put_scalar now route through one f64 Abramowitz-Stegun body and downcast, while
-- the reference is the f32 Nautilus-erfc evaluation of the same A&S formula. The two
-- therefore differ by f32-vs-f64 rounding of identical math, amplified by the price's
-- cancellation. Measured worst over the exercised fixed points: K=110 call 1.14e-5,
-- ATM put 1.05e-5; most cells ~1e-6. The bound is 5e-5 -- ~4.4x over the worst
-- measured gap, tight enough to catch a per-PR regression yet safely above the
-- f32-vs-f64 A&S rounding. This loosening is accuracy-monotone, NOT a regression: the
-- f64 body is closer to true BS than the old f32 path (max abs err 1.44e-5 vs 3.64e-5,
-- oracle_greeks_gate accuracy-monotone guard).
def matches_textbook_reference(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool = {
  optimized = bs_call_scalar(s, k, r, sigma, t)
  reference = call_textbook(s, k, r, sigma, t)
  diff = sub(optimized, reference)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  lt(abs_diff, cast(0.00005, f32))
}
def matches_textbook_reference_put(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool = {
  optimized = bs_put_scalar(s, k, r, sigma, t)
  reference = put_textbook(s, k, r, sigma, t)
  diff = sub(optimized, reference)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  lt(abs_diff, cast(0.00005, f32))
}
def mc_matches_textbook_mc_reference[n](template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool ! { Random } = {
  optimized = with seed(42i64) { mc_call_price(copy(template), s0, k, r, sigma, t) }
  reference = with seed(42i64) { vanilla_call_textbook(template, s0, k, r, sigma, t) }
  diff = sub(optimized, reference)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  ref_abs = if lt(reference, cast(0.0, f32)) then neg(reference) else reference
  rel = div(abs_diff, add(ref_abs, cast(0.0001, f32)))
  lt(rel, cast(0.05, f32))
}
