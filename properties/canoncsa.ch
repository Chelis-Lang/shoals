module Shoals.Properties.CanonCsa
import Shoals.Csa (csa_collateralized_exposure)
-- The CSA's nonnegative threshold, minimum transfer and independent amount
-- leave residual exposure between zero and uncollateralized positive exposure.
-- Haircuts in [0, 1] reduce collateral received and cannot reduce residual.
-- The SMT claims use exact real arithmetic on the imported f32 function body.
@property csa_residual_nonnegative forall(e: f32, th: f32, mta: f32, ia: f32, h: f32) where th >= 0.0, mta >= 0.0, ia >= 0.0, h >= 0.0, h <= 1.0:
  (csa_collateralized_exposure(e, th, mta, ia, h) >= 0.0)
@property csa_residual_not_above_exposure forall(e: f32, th: f32, mta: f32, ia: f32, h: f32) where e >= 0.0, th >= 0.0, mta >= 0.0, ia >= 0.0, h >= 0.0, h <= 1.0:
  (csa_collateralized_exposure(e, th, mta, ia, h) <= e)
@property csa_negative_exposure_zero forall(e: f32, th: f32, mta: f32, ia: f32, h: f32) where e <= 0.0, th >= 0.0, mta >= 0.0, ia >= 0.0, h >= 0.0, h <= 1.0:
  (csa_collateralized_exposure(e, th, mta, ia, h) == 0.0)
@property csa_residual_bounded_corrupted forall(e: f32, th: f32, mta: f32, ia: f32, h: f32) where th >= 0.0, mta >= 0.0, ia >= 0.0, h >= 0.0, h <= 1.0:
  (csa_collateralized_exposure(e, th, mta, ia, h) <= th)
@property csa_bounded_guards_satisfiable forall(e: f32, th: f32, mta: f32, ia: f32, h: f32) where th >= 0.0, mta >= 0.0, ia >= 0.0, h >= 0.0, h <= 1.0:
  false
@property csa_haircut_monotone forall(e: f32, th: f32, mta: f32, ia: f32, h1: f32, h2: f32) where th >= 0.0, mta >= 0.0, ia >= 0.0, h1 >= 0.0, h2 <= 1.0, h1 <= h2:
  (csa_collateralized_exposure(e, th, mta, ia, h1) <= csa_collateralized_exposure(e, th, mta, ia, h2))
@property csa_haircut_monotone_corrupted forall(e: f32, th: f32, mta: f32, ia: f32, h1: f32, h2: f32) where th >= 0.0, mta >= 0.0, ia >= 0.0, h1 >= 0.0, h2 <= 1.0, h1 < h2:
  (csa_collateralized_exposure(e, th, mta, ia, h1) >= csa_collateralized_exposure(e, th, mta, ia, h2))
@property csa_haircut_guards_satisfiable forall(e: f32, th: f32, mta: f32, ia: f32, h1: f32, h2: f32) where th >= 0.0, mta >= 0.0, ia >= 0.0, h1 >= 0.0, h2 <= 1.0, h1 <= h2:
  false
