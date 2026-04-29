module Shoals.Properties.Pricing
import Shoals.Pricing (bs_call_scalar, bs_put_scalar)
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
