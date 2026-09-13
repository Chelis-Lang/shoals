module Shoals.TestsManual.CompositesBindingHeavy
import Std.Test (assert_true)
import Shoals.Pricing (bs_call_scalar)
import Std.Contracts (normal_cdf)
-- S7 binding cross-check -- FULL 405-cell grid sweep (nightly / manual).
--
-- The fast CI smoke (`tests/composites_binding.ch`) checks a handful of cells;
-- this file sweeps the whole 5*3*3*3*3 grid of (spot, strike, rate, sigma,
-- maturity) and asserts the worst-cell abs diff between the shipped f64-erf
-- pricer `bs_call_scalar` and a Black-Scholes price rebuilt from the certified
-- f32 `Std.Contracts.normal_cdf` stays under 1e-4. Worst cell 2.67e-5, measured
-- under the old A&S `erf64` and not re-measured since shoals#61; the grid still
-- passes. The two sides are NOT the same model any more -- `erf64` evaluates
-- Cody's approximation while the contract symbol is f32 A&S -- so the binding
-- that scopes the S8 composites to the shipped pricer is measured agreement,
-- not identity. The 1e-4 bound is what carries that scoping; the two
-- approximations are not interchangeable below it, differing by up to ~8.2e-6
-- at the money at price level.
--
-- It is in tests-manual/ because the host evaluator runs the grid through the
-- full Pricing module graph interpretively (~3 min), which overruns the fast
-- per-PR CI budget. The nightly matrix runs it by file.
def d1_f32(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  num = add(log(div(s, k)), mul(add(r, mul(cast(0.5, f32), mul(sigma, sigma))), t))
  div(num, mul(sigma, sqrt(t)))
}
def d2_f32(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = sub(d1_f32(s, k, r, sigma, t), mul(sigma, sqrt(t)))
def bs_call_contract(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  nd1 = normal_cdf(d1_f32(s, k, r, sigma, t))
  nd2 = normal_cdf(d2_f32(s, k, r, sigma, t))
  disc = exp(neg(mul(r, t)))
  sub(mul(s, nd1), mul(k, mul(disc, nd2)))
}
def abs_diff(s: f32, k: f32, r: f32, sigma: f32, t: f32) -> f32 = {
  shipped = bs_call_scalar(s, k, r, sigma, t)
  contract = bs_call_contract(s, k, r, sigma, t)
  d = sub(shipped, contract)
  if lt(d, cast(0.0, f32)) then neg(d) else d
}
-- NaN-aware max: a non-finite cell (d != d) is propagated into the accumulator so
-- any NaN reaches `worst` and fails the binding assertion. A plain gt-max drops
-- NaN (gt(NaN, acc) is false), which would let a NaN cell pass silently.
def maxcell(acc: f32, d: f32) -> f32 = if eq(d, d) then if gt(d, acc) then d else acc else d
def mats_max(s: f32, k: f32, r: f32, sg: f32, acc: f32) -> f32 = fold(fn (a: f32, t: f32) -> maxcell(a, abs_diff(s, k, r, sg, t)), acc, [cast(0.25, f32), cast(1.0, f32), cast(2.0, f32)])
def sigmas_max(s: f32, k: f32, r: f32, acc: f32) -> f32 = fold(fn (a: f32, sg: f32) -> mats_max(s, k, r, sg, a), acc, [cast(0.1, f32), cast(0.2, f32), cast(0.4, f32)])
def rates_max(s: f32, k: f32, acc: f32) -> f32 = fold(fn (a: f32, r: f32) -> sigmas_max(s, k, r, a), acc, [cast(0.01, f32), cast(0.05, f32), cast(0.1, f32)])
def strikes_max(s: f32, acc: f32) -> f32 = fold(fn (a: f32, k: f32) -> rates_max(s, k, a), acc, [cast(70.0, f32), cast(100.0, f32), cast(130.0, f32)])
def grid_max_abs_diff() -> f32 = fold(fn (a: f32, s: f32) -> strikes_max(s, a), cast(0.0, f32), [cast(60.0, f32), cast(80.0, f32), cast(100.0, f32), cast(120.0, f32), cast(140.0, f32)])
def test_binding_full_grid() -> unit ! { Test } = {
  worst = grid_max_abs_diff()
  assert_true(lt(worst, cast(0.0001, f32)), "405-cell grid: shipped bs_call_scalar agrees with Std.Contracts.normal_cdf BS within 1e-4")
}
