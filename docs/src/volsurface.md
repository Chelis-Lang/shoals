# Volatility surface

Module: `Shoals.VolSurface`.

This module parameterizes a volatility smile with the five-parameter SVI
total-variance form and a four-parameter SABR approximation. It converts
total variance to implied volatility, applies parameter shifts, and solves
for an implied volatility from a call price by bisection.

## The SVI type

```chelis
type SVI =
  | SVI { a: f32, b: f32, rho: f32, m: f32, sigma: f32 }
```

The SVI parameters are `a` (the vertical level), `b` (the slope of the
wings), `rho` (the rotation, or skew), `m` (the horizontal translation),
and `sigma` (the smoothness of the curvature near the money). For example, a flat surface and a downward-skewed smile:

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
`sqrt(max(w, 0) / t)`, clamping negative variance to zero. Supply `t > 0`;
the function does not validate its input.

For example, a flat surface has total variance equal to `a`
at the money and constant across strikes, and its implied vol at one year
is `sqrt(a / t)`:

```chelis
p = flat_svi()
w = vs_total_variance(p, cast(0.0, f32))      // w == 0.04
iv = vs_implied_vol(p, cast(0.0, f32), cast(1.0, f32))  // iv == 0.2
```

The example's left wing has higher total variance than its at-the-money
value; the skew can make the two wings behave differently.

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

For example:

```chelis
p = smile_svi()
shifted = parallel_shift_atm_iv(p, cast(0.01, f32), cast(1.0, f32))
// the ATM implied vol of shifted is 0.01 above that of p
```

## Implied-vol solver

```chelis
def implied_vol_from_call(spot: f32, strike: f32, r: f32, t: f32, target_price: f32) -> f32
def implied_vol_bisect(spot: f32, strike: f32, r: f32, t: f32, target: f32, vol_lo: f32, vol_hi: f32, max_iters: i64, tol: f32) -> f32
def bracket_brackets_root(spot: f32, strike: f32, r: f32, t: f32, target: f32, vol_lo: f32, vol_hi: f32) -> bool
def is_iv_solver_failed(iv: f32) -> bool
```

`implied_vol_from_call` inverts the Black-Scholes call to find the
volatility that reproduces `target_price`. It calls `implied_vol_bisect`
with a search bracket of `0.0001` to `5.0`, sixty iterations, and a price
tolerance of `0.000001`. For example, the solver round-trips
a Black-Scholes price back to its volatility:

```chelis
price = bs_call_scalar(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
iv = implied_vol_from_call(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(1.0, f32), price)
// iv == 0.2
```

`implied_vol_bisect` exposes the full bisection with an explicit bracket,
iteration cap, and tolerance. It requires a strict sign change across the
bracket; even an exact target at an endpoint fails that test. On failure it
returns a NaN sentinel.
`bracket_brackets_root` reports whether a `[vol_lo, vol_hi]` pair brackets
the target, and `is_iv_solver_failed` tests the returned value for the NaN
sentinel:

```chelis
iv = implied_vol_bisect(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(1.0, f32), cast(200.0, f32), cast(0.0001, f32), cast(5.0, f32), cast(60, i64), cast(0.000001, f32))
failed = is_iv_solver_failed(iv)  // true: 200.0 is not a reachable call price here
```

## SABR approximation

```chelis
type SABR =
  | SABR { alpha: f32, beta: f32, rho: f32, nu: f32 }

def vs_sabr_implied_vol(p: SABR, f: f32, k: f32, t: f32) -> f32
def vs_sabr_atm_implied_vol(p: SABR, f: f32, t: f32) -> f32
def vs_sabr_shift_alpha(p: SABR, d: f32) -> SABR
def vs_sabr_shift_rho(p: SABR, d: f32) -> SABR
def vs_sabr_shift_nu(p: SABR, d: f32) -> SABR
```

The two implied-vol functions evaluate a Hagan-style SABR expansion for
an off-ATM strike or at the money. They do not calibrate parameters or
enforce `f > 0`, `k > 0`, `alpha > 0`, or `|rho| < 1`; supply admissible
values. The shift functions change one parameter at a time.
