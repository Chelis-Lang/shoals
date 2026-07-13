module Shoals.Properties.CanonTrees
import Shoals.Trees (tr_crr_call_2step, tr_crr_call_2step_nodisc, tr_crr_call_2step_rn)
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
-- ===========================================================================
-- MODEL-FREE EUROPEAN-CALL CANON (kind finance.option_pricer.european_call).
-- Anchored on the risk-neutral tr_crr_call_2step_rn (disc derived from the
-- martingale condition, so no-arbitrage-consistent by construction). Unlike the
-- structural composites lane (which abstracts normal_cdf and is unbindable to a
-- user pricer), each of these references the output fn DIRECTLY, so the C Note
-- engine instantiates them against ANY european-call pricer's output fn via the
-- manifest goal_pattern. All discharge unqualified at Tier B
-- (proven_modulo_real_arithmetic) over the reals; on the transcendental
-- Black-Scholes flagship the same invariants are deferred (chelis#637). Each
-- ships a corrupted twin that cvc5 must refute with an in-domain witness and a
-- `_guards_satisfiable` non-vacuity witness that cvc5 refutes with a
-- guard-satisfying model.
-- (1) NON-NEGATIVITY: a call price is never negative (each relu payoff and each
-- binomial weight is non-negative, disc^2 > 0).
@property crr_rn_call_nonneg forall(s: f32, k: f32, u: f32, d: f32, q: f32) where (s > 0.0), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  (tr_crr_call_2step_rn(s, k, u, d, q) >= 0.0)
@property crr_rn_call_nonneg_corrupted forall(s: f32, k: f32, u: f32, d: f32, q: f32) where (s > 0.0), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  (tr_crr_call_2step_rn(s, k, u, d, q) >= 0.05)
@property crr_rn_price_guards_satisfiable forall(s: f32, k: f32, u: f32, d: f32, q: f32) where (s > 0.0), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  false
-- (2) NO-ARBITRAGE UPPER BOUND: a call is never worth more than the underlying
-- spot. Holds ONLY under the martingale condition (disc * expected gross return
-- = 1), which tr_crr_call_2step_rn enforces by construction; the free-parameter
-- tr_crr_call_2step VIOLATES this (see the nodisc arbitrage twin above). The
-- corrupted twin claims the too-tight bound C <= s - 0.1, refuted by a low-strike
-- (near-the-spot) call.
@property crr_rn_call_upper_bounded_by_spot forall(s: f32, k: f32, u: f32, d: f32, q: f32) where (s > 0.0), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  (tr_crr_call_2step_rn(s, k, u, d, q) <= s)
@property crr_rn_call_upper_bounded_by_spot_corrupted forall(s: f32, k: f32, u: f32, d: f32, q: f32) where (s > 0.0), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  (tr_crr_call_2step_rn(s, k, u, d, q) <= (s - 0.1))
-- (3) INTRINSIC / FORWARD LOWER BOUND: a call is worth at least its discounted
-- intrinsic value s - k*disc^2 (and >= 0, covered by (1)). disc^2 = 1/g^2 with
-- g = q*u + (1-q)*d. This is the exemplar of the genuine-vs-deferred split: the
-- identical bound is DEFERRED on Black-Scholes (needs the N(d1)/N(d2) coupling
-- that value-level abstraction discards, chelis#637) yet PROVES here over the
-- reals. Corrupted twin drops the strike term (claims C >= s), refuted by an
-- out-of-the-money call worth ~0.
@property crr_rn_call_intrinsic_lower_bound forall(s: f32, k: f32, u: f32, d: f32, q: f32) where (s > 0.0), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  (tr_crr_call_2step_rn(s, k, u, d, q) >= (s - (k * ((1.0 / ((q * u) + ((1.0 - q) * d))) * (1.0 / ((q * u) + ((1.0 - q) * d)))))))
@property crr_rn_call_intrinsic_lower_bound_corrupted forall(s: f32, k: f32, u: f32, d: f32, q: f32) where (s > 0.0), (k > 0.0), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  (tr_crr_call_2step_rn(s, k, u, d, q) >= s)
-- (4) BULL SPREAD / MONOTONE-DECREASING IN STRIKE: a call with a lower strike is
-- worth at least as much as one with a higher strike (a bull call spread has
-- non-negative value). Re-anchors the noarbitrage.ch bull_spread form on the CRR
-- pricer so it proves (it calls the transcendental bs_call_scalar there and falls
-- to fuzz). Corrupted twin claims increasing-in-strike.
@property crr_rn_call_bull_spread_nonneg forall(s: f32, klo: f32, khi: f32, u: f32, d: f32, q: f32) where (s > 0.0), (klo > 0.0), (khi > klo), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  (tr_crr_call_2step_rn(s, klo, u, d, q) >= tr_crr_call_2step_rn(s, khi, u, d, q))
@property crr_rn_call_bull_spread_nonneg_corrupted forall(s: f32, klo: f32, khi: f32, u: f32, d: f32, q: f32) where (s > 0.0), (klo > 0.0), (khi > klo), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  (tr_crr_call_2step_rn(s, klo, u, d, q) <= tr_crr_call_2step_rn(s, khi, u, d, q))
@property crr_rn_bull_guards_satisfiable forall(s: f32, klo: f32, khi: f32, u: f32, d: f32, q: f32) where (s > 0.0), (klo > 0.0), (khi > klo), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  false
-- (5) BUTTERFLY / CONVEXITY IN STRIKE: the call price is convex in strike (a
-- long butterfly on equally-spaced strikes k-h, k, k+h has non-negative value).
-- Re-anchors the noarbitrage.ch butterfly form on the CRR pricer. Corrupted twin
-- claims strict concavity (<= -0.01).
@property crr_rn_call_butterfly_convex forall(s: f32, k: f32, h: f32, u: f32, d: f32, q: f32) where (s > 0.0), (h > 0.0), (k > h), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  (((tr_crr_call_2step_rn(s, (k - h), u, d, q) + tr_crr_call_2step_rn(s, (k + h), u, d, q)) - (2.0 * tr_crr_call_2step_rn(s, k, u, d, q))) >= 0.0)
@property crr_rn_call_butterfly_convex_corrupted forall(s: f32, k: f32, h: f32, u: f32, d: f32, q: f32) where (s > 0.0), (h > 0.0), (k > h), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  (((tr_crr_call_2step_rn(s, (k - h), u, d, q) + tr_crr_call_2step_rn(s, (k + h), u, d, q)) - (2.0 * tr_crr_call_2step_rn(s, k, u, d, q))) <= (0.0 - 0.01))
@property crr_rn_butterfly_guards_satisfiable forall(s: f32, k: f32, h: f32, u: f32, d: f32, q: f32) where (s > 0.0), (h > 0.0), (k > h), (u > 1.0), (d > 0.0), (d < 1.0), (q > 0.0), (q < 1.0):
  false
