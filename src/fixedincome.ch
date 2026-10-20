module Shoals.FixedIncome
export (fi_df2, fi_bond2, fi_bond2_nodisc, fi_bond_general)
-- Fixed two-period, discrete-compounding formulas in the per-period yield y.
-- These arithmetic bodies avoid list folds and transcendentals, so their
-- guarded properties can be submitted directly to the SMT verifier.
-- fi_bond_general below discounts an explicit cashflow list; a property of
-- the two-period formulas does not establish a general-schedule theorem.
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
-- General n-period unit-face coupon bond: PV = sum_{i=1}^{n-1} c/(1+y)^i + (1+c)/(1+y)^n.
-- This is the fold-based generalization of fi_bond2: it computes the discounted sum of
-- n coupon cashflows plus the face repayment at maturity. At n=2 it should agree with
-- fi_bond2 (c/(1+y) + (1+c)/(1+y)^2). At general n it requires induction/fold over the
-- cashflow list to prove its canonical properties (monotonicity, convexity, bounded PV)
-- -- that capability does not exist at chelis 0.14.0.
-- v^i computed via exp(i * log(v)); for the canon this is equivalent to
-- repeated multiplication, but avoids a nested fold for the power.
def fi_bond_general(c: f32, y: f32, n: i64) -> f32 = {
  periods = range(cast(1, i64), add(n, cast(1, i64)))
  v = (1.0 / (1.0 + y))
  fold(fn (acc: f32, i: i64) -> {
    i_f = cast(i, f32)
    disc_i = exp(mul(i_f, log(v)))
    cf = if eq(i, n) then (1.0 + c) else c
    add(acc, mul(cf, disc_i))
  }, 0.0, periods)
}
