module Shoals.FixedIncome
export (fi_df2, fi_bond2, fi_bond2_nodisc)
-- Discrete-compounding fixed-income canon anchors: closed-form, fixed 2-period
-- schedule, priced in the yield variable y (per-period yield). Pure arithmetic +
-- division (no transcendentals, no fold/induction), so the pricing structure
-- lowers to cvc5 -- the genuine proven-over-reals rates lane (dischargeability
-- lane p14; properties in Shoals.Properties.CanonFixedIncome). The schedule is
-- held at n = 2: the three-point convexity second difference over reciprocal
-- powers 1/(1+y)^i is tractable at n <= 2 and goes unsupported at n >= 3 at this
-- pin, so a 2-period bond is the largest schedule that proves d2P/dy2 > 0 in the
-- faithful yield form (rather than reparameterizing to the discount factor, which
-- is a different statement). General-schedule discounting needs a fold over the
-- cashflow list (no induction tier at 0.14.0) and is held out -- do NOT build the
-- rates canon via curves.ch tensor-fold/interp, which falls to fuzz.
-- 2-period discount factor at per-period yield y: 1 / (1 + y)^2. In (0, 1] for
-- y >= 0. Denominator 1 + y >= 1 > 0 under the guard, so the reciprocal is well
-- defined.
def fi_df2(y: f32) -> f32 = {
  v = (1.0 / (1.0 + y))
  (v * v)
}
-- Present value of a 2-period unit-face coupon bond: coupon c at t = 1, coupon c
-- plus face 1 at t = 2, discounted at per-period yield y. P = c/(1+y) + (1+c)/(1+y)^2.
def fi_bond2(c: f32, y: f32) -> f32 = {
  v = (1.0 / (1.0 + y))
  ((c * v) + ((1.0 + c) * (v * v)))
}
-- DEFECTIVE reference bond (manifest defective: true): the same 2-period cashflows
-- summed with NO discounting -- it returns the nominal sum c + (1 + c) and ignores
-- the yield entirely, a real and common rates bug (forgetting the time value of
-- money). It conforms to the coupon_bond kind but VIOLATES strict price-yield
-- monotonicity inside the valid region: its price does not fall as yield rises, so
-- its rate sensitivity (DV01 / duration) is understated to zero. The break is
-- constant-valued (no division), so cvc5 refutes dP/dy < 0 with an in-domain
-- witness that re-executes at f32 (in_region_defect). Rates analogue of
-- Shoals.Trees.tr_crr_call_2step_nodisc.
def fi_bond2_nodisc(c: f32, y: f32) -> f32 = (c + (1.0 + c))
