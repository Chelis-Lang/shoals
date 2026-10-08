# Lattices, PDEs, and early exercise

Modules: `Shoals.Trees`, `Shoals.Pde`, `Shoals.Lsm`, `Shoals.FixedIncome`.

These modules price options numerically where
[Pricing](pricing.md) and
[Extended pricers](pricing-extended.md) use closed forms: on a
recombining tree, on a finite-difference grid, or by regression Monte
Carlo, which is what an American option needs. All values are `f32`;
rates and the dividend yield `q` are continuously compounded decimals and
times are years.

## Trees

```chelis
def tr_crr_european_call(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_steps: i64) -> f32
```

Every named tree pricer takes these seven arguments in this order:

| Function | Tree | Exercise |
|---|---|---|
| `tr_crr_european_call`, `tr_crr_european_put` | Cox-Ross-Rubinstein | European |
| `tr_crr_american_call`, `tr_crr_american_put` | Cox-Ross-Rubinstein | American |
| `tr_tian_european_call`, `tr_tian_european_put` | Tian (moment matching) | European |
| `tr_jr_european_call`, `tr_jr_european_put` | Jarrow-Rudd (equal probabilities) | European |
| `tr_trinomial_european_call` | trinomial | European |
| `tr_trinomial_american_put` | trinomial | American |

Each tree has `n_steps` steps of `dt = t / n_steps`. The CRR tree moves
`ln S` by `±sigma * sqrt(dt)` with up probability
`(exp((r - q) * dt) - d) / (u - d)`; Jarrow-Rudd moves it by
`(r - q - sigma^2 / 2) * dt ± sigma * sqrt(dt)` with probability one half;
the trinomial tree moves it by `±sigma * sqrt(3 * dt)` or not at all, with
middle probability 2/3. An American tree takes the larger of the
continuation value and the intrinsic value at every node. Below
`sigma = 0.001` every pricer returns the deterministic forward intrinsic
`max(s0 * exp(-q * t) - k * exp(-r * t), 0)` (or its put form) without
building a tree.

At `s0 = k = 100`, `r = 0.05`, `q = 0`, `sigma = 0.2`, `t = 1` and 200
steps, against the Black-Scholes call `10.450583` and put `5.5735`:

| Pricer | Value |
|---|---:|
| `tr_crr_european_call` | 10.439744 |
| `tr_tian_european_call` | 10.450348 |
| `tr_jr_european_call` | 10.445262 |
| `tr_trinomial_european_call` | 10.4406595 |
| `tr_crr_european_put` | 5.5639877 |
| `tr_crr_american_put` | 6.0867205 |
| `tr_trinomial_american_put` | 6.0810556 |
| `tr_crr_american_call` | 10.439744 |

The American call equals the European call here because with `q = 0` early
exercise of a call is never optimal.

No input is checked. Supply positive `s0`, `k`, and `t` (`sigma` below
0.001 takes the deterministic branch above); a non-positive spot or strike
gives NaN through a logarithm or a meaningless price. `n_steps` must be at
least 1 (zero divides `t` by zero). With few steps and a large drift `(r - q) * dt` relative to
`sigma * sqrt(dt)`, the CRR up probability leaves `[0, 1]` and the price
is meaningless; use more steps.

```chelis
def tr_binom_european_call_generic(s0: f32, k: f32, log_u: f32, log_d: f32, p: f32, disc: f32, n_steps: i64) -> f32
def tr_crr_call_2step(s: f32, k: f32, u: f32, d: f32, q: f32, disc: f32) -> f32
def tr_crr_call_2step_nodisc(s: f32, k: f32, u: f32, d: f32, q: f32) -> f32
def tr_crr_call_2step_rn(s: f32, k: f32, u: f32, d: f32, q: f32) -> f32
def pde_thomas_solve(lower: List[f32], diag: List[f32], upper: List[f32], b_vec: List[f32], n_x: i64) -> List[f32]
```

`tr_binom_european_call_generic` is
the backward induction behind the binomial calls, for a tree you
parameterize yourself: terminal node `j` of `n_steps + 1` is
`s0 * exp(j * log_u + (n_steps - j) * log_d)`, `p` is the up probability
per step, and `disc` the discount factor per step. It checks neither `p`
nor `disc`, and `n_steps = 0` returns the intrinsic `max(s0 - k, 0)`.

`tr_crr_call_2step(s, k, u, d, q, disc)` is the two-step tree written out:
`disc^2 * (q^2 * (s u^2 - k)+ + 2 q (1 - q) * (s u d - k)+ + (1 - q)^2 * (s d^2 - k)+)`,
where `q` is the up probability, not a dividend yield.
`tr_crr_call_2step_nodisc` omits `disc^2`, and `tr_crr_call_2step_rn`
discounts each step by `1 / (q * u + (1 - q) * d)`.
`tr_crr_call_2step(100, 100, 1.1, 0.9, 0.6, 0.98)` is `7.260625`.

## Finite differences

```chelis
def pde_european_call_cn(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_x: i64, n_t: i64, s_max_mult: f32) -> f32
def pde_european_put_cn(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_x: i64, n_t: i64, s_max_mult: f32) -> f32
def pde_american_put_cn(s0: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32, n_x: i64, n_t: i64, s_max_mult: f32) -> f32
```

These solve the Black-Scholes PDE in `x = ln S` on `n_x` evenly spaced
nodes from `ln(s0 / s_max_mult)` to `ln(s0 * s_max_mult)`, with `n_t` time
steps. The first two steps are fully implicit (Rannacher smoothing of the
payoff kink) and the rest Crank-Nicolson. At the grid edges the call is 0
below and `s_max * exp(-q * tau) - k * exp(-r * tau)` above; the put is
`k * exp(-r * tau)` below and 0 above. The American put replaces each value
by the intrinsic value where that is larger after every step. The result is
interpolated linearly in `ln S` at `s0`.

```chelis
pc = pde_european_call_cn(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.2, f32), cast(1.0, f32), cast(201, i64), cast(100, i64), cast(4.0, f32))
-- 10.446156 (Black-Scholes 10.450583)
pap = pde_american_put_cn(cast(100.0, f32), cast(100.0, f32), cast(0.05, f32), cast(0.0, f32), cast(0.2, f32), cast(1.0, f32), cast(201, i64), cast(100, i64), cast(4.0, f32))
-- 6.078748
```

The European put at the same settings is `5.568951`. Choose `s_max_mult`
large enough that the edges are far from the strike (4 puts them at a
quarter and four times the spot); `s0` must be positive and
`s_max_mult` greater than 1, since `s_max_mult = 1` collapses the grid to
one point and divides by zero. Use `n_x >= 3` and `n_t >= 1`. None of
this is checked: invalid grid inputs return NaN or a meaningless
value rather than failing.

```chelis
def pde_spread_option_adi(s1_0: f32, s2_0: f32, k: f32, r: f32, q1: f32, q2: f32, sigma1: f32, sigma2: f32, rho: f32, t: f32, n_x1: i64, n_x2: i64, n_t: i64) -> f32
```

`pde_spread_option_adi` prices the European spread call
`max(S1 - S2 - k, 0)` on a two-dimensional log grid. It uses the
Craig-Sneyd ADI (alternating-direction implicit) scheme: the predictor
includes the full correlation term, and a second pair of implicit
sweeps corrects that term. The first two time intervals each use two
damped half-steps to smooth the payoff kink.

Each grid axis is centered on its initial log spot. Its half-width is
the larger of `log(2)` and
`abs(r - q - 0.5 * sigma^2) * t + sigma^2 * t + 6 * sigma * sqrt(t)`.
The perimeter is updated at every stage to
`max(S1 * exp(-q1 * tau) - S2 * exp(-q2 * tau) - k * exp(-r * tau), 0)`,
where `tau` is the time to maturity at that stage. This is an
asymptotic boundary approximation, so check grid convergence for the
parameters you price.

For `s1_0 = 100`, `s2_0 = 95`, `k = 5`, `r = 0.05`, no yields, vols
`0.2` and `0.3`, `rho = 0.5`, and `t = 1`, a 41 x 41 grid with 50 steps
returns `10.272353`. Independent integration gives about `10.211501`.
Increase the spatial grid and time steps together; a wider domain also
needs more spatial points to retain the same spacing.

Use finite positive spots, non-negative volatilities and maturity,
`rho` in `[-1, 1]`, at least three points per axis, and at least one time
step. At zero maturity the function returns the intrinsic payoff
without solving the PDE. Invalid grid inputs are not checked.

`pde_thomas_solve` solves the `n_x x n_x` tridiagonal
system with sub-diagonal `lower`, diagonal `diag`, and super-diagonal
`upper`, each a `List[f32]` with at least `n_x` entries (`lower[0]` and
`upper[n_x - 1]` are not read, nor are entries past `n_x`). It returns
`n_x` values. It does not pivot. It substitutes one when a
pivot's absolute magnitude is below `1e-10`, without a diagnostic, so
near-singular systems are outside its accuracy contract. The system with
diagonal 4, off-diagonals 1, and right-hand side `[5, 6, 5]` returns
`[1.0, 1.0, 0.99999994]`.

## Longstaff-Schwartz

```chelis
def lsm_american_put[n](rng_key: key, paths_template: tensor[n, f32], s0: f32, k: f32, r: f32, sigma: f32, t: f32, n_steps: i64) -> f32
def lsm_polynomial_regression[k](xs: tensor[k, f32], ys: tensor[k, f32]) -> (f32, f32, f32)
def lsm_put_payoff(s: f32, k: f32) -> f32
```

`lsm_american_put` simulates GBM paths with no dividend yield and
allows exercise at time 0 and at each date `i * t / n_steps`, for
`i = 1 .. n_steps`. At each
intermediate date it fits the discounted continuation values of the
in-the-money paths to a quadratic in spot. Each selected cash flow is
discounted from its exercise date once. The same paths serve for
regression and valuation.

The fit centers and scales spot values, then solves the least-squares
problem by QR in `f64`. Continuation values are evaluated in those
normalized coordinates. A rank-deficient fit uses a linear or constant
basis. This avoids forming normal equations from spot values and their
squares, which can lose the quadratic fit in `f32`.

With 2000 paths, seed 21, `s0 = k = 100`, `r = 0.05`, `sigma = 0.2`, and
`t = 1`, the prices are:

| Exercise steps | Price |
| --- | --- |
| 1 | 5.651484 |
| 2 | 5.7318807 |
| 10 | 6.0377645 |
| 50 | 6.1672 |

These are Monte Carlo estimates. Changing the number of dates also
changes the simulated paths, so individual estimates need not increase
with the number of steps or exceed an analytic European price. Using the
same paths to fit and value the exercise policy also introduces regression
bias. Several seeds help measure random variation; increase the path
count to reduce the fitting bias. For this case, a refined
`tr_crr_american_put` tree gives about `6.09`.

Supply at least one path and one step, finite positive `s0` and `k`, a
finite rate, and finite non-negative `sigma` and `t`. At zero maturity
the result is the intrinsic payoff. Invalid inputs fail with a diagnostic.

`lsm_polynomial_regression` returns the coefficients `(b0, b1, b2)` of
`y = b0 + b1 * x + b2 * x^2` in the original coordinates. For
`x = [90, 95, 100, 105, 110]` and `y = [101, 26, 1, 26, 101]`, it returns
`(10001, -200, 1)`. Repeated spots use a constant fit; two distinct spots
use a linear fit. Supply equal, nonempty lengths and finite observations.
If coefficients cannot be represented in `f32`, the function fails.
`lsm_put_payoff(s, k)` is `max(k - s, 0)`.

## Fixed-coupon bonds

```chelis
def fi_bond_general(c: f32, y: f32, n: i64) -> f32
def fi_bond2(c: f32, y: f32) -> f32
def fi_df2(y: f32) -> f32
def fi_bond2_nodisc(c: f32, y: f32) -> f32
```

Prices per unit of face value, with the coupon `c` and yield `y` both per
period: `fi_bond_general` is `sum_{i=1..n} c / (1 + y)^i + 1 / (1 + y)^n`,
a bond paying `c` each period and the face value with the last coupon.
`fi_bond2` is the two-period case, `fi_df2` the two-period discount factor
`1 / (1 + y)^2`, and `fi_bond2_nodisc` the undiscounted cash flow
`c + (1 + c)`.

A 30-year bond with a 5% annual coupon paid semiannually, at a 4% yield,
has `c = 0.025`, `y = 0.02`, and 60 periods:

```chelis
pv = fi_bond_general(cast(0.025, f32), cast(0.02, f32), cast(60, i64))
-- 1.1738045
```

`fi_bond2(0.05, 0.04)` is `1.0188609` and `fi_df2(0.04)` is `0.92455626`.
These take a flat per-period yield; for a curve, discount each cash flow
with [Yield curves](curves.md).
