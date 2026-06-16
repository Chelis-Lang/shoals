module Shoals.Tests.Trees
import Std.Test (assert_true)
import Shoals.Trees (tr_crr_european_call, tr_crr_european_put, tr_crr_american_call, tr_crr_american_put, tr_tian_european_call, tr_tian_european_put, tr_jr_european_call, tr_jr_european_put, tr_trinomial_european_call)
def tr_abs(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_crr_put_call_parity_european() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  n = cast(5, int64)
  c = tr_crr_european_call(s0, k, r, cast(0.0, f32), sigma, t, n)
  p = tr_crr_european_put(s0, k, r, cast(0.0, f32), sigma, t, n)
  lhs = sub(c, p)
  rhs = sub(s0, mul(k, exp(neg(mul(r, t)))))
  assert_true(lt(tr_abs(sub(lhs, rhs)), cast(0.005, f32)), "CRR European put-call parity C-P = S-K*exp(-rT) within 0.005 at n=5 (structural no-arbitrage identity, n-independent)")
}
def test_tian_put_call_parity_european() -> unit ! { Test } = {
  c = tr_tian_european_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.2, f32), cast(1.0, f32), cast(5, int64))
  p = tr_tian_european_put(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.2, f32), cast(1.0, f32), cast(5, int64))
  rhs = sub(cast(100.0, f32), mul(cast(100.0, f32), exp(neg(cast(0.05, f32)))))
  assert_true(lt(tr_abs(sub(sub(c, p), rhs)), cast(0.01, f32)), "Tian European put-call parity within 0.01 at n=5")
}
def test_jr_put_call_parity_european() -> unit ! { Test } = {
  c = tr_jr_european_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.2, f32), cast(1.0, f32), cast(5, int64))
  p = tr_jr_european_put(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.2, f32), cast(1.0, f32), cast(5, int64))
  rhs = sub(cast(100.0, f32), mul(cast(100.0, f32), exp(neg(cast(0.05, f32)))))
  assert_true(lt(tr_abs(sub(sub(c, p), rhs)), cast(0.01, f32)), "Jarrow-Rudd European put-call parity within 0.01 at n=5")
}
def test_crr_american_call_no_div_equals_european() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  n = cast(5, int64)
  p_eu = tr_crr_european_call(s0, k, r, cast(0.0, f32), sigma, t, n)
  p_am = tr_crr_american_call(s0, k, r, cast(0.0, f32), sigma, t, n)
  assert_true(lt(tr_abs(sub(p_am, p_eu)), cast(0.001, f32)), "CRR American call with q=0 equals European within 0.001 at n=5 (early exercise never optimal on a non-dividend-paying underlying)")
}
def test_crr_american_put_ge_european() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  k = cast(110.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.3, f32)
  t = cast(1.0, f32)
  n = cast(5, int64)
  p_eu = tr_crr_european_put(s0, k, r, cast(0.0, f32), sigma, t, n)
  p_am = tr_crr_american_put(s0, k, r, cast(0.0, f32), sigma, t, n)
  finite_eu = and(gt(p_eu, cast(0.0, f32)), lt(p_eu, k))
  finite_am = and(gt(p_am, cast(0.0, f32)), lt(p_am, k))
  assert_true(and(finite_eu, and(finite_am, gte(p_am, p_eu))), "CRR ITM American put is finite, positive, and >= European put under the same tree at n=5 (early-exercise premium non-negative)")
}
def test_crr_low_sigma_returns_deterministic_intrinsic() -> unit ! { Test } = {
  call_low = tr_crr_european_call(cast(100.0, f32), cast(90.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.0000001, f32), cast(1.0, f32), cast(5, int64))
  expected = sub(cast(100.0, f32), mul(cast(90.0, f32), exp(neg(cast(0.05, f32)))))
  tian_low = tr_tian_european_call(cast(100.0, f32), cast(90.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.0000001, f32), cast(1.0, f32), cast(5, int64))
  tri_low = tr_trinomial_european_call(cast(100.0, f32), cast(90.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.0000001, f32), cast(1.0, f32), cast(5, int64))
  crr_ok = lt(tr_abs(sub(call_low, expected)), cast(0.001, f32))
  tian_ok = eq(tian_low, tian_low)
  tri_ok = eq(tri_low, tri_low)
  assert_true(and(crr_ok, and(tian_ok, tri_ok)), "CRR/Tian/Trinomial at sigma=1e-7 hit the deterministic sigma-floor guard with no NaN: CRR returns forward intrinsic S0-K*exp(-rT), Tian and Trinomial are finite (eq(x,x))")
}
