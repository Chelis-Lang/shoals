module Shoals.Properties.CanonTrees
import Shoals.Trees (tr_crr_call_2step, tr_crr_call_2step_nodisc)
-- Canon proven-over-reals lane: the 2-step CRR European call is pure arithmetic
-- + ITE (no transcendentals), so its pricing structure lowers to cvc5 and these
-- goals discharge unqualified at Tier B (proven_modulo_real_arithmetic).
-- Dischargeability probe p14 (both goals recorded `passed/smt` at 0.14.0). Each
-- invariant references the real output fn tr_crr_call_2step (anti-vacuity: the
-- dependency edge names the pricer, never a guard restatement), ships a
-- corrupted twin that must refute with a counterexample, and a
-- `_guards_satisfiable` non-vacuity witness that cvc5 refutes with a
-- guard-satisfying model. Guards keep the goal-site call chain within the
-- depth-3 SMT inlining cap (p07): goal -> tr_crr_call_2step -> relu is depth 2.
-- crr_call_nonneg: a 2-step CRR call price is non-negative under the model
-- guards (u>1>d>0 no-arbitrage move factors, q and disc in the unit ranges).
@property crr_call_nonneg forall(s: f32, k: f32, u: f32, d: f32, q: f32, disc: f32) where (s > 0.0), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0), (disc > 0.0), (disc <= 1.0):
  (tr_crr_call_2step(s, k, u, d, q, disc) >= 0.0)
-- Corrupted twin: claims a strictly-positive floor the price does not meet at
-- the all-out-of-the-money corner (every relu payoff zero => price 0 < 0.05),
-- so cvc5 must refute with an in-domain counterexample.
@property crr_call_nonneg_corrupted forall(s: f32, k: f32, u: f32, d: f32, q: f32, disc: f32) where (s > 0.0), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0), (disc > 0.0), (disc <= 1.0):
  (tr_crr_call_2step(s, k, u, d, q, disc) >= 0.05)
-- Non-vacuity: the guard set is satisfiable (cvc5 exhibits a model), so the
-- proven green above is not vacuously true over an empty precondition set.
@property crr_call_nonneg_guards_satisfiable forall(s: f32, k: f32, u: f32, d: f32, q: f32, disc: f32) where (s > 0.0), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0), (disc > 0.0), (disc <= 1.0):
  false
-- crr_call_monotone_in_s: the call price is non-decreasing in spot (two calls of
-- the real pricer at s2 > s1; sound at Tier B post-chelis#426, verified by p04).
@property crr_call_monotone_in_s forall(s1: f32, s2: f32, k: f32, u: f32, d: f32, q: f32, disc: f32) where (s1 > 0.0), (s2 > s1), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0), (disc > 0.0), (disc <= 1.0):
  (tr_crr_call_2step(s2, k, u, d, q, disc) >= tr_crr_call_2step(s1, k, u, d, q, disc))
-- Corrupted twin: claims monotone DECREASING in spot, which the pricer violates.
@property crr_call_monotone_in_s_corrupted forall(s1: f32, s2: f32, k: f32, u: f32, d: f32, q: f32, disc: f32) where (s1 > 0.0), (s2 > s1), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0), (disc > 0.0), (disc <= 1.0):
  (tr_crr_call_2step(s2, k, u, d, q, disc) <= tr_crr_call_2step(s1, k, u, d, q, disc))
@property crr_call_monotone_in_s_guards_satisfiable forall(s1: f32, s2: f32, k: f32, u: f32, d: f32, q: f32, disc: f32) where (s1 > 0.0), (s2 > s1), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0), (disc > 0.0), (disc <= 1.0):
  false
-- DEFECTIVE MODEL (manifest defective: true). tr_crr_call_2step_nodisc drops the
-- discount factor, so it violates the no-arbitrage upper bound C <= s inside the
-- valid input region. This goal ASSERTS the bound; cvc5 REFUTES it with a
-- concrete in-domain counterexample (the arbitrage witness). Expected verdict:
-- disproved_modulo_real_arithmetic. The witness re-executes at f32 (polynomial,
-- no transcendental) => in_region_defect. violation: admits arbitrage (prices
-- the call above the underlying spot at these inputs).
@property crr_nodisc_call_upper_bound forall(s: f32, k: f32, u: f32, d: f32, q: f32) where (s > 0.0), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  (tr_crr_call_2step_nodisc(s, k, u, d, q) <= s)
