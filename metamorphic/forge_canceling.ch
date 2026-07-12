-- Metamorphic forge fixture (NOT a package source; consumed by
-- scripts/prove_gate.py metamorphic_self_test). A CANCELING-call green: the
-- goal textually names the model fn `fc` but its truth (0 < 1) is INDEPENDENT
-- of fc's body. A syntactic "goal names the output fn" anti-vacuity check
-- passes it; the metamorphic check must REJECT it -- no body substitution
-- (identity / negated / constant) changes the outcome.
module Metamorphic.ForgeCanceling
def fc(x: f32) -> f32 = ((x * x) * x)
@property forge_canceling forall(x: f32) where (x > 0.0):
  ((fc(x) - fc(x)) < 1.0)
