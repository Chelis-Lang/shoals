module Shoals.Properties.CountContracts
import Shoals.Pde (pde_spread_option_adi)
import Shoals.Heston (heston_call_carr_madan, heston_call_carr_madan_panels)
import Shoals.Cds (hazard_curve_from_pillars, cds_premium_leg_value)
-- shoals#166: bounded numerical identities and their false controls.
-- These assertions do not prove general PDE or Fourier pricing accuracy.
def expiry_unused_counts(s: f32) -> f32 = pde_spread_option_adi(s, 90f32, 5f32, 0.05f32, 0f32, 0f32, 0.2f32, 0.3f32, 0.3f32, 0f32, -1i64, 0i64, -2i64)
@property spread_expiry_unused_invalid_counts forall(s: f32) where s > 100.0, s < 110.0:
  eq(expiry_unused_counts(s), sub(sub(s, 90f32), 5f32))
@property spread_expiry_unused_invalid_counts_corrupted forall(s: f32) where s > 100.0, s < 110.0:
  eq(expiry_unused_counts(s), add(sub(sub(s, 90f32), 5f32), 1f32))
def single_panel_difference(k: f32) -> f32 = sub(heston_call_carr_madan_panels(100f32, k, 1f32, 0.05f32, 0.04f32, 2f32, 0.04f32, 0.3f32, -0.7f32, 1.5f32, 10f32, 1i64), heston_call_carr_madan(100f32, k, 1f32, 0.05f32, 0.04f32, 2f32, 0.04f32, 0.3f32, -0.7f32, 1.5f32, 10f32))
@property heston_one_panel_single_rule_equivalence forall(k: f32) where k > 95.0, k < 105.0:
  lt(abs(single_panel_difference(k)), 0.00001f32)
@property heston_one_panel_single_rule_equivalence_corrupted forall(k: f32) where k > 95.0, k < 105.0:
  lt(abs(add(single_panel_difference(k), 1f32)), 0.00001f32)
def annual_premium_difference(spread: f32) -> f32 = sub(cds_premium_leg_value(spread, 2f32, 1i64, hazard_curve_from_pillars(to_tensor([2f32]), to_tensor([0.02f32])), 0.03f32), mul(spread, add(exp(-0.05f32), exp(-0.1f32))))
@property cds_annual_premium_identity forall(spread: f32) where spread > 0.005, spread < 0.02:
  lt(abs(annual_premium_difference(spread)), 1e-7f32)
@property cds_annual_premium_identity_corrupted forall(spread: f32) where spread > 0.005, spread < 0.02:
  lt(abs(add(annual_premium_difference(spread), 1f32)), 1e-7f32)
