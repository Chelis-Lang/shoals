-- Metamorphic forge fixture (POSITIVE control for the sum-based substitution
-- strengthening). A LEGIT convexity green: the butterfly second difference
-- `g(k-h) + g(k+h) - 2 g(k) >= 0` holds for a convex body g(k) = k*k (equals
-- 2 h^2) but FLIPS to disproved under the concave `neg_sq_sum` substitution. The
-- affine trio (identity / negated / constant) CANNOT flip a butterfly -- the
-- second difference of any affine body is identically zero -- so without the
-- sum-based substitutions this genuine convexity green would read as vacuous.
-- The metamorphic check must let this SURVIVE (proves the strengthened gate does
-- not reject genuine convexity greens: the model-free canon's butterfly / bond
-- convexity invariants).
module Metamorphic.ForgeLegitConvex
def gm(k: f32, h: f32) -> f32 = (k * k)
@property forge_legit_convex forall(k: f32, h: f32) where h > 0.0:
  (((gm((k - h), h) + gm((k + h), h)) - (2.0 * gm(k, h))) >= 0.0)
