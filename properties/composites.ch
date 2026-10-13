module Shoals.Properties.Composites
import Std.Contracts (normal_cdf)
-- Structural derivatives properties using `chelis prove --tier smt-only`.
--
-- These goals concern the Black-Scholes algebra under separately discharged
-- normal-CDF contracts; they do not prove the direct pricing export. The
-- prover abstracts each syntactic call to
-- `Std.Contracts.normal_cdf` into a fresh symbol carrying the declared
-- assumptions. The upper-bound and delta-range goals use the certified
-- `0<=N<=1` envelope and an SMT structural proof over the reals; their result
-- is `proven_modulo_certified_envelope` / `sound_approximate` in the C Note
-- manifest. The reflection/parity candidate remains deferred under
-- chelis#3116; its contract is sampled, not a certified range proof.
--
-- `Std.Contracts.normal_cdf` delegates to Chelis's `standard_normal_cdf` at
-- its input precision. The scalar pricer (`Shoals.Pricing.bs_call_scalar`)
-- evaluates that function in f64 before downcasting. The binding is measured
-- agreement within a stated f32 bound, not identity of the evaluated graph.
-- Their price-level gap
-- scales with spot, so no fixed figure bounds it over free parameters.
-- That binding is the S7 cross-check (`tests/composites_binding.ch`), not a
-- value-level proof of the direct pricer or its f32 execution.
--
-- Abstracted bodies (exactly the Shoals.Pricing structure, transcendentals
-- lifted to the abstracted normal_cdf calls):
--   C = s*N(d1) - k*disc*N(d2)
--   P = k*disc*N(-d2) - s*N(-d1)
-- Free f32 params; d1, d2 stand for the (log/sqrt-bearing) moneyness arguments
-- and disc = exp(-r t). Preconditions encode only the SOUND domain facts that do
-- not require the discarded moneyness coupling: s,k >= 0 and disc in [0,1].
-- ===========================================================================
-- COMPOSITE CANDIDATES AND CERTIFIED BOUNDS
-- ===========================================================================
-- C1 -- Put-call parity C - P = S - K*disc, resting on the reflection contract.
-- Parity is NOT a free algebraic identity under abstraction: it needs
-- N(-x) = 1 - N(x), which the reflection contract supplies. The body must call
-- normal_cdf(d1)/normal_cdf(neg(d1)) and normal_cdf(d2)/normal_cdf(neg(d2)) so
-- the prover can pair the negated-argument calls. This candidate is deferred
-- under chelis#3116 and carries no active manifest proof claim.
@property put_call_parity_reflection forall(s: f32, k: f32, d1: f32, d2: f32, disc: f32) where s >= 0.0, k >= 0.0, disc >= 0.0, disc <= 1.0:
  ((((s * normal_cdf(d1)) - (k * (disc * normal_cdf(d2)))) - ((k * (disc * normal_cdf(neg(d2)))) - (s * normal_cdf(neg(d1))))) == (s - (k * disc)))
  with contract = "std.normal_cdf.reflection"
-- C2 -- Upper bound C <= S. From ranges alone: s,k,disc,N(d2) >= 0 and
-- N(d1) <= 1, so s*N(d1) - k*disc*N(d2) <= s. Rests on the range contract.
-- The range assumption discharges through a certified envelope at this pin.
-- Expect: composite_verdict = proven_modulo_certified_envelope.
@property call_upper_bounded_by_spot forall(s: f32, k: f32, d1: f32, d2: f32, disc: f32) where s >= 0.0, k >= 0.0, disc >= 0.0, disc <= 1.0:
  (((s * normal_cdf(d1)) - (k * (disc * normal_cdf(d2)))) <= s)
  with contract = "std.normal_cdf.range"
-- C3 -- Delta bounds: the call delta N(d1) lies in [0,1] (its sign and bound,
-- the structural Greek fact paired with the AD-derived delta value). Directly
-- the range contract on a single normal_cdf call.
-- The range assumption discharges through a certified envelope at this pin.
-- Expect: composite_verdict = proven_modulo_certified_envelope.
@property delta_in_unit_interval forall(d1: f32):
  ((normal_cdf(d1) >= 0.0) && (normal_cdf(d1) <= 1.0))
  with contract = "std.normal_cdf.range"
-- ===========================================================================
-- EDGE / INTEGRITY probes -- these must NOT pass. They show the verdict depends
-- on the REAL contract, not on the syntax.
-- ===========================================================================
-- E1 -- Corrupted coupling: parity with an UNSOUND reflection. The body asserts
-- the parity identity but uses normal_cdf(neg(d1)) on the spot leg while pairing
-- it against a DOUBLED-spot structural goal (C - P claimed to equal s - k*disc
-- with the put leg's spot term scaled by 2). The structural goal no longer
-- follows from the sound reflection contract, so cvc5 returns a counterexample.
-- Expect: status = failed (the verdict FLIPS away from proven).
@property put_call_parity_corrupted forall(s: f32, k: f32, d1: f32, d2: f32, disc: f32) where s >= 0.0, k >= 0.0, disc >= 0.0, disc <= 1.0:
  ((((s * normal_cdf(d1)) - (k * (disc * normal_cdf(d2)))) - ((k * (disc * normal_cdf(neg(d2)))) - ((2.0 * s) * normal_cdf(neg(d1))))) == (s - (k * disc)))
  with contract = "std.normal_cdf.reflection"
-- E2 -- Unknown contract id. The body calls the real normal_cdf but cites a
-- contract the prover does not know, so it cannot bind the assumptions.
-- Expect: status = unsupported, reason naming the unknown contract.
@property delta_unknown_contract forall(d1: f32):
  ((normal_cdf(d1) >= 0.0) && (normal_cdf(d1) <= 1.0))
  with contract = "std.normal_cdf.not_a_contract"
-- E3 -- Corrupted upper bound: claims the call is bounded by HALF the spot,
-- which the range contract refutes (N(d1) can reach 1 with the strike leg near
-- 0, so the call approaches s > 0.5*s). Expect: status = failed.
@property call_upper_bounded_by_spot_corrupted forall(s: f32, k: f32, d1: f32, d2: f32, disc: f32) where s >= 0.0, k >= 0.0, disc >= 0.0, disc <= 1.0:
  (((s * normal_cdf(d1)) - (k * (disc * normal_cdf(d2)))) <= (0.5 * s))
  with contract = "std.normal_cdf.range"
-- E4 -- Corrupted delta bound: claims the call delta N(d1) never exceeds 0.5,
-- which the range contract refutes (N(d1) reaches 1). Expect: status = failed.
@property delta_in_unit_interval_corrupted forall(d1: f32):
  ((normal_cdf(d1) >= 0.0) && (normal_cdf(d1) <= 0.5))
  with contract = "std.normal_cdf.range"
