module Shoals.Tests.Lsm
import Std.Test (assert_true)
import Shoals.Lsm (lsm_polynomial_regression, lsm_american_put, lsm_put_payoff)
import Nautilus.Distributions (normal_sample)
def lsm_t_abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
def test_lsm_polynomial_regression_recovers_quadratic() -> unit ! { Test } = {
  xs = to_tensor(map(fn (i: i64) -> add(cast(-1.0, f32), cast(i, f32)), range(cast(0, i64), cast(5, i64))))
  xs_l = to_list(copy(xs))
  ys = to_tensor(map(fn (x: f32) -> add(cast(2.0, f32), add(mul(cast(3.0, f32), x), mul(cast(4.0, f32), mul(x, x)))), xs_l))
  coeffs = lsm_polynomial_regression(xs, ys)
  b0 = coeffs.0
  b1 = coeffs.1
  b2 = coeffs.2
  tol = cast(0.001, f32)
  e0 = lt(lsm_t_abs_f32(sub(b0, cast(2.0, f32))), tol)
  e1 = lt(lsm_t_abs_f32(sub(b1, cast(3.0, f32))), tol)
  e2 = lt(lsm_t_abs_f32(sub(b2, cast(4.0, f32))), tol)
  ok = and(e0, and(e1, e2))
  assert_true(ok, "regression recovers (2, 3, 4) on noise-free quadratic y=2+3x+4x^2 at 5 evenly spaced x in {-1,0,1,2,3} within 1e-3 (5 data > 3 unknowns => exact LS fit)")
}
def test_lsm_translated_quadratic() -> unit ! { Test } = {
  xs = to_tensor([90f32, 95f32, 100f32, 105f32, 110f32])
  ys = to_tensor([101f32, 26f32, 1f32, 26f32, 101f32])
  b = lsm_polynomial_regression(xs, ys)
  assert_true(and(lt(abs(sub(b.0, 10001f32)), 0.01f32), and(lt(abs(add(b.1, 200f32)), 0.0001f32), lt(abs(sub(b.2, 1f32)), 1e-6f32))), "the spot-scale translated quadratic 1 + (x - 100)^2 recovers original-basis coefficients")
}
def test_lsm_tightly_clustered_quadratic() -> unit ! { Test } = {
  b = lsm_polynomial_regression(to_tensor([99f32, 99.5f32, 100f32, 100.5f32, 101f32]), to_tensor([2f32, 1.25f32, 1f32, 1.25f32, 2f32]))
  assert_true(and(lt(abs(sub(b.0, 10001f32)), 0.01f32), and(lt(abs(add(b.1, 200f32)), 0.0001f32), lt(abs(sub(b.2, 1f32)), 1e-6f32))), "centering/scaling keeps a narrow spot cluster accurate")
}
def test_lsm_degenerate_fits() -> unit ! { Test } = {
  constant = lsm_polynomial_regression(to_tensor([100f32, 100f32, 100f32, 100f32]), to_tensor([1f32, 2f32, 3f32, 4f32]))
  linear = lsm_polynomial_regression(to_tensor([90f32, 100f32, 90f32, 100f32]), to_tensor([2f32, 4f32, 4f32, 6f32]))
  _ = assert_true(and(eq(constant.0, 2.5f32), and(eq(constant.1, 0f32), eq(constant.2, 0f32))), "one distinct x fits the mean as a constant")
  assert_true(and(lt(abs(add(linear.0, 15f32)), 0.00001f32), and(lt(abs(sub(linear.1, 0.2f32)), 1e-6f32), eq(linear.2, 0f32))), "two distinct x fit their group means linearly")
}
def test_lsm_observation_order_invariance() -> unit ! { Test } = {
  a = lsm_polynomial_regression(to_tensor([90f32, 95f32, 100f32, 105f32, 110f32]), to_tensor([4f32, 6f32, 8f32, 11f32, 15f32]))
  b = lsm_polynomial_regression(to_tensor([110f32, 105f32, 100f32, 95f32, 90f32]), to_tensor([15f32, 11f32, 8f32, 6f32, 4f32]))
  assert_true(and(lt(abs(sub(a.0, b.0)), 0.0001f32), and(lt(abs(sub(a.1, b.1)), 1e-6f32), lt(abs(sub(a.2, b.2)), 1e-8f32))), "reordering paired observations preserves the polynomial fit")
}
def test_lsm_expiry_and_immediate_exercise() -> unit ! { Test } = {
  expiry = lsm_american_put(key_from_seed(11i64), to_tensor([0f32]), 50f32, 100f32, 0.05f32, 0.2f32, 0f32, 3i64)
  deterministic = lsm_american_put(key_from_seed(11i64), to_tensor([0f32, 0f32, 0f32, 0f32]), 50f32, 100f32, 0.05f32, 0f32, 1f32, 3i64)
  assert_true(and(eq(expiry, 50f32), eq(deterministic, 50f32)), "expiry and optimal time-zero exercise return intrinsic exactly")
}
def test_lsm_deterministic_negative_rate_discount() -> unit ! { Test } = {
  price = lsm_american_put(key_from_seed(11i64), to_tensor([0f32, 0f32, 0f32, 0f32]), 80f32, 100f32, -0.05f32, 0f32, 1f32, 4i64)
  expected = sub(mul(100f32, exp(0.05f32)), 80f32)
  assert_true(lt(abs(sub(price, expected)), 0.0001f32), "at sigma zero and negative rate terminal exercise dominates; discount the terminal cash flow once")
}
-- With two paths, each date has at most two distinct ITM spots. The
-- degree-adapted fit interpolates each path's continuation, so this tiny
-- fixture has an exact discounted-path-maximum oracle (not a pricing oracle).
-- Replaying the keyed draws independently catches path/time mixing and
-- wrong stopping dates without exporting implementation helpers.
-- Replay each date from the sum of Brownian draws, rather than the
-- implementation's tensor cumulative sum of drift-plus-diffusion increments.
def lsm_two_path_replay(seed: i64, s0: f32, k: f32, r: f32, sigma: f32, t: f32, steps: i64) -> f32 = {
  zs = to_list(normal_sample(key_from_seed(seed), to_tensor(map(fn (i: i64) -> 0f32, range(0i64, mul(2i64, steps)))), 0f32, 1f32))
  dt = div(cast(t, f64), cast(steps, f64))
  sigma64 = cast(sigma, f64)
  variance = mul(mul(sigma64, sigma64), dt)
  path_values = map(fn (p: i64) -> {
    result = fold(fn (state: (f64, f64), j: i64) -> {
      draws = add(state.0, cast(index(zs, add(mul(p, steps), j)), f64))
      date = cast(add(j, 1i64), f64)
      elapsed = mul(dt, date)
      log_s = add(log(cast(s0, f64)), add(sub(mul(cast(r, f64), elapsed), mul(0.5f64, mul(variance, date))), mul(sqrt(variance), draws)))
      spot = cast(exp(log_s), f32)
      pv = mul(exp(neg(mul(cast(r, f64), elapsed))), cast(lsm_put_payoff(spot, k), f64))
      (draws, if gt(pv, state.1) then pv else state.1)
    }, (0f64, 0f64), range(0i64, steps))
    result.1
  }, range(0i64, 2i64))
  continuation = div(add(index(path_values, 0i64), index(path_values, 1i64)), 2f64)
  intrinsic = cast(lsm_put_payoff(s0, k), f64)
  cast(if gt(intrinsic, continuation) then intrinsic else continuation, f32)
}
def test_lsm_two_path_identity_stopping_and_discount() -> unit ! { Test } = {
  expected = lsm_two_path_replay(21i64, 100f32, 100f32, 0.05f32, 0.2f32, 1f32, 3i64)
  price = lsm_american_put(key_from_seed(21i64), to_tensor([0f32, 0f32]), 100f32, 100f32, 0.05f32, 0.2f32, 1f32, 3i64)
  assert_true(lt(abs(sub(price, expected)), 0.0001f32), "2 paths x 3 dates retain path identity, stopping date, and exactly one discount to time zero")
}
def test_lsm_single_observation_and_two_observations() -> unit ! { Test } = {
  one = lsm_polynomial_regression(to_tensor([99f32]), to_tensor([7f32]))
  two = lsm_polynomial_regression(to_tensor([90f32, 100f32]), to_tensor([3f32, 5f32]))
  _ = assert_true(and(eq(one.0, 7f32), and(eq(one.1, 0f32), eq(one.2, 0f32))), "one observation gives its constant value")
  assert_true(and(lt(abs(add(two.0, 15f32)), 0.00001f32), and(lt(abs(sub(two.1, 0.2f32)), 1e-6f32), eq(two.2, 0f32))), "two observations interpolate with a linear fit")
}
def lsm_one_step_replay(seed: i64, paths: i64, s0: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  zs = to_list(normal_sample(key_from_seed(seed), to_tensor(map(fn (i: i64) -> 0f32, range(0i64, paths))), 0f32, 1f32))
  variance = mul(mul(cast(sigma, f64), cast(sigma, f64)), cast(t, f64))
  terminal = map(fn (z: f32) -> cast(exp(add(log(cast(s0, f64)), add(sub(mul(cast(r, f64), cast(t, f64)), mul(0.5f64, variance)), mul(sqrt(variance), cast(z, f64))))), f32), zs)
  mean_payoff = div(fold(fn (acc: f64, s: f32) -> add(acc, cast(lsm_put_payoff(s, k), f64)), 0f64, terminal), cast(paths, f64))
  discounted = mul(exp(neg(mul(cast(r, f64), cast(t, f64)))), mean_payoff)
  intrinsic = cast(lsm_put_payoff(s0, k), f64)
  cast(if gt(intrinsic, discounted) then intrinsic else discounted, f32)
}
def test_lsm_one_step_replayed_european_sample() -> unit ! { Test } = {
  checks = map(fn (seed: i64) -> {
    expected = lsm_one_step_replay(seed, 8i64, 100f32, 100f32, 0.05f32, 0.2f32, 1f32)
    price = lsm_american_put(key_from_seed(seed), to_tensor([0f32, 0f32, 0f32, 0f32, 0f32, 0f32, 0f32, 0f32]), 100f32, 100f32, 0.05f32, 0.2f32, 1f32, 1i64)
    lt(abs(sub(price, expected)), 1e-6f32)
  }, [0i64, 1i64, 2i64, 17i64, 21i64])
  assert_true(fold(fn (ok: bool, check: bool) -> and(ok, check), true, checks), "ordinary one-date prices agree with independent keyed GBM replay across five seeds")
}
-- shoals#163: input f32 rounding makes sigma^2*T about 0.99999465;
-- it explains less than 0.00017 of the ATM same-key price difference.
def test_lsm_extreme_variance_and_replay() -> unit ! { Test } = {
  extreme = lsm_american_put(key_from_seed(17i64), to_tensor([0f32, 0f32, 0f32, 0f32, 0f32]), 100f32, 100f32, 0f32, 1e20f32, 1e-40f32, 1i64)
  ordinary = lsm_american_put(key_from_seed(17i64), to_tensor([0f32, 0f32, 0f32, 0f32, 0f32]), 100f32, 100f32, 0f32, 1f32, 1f32, 1i64)
  replay = lsm_one_step_replay(17i64, 5i64, 100f32, 100f32, 0f32, 1e20f32, 1e-40f32)
  assert_true(and(lt(abs(sub(extreme, ordinary)), 0.001f32), lt(abs(sub(extreme, replay)), 1e-6f32)), "finite effective variance survives an overflowing f32 volatility square and matches independent replay")
}
def test_lsm_multidate_extreme_replay() -> unit ! { Test } = {
  checks = map(fn (steps: i64) -> {
    expected = lsm_two_path_replay(17i64, 100f32, 100f32, 0f32, 1e20f32, 1e-40f32, steps)
    price = lsm_american_put(key_from_seed(17i64), to_tensor([0f32, 0f32]), 100f32, 100f32, 0f32, 1e20f32, 1e-40f32, steps)
    lt(abs(sub(price, expected)), 0.0001f32)
  }, [3i64, 4i64])
  assert_true(fold(fn (ok: bool, check: bool) -> and(ok, check), true, checks), "tiny-horizon three- and four-date simulations agree with independent Brownian replay")
}
def test_lsm_subnormal_time_step_replay() -> unit ! { Test } = {
  expected = lsm_two_path_replay(17i64, 100f32, 100f32, 0f32, 1e20f32, 1e-45f32, 2i64)
  price = lsm_american_put(key_from_seed(17i64), to_tensor([0f32, 0f32]), 100f32, 100f32, 0f32, 1e20f32, 1e-45f32, 2i64)
  assert_true(and(gt(expected, 0.001f32), lt(abs(sub(price, expected)), 0.00001f32)), "a positive horizon whose half rounds to zero in f32 still produces the replayed diffusion")
}
def test_lsm_finite_log_underflow_and_expiry() -> unit ! { Test } = {
  underflow = lsm_american_put(key_from_seed(17i64), to_tensor([0f32]), 100f32, 100f32, 0f32, 3e38f32, 1f32, 2i64)
  expiry = lsm_american_put(key_from_seed(17i64), to_tensor([0f32]), 80f32, 100f32, 3e38f32, 3e38f32, 0f32, 2i64)
  assert_true(and(eq(underflow, 100f32), eq(expiry, 20f32)), "finite negative log paths may round to zero spots; expiry remains intrinsic without simulation")
}
def test_lsm_largest_spot_rounding() -> unit ! { Test } = {
  price = lsm_american_put(key_from_seed(17i64), to_tensor([0f32]), 3.4028235e38f32, 3.4028235e38f32, 0f32, 0f32, 1f32, 1i64)
  assert_true(eq(price, 0f32), "exp(log(maximum f32 spot)) may round back to maximum f32 without a false range refusal")
}
-- Exact rational LS reference: solve the three normal equations over Q for
-- x=[90,95,100,105,110], y=[4,6,8,11,15]. This noisy case also tests the
-- least-squares projection, not only interpolation of an exact polynomial.
def test_lsm_noisy_fit_rational_reference() -> unit ! { Test } = {
  b = lsm_polynomial_regression(to_tensor([90f32, 95f32, 100f32, 105f32, 110f32]), to_tensor([4f32, 6f32, 8f32, 11f32, 15f32]))
  expected0 = cast(div(3393f64, 35f64), f32)
  expected1 = cast(div(-811f64, 350f64), f32)
  expected2 = cast(div(1f64, 70f64), f32)
  assert_true(and(lt(abs(sub(b.0, expected0)), 0.00001f32), and(lt(abs(sub(b.1, expected1)), 1e-6f32), lt(abs(sub(b.2, expected2)), 1e-8f32))), "noisy spot-scale least-squares fit agrees with exact rational reference (3393/35, -811/350, 1/70)")
}
