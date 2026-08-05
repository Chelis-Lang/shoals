module Shoals.Properties.Curves
import Shoals.Curves (YieldCurve, yield_curve_from_pillars, rate_at, parallel_shift, key_rate_shift, twist, butterfly, scale_rates)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def parallel_shift_uniformly_lifts(c: YieldCurve[3], delta: f32, probe_t: f32) -> bool = {
  r_before = rate_at(c, probe_t)
  shifted = parallel_shift(c, delta)
  r_after = rate_at(shifted, probe_t)
  observed_delta = sub(r_after, r_before)
  lt(abs_f32(sub(observed_delta, delta)), cast(1e-6, f32))
}
def parallel_shift_zero_is_identity(c: YieldCurve[3], probe_t: f32) -> bool = {
  shifted = parallel_shift(c, cast(0.0, f32))
  diff = sub(rate_at(shifted, probe_t), rate_at(c, probe_t))
  lt(abs_f32(diff), cast(1e-6, f32))
}
def twist_at_midpoint_is_average(c: YieldCurve[3], short_d: f32, long_d: f32, t_mid: f32) -> bool = {
  twisted = twist(c, short_d, long_d)
  r_before = rate_at(c, t_mid)
  r_after = rate_at(twisted, t_mid)
  observed_delta = sub(r_after, r_before)
  expected_delta = mul(cast(0.5, f32), add(short_d, long_d))
  lt(abs_f32(sub(observed_delta, expected_delta)), cast(0.00001, f32))
}
def key_rate_shift_localized_at_unmoved_pillar(c: YieldCurve[3], pillar_idx: int64, delta: f32, far_t: f32) -> bool = {
  shifted = key_rate_shift(c, pillar_idx, delta)
  r_before = rate_at(c, far_t)
  r_after = rate_at(shifted, far_t)
  lt(abs_f32(sub(r_after, r_before)), cast(0.00001, f32))
}
def scale_rates_linear(c: YieldCurve[3], factor: f32, probe_t: f32) -> bool = {
  scaled = scale_rates(c, factor)
  r_before = rate_at(c, probe_t)
  r_after = rate_at(scaled, probe_t)
  expected = mul(r_before, factor)
  lt(abs_f32(sub(r_after, expected)), cast(0.00001, f32))
}
