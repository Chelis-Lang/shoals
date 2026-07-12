-- Metamorphic forge fixture. A REFLEXIVE green: `fr(x) == fr(x)` is true for
-- ANY body, so its truth is independent of the model. The metamorphic check
-- must REJECT it -- no substitution flips the outcome.
module Metamorphic.ForgeReflexive
def fr(x: f32) -> f32 = ((x * x) * x)
@property forge_reflexive forall(x: f32) where (x > 0.0):
  (fr(x) == fr(x))
