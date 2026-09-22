module Shoals.Properties.CanonGeneral
import Shoals.Trees (tr_binom_european_call_generic)
import Shoals.FixedIncome (fi_bond_general)
-- General-size promotion stubs: the same canonical invariants that are PROVEN at
-- fixed size (2-step CRR, 2-period bond) restated on the fold-based general-size
-- bodies. These are the claims a desk needs: a property proven for ANY number of
-- steps, not just at a fixed small depth. At chelis 0.14.0 these are DEFERRED:
-- the fold-based bodies require induction/fixed-point reasoning over the lattice
-- traversal (CRR) or the cashflow summation (bond), which Tier B cannot express
-- (it inlines calls, not fold iterations), and Tier C is intractable for n > ~3
-- (the CRR terminal vector is exponential in n, and each sample evaluates the
-- full fold). Each references the real output fn directly (anti-vacuity), ships a
-- corrupted twin, and a guards_satisfiable witness. No tier is claimed.
-- ===========================================================================
-- (1) GENERAL CRR NON-NEGATIVITY: an n-step CRR European call is non-negative
-- under no-arbitrage guards (p in (0,1), disc > 0). Same claim as
-- crr_rn_call_nonneg but at general depth.
@property crr_general_nonneg forall(s: f32, k: f32, log_u: f32, log_d: f32, p: f32, disc: f32) where s > 0.0, k > 0.0, p > 0.0, p < 1.0, disc > 0.0, disc <= 1.0, log_u > 0.0, log_d < 0.0:
  (tr_binom_european_call_generic(s, k, log_u, log_d, p, disc, cast(5, i64)) >= 0.0)
@property crr_general_nonneg_corrupted forall(s: f32, k: f32, log_u: f32, log_d: f32, p: f32, disc: f32) where s > 0.0, k > 0.0, p > 0.0, p < 1.0, disc > 0.0, disc <= 1.0, log_u > 0.0, log_d < 0.0:
  (tr_binom_european_call_generic(s, k, log_u, log_d, p, disc, cast(5, i64)) >= 0.05)
@property crr_general_nonneg_guards_satisfiable forall(s: f32, k: f32, log_u: f32, log_d: f32, p: f32, disc: f32) where s > 0.0, k > 0.0, p > 0.0, p < 1.0, disc > 0.0, disc <= 1.0, log_u > 0.0, log_d < 0.0:
  false
-- ===========================================================================
-- (2) GENERAL CRR MONOTONE IN SPOT (delta sign): an n-step CRR call is
-- non-decreasing in spot. Same claim as crr_call_monotone_in_s but at general n.
@property crr_general_monotone_in_s forall(s1: f32, s2: f32, k: f32, log_u: f32, log_d: f32, p: f32, disc: f32) where s1 > 0.0, s2 > s1, k > 0.0, p > 0.0, p < 1.0, disc > 0.0, disc <= 1.0, log_u > 0.0, log_d < 0.0:
  (tr_binom_european_call_generic(s2, k, log_u, log_d, p, disc, cast(5, i64)) >= tr_binom_european_call_generic(s1, k, log_u, log_d, p, disc, cast(5, i64)))
@property crr_general_monotone_in_s_corrupted forall(s1: f32, s2: f32, k: f32, log_u: f32, log_d: f32, p: f32, disc: f32) where s1 > 0.0, s2 > s1, k > 0.0, p > 0.0, p < 1.0, disc > 0.0, disc <= 1.0, log_u > 0.0, log_d < 0.0:
  (tr_binom_european_call_generic(s2, k, log_u, log_d, p, disc, cast(5, i64)) <= tr_binom_european_call_generic(s1, k, log_u, log_d, p, disc, cast(5, i64)))
@property crr_general_mono_guards_satisfiable forall(s1: f32, s2: f32, k: f32, log_u: f32, log_d: f32, p: f32, disc: f32) where s1 > 0.0, s2 > s1, k > 0.0, p > 0.0, p < 1.0, disc > 0.0, disc <= 1.0, log_u > 0.0, log_d < 0.0:
  false
-- ===========================================================================
-- (3) GENERAL BOND PRICE-YIELD MONOTONICITY (duration sign): the n-period bond
-- price is strictly decreasing in yield. Same claim as fi_bond_pv_monotone_in_yield
-- but for any n. Uses fi_bond_general with n=5 (a 5-period bond).
@property fi_bond_general_monotone_in_yield forall(c: f32, y1: f32, y2: f32) where c > 0.0, y1 >= 0.0, y2 > y1:
  (fi_bond_general(c, y2, cast(5, i64)) < fi_bond_general(c, y1, cast(5, i64)))
@property fi_bond_general_monotone_in_yield_corrupted forall(c: f32, y1: f32, y2: f32) where c > 0.0, y1 >= 0.0, y2 > y1:
  (fi_bond_general(c, y2, cast(5, i64)) >= fi_bond_general(c, y1, cast(5, i64)))
@property fi_bond_general_mono_guards_satisfiable forall(c: f32, y1: f32, y2: f32) where c > 0.0, y1 >= 0.0, y2 > y1:
  false
-- ===========================================================================
-- (4) GENERAL BOND PV BOUNDED: the n-period bond PV is positive and bounded by
-- the undiscounted nominal sum (n*c + 1, since there are n-1 coupon payments of
-- c plus one final of (1+c), totaling n*c + 1 -- wait, more precisely:
-- (n-1)*c + (1+c) = n*c + 1... no: n-1 coupons of c PLUS one final cashflow of
-- (1+c) = (n-1)*c + 1 + c = n*c + 1. Yes.) At n=5: nominal = 5*c + 1.
-- Guard: c > 0, y >= 0. Corrupted: PV >= nominal (impossible when y > 0).
@property fi_bond_general_pv_bounded forall(c: f32, y: f32) where c > 0.0, y >= 0.0:
  and(gt(fi_bond_general(c, y, cast(5, i64)), 0.0), lte(fi_bond_general(c, y, cast(5, i64)), ((5.0 * c) + 1.0)))
@property fi_bond_general_pv_bounded_corrupted forall(c: f32, y: f32) where c > 0.0, y >= 0.0:
  and(gt(fi_bond_general(c, y, cast(5, i64)), 0.0), gte(fi_bond_general(c, y, cast(5, i64)), ((5.0 * c) + 1.0)))
@property fi_bond_general_pv_guards_satisfiable forall(c: f32, y: f32) where c > 0.0, y >= 0.0:
  false
