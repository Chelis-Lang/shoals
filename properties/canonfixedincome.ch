module Shoals.Properties.CanonFixedIncome
import Shoals.FixedIncome (fi_df2, fi_bond2, fi_bond2_nodisc)
-- Discrete-compounding fixed-income canon (kinds finance.fixed_income.*),
-- anchored on the closed-form 2-period bond fi_bond2 and its discount factor
-- fi_df2. Pure arithmetic + division (no transcendentals, no fold/induction), so
-- the bodies lower to cvc5 and these goals discharge unqualified at Tier B
-- (proven_modulo_real_arithmetic) over the reals. Each references its output fn
-- directly, so the C Note engine instantiates it against any bond pricer's output
-- fn via the manifest goal_pattern. Each ships a corrupted twin that cvc5 must
-- refute with an in-domain witness and a `_guards_satisfiable` non-vacuity
-- witness. Dischargeability lane p14.
-- (1) DISCOUNT FACTOR IN (0, 1]: multi-period discounting neither creates value
-- nor drives it negative for non-negative yields. Corrupted twin claims the
-- too-tight ceiling df <= 0.5, refuted near y = 0 where df -> 1.
@property fi_discount_factor_bounded forall(y: f32) where (y >= 0.0):
  and(lte(fi_df2(y), 1.0), gt(fi_df2(y), 0.0))
@property fi_discount_factor_bounded_corrupted forall(y: f32) where (y >= 0.0):
  and(lte(fi_df2(y), 0.5), gt(fi_df2(y), 0.0))
@property fi_discount_guards_satisfiable forall(y: f32) where (y >= 0.0):
  false
-- (2) PV BRACKETED BY (0, nominal]: the present value of a coupon bond with
-- positive coupons is positive and never exceeds the undiscounted sum of its
-- cashflows (c per period plus face 1 over 2 periods = 2c + 1). Corrupted twin
-- claims PV >= nominal, refuted at any positive yield where discounting bites.
@property fi_bond_pv_bounded forall(c: f32, y: f32) where (c > 0.0), (y >= 0.0):
  and(gt(fi_bond2(c, y), 0.0), lte(fi_bond2(c, y), ((c * 2.0) + 1.0)))
@property fi_bond_pv_bounded_corrupted forall(c: f32, y: f32) where (c > 0.0), (y >= 0.0):
  and(gt(fi_bond2(c, y), 0.0), gte(fi_bond2(c, y), ((c * 2.0) + 1.0)))
@property fi_bond_pv_guards_satisfiable forall(c: f32, y: f32) where (c > 0.0), (y >= 0.0):
  false
-- (3) PRICE-YIELD MONOTONICITY (dP/dy < 0, the DV01 / duration sign): the bond
-- price strictly falls as yield rises (two-point difference). Corrupted twin
-- claims price rises with yield.
@property fi_bond_pv_monotone_in_yield forall(c: f32, y1: f32, y2: f32) where (c > 0.0), (y1 >= 0.0), (y2 > y1):
  (fi_bond2(c, y2) < fi_bond2(c, y1))
@property fi_bond_pv_monotone_in_yield_corrupted forall(c: f32, y1: f32, y2: f32) where (c > 0.0), (y1 >= 0.0), (y2 > y1):
  (fi_bond2(c, y2) >= fi_bond2(c, y1))
@property fi_bond_mono_guards_satisfiable forall(c: f32, y1: f32, y2: f32) where (c > 0.0), (y1 >= 0.0), (y2 > y1):
  false
-- (4) CONVEXITY (d2P/dy2 > 0, positive bond convexity): the price is convex in
-- yield (a long butterfly on equally-spaced yields y-h, y, y+h has non-negative
-- value, three-point second difference). Corrupted twin claims concavity.
@property fi_bond_pv_convex_in_yield forall(c: f32, y: f32, h: f32) where (c > 0.0), (h > 0.0), (y >= h):
  (((fi_bond2(c, (y - h)) + fi_bond2(c, (y + h))) - (2.0 * fi_bond2(c, y))) >= 0.0)
@property fi_bond_pv_convex_in_yield_corrupted forall(c: f32, y: f32, h: f32) where (c > 0.0), (h > 0.0), (y >= h):
  (((fi_bond2(c, (y - h)) + fi_bond2(c, (y + h))) - (2.0 * fi_bond2(c, y))) <= (0.0 - 0.01))
@property fi_bond_convex_guards_satisfiable forall(c: f32, y: f32, h: f32) where (c > 0.0), (h > 0.0), (y >= h):
  false
-- DEFECTIVE MODEL (manifest defective: true). fi_bond2_nodisc drops discounting,
-- so its price is constant in yield and it VIOLATES strict price-yield
-- monotonicity inside the valid region: cvc5 REFUTES dP/dy < 0 with an in-domain
-- witness (two yields at which the price is equal). Expected verdict:
-- disproved_modulo_real_arithmetic. The witness re-executes at f32 (constant, no
-- division) => in_region_defect. violation: reports zero rate sensitivity (DV01
-- understated to zero, a bond that ignores the time value of money).
@property fi_bond_nodisc_monotone_defect forall(c: f32, y1: f32, y2: f32) where (c > 0.0), (y1 >= 0.0), (y2 > y1):
  (fi_bond2_nodisc(c, y2) < fi_bond2_nodisc(c, y1))
