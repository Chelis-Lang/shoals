module Shoals.Tests.PricingExpiry
import Std.Test (assert_close, assert_true)
import Shoals.Pricing (bs_call_f64, bs_call_scalar, bs_put_scalar, bs_call_f64_vector, bs_call_wire_f64, deltas_call, vegas_call)
-- shoals#88. `bs_call_f64` returned NaN where the forward sits exactly on the
-- strike with no remaining uncertainty. The issue frames it as "t = 0 returns
-- NaN"; measured on the pre-fix tree that is wrong in both directions.
--
-- CORRECT BEFORE THE FIX (these pin that the fix did not disturb them):
--   t = 0 in the money      -> s - k
--   t = 0 out of the money  -> 0
--   sigma = 0 with r != 0   -> max(s - k*exp(-rt), 0)
-- BROKEN BEFORE THE FIX (num = 0 and den = 0 together):
--   s = k with t = 0, any sigma, any r
--   s = k with sigma = 0 and r = 0, at any t   <- not an expiry case at all
--
-- Every one of these is `max(s - k*exp(-rt), 0)`, so the suite asserts that
-- closed form rather than a transcribed decimal.
def nan_free(x: f64) -> bool = eq(x, x)
def nan_free32(x: f32) -> bool = eq(x, x)
def k100() -> f64 = cast(100.0, f64)
def r5() -> f64 = cast(0.05, f64)
def v20() -> f64 = cast(0.2, f64)
def z() -> f64 = cast(0.0, f64)
def tol() -> f64 = cast(1e-9, f64)
def test_expiry_in_the_money_is_intrinsic() -> unit ! { Test } = assert_close(bs_call_f64(cast(110.0, f64), k100(), r5(), v20(), z()), cast(10.0, f64), tol(), "t=0 ITM call == s - k")
def test_expiry_out_of_the_money_is_zero() -> unit ! { Test } = assert_close(bs_call_f64(cast(90.0, f64), k100(), r5(), v20(), z()), z(), tol(), "t=0 OTM call == 0")
def test_expiry_at_the_money_is_zero_not_nan() -> unit ! { Test } = assert_close(bs_call_f64(k100(), k100(), r5(), v20(), z()), z(), tol(), "t=0 ATM call == 0 (was NaN, shoals#88)")
def test_expiry_at_the_money_zero_rate_is_zero() -> unit ! { Test } = assert_close(bs_call_f64(k100(), k100(), z(), v20(), z()), z(), tol(), "t=0 ATM r=0 call == 0 (was NaN)")
def test_expiry_at_the_money_zero_vol_is_zero() -> unit ! { Test } = assert_close(bs_call_f64(k100(), k100(), r5(), z(), z()), z(), tol(), "t=0 ATM sigma=0 call == 0 (was NaN)")
-- The member the issue does not describe: no expiry involved.
def test_zero_vol_zero_rate_at_the_money_is_zero() -> unit ! { Test } = assert_close(bs_call_f64(k100(), k100(), z(), z(), cast(1.0, f64)), z(), tol(), "sigma=0 r=0 ATM at t=1 == 0 (was NaN, and not an expiry case)")
-- Unchanged behaviour the fix must not move: zero vol with a rate is the
-- discounted intrinsic, and it was already correct.
def test_zero_vol_with_rate_is_discounted_intrinsic() -> unit ! { Test } = {
  disc = exp(neg(mul(r5(), cast(1.0, f64))))
  _ = assert_close(bs_call_f64(k100(), k100(), r5(), z(), cast(1.0, f64)), sub(k100(), mul(k100(), disc)), tol(), "sigma=0 ATM == s - k*disc, unchanged")
  assert_close(bs_call_f64(cast(110.0, f64), k100(), r5(), z(), cast(1.0, f64)), sub(cast(110.0, f64), mul(k100(), disc)), tol(), "sigma=0 ITM == s - k*disc, unchanged")
}
-- Both f32 entry points share the body, so both were broken and both are fixed.
def test_f32_entry_points_at_expiry() -> unit ! { Test } = {
  _ = assert_close(bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.0, f32)), cast(0.0, f32), cast(0.0001, f32), "bs_call_scalar t=0 ATM == 0 (the issue's named entry point)")
  assert_close(bs_put_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.0, f32)), cast(0.0, f32), cast(0.0001, f32), "bs_put_scalar t=0 ATM == 0")
}
-- The vmap lane runs the same body under a masked select. The fix is a
-- denominator clamp and not a branch on the price because of the adjoint, not
-- the value: a branch returns the right price and a NaN delta (chelis#2640).
def test_vmap_lane_at_expiry() -> unit ! { Test } = {
  out = bs_call_f64_vector(to_tensor([cast(100.0, f64), cast(110.0, f64)]), to_tensor([k100(), k100()]), to_tensor([r5(), r5()]), to_tensor([v20(), v20()]), to_tensor([z(), z()]))
  vals = to_list(out)
  _ = assert_close(index(vals, cast(0, i64)), z(), tol(), "vmap t=0 ATM == 0 (was NaN)")
  assert_close(index(vals, cast(1, i64)), cast(10.0, f64), tol(), "vmap t=0 ITM == 10, unchanged")
}
-- The Greeks differentiate this body, which is where a branch would have
-- reintroduced the defect (see the adjoint note above `d1_64`). Read the scope
-- of these two tests precisely, because it is narrower than the Greek class:
--
--   * They assert NAN-FREEDOM, not finiteness. `nan_free32` is `eq(x, x)`,
--     which is TRUE for +/-inf -- measured -- so an infinite Greek passes here.
--   * They cover DELTA and VEGA only. Measured post-fix at expiry, those two
--     are clean (`[0,1,0]` and `[0,0,0]`) but gamma is `[inf,NaN,NaN]`, theta
--     is `[NaN,NaN,NaN]` and vanna is `[0.0,NaN,NaN]`. That residue is not a
--     regression -- pre-fix all seven exported Greeks were NaN at every
--     moneyness -- so the fix is neutral-or-better everywhere, but it is not
--     fixed, and this file does not claim it is.
--
-- Also unasserted, and worth knowing before trusting delta at expiry: the ATM
-- value is 0.0 where the one-sided limits are 0 and 1, so the conventional 0.5
-- midpoint is not what comes back.
--
-- The Greek vectors are the f32 surface and take scalar k/r/sigma/t.
def test_greeks_are_nan_free_at_expiry() -> unit ! { Test } = {
  spots = to_tensor([cast(100.0, f32), cast(110.0, f32), cast(90.0, f32)])
  d = to_list(deltas_call(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.0, f32)))
  _ = assert_true(nan_free32(index(d, cast(0, i64))), "delta at t=0 ATM is not NaN")
  _ = assert_true(nan_free32(index(d, cast(1, i64))), "delta at t=0 ITM is not NaN")
  assert_true(nan_free32(index(d, cast(2, i64))), "delta at t=0 OTM is not NaN")
}
def test_vegas_are_nan_free_at_expiry() -> unit ! { Test } = {
  spots = to_tensor([cast(100.0, f32), cast(110.0, f32), cast(90.0, f32)])
  v = to_list(vegas_call(spots, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.0, f32)))
  _ = assert_true(nan_free32(index(v, cast(0, i64))), "vega at t=0 ATM is not NaN")
  _ = assert_true(nan_free32(index(v, cast(1, i64))), "vega at t=0 ITM is not NaN")
  assert_true(nan_free32(index(v, cast(2, i64))), "vega at t=0 OTM is not NaN")
}
-- THE WIRE LANE, which was strictly worse than the scalar one: NaN at EVERY
-- moneyness on expiry, not only at the money, because nothing in it saturates.
-- Every selector is arithmetic and `0 * inf` is NaN, so the first `+/-inf` to
-- reach `pricing_wire_abs_f64` poisoned the result regardless of which branch
-- the mask chose. These pin the fix at all three moneyness positions plus the
-- non-expiry member.
def c2(v: f64) -> tensor[2, f64] = to_tensor([v, v])
def wirelane_call(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = {
  out = bs_call_wire_f64(c2(s), c2(k), c2(r), c2(sigma), c2(t), c2(cast(0.5, f64)), c2(cast(0.7071067811865476, f64)), c2(cast(0.254829592, f64)), c2(cast(-0.284496736, f64)), c2(cast(1.421413741, f64)), c2(cast(-1.453152027, f64)), c2(cast(1.061405429, f64)), c2(cast(0.3275911, f64)), c2(cast(1.1283791670955126, f64)), c2(cast(0.00001, f64)))
  index(to_list(out), cast(0, i64))
}
def wirelane_tol() -> f64 = cast(0.0001, f64)
def test_wire_expiry_in_the_money() -> unit ! { Test } = assert_close(wirelane_call(cast(110.0, f64), k100(), r5(), v20(), z()), cast(10.0, f64), wirelane_tol(), "wire t=0 ITM == 10 (was NaN)")
def test_wire_expiry_out_of_the_money() -> unit ! { Test } = assert_close(wirelane_call(cast(90.0, f64), k100(), r5(), v20(), z()), z(), wirelane_tol(), "wire t=0 OTM == 0 (was NaN)")
def test_wire_expiry_at_the_money() -> unit ! { Test } = assert_close(wirelane_call(k100(), k100(), r5(), v20(), z()), z(), wirelane_tol(), "wire t=0 ATM == 0 (was NaN)")
def test_wire_zero_vol_zero_rate_at_the_money() -> unit ! { Test } = assert_close(wirelane_call(k100(), k100(), z(), z(), cast(1.0, f64)), z(), wirelane_tol(), "wire sigma=0 r=0 ATM == 0 (was NaN, not an expiry case)")
-- Unchanged behaviour: the wire lane must still agree with the scalar body away
-- from the degenerate points, which is what makes the floor a fix and not a
-- reparameterisation.
def test_wire_agrees_with_scalar_away_from_the_boundary() -> unit ! { Test } = {
  _ = assert_close(wirelane_call(cast(110.0, f64), k100(), r5(), v20(), cast(1.0, f64)), bs_call_f64(cast(110.0, f64), k100(), r5(), v20(), cast(1.0, f64)), cast(0.01, f64), "wire == scalar, ITM t=1")
  _ = assert_close(wirelane_call(k100(), k100(), r5(), v20(), cast(1.0, f64)), bs_call_f64(k100(), k100(), r5(), v20(), cast(1.0, f64)), cast(0.01, f64), "wire == scalar, ATM t=1")
  assert_close(wirelane_call(cast(90.0, f64), k100(), r5(), v20(), cast(0.25, f64)), bs_call_f64(cast(90.0, f64), k100(), r5(), v20(), cast(0.25, f64)), cast(0.01, f64), "wire == scalar, OTM t=0.25")
}
