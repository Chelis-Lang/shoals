module ProofInfraContract.Contract
import Nautilus.Special (erfc)
export (n_cdf)
-- The EXACT normal-CDF expression Shoals.Pricing uses (src/pricing.ch:5-8),
-- reproduced here because n_cdf is not exported. This is the real transcendental
-- whose contract the Track A greens assume. We validate that contract empirically.
def n_cdf(x: f32) -> f32 = {
  inv_sqrt_2 = cast(0.7071067811865475, f32)
  mul(cast(0.5, f32), erfc(neg(mul(x, inv_sqrt_2))))
}
-- Tier-C contract validation (composite green, second half). Binder x is
-- unconstrained f32 so the fuzz generator does not starve. N(x) in [0,1] holds for
-- ALL x, so no precondition is needed.
@property real_n_in_unit_interval forall(x: f32):
  ((n_cdf(x) >= 0.0) && (n_cdf(x) <= 1.0))
-- Reflection contract N(-x) = 1 - N(x), checked to an f32 tolerance.
@property real_n_reflection forall(x: f32):
  (((n_cdf(neg(x)) - (1.0 - n_cdf(x))) < 0.0001) && (((1.0 - n_cdf(x)) - n_cdf(neg(x))) < 0.0001))
-- Discount factor contract: disc = exp(-r t) in (0,1] for r,t >= 0. Validated on
-- the real exp. Binders r,t unconstrained-nonneg (generatable).
@property real_disc_in_unit_interval forall(r: f32, t: f32) where r >= 0.0, t >= 0.0:
  ((exp(neg(mul(r, t))) > 0.0) && (exp(neg(mul(r, t))) <= 1.0))
