# Volatility surface

Module: `Shoals.VolSurface`.

This module parameterizes a volatility smile with the five-parameter SVI
total-variance form, converts total variance to implied volatility, applies
structured shifts to a surface, and solves for an implied volatility from a
call price by bisection over Black-Scholes.

## The SVI type

```chelis
type SVI =
  | SVI { a: f32, b: f32, rho: f32, m: f32, sigma: f32 }
```

The SVI parameters are `a` (the vertical level), `b` (the slope of the
wings), `rho` (the rotation, or skew), `m` (the horizontal translation),
and `sigma` (the smoothness of the curvature near the money). From
`tests/volsurface.ch`, a flat surface and a downward-skewed smile:

```chelis
def flat_svi() -> SVI = SVI { a: cast(0.04, f32), b: cast(0.0, f32), rho: cast(0.0, f32), m: cast(0.0, f32), sigma: cast(0.1, f32) }
def smile_svi() -> SVI = SVI { a: cast(0.04, f32), b: cast(0.2, f32), rho: cast(-0.3, f32), m: cast(0.0, f32), sigma: cast(0.1, f32) }
```

## Total variance and implied volatility

```chelis
def vs_total_variance(p: SVI, k: f32) -> f32
def vs_implied_vol(p: SVI, k: f32, t: f32) -> f32
```

`vs_total_variance` evaluates the SVI total variance `w(k)` at log-moneyness
`k`. `vs_implied_vol` converts total variance to an implied volatility by
`sqrt(max(w, 0) / t)`, clamping negative variance to zero.

From `tests/volsurface.ch`, a flat surface has total variance equal to `a`
at the money and constant across strikes, and its implied vol at one year
is `sqrt(a / t)`:

```chelis
p = flat_svi()
w = vs_total_variance(p, cast(0.0, f32))      // w == 0.04
iv = vs_implied_vol(p, cast(0.0, f32), cast(1.0, f32))  // iv == 0.2
```

A smile has higher total variance out of the money than at the money.

## Surface shifts

```chelis
def vs_shift_atm(p: SVI, delta_a: f32) -> SVI
def vs_shift_skew(p: SVI, delta_rho: f32) -> SVI
def smile_shift_skew_wing(p: SVI, delta_b: f32) -> SVI
def parallel_shift_atm_iv(p: SVI, delta_iv: f32, t: f32) -> SVI
```

`vs_shift_atm` adds `delta_a` to the level parameter, which adds the same
amount to total variance. `vs_shift_skew` adds to `rho`. `smile_shift_skew_wing`
adds to `b`. `parallel_shift_atm_iv` is the structured shift that lifts the
at-the-money implied volatility by exactly `delta_iv`, recomputing the level
parameter so the change to total variance is consistent at maturity `t`.

From `tests/volsurface.ch`:

```chelis
p = smile_svi()
shifted = parallel_shift_atm_iv(p, cast(0.01, f32), cast(1.0, f32))
// the ATM implied vol of shifted is 0.01 above that of p
```

## Implied-vol solver

```chelis
def implied_vol_from_call(spot: f32, strike: f32, r: f32, t: f32, target_price: f32) -> f32
def implied_vol_bisect(spot: f32, strike: f32, r: f32, t: f32, target: f32, vol_lo: f32, vol_hi: f32, max_iters: int64, tol: f32) -> f32
def bracket_brackets_root(spot: f32, strike: f32, r: f32, t: f32, target: f32, vol_lo: f32, vol_hi: f32) -> bool
def is_iv_solver_failed(iv: f32) -> bool
```

`implied_vol_from_call` inverts the Black-Scholes call to find the
volatility that reproduces `target_price`. It calls `implied_vol_bisect`
with a search bracket of `0.0001` to `5.0`, sixty iterations, and a price
tolerance of `0.000001`. From `tests/volsurface.ch`, the solver round-trips
a Black-Scholes price back to its volatility:

```chelis
price = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
iv = implied_vol_from_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(1.0, f32), price)
// iv == 0.2
```

`implied_vol_bisect` exposes the full bisection with an explicit bracket,
iteration cap, and tolerance. If the bracket does not contain a sign change,
it returns a NaN sentinel rather than pinning silently at the bracket edge.
`bracket_brackets_root` reports whether a `[vol_lo, vol_hi]` pair brackets
the target, and `is_iv_solver_failed` tests the returned value for the NaN
sentinel:

```chelis
iv = implied_vol_bisect(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(1.0, f32), cast(200.0, f32), cast(0.0001, f32), cast(5.0, f32), cast(60, int64), cast(0.000001, f32))
failed = is_iv_solver_failed(iv)  // true: 200.0 is not a reachable call price here
```
