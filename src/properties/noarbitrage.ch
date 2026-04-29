module Shoals.Properties.NoArbitrage
import Shoals.Pricing (bs_call_scalar)
def bull_spread_nonneg(s: f32, k_low: f32, k_high: f32, r: f32, sigma: f32, t: f32) -> bool = {
  c_low = bs_call_scalar(s, k_low, r, sigma, t)
  c_high = bs_call_scalar(s, k_high, r, sigma, t)
  spread = sub(c_low, c_high)
  gte(spread, cast(0.0, f32))
}
def butterfly_nonneg(s: f32, k: f32, h: f32, r: f32, sigma: f32, t: f32) -> bool = {
  c_low = bs_call_scalar(s, sub(k, h), r, sigma, t)
  c_mid = bs_call_scalar(s, k, r, sigma, t)
  c_high = bs_call_scalar(s, add(k, h), r, sigma, t)
  payoff = sub(add(c_low, c_high), mul(cast(2.0, f32), c_mid))
  gte(payoff, cast(-0.001, f32))
}
