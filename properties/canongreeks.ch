module Shoals.Properties.CanonGreeks
import Shoals.Trees (tr_crr_call_2step)
-- Canon proven-over-reals Greek-sign lane: sign invariants of the first- and
-- second-order sensitivities of the 2-step CRR European call. Each is a
-- two-point relational comparison or a three-point second difference on the
-- same pure-arithmetic body as canontrees.ch. The target fn tr_crr_call_2step
-- is depth-1 from the goal site (relu is depth-2), within the depth-3 inlining
-- cap. All discharge unqualified at Tier B (proven_modulo_real_arithmetic).
-- Dischargeability probe p14. Each ships a corrupted twin and a
-- `_guards_satisfiable` non-vacuity witness.
-- ===========================================================================
-- (1) VEGA SIGN (monotone-nondecreasing in u): a call price is non-decreasing
-- in the up-move factor u, holding spot, strike, down-move, probability, and
-- discount fixed. Economically: higher u (wider upside) increases every terminal
-- node at which the option is in the money (uu node: s*u^2, ud node: s*u*d),
-- while the dd node is unaffected. Since all binomial weights are strictly
-- positive and relu is non-decreasing, the weighted discounted expected payoff
-- is non-decreasing in u. This is the lattice analog of vega >= 0: wider
-- volatility (larger u) increases call value. Corrupted twin: claims monotone
-- DECREASING in u, refuted by an in-the-money call where u2 > u1.
@property crr_call_vega_sign forall(s: f32, k: f32, u1: f32, u2: f32, d: f32, q: f32, disc: f32) where s > 0.0, k > 0.0, u1 > 1.0, u2 > u1, d > 0.0, d < 1.0, q > 0.0, q < 1.0, disc > 0.0, disc <= 1.0:
  (tr_crr_call_2step(s, k, u2, d, q, disc) >= tr_crr_call_2step(s, k, u1, d, q, disc))
@property crr_call_vega_sign_corrupted forall(s: f32, k: f32, u1: f32, u2: f32, d: f32, q: f32, disc: f32) where s > 0.0, k > 0.0, u1 > 1.0, u2 > u1, d > 0.0, d < 1.0, q > 0.0, q < 1.0, disc > 0.0, disc <= 1.0:
  (tr_crr_call_2step(s, k, u2, d, q, disc) <= tr_crr_call_2step(s, k, u1, d, q, disc))
@property crr_call_vega_guards_satisfiable forall(s: f32, k: f32, u1: f32, u2: f32, d: f32, q: f32, disc: f32) where s > 0.0, k > 0.0, u1 > 1.0, u2 > u1, d > 0.0, d < 1.0, q > 0.0, q < 1.0, disc > 0.0, disc <= 1.0:
  false
-- ===========================================================================
-- (2) DISC SENSITIVITY / RHO ANALOG (monotone-nondecreasing in disc): on the
-- free-parameter CRR the call price C = disc^2 * (nonneg weighted payoff sum).
-- Since the weighted payoff sum is non-negative (product of non-negative
-- weights and relu payoffs) and disc^2 is non-decreasing in disc for disc > 0,
-- C is non-decreasing in disc. Financially, disc = exp(-r*dt) so higher disc
-- means lower rate, and ∂C/∂disc >= 0 is equivalent to ∂C/∂r <= 0 on this
-- formulation. (On the real BS model, rho > 0 for a call because higher r
-- increases the forward; here disc is a free parameter decoupled from the
-- payoff's dependence on spot growth, so the sign is reversed vs the standard
-- rho. The invariant is stated honestly as monotone-in-disc, not "rho > 0".)
-- Corrupted twin: claims monotone DECREASING in disc (more discounting =>
-- higher price), refuted by any in-the-money call.
@property crr_call_disc_sensitivity forall(s: f32, k: f32, u: f32, d: f32, q: f32, disc1: f32, disc2: f32) where s > 0.0, k > 0.0, u > 1.0, d > 0.0, d < 1.0, q > 0.0, q < 1.0, disc1 > 0.0, disc2 > disc1, disc2 <= 1.0:
  (tr_crr_call_2step(s, k, u, d, q, disc2) >= tr_crr_call_2step(s, k, u, d, q, disc1))
@property crr_call_disc_sensitivity_corrupted forall(s: f32, k: f32, u: f32, d: f32, q: f32, disc1: f32, disc2: f32) where s > 0.0, k > 0.0, u > 1.0, d > 0.0, d < 1.0, q > 0.0, q < 1.0, disc1 > 0.0, disc2 > disc1, disc2 <= 1.0:
  (tr_crr_call_2step(s, k, u, d, q, disc2) <= tr_crr_call_2step(s, k, u, d, q, disc1))
@property crr_call_disc_guards_satisfiable forall(s: f32, k: f32, u: f32, d: f32, q: f32, disc1: f32, disc2: f32) where s > 0.0, k > 0.0, u > 1.0, d > 0.0, d < 1.0, q > 0.0, q < 1.0, disc1 > 0.0, disc2 > disc1, disc2 <= 1.0:
  false
-- ===========================================================================
-- (3) GAMMA SIGN (convexity in spot): the call price is convex in spot (a long
-- butterfly in spot-space has non-negative value). Three-point second
-- difference: C(s+h) + C(s-h) - 2*C(s) >= 0. Economically: the terminal
-- payoffs relu(S_T - K) are convex in S_0 (since S_T is linear in S_0 on the
-- CRR lattice: S_T = S_0 * u^j * d^(n-j), and relu of a linear fn is convex),
-- and a positively-weighted sum of convex functions is convex. This is the
-- lattice analog of gamma >= 0. Corrupted twin: claims strict concavity
-- (second difference <= -0.01). Guard: s > h > 0 ensures s-h > 0.
@property crr_call_gamma_sign forall(s: f32, k: f32, h: f32, u: f32, d: f32, q: f32, disc: f32) where s > 0.0, h > 0.0, s > h, k > 0.0, u > 1.0, d > 0.0, d < 1.0, q > 0.0, q < 1.0, disc > 0.0, disc <= 1.0:
  (((tr_crr_call_2step((s + h), k, u, d, q, disc) + tr_crr_call_2step((s - h), k, u, d, q, disc)) - (2.0 * tr_crr_call_2step(s, k, u, d, q, disc))) >= 0.0)
@property crr_call_gamma_sign_corrupted forall(s: f32, k: f32, h: f32, u: f32, d: f32, q: f32, disc: f32) where s > 0.0, h > 0.0, s > h, k > 0.0, u > 1.0, d > 0.0, d < 1.0, q > 0.0, q < 1.0, disc > 0.0, disc <= 1.0:
  (((tr_crr_call_2step((s + h), k, u, d, q, disc) + tr_crr_call_2step((s - h), k, u, d, q, disc)) - (2.0 * tr_crr_call_2step(s, k, u, d, q, disc))) <= (0.0 - 0.01))
@property crr_call_gamma_guards_satisfiable forall(s: f32, k: f32, h: f32, u: f32, d: f32, q: f32, disc: f32) where s > 0.0, h > 0.0, s > h, k > 0.0, u > 1.0, d > 0.0, d < 1.0, q > 0.0, q < 1.0, disc > 0.0, disc <= 1.0:
  false
