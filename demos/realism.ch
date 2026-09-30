module Shoals.Demos.Realism
import Std.Test (assert_close)
import Shoals.Trees (tr_crr_european_call)
import Shoals.Pricing (bs_call_scalar, mc_call_price)
import Shoals.FixedIncome (fi_bond_general)
-- Model realism demos: practitioner-scale pricers that exercise the canon's
-- model universe at sizes and parameters a desk recognizes. These are runnable
-- characterization tests, NOT proof-tier claims. They demonstrate that the
-- verified models (whose invariants are proven at small fixed size) produce
-- correct prices at realistic scale, converging to known closed-form references.
-- Run: chelis test demos/realism.ch --timeout 120
-- ===========================================================================
-- (1) 200-STEP CRR LATTICE: price a 1Y ATM European call on a 200-step CRR
-- tree with standard market parameters (S=100, K=100, r=5%, div=0%, σ=20%,
-- T=1Y). At 200 steps the CRR lattice converges to the Black-Scholes price to
-- within 0.5%. This is the realistic lattice depth a desk uses for vanilla
-- pricing and early-exercise decisions.
def test_crr_200step_converges_to_bs() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  q = cast(0.0, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  n = cast(200, i64)
  crr_px = tr_crr_european_call(s0, k, r, q, sigma, t, n)
  bs_px = bs_call_scalar(s0, k, r, sigma, t)
  diff = sub(crr_px, bs_px)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  rel = div(abs_diff, bs_px)
  ok = lt(rel, cast(0.005, f32))
  assert_close(if ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "200-step CRR converges to BS within 0.5% (S=100 K=100 r=5% sigma=20% T=1Y)")
}
-- ===========================================================================
-- (2) 60-PERIOD (30Y SEMIANNUAL) COUPON BOND: PV a 30-year semiannual 5%
-- coupon bond at 4% yield (per period = 2% semiannual). This is a standard
-- rates desk instrument. The analytic PV is c/y * (1 - 1/(1+y)^n) + 1/(1+y)^n
-- where c = 2.5% (semiannual coupon on a 5% annual rate), y = 2% (semiannual
-- yield on a 4% annual), n = 60 periods. Expected PV ≈ 1.1725 (bond trades
-- above par because coupon > yield).
-- Analytic formula: PV = (c/y)*(1 - v^n) + v^n where v = 1/(1+y)
def test_bond_60period_semiannual() -> unit ! { Test } = {
  c_semi = cast(0.025, f32)
  y_semi = cast(0.02, f32)
  n = cast(60, i64)
  pv = fi_bond_general(c_semi, y_semi, n)
  v = div(cast(1.0, f32), add(cast(1.0, f32), y_semi))
  v_n = exp(mul(cast(60.0, f32), log(v)))
  analytic = add(mul(div(c_semi, y_semi), sub(cast(1.0, f32), v_n)), v_n)
  diff = sub(pv, analytic)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  rel = div(abs_diff, analytic)
  ok = lt(rel, cast(0.01, f32))
  assert_close(if ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "60-period bond PV within 1% of analytic (30Y semiannual, c=5% y=4%)")
}
-- ===========================================================================
-- (3) 10,000-PATH MONTE CARLO: price a 1Y ATM European call with 10,000 GBM
-- paths. At 10K paths the MC estimate converges to the BS price within 2%.
-- This is the path count a desk uses for quick intraday checks (full overnight
-- risk runs use 100K+, which is deferred to manual-gates/).
def test_mc_10k_converges_to_bs() -> unit ! { Test } = {
  s0 = cast(100.0, f32)
  k = cast(100.0, f32)
  r = cast(0.05, f32)
  sigma = cast(0.2, f32)
  t = cast(1.0, f32)
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(10000, i64))))
  mc_px = mc_call_price(key_from_seed(42i64), template, s0, k, r, sigma, t)
  bs_px = bs_call_scalar(s0, k, r, sigma, t)
  diff = sub(mc_px, bs_px)
  abs_diff = if lt(diff, cast(0.0, f32)) then neg(diff) else diff
  rel = div(abs_diff, bs_px)
  ok = lt(rel, cast(0.02, f32))
  assert_close(if ok then cast(1.0, f32) else cast(0.0, f32), cast(1.0, f32), cast(0.001, f32), "10K-path MC converges to BS within 2% (S=100 K=100 r=5% sigma=20% T=1Y)")
}
