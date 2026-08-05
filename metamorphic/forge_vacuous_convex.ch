-- Metamorphic forge fixture (NEGATIVE control for the sum-based substitution
-- strengthening -- the adversarial partner of forge_legit_convex). A VACUOUS
-- convexity green: it has the butterfly SHAPE and names the model fn `fv` three
-- times, but every evaluation is at the SAME point (k, h), so the second
-- difference is fv + fv - 2*fv = 0 for ANY body -- its truth (0 >= 0) is
-- INDEPENDENT of the model. A check that merely recognized "a butterfly on fv"
-- would wrongly accept it; the metamorphic check must REJECT it -- no
-- substitution, including the new concave `neg_sq_sum`, flips 0 >= 0. This is the
-- proof that the strengthened substitution set did not open a convexity-shaped
-- vacuity hole: sum-based substitutions catch GENUINE convexity
-- (forge_legit_convex) while still rejecting a guard-restatement / canceling one.
module Metamorphic.ForgeVacuousConvex
def fv(k: f32, h: f32) -> f32 = (k * k)
@property forge_vacuous_convex forall(k: f32, h: f32) where h > 0.0:
  (((fv(k, h) + fv(k, h)) - (2.0 * fv(k, h))) >= 0.0)
