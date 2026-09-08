module ProofInfraAd.Bs
-- Track B: a grad-able Black-Scholes body in PURE SCALAR ops (f64).
--
-- Design choices (each load-bearing for AD):
--  * All quantities are scalar `f64`. In the Chelis host evaluator a scalar
--    `f64` is a rank-0 tensor and `grad(f, wrt=x)` differentiates it directly
--    (verified: grad(fn x -> x*x)(3) = 6). No to_list/map/fold anywhere, so
--    the host-lane combinator blocker (Step 1) never appears.
--  * The normal CDF is the EXACT expression Shoals.Pricing / references use:
--        n_cdf(x) = 0.5 * erfc(-x/sqrt2)
--    with erfc = 1 - erf, and erf the Abramowitz-Stegun 7.1.26 rational
--    approximation -- byte-for-byte the same coefficients as
--    Nautilus.Special.erf (0.7.26 src/special.ch:15-37), reimplemented here
--    in f64 because the package symbol is f32-only and not re-exported through
--    the path the brief needs for self-contained grad. The `erf` value is thus
--    identical (up to f32->f64 widening of the literals) to what
--    `Nautilus.Special.erf` evaluates. It is NO LONGER what Shoals uses:
--    this shell's issue 61 moved `Shoals.Pricing.erf64` to Cody's
--    approximation, so the shipped kernel and this probe are now different
--    approximations. The isolation argument below is unaffected, because it
--    rests on this file and its oracle sharing one `n_cdf`, not on agreeing
--    with the package;
--    AD differentiates exactly this approximation, and the oracle below uses
--    the same `n_cdf`, so the AD-vs-oracle comparison isolates the chain rule,
--    not erf accuracy.
-- |x|, branch-free-ish via if (lowers to masked arithmetic: mask*then + (1-mask)*else)
def abs_f64(x: f64) -> f64 = if lt(x, cast(0.0, f64)) then neg(x) else x
-- erf via A&S 7.1.26 (same coefficients as Nautilus.Special.erf), f64 literals.
-- Small-|x| branch uses the 2/sqrt(pi) * x linearization, matching Nautilus.
def erf64(x: f64) -> f64 = {
  a1 = cast(0.254829592, f64)
  a2 = cast(-0.284496736, f64)
  a3 = cast(1.421413741, f64)
  a4 = cast(-1.453152027, f64)
  a5 = cast(1.061405429, f64)
  p = cast(0.3275911, f64)
  one = cast(1.0, f64)
  ax = abs_f64(x)
  small = cast(0.00001, f64)
  if lt(ax, small) then mul(x, cast(1.1283791670955126, f64)) else {
    t = div(one, add(one, mul(p, ax)))
    poly = mul(t, add(a1, mul(t, add(a2, mul(t, add(a3, mul(t, add(a4, mul(t, a5)))))))))
    e = exp(neg(mul(ax, ax)))
    y = sub(one, mul(poly, e))
    if lt(x, cast(0.0, f64)) then neg(y) else y
  }
}
def erfc64(x: f64) -> f64 = sub(cast(1.0, f64), erf64(x))
-- EXACT Shoals/references n_cdf expression: 0.5 * erfc(-x/sqrt2)
def n_cdf64(x: f64) -> f64 = {
  inv_sqrt_2 = cast(0.7071067811865476, f64)
  mul(cast(0.5, f64), erfc64(neg(mul(x, inv_sqrt_2))))
}
def d1_64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = {
  num = add(log(div(s, k)), mul(add(r, mul(cast(0.5, f64), mul(sigma, sigma))), t))
  den = mul(sigma, sqrt(t))
  div(num, den)
}
def d2_64(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = sub(d1_64(s, k, r, sigma, t), mul(sigma, sqrt(t)))
-- Black-Scholes call, pure scalar f64. Same algebra as Shoals.Pricing.bs_call_scalar.
def bs_call(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = {
  d1v = d1_64(s, k, r, sigma, t)
  d2v = d2_64(s, k, r, sigma, t)
  nd1 = n_cdf64(d1v)
  nd2 = n_cdf64(d2v)
  disc = exp(neg(mul(r, t)))
  sub(mul(s, nd1), mul(k, mul(disc, nd2)))
}
def bs_put(s: f64, k: f64, r: f64, sigma: f64, t: f64) -> f64 = {
  d1v = d1_64(s, k, r, sigma, t)
  d2v = d2_64(s, k, r, sigma, t)
  nnd1 = n_cdf64(neg(d1v))
  nnd2 = n_cdf64(neg(d2v))
  disc = exp(neg(mul(r, t)))
  sub(mul(k, mul(disc, nnd2)), mul(s, nnd1))
}
