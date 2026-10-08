module Shoals.Properties.Pde
import Shoals.Pde (pde_spread_option_adi)
import Shoals.PricingExtended (pe_margrabe_stulz)
def spread_property_abs(x: f32) -> f32 = if lt(x, 0.0f32) then neg(x) else x
def spread_property_price(s: f32, rho: f32) -> f32 = {
  n_x = if gt(rho, 0.5f32) then 31i64 else 21i64
  pde_spread_option_adi(s, s, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.2f32, 0.2f32, rho, 1.0f32, n_x, n_x, 20i64)
}
-- Bounded fixed-budget claims for shoals#153, not universal PDE accuracy or
-- SMT proofs of the time-stepping loop. The small grid is intentional: the
-- larger mesh/time/domain convergence claims live in executable heavy tests.
-- Exchange uses 31x31 for rho>0.5 and 21x21 otherwise, each with 20 steps.
-- The exchange tolerance is 0.4% of spot on these meshes, distinct
-- from the strict fine-grid reference tolerances in the heavy suite.
-- Fuzz sampling runs 25 accepted samples at seeds 0,1,2; every declaration
-- has a corrupted numerical twin to reject a vacuous always-green oracle.
@property spread_expiry_matches_intrinsic forall(s: f32) where s >= 1.0, s <= 9.0:
  (pde_spread_option_adi(s, 1.0f32, 0.5f32, 0.05f32, 0.02f32, 0.01f32, 0.2f32, 0.3f32, 0.5f32, 0.0f32, 3i64, 3i64, 1i64) == (if (s > 1.5) then (s - 1.5) else 0.0))
@property spread_expiry_matches_intrinsic_corrupted forall(s: f32) where s >= 1.0, s <= 9.0:
  ((pde_spread_option_adi(s, 1.0f32, 0.5f32, 0.05f32, 0.02f32, 0.01f32, 0.2f32, 0.3f32, 0.5f32, 0.0f32, 3i64, 3i64, 1i64) + 1.0) == (if (s > 1.5) then (s - 1.5) else 0.0))
@property spread_exchange_matches_margrabe forall(s: f32, rho: f32) where s >= 1.0, s <= 9.0, rho >= -0.8, rho <= 0.8:
  (spread_property_abs((spread_property_price(s, rho) - pe_margrabe_stulz(s, s, 0.2f32, 0.2f32, rho, 0.0f32, 0.0f32, 1.0f32))) < (0.004 * s))
@property spread_exchange_matches_margrabe_corrupted forall(s: f32, rho: f32) where s >= 1.0, s <= 9.0, rho >= -0.8, rho <= 0.8:
  (spread_property_abs(((spread_property_price(s, rho) + s) - pe_margrabe_stulz(s, s, 0.2f32, 0.2f32, rho, 0.0f32, 0.0f32, 1.0f32))) < (0.004 * s))
@property spread_bounded_input_price_bounds forall(s: f32, rho: f32) where s >= 1.0, s <= 9.0, rho >= -0.8, rho <= 0.8:
  {
    px = spread_property_price(s, rho)
    and((px >= 0.0), (px <= s))
  }
@property spread_bounded_input_price_bounds_corrupted forall(s: f32, rho: f32) where s >= 1.0, s <= 9.0, rho >= -0.8, rho <= 0.8:
  {
    px = (spread_property_price(s, rho) + (2.0 * s))
    and((px >= 0.0), (px <= s))
  }
