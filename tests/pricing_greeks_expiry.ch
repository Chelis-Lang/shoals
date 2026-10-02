module Shoals.Tests.PricingGreeksExpiry
import Std.Test (assert_close, assert_true)
import Shoals.Pricing (deltas_call, deltas_put, vegas_call, rhos_call, thetas_call, gammas_call, volgas_call, vannas_call)
-- shoals#101. Every exported Greek at t = 0, pinned against the limit measured
-- by approaching expiry rather than against a transcribed decimal.
--
-- Two of the nine cells are genuinely non-finite and that is the correct answer,
-- not a defect: at the strike gamma diverges like n(d1)/(s*sigma*sqrt(t)) and
-- theta like -s*sigma*n(d1)/(2*sqrt(t)), n being the normal density. Those are
-- asserted as signed infinities. Every
-- other cell has a finite limit and is asserted as a number. NO cell is NaN.
--
-- The predicate below is the one shoals#101 asked for. `nan_free`-style
-- `eq(x, x)` is TRUE for +/-inf, so it cannot express "finite"; these tests need
-- both notions and keep them separate.
def inf32() -> f32 = div(cast(1.0, f32), cast(0.0, f32))
def is_nan32(x: f32) -> bool = not(eq(x, x))
def is_finite32(x: f32) -> bool = and(eq(x, x), lt(abs(x), inf32()))
def is_pos_inf32(x: f32) -> bool = and(eq(x, inf32()), not(is_nan32(x)))
def is_neg_inf32(x: f32) -> bool = and(eq(x, neg(inf32())), not(is_nan32(x)))
def spots3() -> tensor[3, f32] = to_tensor([cast(100.0, f32), cast(110.0, f32), cast(90.0, f32)])
def k100() -> f32 = cast(100.0, f32)
def r5() -> f32 = cast(0.05, f32)
def v20() -> f32 = cast(0.2, f32)
def zero() -> f32 = cast(0.0, f32)
def tol() -> f32 = cast(0.0001, f32)
-- The predicate itself needs pinning, because a predicate that cannot see what
-- it claims to see is how this defect survived in the first place.
def test_is_finite_rejects_positive_infinity() -> unit ! { Test } = assert_true(not(is_finite32(inf32())), "is_finite32(+inf) must be false")
def test_is_finite_rejects_negative_infinity() -> unit ! { Test } = assert_true(not(is_finite32(neg(inf32()))), "is_finite32(-inf) must be false")
def test_is_finite_rejects_nan() -> unit ! { Test } = assert_true(not(is_finite32(div(zero(), zero()))), "is_finite32(NaN) must be false")
def test_is_finite_accepts_a_number() -> unit ! { Test } = assert_true(is_finite32(cast(1.5, f32)), "is_finite32(1.5) must be true")
def test_nan_free_style_predicate_cannot_see_infinity() -> unit ! { Test } = assert_true(eq(inf32(), inf32()), "eq(x,x) is TRUE for +inf -- the reason is_finite32 exists")
-- DELTA at t = 0: 1 above the strike, 0 below, 0.5 at it. The 0.5 is the limit
-- in time at s = k (d1 -> 0 so N(d1) -> N(0)), measured 0.50014 at t = 1e-6.
def test_delta_at_expiry_at_the_strike_is_one_half() -> unit ! { Test } = {
  d = to_list(deltas_call(spots3(), k100(), r5(), v20(), zero()))
  assert_close(index(d, cast(0, i64)), cast(0.5, f32), tol(), "delta at t=0, s=k is 0.5, the limit in time")
}
def test_delta_at_expiry_above_the_strike_is_one() -> unit ! { Test } = {
  d = to_list(deltas_call(spots3(), k100(), r5(), v20(), zero()))
  assert_close(index(d, cast(1, i64)), cast(1.0, f32), tol(), "delta at t=0, s>k is 1")
}
def test_delta_at_expiry_below_the_strike_is_zero() -> unit ! { Test } = {
  d = to_list(deltas_call(spots3(), k100(), r5(), v20(), zero()))
  assert_close(index(d, cast(2, i64)), zero(), tol(), "delta at t=0, s<k is 0")
}
-- GAMMA at t = 0: +inf at the strike (a real singularity), 0 elsewhere.
def test_gamma_at_expiry_diverges_at_the_strike() -> unit ! { Test } = {
  g = to_list(gammas_call(spots3(), k100(), r5(), v20(), zero()))
  assert_true(is_pos_inf32(index(g, cast(0, i64))), "gamma at t=0, s=k is +inf, and must not be NaN")
}
def test_gamma_at_expiry_is_zero_off_the_strike() -> unit ! { Test } = {
  g = to_list(gammas_call(spots3(), k100(), r5(), v20(), zero()))
  _ = assert_close(index(g, cast(1, i64)), zero(), tol(), "gamma at t=0, s>k is 0")
  assert_close(index(g, cast(2, i64)), zero(), tol(), "gamma at t=0, s<k is 0")
}
-- THETA at t = 0: -r*k above the strike, 0 below, -inf at it.
def test_theta_at_expiry_above_the_strike_is_minus_rk() -> unit ! { Test } = {
  th = to_list(thetas_call(spots3(), k100(), r5(), v20(), zero()))
  assert_close(index(th, cast(1, i64)), neg(mul(r5(), k100())), tol(), "theta at t=0, s>k is -r*k")
}
def test_theta_at_expiry_below_the_strike_is_zero() -> unit ! { Test } = {
  th = to_list(thetas_call(spots3(), k100(), r5(), v20(), zero()))
  assert_close(index(th, cast(2, i64)), zero(), tol(), "theta at t=0, s<k is 0")
}
def test_theta_at_expiry_diverges_at_the_strike() -> unit ! { Test } = {
  th = to_list(thetas_call(spots3(), k100(), r5(), v20(), zero()))
  assert_true(is_neg_inf32(index(th, cast(0, i64))), "theta at t=0, s=k is -inf, and must not be NaN")
}
-- VANNA at t = 0 is 0 everywhere; VEGA, RHO and VOLGA were already correct.
def test_vanna_at_expiry_is_zero_everywhere() -> unit ! { Test } = {
  v = to_list(vannas_call(spots3(), k100(), r5(), v20(), zero()))
  _ = assert_close(index(v, cast(0, i64)), zero(), tol(), "vanna at t=0, s=k is 0")
  _ = assert_close(index(v, cast(1, i64)), zero(), tol(), "vanna at t=0, s>k is 0")
  assert_close(index(v, cast(2, i64)), zero(), tol(), "vanna at t=0, s<k is 0")
}
def test_vega_rho_volga_at_expiry_are_zero() -> unit ! { Test } = {
  ve = to_list(vegas_call(spots3(), k100(), r5(), v20(), zero()))
  rh = to_list(rhos_call(spots3(), k100(), r5(), v20(), zero()))
  vo = to_list(volgas_call(spots3(), k100(), r5(), v20(), zero()))
  _ = assert_close(index(ve, cast(0, i64)), zero(), tol(), "vega at t=0 is 0")
  _ = assert_close(index(rh, cast(0, i64)), zero(), tol(), "rho at t=0 is 0")
  assert_close(index(vo, cast(0, i64)), zero(), tol(), "volga at t=0 is 0")
}
-- THE CLASS ASSERTION: no cell of the Greek surface at t = 0 is NaN. This is the
-- sentence shoals#101 exists to make true, so it is asserted directly rather
-- than left to the per-cell tests above.
def test_no_greek_is_nan_at_expiry() -> unit ! { Test } = {
  d = to_list(deltas_call(spots3(), k100(), r5(), v20(), zero()))
  g = to_list(gammas_call(spots3(), k100(), r5(), v20(), zero()))
  th = to_list(thetas_call(spots3(), k100(), r5(), v20(), zero()))
  vn = to_list(vannas_call(spots3(), k100(), r5(), v20(), zero()))
  _ = assert_true(not(is_nan32(index(d, cast(0, i64)))), "delta at t=0 s=k is not NaN")
  _ = assert_true(not(is_nan32(index(g, cast(1, i64)))), "gamma at t=0 s>k is not NaN")
  _ = assert_true(not(is_nan32(index(g, cast(2, i64)))), "gamma at t=0 s<k is not NaN")
  _ = assert_true(not(is_nan32(index(th, cast(0, i64)))), "theta at t=0 s=k is not NaN")
  _ = assert_true(not(is_nan32(index(th, cast(1, i64)))), "theta at t=0 s>k is not NaN")
  _ = assert_true(not(is_nan32(index(th, cast(2, i64)))), "theta at t=0 s<k is not NaN")
  _ = assert_true(not(is_nan32(index(vn, cast(1, i64)))), "vanna at t=0 s>k is not NaN")
  assert_true(not(is_nan32(index(vn, cast(2, i64)))), "vanna at t=0 s<k is not NaN")
}
-- CONTINUITY: where the limit is finite, the t = 0 answer must agree with a
-- near-expiry AD evaluation. This is what makes the closed forms above
-- answers to the same question the AD path answers, rather than new constants.
def test_expiry_limits_agree_with_near_expiry_ad() -> unit ! { Test } = {
  near = cast(1e-6, f32)
  d0 = to_list(deltas_call(spots3(), k100(), r5(), v20(), zero()))
  dn = to_list(deltas_call(spots3(), k100(), r5(), v20(), near))
  th0 = to_list(thetas_call(spots3(), k100(), r5(), v20(), zero()))
  thn = to_list(thetas_call(spots3(), k100(), r5(), v20(), near))
  _ = assert_close(index(d0, cast(0, i64)), index(dn, cast(0, i64)), cast(0.001, f32), "delta at s=k agrees with t=1e-6")
  _ = assert_close(index(d0, cast(1, i64)), index(dn, cast(1, i64)), cast(0.001, f32), "delta at s>k agrees with t=1e-6")
  assert_close(index(th0, cast(1, i64)), index(thn, cast(1, i64)), cast(0.001, f32), "theta at s>k agrees with t=1e-6")
}
-- The AD path for t > 0 must be untouched by the t = 0 branch.
def test_positive_t_path_is_unchanged() -> unit ! { Test } = {
  g = to_list(gammas_call(spots3(), k100(), r5(), v20(), cast(0.01, f32)))
  th = to_list(thetas_call(spots3(), k100(), r5(), v20(), cast(0.01, f32)))
  d = to_list(deltas_call(spots3(), k100(), r5(), v20(), cast(0.01, f32)))
  vn = to_list(vannas_call(spots3(), k100(), r5(), v20(), cast(0.01, f32)))
  _ = assert_close(index(g, cast(0, i64)), cast(0.199349, f32), cast(0.00001, f32), "gamma at t=0.01 unchanged")
  _ = assert_close(index(th, cast(0, i64)), cast(-42.398457, f32), cast(0.001, f32), "theta at t=0.01 unchanged")
  _ = assert_close(index(d, cast(0, i64)), cast(0.5139601, f32), cast(0.00001, f32), "delta at t=0.01 unchanged -- pins the t==0 branch boundary, not only the limit")
  _ = assert_close(index(vn, cast(0, i64)), cast(-0.029902348, f32), cast(1e-6, f32), "vanna at t=0.01 unchanged -- same boundary pin")
  -- The boundary pin that matters sits INSIDE any plausible widening of the
  -- condition. A t == 0 assertion and a loose near-expiry one both survive
  -- `eq(t, 0)` becoming `lt(t, 1e-3)`, because the closed form and the AD answer
  -- agree to about 1e-4 there. At t = 1e-4 the AD delta is 0.5013963 while the
  -- closed form is 0.5, and a 1e-5 tolerance separates them.
  dn = to_list(deltas_call(spots3(), k100(), r5(), v20(), cast(0.0001, f32)))
  assert_close(index(dn, cast(0, i64)), cast(0.5013963, f32), cast(0.00001, f32), "delta at t=1e-4 is the AD value, not the t=0 closed form")
}
-- PUT DELTA at t = 0 (shoals#106). The limits mirror the call: -1 below the
-- strike, -0.5 at it, 0 above. At expiry the put price is max(k - s, 0).
--
-- Two independent legs, and neither is decoration: with the cell assertions
-- made vacuous the parity test still catches the defect, and with parity made
-- vacuous the cells still do.
--
-- Parity is the more interesting leg because it is not a transcribed decimal.
-- Put-call parity differentiated in the spot gives delta_call - delta_put = 1 for
-- every spot and every t, so it ties the put cells to the call cells. Those call
-- cells are pinned in this file, against a near-expiry AD evaluation -- NOT by
-- `scripts/oracle_greeks_gate.py`, whose grid is t in {0.25, 1, 2} and which
-- never evaluates a put. The oracle pins the AD path; this file pins the expiry
-- cells. Parity is also falsifiable on exactly the defect this fixes: with put
-- delta 0.0 at the strike and call delta 0.5, parity there reads 0.5, not 1.
def test_put_delta_at_expiry_below_the_strike_is_minus_one() -> unit ! { Test } = {
  d = to_list(deltas_put(spots3(), k100(), r5(), v20(), zero()))
  assert_close(index(d, cast(2, i64)), cast(-1.0, f32), tol(), "put delta at t=0, s<k is -1")
}
def test_put_delta_at_expiry_at_the_strike_is_minus_one_half() -> unit ! { Test } = {
  d = to_list(deltas_put(spots3(), k100(), r5(), v20(), zero()))
  assert_close(index(d, cast(0, i64)), cast(-0.5, f32), tol(), "put delta at t=0, s=k is -0.5, the limit in time")
}
def test_put_delta_at_expiry_above_the_strike_is_zero() -> unit ! { Test } = {
  d = to_list(deltas_put(spots3(), k100(), r5(), v20(), zero()))
  assert_close(index(d, cast(1, i64)), zero(), tol(), "put delta at t=0, s>k is 0")
}
def test_put_call_parity_for_delta_holds_at_expiry() -> unit ! { Test } = {
  c = to_list(deltas_call(spots3(), k100(), r5(), v20(), zero()))
  p = to_list(deltas_put(spots3(), k100(), r5(), v20(), zero()))
  _ = assert_close(sub(index(c, cast(0, i64)), index(p, cast(0, i64))), cast(1.0, f32), tol(), "parity at t=0, s=k -- 0.5 here before shoals#106")
  _ = assert_close(sub(index(c, cast(1, i64)), index(p, cast(1, i64))), cast(1.0, f32), tol(), "parity at t=0, s>k")
  assert_close(sub(index(c, cast(2, i64)), index(p, cast(2, i64))), cast(1.0, f32), tol(), "parity at t=0, s<k")
}
-- If you widen this grid: parity holds for every t down to normal f32 range, and
-- breaks at the strike ONLY for t <= 1e-32, where both deltas collapse to 0.0
-- through catastrophic cancellation in the shared AD path. Off-strike cells stay
-- correct there. 1e-32 years is 3e-25 seconds, so no caller reaches it; it is
-- recorded here rather than tracked, and it is identical on the call side.
def test_put_call_parity_for_delta_holds_away_from_expiry() -> unit ! { Test } = {
  c = to_list(deltas_call(spots3(), k100(), r5(), v20(), cast(1.0, f32)))
  p = to_list(deltas_put(spots3(), k100(), r5(), v20(), cast(1.0, f32)))
  _ = assert_close(sub(index(c, cast(0, i64)), index(p, cast(0, i64))), cast(1.0, f32), tol(), "parity at t=1, s=k -- the AD path")
  assert_close(sub(index(c, cast(2, i64)), index(p, cast(2, i64))), cast(1.0, f32), tol(), "parity at t=1, s<k -- the AD path")
}
-- A second strike, because every other assertion here uses k = 100 and the
-- expiry helpers take `k` as an argument. Without this, both helpers can discard
-- `k` and hardcode 100.0 with the whole file still green -- measured.
def test_put_call_parity_at_a_second_strike() -> unit ! { Test } = {
  k90 = cast(90.0, f32)
  c = to_list(deltas_call(spots3(), k90, r5(), v20(), zero()))
  p = to_list(deltas_put(spots3(), k90, r5(), v20(), zero()))
  _ = assert_close(sub(index(c, cast(2, i64)), index(p, cast(2, i64))), cast(1.0, f32), tol(), "parity at t=0, k=90, s=k")
  _ = assert_close(index(c, cast(2, i64)), cast(0.5, f32), tol(), "call delta at t=0, k=90, s=k is 0.5")
  assert_close(index(p, cast(2, i64)), cast(-0.5, f32), tol(), "put delta at t=0, k=90, s=k is -0.5")
}
def test_put_delta_positive_t_path_is_unchanged() -> unit ! { Test } = {
  p = to_list(deltas_put(spots3(), k100(), r5(), v20(), cast(0.0001, f32)))
  assert_close(index(p, cast(0, i64)), cast(-0.4986037, f32), cast(0.00001, f32), "put delta at t=1e-4 is the AD value, not the t=0 closed form")
}
def test_put_delta_is_not_nan_at_expiry() -> unit ! { Test } = {
  p = to_list(deltas_put(spots3(), k100(), r5(), v20(), zero()))
  _ = assert_true(not(is_nan32(index(p, cast(0, i64)))), "put delta at t=0 s=k is not NaN")
  _ = assert_true(is_finite32(index(p, cast(1, i64))), "put delta at t=0 s>k is finite")
  assert_true(is_finite32(index(p, cast(2, i64))), "put delta at t=0 s<k is finite")
}
