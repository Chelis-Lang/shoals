module Shoals.Properties.CanonLsm
import Shoals.Lsm (lsm_polynomial_regression, lsm_american_put, lsm_put_payoff)
import Nautilus.Distributions (normal_sample)
-- shoals#152: these bounded numerical observations use fuzz-only sampling,
-- not SMT proof over reals. Corrupted twins ensure each assertion can fail.
def translated_fit(a: f32) -> (f32, f32, f32) = lsm_polynomial_regression(to_tensor([90f32, 95f32, 100f32, 105f32, 110f32]), to_tensor([add(101f32, a), add(26f32, a), add(1f32, a), add(26f32, a), add(101f32, a)]))
@property lsm_translated_quadratic_recovery forall(a: f32) where a > -5.0, a < 5.0:
  {
    b = translated_fit(a)
    and(lt(abs(sub(b.0, add(10001f32, a))), 0.002f32), and(lt(abs(add(b.1, 200f32)), 0.0001f32), lt(abs(sub(b.2, 1f32)), 1e-6f32)))
  }
@property lsm_translated_quadratic_recovery_corrupted forall(a: f32) where a > -5.0, a < 5.0:
  {
    b = translated_fit(a)
    lt(abs(add(b.2, 1f32)), 1e-6f32)
  }
def order_difference(a: f32) -> f32 = {
  p = lsm_polynomial_regression(to_tensor([90f32, 95f32, 100f32, 105f32, 110f32]), to_tensor([add(4f32, a), 6f32, sub(8f32, a), 11f32, add(15f32, a)]))
  q = lsm_polynomial_regression(to_tensor([110f32, 105f32, 100f32, 95f32, 90f32]), to_tensor([add(15f32, a), 11f32, sub(8f32, a), 6f32, add(4f32, a)]))
  add(abs(sub(p.0, q.0)), add(abs(sub(p.1, q.1)), abs(sub(p.2, q.2))))
}
@property lsm_observation_order_invariance forall(a: f32) where a > -5.0, a < 5.0:
  lt(order_difference(a), 0.0001f32)
@property lsm_observation_order_invariance_corrupted forall(a: f32) where a > -5.0, a < 5.0:
  gt(order_difference(a), 1f32)
def constant_fit(x: f32, y: f32) -> (f32, f32, f32) = lsm_polynomial_regression(to_tensor([x, x, x, x]), to_tensor([y, y, y, y]))
@property lsm_degenerate_constant_fit forall(x: f32, y: f32) where x > -10.0, x < 10.0, y > -10.0, y < 10.0:
  {
    b = constant_fit(x, y)
    and(eq(b.0, y), and(eq(b.1, 0f32), eq(b.2, 0f32)))
  }
@property lsm_degenerate_constant_fit_corrupted forall(x: f32, y: f32) where x > -10.0, x < 10.0, y > -10.0, y < 10.0:
  {
    b = constant_fit(x, y)
    gt(abs(b.2), 1f32)
  }
@property lsm_put_payoff_bounds forall(s: f32, k: f32) where s >= 0.0, k >= 0.0:
  {
    p = lsm_put_payoff(s, k)
    and(gte(p, 0f32), lte(p, k))
  }
@property lsm_put_payoff_bounds_corrupted forall(s: f32, k: f32) where s >= 0.0, k > 0.0:
  gt(lsm_put_payoff(s, k), k)
@property lsm_expiry_intrinsic forall(s: f32, k: f32) where s > 0.0, k > 0.0:
  eq(lsm_american_put(key_from_seed(17i64), to_tensor([0f32]), s, k, 0.05f32, 0.2f32, 0f32, 1i64), lsm_put_payoff(s, k))
@property lsm_expiry_intrinsic_corrupted forall(s: f32, k: f32) where s > 0.0, k > 0.0:
  eq(lsm_american_put(key_from_seed(17i64), to_tensor([0f32]), s, k, 0.05f32, 0.2f32, 0f32, 1i64), add(lsm_put_payoff(s, k), 1f32))
-- shoals#163: use the actual f32 inputs to define the effective variance.
-- Small keyed samples observe arithmetic equivalence, not MC accuracy.
def effective_variance_prices(a: f32) -> (f32, f32) = {
  sigma = mul(a, 1e20f32)
  variance = mul(mul(cast(sigma, f64), cast(sigma, f64)), cast(1e-40f32, f64))
  equivalent_sigma = cast(sqrt(variance), f32)
  extreme = lsm_american_put(key_from_seed(17i64), to_tensor([0f32, 0f32, 0f32, 0f32, 0f32]), 100f32, 100f32, 0f32, sigma, 1e-40f32, 1i64)
  ordinary = lsm_american_put(key_from_seed(17i64), to_tensor([0f32, 0f32, 0f32, 0f32, 0f32]), 100f32, 100f32, 0f32, equivalent_sigma, 1f32, 1i64)
  (extreme, ordinary)
}
@property lsm_effective_variance_equivalence forall(a: f32) where a > 0.5, a < 1.0:
  {
    prices = effective_variance_prices(a)
    lt(abs(sub(prices.0, prices.1)), 0.001f32)
  }
@property lsm_effective_variance_equivalence_corrupted forall(a: f32) where a > 0.5, a < 1.0:
  {
    prices = effective_variance_prices(a)
    gt(abs(sub(prices.0, prices.1)), 1f32)
  }
def extreme_replay_prices(s: f32) -> (f32, f32) = {
  zs = to_list(normal_sample(key_from_seed(21i64), to_tensor([0f32, 0f32, 0f32]), 0f32, 1f32))
  variance = mul(mul(cast(1e20f32, f64), cast(1e20f32, f64)), cast(1e-40f32, f64))
  terminal = map(fn (z: f32) -> cast(exp(add(log(cast(s, f64)), add(neg(mul(0.5f64, variance)), mul(sqrt(variance), cast(z, f64))))), f32), zs)
  continuation = div(fold(fn (acc: f64, spot: f32) -> add(acc, cast(lsm_put_payoff(spot, 100f32), f64)), 0f64, terminal), 3f64)
  intrinsic = cast(lsm_put_payoff(s, 100f32), f64)
  expected = cast(if gt(intrinsic, continuation) then intrinsic else continuation, f32)
  actual = lsm_american_put(key_from_seed(21i64), to_tensor([0f32, 0f32, 0f32]), s, 100f32, 0f32, 1e20f32, 1e-40f32, 1i64)
  (actual, expected)
}
@property lsm_extreme_one_step_replay forall(s: f32) where s > 90.0, s < 110.0:
  {
    prices = extreme_replay_prices(s)
    lt(abs(sub(prices.0, prices.1)), 0.0001f32)
  }
@property lsm_extreme_one_step_replay_corrupted forall(s: f32) where s > 90.0, s < 110.0:
  {
    prices = extreme_replay_prices(s)
    lt(abs(sub(prices.0, add(prices.1, 1f32))), 0.0001f32)
  }
