module Shoals.Properties.CanonAdGreeks
import Shoals.Pricing (bs_call_scalar, deltas_call, vegas_call, rhos_call, thetas_call, gammas_call, volgas_call, vannas_call)
def abs_f32(x: f32) -> f32 = if lt(x, cast(0.0, f32)) then neg(x) else x
-- Shoals#42: sampled, direct bindings between every exported Black-Scholes AD
-- Greek and the displayed bs_call_scalar price. These are runtime/fuzz
-- consistency claims, not proofs of the AD transform (the verified-AD/global
-- promotion remains explicitly deferred on shoals#42).
--
-- The single sampled input is deliberately dense in the prover's [-10,10]
-- box. All nuisance inputs are fixed at a representative one-year call so the
-- finite-difference steps and precision-derived tolerances remain meaningful.
-- Each satisfying goal directly names both the exported AD function and the
-- displayed price. Every corrupt twin adds a material bias to the actual AD
-- output and must refute with an in-domain witness.
@property bs_ad_delta_matches_displayed_price forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32((index(to_list(deltas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) - ((bs_call_scalar((s + 0.01), 5.0, 0.05, 0.2, 1.0) - bs_call_scalar((s - 0.01), 5.0, 0.05, 0.2, 1.0)) / 0.02))) < 0.002)
@property bs_ad_delta_matches_displayed_price_corrupted forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32(((index(to_list(deltas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) + 1.0) - ((bs_call_scalar((s + 0.01), 5.0, 0.05, 0.2, 1.0) - bs_call_scalar((s - 0.01), 5.0, 0.05, 0.2, 1.0)) / 0.02))) < 0.002)
@property bs_ad_vega_matches_displayed_price forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32((index(to_list(vegas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) - ((bs_call_scalar(s, 5.0, 0.05, 0.201, 1.0) - bs_call_scalar(s, 5.0, 0.05, 0.199, 1.0)) / 0.002))) < 0.005)
@property bs_ad_vega_matches_displayed_price_corrupted forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32(((index(to_list(vegas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) + 1.0) - ((bs_call_scalar(s, 5.0, 0.05, 0.201, 1.0) - bs_call_scalar(s, 5.0, 0.05, 0.199, 1.0)) / 0.002))) < 0.005)
@property bs_ad_rho_matches_displayed_price forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32((index(to_list(rhos_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) - ((bs_call_scalar(s, 5.0, 0.051, 0.2, 1.0) - bs_call_scalar(s, 5.0, 0.049, 0.2, 1.0)) / 0.002))) < 0.005)
@property bs_ad_rho_matches_displayed_price_corrupted forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32(((index(to_list(rhos_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) + 1.0) - ((bs_call_scalar(s, 5.0, 0.051, 0.2, 1.0) - bs_call_scalar(s, 5.0, 0.049, 0.2, 1.0)) / 0.002))) < 0.005)
@property bs_ad_theta_matches_displayed_price forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32((index(to_list(thetas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) + ((bs_call_scalar(s, 5.0, 0.05, 0.2, 1.001) - bs_call_scalar(s, 5.0, 0.05, 0.2, 0.999)) / 0.002))) < 0.005)
@property bs_ad_theta_matches_displayed_price_corrupted forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32(((index(to_list(thetas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) + 1.0) + ((bs_call_scalar(s, 5.0, 0.05, 0.2, 1.001) - bs_call_scalar(s, 5.0, 0.05, 0.2, 0.999)) / 0.002))) < 0.005)
@property bs_ad_gamma_matches_displayed_price forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32((index(to_list(gammas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) - (((bs_call_scalar((s + 0.1), 5.0, 0.05, 0.2, 1.0) - (2.0 * bs_call_scalar(s, 5.0, 0.05, 0.2, 1.0))) + bs_call_scalar((s - 0.1), 5.0, 0.05, 0.2, 1.0)) / 0.01))) < 0.002)
@property bs_ad_gamma_matches_displayed_price_corrupted forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32(((index(to_list(gammas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) + 1.0) - (((bs_call_scalar((s + 0.1), 5.0, 0.05, 0.2, 1.0) - (2.0 * bs_call_scalar(s, 5.0, 0.05, 0.2, 1.0))) + bs_call_scalar((s - 0.1), 5.0, 0.05, 0.2, 1.0)) / 0.01))) < 0.002)
@property bs_ad_volga_matches_displayed_price forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32((index(to_list(volgas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) - (((bs_call_scalar(s, 5.0, 0.05, 0.21, 1.0) - (2.0 * bs_call_scalar(s, 5.0, 0.05, 0.2, 1.0))) + bs_call_scalar(s, 5.0, 0.05, 0.19, 1.0)) / 0.0001))) < 0.5)
@property bs_ad_volga_matches_displayed_price_corrupted forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32(((index(to_list(volgas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) + 10.0) - (((bs_call_scalar(s, 5.0, 0.05, 0.21, 1.0) - (2.0 * bs_call_scalar(s, 5.0, 0.05, 0.2, 1.0))) + bs_call_scalar(s, 5.0, 0.05, 0.19, 1.0)) / 0.0001))) < 0.5)
@property bs_ad_vanna_matches_displayed_price forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32((index(to_list(vannas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) - ((((bs_call_scalar((s + 0.1), 5.0, 0.05, 0.21, 1.0) - bs_call_scalar((s + 0.1), 5.0, 0.05, 0.19, 1.0)) - bs_call_scalar((s - 0.1), 5.0, 0.05, 0.21, 1.0)) + bs_call_scalar((s - 0.1), 5.0, 0.05, 0.19, 1.0)) / 0.004))) < 0.05)
@property bs_ad_vanna_matches_displayed_price_corrupted forall(s: f32) where s > 1.0, s < 9.0:
  (abs_f32(((index(to_list(vannas_call(to_tensor([s]), 5.0, 0.05, 0.2, 1.0)), cast(0, int64)) + 1.0) - ((((bs_call_scalar((s + 0.1), 5.0, 0.05, 0.21, 1.0) - bs_call_scalar((s + 0.1), 5.0, 0.05, 0.19, 1.0)) - bs_call_scalar((s - 0.1), 5.0, 0.05, 0.21, 1.0)) + bs_call_scalar((s - 0.1), 5.0, 0.05, 0.19, 1.0)) / 0.004))) < 0.05)
