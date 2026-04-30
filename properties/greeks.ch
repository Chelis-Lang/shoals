module Shoals.Properties.Greeks
import Shoals.Pricing (bs_call_scalar)
import Shoals.References.BlackScholes (delta_call_textbook)
def fd_delta_in_unit_range_for_call(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool = {
  h = cast(0.01, f32)
  up = bs_call_scalar(add(s, h), k, r, sigma, t)
  dn = bs_call_scalar(sub(s, h), k, r, sigma, t)
  fd = div(sub(up, dn), mul(cast(2.0, f32), h))
  in_range = and(gte(fd, cast(0.0, f32)), lte(fd, cast(1.0, f32)))
  in_range
}
def fd_delta_matches_analytic(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool = {
  h = cast(0.01, f32)
  up = bs_call_scalar(add(s, h), k, r, sigma, t)
  dn = bs_call_scalar(sub(s, h), k, r, sigma, t)
  fd = div(sub(up, dn), mul(cast(2.0, f32), h))
  analytic = delta_call_textbook(s, k, r, sigma, t)
  diff = sub(fd, analytic)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  lt(abs_diff, cast(0.005, f32))
}
def vega_nonneg(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> bool = {
  h = cast(0.001, f32)
  up = bs_call_scalar(s, k, r, add(sigma, h), t)
  dn = bs_call_scalar(s, k, r, sub(sigma, h), t)
  fd_vega = div(sub(up, dn), mul(cast(2.0, f32), h))
  gte(fd_vega, cast(0.0, f32))
}
