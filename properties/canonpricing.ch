module Shoals.Properties.CanonPricing
import Shoals.Pricing (bs_call_scalar)
import Shoals.PricingExtended (black_call)
-- Canon fuzz-validated lane: direct-call invariants against the REAL
-- transcendental pricers. The certified-envelope discharge (chelis#434,
-- CLOSED at 0.16.0) abstracts each `log`/`exp`/`sqrt`/`erf` subterm to an
-- independent envelope-bounded variable, but these goals depend on the
-- COUPLING between `N(d1)`/`N(d2)` abstractions of the same quantity, which
-- free-variable abstraction discards (chelis#637) -- so `--tier auto` still
-- degrades HONESTLY to fuzz, never a false proven. At Chelis 0.17.4 the fuzz
-- lane is observed and gated as fuzz_validated for both direct-call positivity
-- properties and their corrupted twins. The upgrade to a proven tier remains
-- blocked by chelis#637 (coupled-subterm / relational abstraction).
-- Dischargeability lane p08 (real bs_call positivity).
--
-- Guard authoring (p11 fuzz-box rule): the prover samples a fixed [-10,10]^n box
-- with rejection, so every guard region must intersect the box with usable
-- acceptance density (~>=1%). Positivity holds for ALL positive inputs, so the
-- guards are the widest sound domain (each half-open positivity guard covers
-- ~50% of the box axis) rather than the narrow realistic finance ranges that
-- starve the sampler. The sweep_defaults in docs/cnote-import-surface.json carry
-- the realistic magnitudes for the UI; these guards carry only the domain facts
-- the invariant needs.
--
-- Each invariant references its output fn directly (anti-vacuity: bs_call_scalar
-- / black_call appear in the dependency edge). Each ships a corrupted twin that
-- must fail with an in-domain fuzz counterexample.
-- bs_call_price_nonneg: a Black-Scholes call present value is non-negative
-- (no-arbitrage) across the positive input domain.
@property bs_call_price_nonneg forall(s: f32, k: f32, r: f32, sigma: f32, t: f32) where (s > 0.0), (k > 0.0), (sigma > 0.0), (t > 0.0), (r >= 0.0):
  (bs_call_scalar(s, k, r, sigma, t) >= 0.0)
-- Corrupted twin: claims a positive price floor the deep-out-of-the-money
-- region violates (a false lower bound: most in-domain calls are worth well
-- under 5, and every out-of-the-money call is worth ~0), so fuzz finds an
-- in-domain counterexample within the first sample or two -- the violating
-- control refutes cheaply even at a small fuzz budget.
@property bs_call_price_nonneg_corrupted forall(s: f32, k: f32, r: f32, sigma: f32, t: f32) where (s > 0.0), (k > 0.0), (sigma > 0.0), (t > 0.0), (r >= 0.0):
  (bs_call_scalar(s, k, r, sigma, t) >= 5.0)
-- Kind-reuse demonstration: the same european-call-forward positivity invariant
-- instantiated against a SECOND model, the Black-76 forward call. Same invariant
-- id family, different output fn (manifest kind_applies_to).
@property b76_call_price_nonneg forall(f: f32, k: f32, sigma: f32, t: f32, df: f32) where (f > 0.0), (k > 0.0), (sigma > 0.0), (t > 0.0), (df > 0.0):
  (black_call(f, k, sigma, t, df) >= 0.0)
@property b76_call_price_nonneg_corrupted forall(f: f32, k: f32, sigma: f32, t: f32, df: f32) where (f > 0.0), (k > 0.0), (sigma > 0.0), (t > 0.0), (df > 0.0):
  (black_call(f, k, sigma, t, df) >= 5.0)
-- Direct Black-Scholes Greek-sign family. These compare the real
-- transcendental bs_call_scalar body at two or three input points. They do not
-- differentiate a surrogate and they are not the structural normal-CDF
-- composites in properties/composites.ch. At Chelis 0.17.4 they are observed
-- only at fuzz_validated; chelis#637 remains the trigger for a global proof.
-- To keep the rejection-sampled box dense at this compiler pin (shoals#38),
-- delta/vega/gamma use the desk baseline r=5%, while rho uses t=1y. Their
-- comparison axes and every other displayed nuisance input remain sampled.
--
-- Spot monotonicity is the finite-comparison form of non-negative call delta.
-- The corrupted twin asserts a strict decrease with a material margin.
@property bs_call_monotone_in_s forall(s: f32, ds: f32, k: f32, sigma: f32, t: f32) where (s > 0.0), (ds > 0.0), (k > 0.0), (sigma > 0.0), (t > 0.0):
  (bs_call_scalar((s + ds), k, 0.05, sigma, t) >= bs_call_scalar(s, k, 0.05, sigma, t))
@property bs_call_monotone_in_s_corrupted forall(s: f32, ds: f32, k: f32, sigma: f32, t: f32) where (s > 0.0), (ds > 0.0), (k > 0.0), (sigma > 0.0), (t > 0.0):
  (bs_call_scalar((s + ds), k, 0.05, sigma, t) <= (bs_call_scalar(s, k, 0.05, sigma, t) - 0.01))
-- Vega sign: increasing volatility does not decrease a European call price.
@property bs_call_vega_sign forall(s: f32, k: f32, sigma: f32, dsigma: f32, t: f32) where (s > 0.0), (k > 0.0), (sigma > 0.0), (dsigma > 0.0), (t > 0.0):
  (bs_call_scalar(s, k, 0.05, (sigma + dsigma), t) >= bs_call_scalar(s, k, 0.05, sigma, t))
@property bs_call_vega_sign_corrupted forall(s: f32, k: f32, sigma: f32, dsigma: f32, t: f32) where (s > 0.0), (k > 0.0), (sigma > 0.0), (dsigma > 0.0), (t > 0.0):
  (bs_call_scalar(s, k, 0.05, (sigma + dsigma), t) <= (bs_call_scalar(s, k, 0.05, sigma, t) - 0.01))
-- Call rho sign: at t=1y, increasing a non-negative risk-free rate does not
-- decrease the non-dividend-paying European call price.
@property bs_call_rho_sign forall(s: f32, k: f32, r: f32, dr: f32, sigma: f32) where (s > 0.0), (k > 0.0), (r >= 0.0), (dr > 0.0), (sigma > 0.0):
  (bs_call_scalar(s, k, (r + dr), sigma, 1.0) >= bs_call_scalar(s, k, r, sigma, 1.0))
@property bs_call_rho_sign_corrupted forall(s: f32, k: f32, r: f32, dr: f32, sigma: f32) where (s > 0.0), (k > 0.0), (r >= 0.0), (dr > 0.0), (sigma > 0.0):
  (bs_call_scalar(s, k, (r + dr), sigma, 1.0) <= (bs_call_scalar(s, k, r, sigma, 1.0) - 0.01))
-- Gamma sign: a centered spot butterfly is non-negative. The -1e-5 floor is
-- an explicit f32 output-rounding allowance; it is not a proof tolerance. The
-- corrupted twin requires material concavity and must produce a witness.
@property bs_call_gamma_sign forall(s: f32, h: f32, k: f32, sigma: f32, t: f32) where (s > 0.0), (h > 0.0), (k > 0.0), (sigma > 0.0), (t > 0.0):
  (((bs_call_scalar((s + (2.0 * h)), k, 0.05, sigma, t) + bs_call_scalar(s, k, 0.05, sigma, t)) - (2.0 * bs_call_scalar((s + h), k, 0.05, sigma, t))) >= (0.0 - 0.00001))
@property bs_call_gamma_sign_corrupted forall(s: f32, h: f32, k: f32, sigma: f32, t: f32) where (s > 0.0), (h > 0.0), (k > 0.0), (sigma > 0.0), (t > 0.0):
  (((bs_call_scalar((s + (2.0 * h)), k, 0.05, sigma, t) + bs_call_scalar(s, k, 0.05, sigma, t)) - (2.0 * bs_call_scalar((s + h), k, 0.05, sigma, t))) <= (0.0 - 0.01))
