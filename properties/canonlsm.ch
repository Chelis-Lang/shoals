module Shoals.Properties.CanonLsm
import Shoals.Lsm (lsm_polynomial_regression, lsm_american_put, lsm_put_payoff)
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
