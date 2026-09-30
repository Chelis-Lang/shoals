module Shoals.Properties.MonteCarlo
import Shoals.Pricing (bs_call_scalar, mc_call_price)
def same_literal_seed_same_price[n](template: tensor[n, f32], s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool = {
  px1 = mc_call_price(key_from_seed(7i64), copy(template), s, k, r, sigma, t)
  px2 = mc_call_price(key_from_seed(7i64), template, s, k, r, sigma, t)
  eq(px1, px2)
}
def mc_within_5pct_of_analytic[n](template: tensor[n, f32], s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool = {
  mc_px = mc_call_price(key_from_seed(42i64), template, s, k, r, sigma, t)
  bs_px = bs_call_scalar(s, k, r, sigma, t)
  diff = sub(mc_px, bs_px)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  rel = div(abs_diff, bs_px)
  lt(rel, cast(0.05, f32))
}
