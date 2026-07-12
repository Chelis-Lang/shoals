-- Metamorphic forge fixture (the POSITIVE control). A LEGIT model-dependent
-- green: `fm(x2) >= fm(x1)` under `x2 > x1` holds for an increasing body but
-- FLIPS to disproved under the negated-first-param substitution. The
-- metamorphic check must let this SURVIVE (proves no false-positive: the
-- hardened gate does not reject genuine F-dependent greens).
module Metamorphic.ForgeLegitMonotone
def fm(x: f32) -> f32 = (x + 1.0)
@property forge_legit_monotone forall(x1: f32, x2: f32) where (x2 > x1):
  (fm(x2) >= fm(x1))
