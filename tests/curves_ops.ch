module Shoals.Tests.CurvesOps
import Std.Test (assert_close, assert_true)
import Shoals.Curves (YieldCurve, Ois, Ibor, Sofr, Sonia, Estr, Custom, yield_curve_from_pillars, yield_curve_tagged, curve_kind, rate_at, parallel_shift, key_rate_shift, twist, butterfly, scale_rates, ois, sofr, sonia, log_linear_rate_at, nss_rate, custom_curve)
def base_curve() -> YieldCurve[3] = yield_curve_from_pillars(to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)]), to_tensor([cast(0.03, f32), cast(0.04, f32), cast(0.045, f32)]))
def test_parallel_shift_lifts_all_pillars() -> unit ! { Test } = {
  shifted = parallel_shift(base_curve(), cast(0.001, f32))
  r1 = rate_at(shifted, cast(1.0, f32))
  r2 = rate_at(shifted, cast(2.0, f32))
  _ = assert_close(r1, cast(0.031, f32), cast(0.00001, f32), "+10bp at 1y")
  assert_close(r2, cast(0.041, f32), cast(0.00001, f32), "+10bp at 2y")
}
def test_parallel_shift_negative() -> unit ! { Test } = {
  shifted = parallel_shift(base_curve(), cast(-0.005, f32))
  r2 = rate_at(shifted, cast(2.0, f32))
  assert_close(r2, cast(0.035, f32), cast(0.00001, f32), "-50bp at 2y")
}
def test_key_rate_shift_affects_only_chosen_pillar() -> unit ! { Test } = {
  shifted = key_rate_shift(base_curve(), cast(1, i64), cast(0.005, f32))
  r1 = rate_at(shifted, cast(1.0, f32))
  r2 = rate_at(shifted, cast(2.0, f32))
  r3 = rate_at(shifted, cast(3.0, f32))
  _ = assert_close(r1, cast(0.03, f32), cast(0.00001, f32), "1y unchanged")
  _ = assert_close(r2, cast(0.045, f32), cast(0.00001, f32), "2y bumped +50bp")
  assert_close(r3, cast(0.045, f32), cast(0.00001, f32), "3y unchanged")
}
def test_twist_short_minus_long_widens_slope() -> unit ! { Test } = {
  twisted = twist(base_curve(), cast(-0.005, f32), cast(0.005, f32))
  r1 = rate_at(twisted, cast(1.0, f32))
  r3 = rate_at(twisted, cast(3.0, f32))
  _ = assert_close(r1, cast(0.025, f32), cast(0.00001, f32), "short end -50bp")
  assert_close(r3, cast(0.05, f32), cast(0.00001, f32), "long end +50bp")
}
def test_butterfly_dips_middle() -> unit ! { Test } = {
  bf = butterfly(base_curve(), cast(0.005, f32), cast(-0.005, f32))
  r1 = rate_at(bf, cast(1.0, f32))
  r2 = rate_at(bf, cast(2.0, f32))
  r3 = rate_at(bf, cast(3.0, f32))
  _ = assert_close(r1, cast(0.035, f32), cast(0.00001, f32), "wing +50bp at short")
  _ = assert_close(r2, cast(0.035, f32), cast(0.00001, f32), "body -50bp at mid")
  assert_close(r3, cast(0.05, f32), cast(0.00001, f32), "wing +50bp at long")
}
def test_scale_rates_uniform() -> unit ! { Test } = {
  scaled = scale_rates(base_curve(), cast(2.0, f32))
  r2 = rate_at(scaled, cast(2.0, f32))
  assert_close(r2, cast(0.08, f32), cast(0.00001, f32), "rates 2x")
}
def test_curve_kind_default_is_custom() -> unit ! { Test } = {
  curve = base_curve()
  is_custom = match curve_kind(curve) with {
    | Custom { label: _ } => true
    | Ois => false
    | Ibor => false
    | Sofr => false
    | Sonia => false
    | Estr => false
  }
  assert_true(is_custom, "untagged curve has Custom kind")
}
def test_curve_kind_ois() -> unit ! { Test } = {
  curve = yield_curve_tagged(ois(), to_tensor([cast(1.0, f32), cast(2.0, f32)]), to_tensor([cast(0.04, f32), cast(0.045, f32)]))
  is_ois = match curve_kind(curve) with {
    | Ois => true
    | Custom { label: _ } => false
    | Ibor => false
    | Sofr => false
    | Sonia => false
    | Estr => false
  }
  assert_true(is_ois, "Ois kind preserved")
}
def test_curve_kind_sofr() -> unit ! { Test } = {
  curve = yield_curve_tagged(sofr(), to_tensor([cast(1.0, f32)]), to_tensor([cast(0.04, f32)]))
  is_sofr = match curve_kind(curve) with {
    | Sofr => true
    | Ois => false
    | Custom { label: _ } => false
    | Ibor => false
    | Sonia => false
    | Estr => false
  }
  assert_true(is_sofr, "Sofr kind preserved")
}
def test_log_linear_at_pillar() -> unit ! { Test } = {
  curve = base_curve()
  r = log_linear_rate_at(curve, cast(2.0, f32))
  assert_close(r, cast(0.04, f32), cast(0.001, f32), "log-linear matches at pillar")
}
def test_nss_rate_at_zero_gives_beta0_plus_beta1() -> unit ! { Test } = {
  r = nss_rate(cast(0.04, f32), cast(-0.02, f32), cast(0.01, f32), cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(0.0, f32))
  assert_close(r, cast(0.02, f32), cast(0.001, f32), "NSS at t=0 == beta0 + beta1 (term1 limit -> 1; term2, term3 limit -> 0)")
}
def test_nss_rate_long_horizon_converges_to_beta0() -> unit ! { Test } = {
  r = nss_rate(cast(0.04, f32), cast(-0.02, f32), cast(0.01, f32), cast(0.005, f32), cast(1.0, f32), cast(2.0, f32), cast(100.0, f32))
  assert_close(r, cast(0.04, f32), cast(0.001, f32), "NSS at t=infty == beta0")
}
def test_custom_curve_label_preserved() -> unit ! { Test } = {
  curve = yield_curve_tagged(custom_curve("USD-IBOR-3M"), to_tensor([cast(1.0, f32)]), to_tensor([cast(0.04, f32)]))
  label_matches = match curve_kind(curve) with {
    | Custom { label: l } => eq(l, "USD-IBOR-3M")
    | Ois => false
    | Ibor => false
    | Sofr => false
    | Sonia => false
    | Estr => false
  }
  assert_true(label_matches, "custom label survives")
}
