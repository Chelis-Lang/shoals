module Shoals.Properties.HestonLewis
import Shoals.Heston (heston_call_lewis_panels, heston_put_lewis_panels, heston_call_carr_madan_panels)
-- shoals#151: bounded numerical properties, not a global Heston proof.
-- The reported model is fixed; strike [80,120] and rate [-0.03,0.08]
-- vary independently. U=200, 100 ten-point panels; tolerance covers f32
-- evaluation and finite quadrature. Corrupted twins must find witnesses.
def lewis_call(k: f32, r: f32) -> f32 = heston_call_lewis_panels(100.0, k, 1.0, r, 0.04, 1.5, 0.04, 0.5, -0.7, 200.0, 100i64)
def lewis_put(k: f32, r: f32) -> f32 = heston_put_lewis_panels(100.0, k, 1.0, r, 0.04, 1.5, 0.04, 0.5, -0.7, 200.0, 100i64)
def carr_madan_call(k: f32, r: f32) -> f32 = heston_call_carr_madan_panels(100.0, k, 1.0, r, 0.04, 1.5, 0.04, 0.5, -0.7, 1.5, 200.0, 100i64)
@property heston_lewis_carr_madan_agreement forall(k: f32, r: f32) where k >= 80.0, k <= 120.0, r >= -0.03, r <= 0.08:
  (abs(sub(lewis_call(k, r), carr_madan_call(k, r))) < 0.001)
@property heston_lewis_carr_madan_agreement_corrupted forall(k: f32, r: f32) where k >= 80.0, k <= 120.0, r >= -0.03, r <= 0.08:
  (abs(sub(lewis_call(k, r), carr_madan_call(k, r))) >= 0.5)
@property heston_lewis_put_call_parity forall(k: f32, r: f32) where k >= 80.0, k <= 120.0, r >= -0.03, r <= 0.08:
  (abs(sub(sub(lewis_call(k, r), lewis_put(k, r)), sub(100.0, mul(k, exp(neg(r)))))) < 0.0001)
@property heston_lewis_put_call_parity_corrupted forall(k: f32, r: f32) where k >= 80.0, k <= 120.0, r >= -0.03, r <= 0.08:
  (abs(sub(sub(lewis_call(k, r), lewis_put(k, r)), add(sub(100.0, mul(k, exp(neg(r)))), 1.0))) < 0.0001)
@property heston_lewis_call_decreases_in_strike forall(k: f32, r: f32) where k >= 80.0, k <= 119.0, r >= -0.03, r <= 0.08:
  (lewis_call(add(k, 1.0), r) <= lewis_call(k, r))
@property heston_lewis_call_decreases_in_strike_corrupted forall(k: f32, r: f32) where k >= 80.0, k <= 119.0, r >= -0.03, r <= 0.08:
  (lewis_call(add(k, 1.0), r) >= add(lewis_call(k, r), 0.01))
