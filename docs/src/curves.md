# Yield curves

Module: `Shoals.Curves`.

This module represents a yield curve as a set of pillar times and rates
tagged with a curve kind, interpolates the rate at an arbitrary maturity by
several methods, derives discount factors, bootstraps a zero curve from par
yields in the single-curve case, and applies sensitivity shifts.

## Types and curve kinds

```chelis
type CurveKind =
  | Ois
  | Ibor
  | Sofr
  | Sonia
  | Estr
  | Custom { label: string }

type YieldCurve[n] =
  | YieldCurve { kind: CurveKind, times: tensor[n, f32], rates: tensor[n, f32] }
```

A `YieldCurve[n]` carries its kind, a tensor of pillar times, and a tensor
of pillar rates, both of length `n`. The kind is one of the standard
overnight or term-rate families, or a `Custom` kind with a free-text label.
Constructors for each kind:

```chelis
def ois() -> CurveKind
def ibor() -> CurveKind
def sofr() -> CurveKind
def sonia() -> CurveKind
def estr() -> CurveKind
def custom_curve(label: string) -> CurveKind
```

## Building a curve

```chelis
def yield_curve_from_pillars[n](times: tensor[n, f32], rates: tensor[n, f32]) -> YieldCurve[n]
def yield_curve_tagged[n](kind: CurveKind, times: tensor[n, f32], rates: tensor[n, f32]) -> YieldCurve[n]
def curve_kind[n](curve: YieldCurve[n]) -> CurveKind
```

`yield_curve_from_pillars` builds an untagged curve (a `Custom` kind with
the label `"untagged"`). `yield_curve_tagged` builds a curve with an
explicit kind. `curve_kind` reads the kind back. For example:

```chelis
curve = yield_curve_from_pillars(
  to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)]),
  to_tensor([cast(0.03, f32), cast(0.04, f32), cast(0.045, f32)])
)
tagged = yield_curve_tagged(sofr(), to_tensor([cast(1.0, f32)]), to_tensor([cast(0.04, f32)]))
kind = curve_kind(tagged)            // Sofr
flat = rate_at(tagged, cast(7.0, f32))  // 0.04: one pillar reads flat
```

Rates are continuously compounded zero rates as decimals (`0.04` is 4%), and
times are years from the curve date.

### Pillar times must be strictly increasing

Both constructors reject pillar times that are not strictly increasing, with a
runtime `fail` naming the entry point, the first offending index, and both
times:

```text
Shoals.Curves.yield_curve_from_pillars: pillar times must be strictly increasing: index 2 has time 2.0, which does not exceed time 3.0 at index 1
```

`rate_at` uses `Nautilus.Interpolation.linear_interp_sorted`, which brackets
a query in traversal order. Without the ordering guard, reordering the example's
pairs can change the rate at `1.5` from `0.035` to `0.025`, changing every
price discounted at that rate. The constructors reject duplicate times and
NaN times among two or more pillars. They do not sort the supplied pairs.

The same guard applies to `bootstrap_zero_from_par` and
`curve_basis_from_pillars`. It checks adjacent ordering, not finiteness:
a single-pillar curve has no pair to compare, so a lone NaN time is accepted
and the curve reads flat.

### Reading opaque curves

`YieldCurve` and `CurveBasis` are opaque. Outside `Shoals.Curves`, use the
constructors above instead of record literals. Direct construction is rejected:

```text
record construction of opaque type `YieldCurve` outside its defining module `Shoals.Curves`
```

Record patterns are also unavailable outside the module. Use `curve_kind`,
`rate_at`, or the pillar readers:

```chelis
def curve_pillars[n](curve: YieldCurve[n]) -> (tensor[n, f32], tensor[n, f32])
def basis_pillars[n](basis: CurveBasis[n]) -> (tensor[n, f32], tensor[n, f32])
```

Each returns the times and rates together. You may name `YieldCurve[3]` in a
signature or annotation; opacity restricts access to its representation, not
use of the type. `copy` accepts tensors, not curve values.

Rebuilding a curve from its pillars goes through the same constructor checks.
Sensitivity shifts preserve the existing times; `bootstrap_multi_curve` checks
the ordering of instrument tenors. These are runtime guards, not a proof of
pillar ordering by the type checker. They do not establish finiteness: the
single-pillar `NaN` case above still applies.

## Interpolation and discount factors

```chelis
def rate_at[n](curve: YieldCurve[n], t: f32) -> f32
def spline_rate_at[n](curve: YieldCurve[n], t: f32) -> f32
def log_linear_rate_at[n](curve: YieldCurve[n], t: f32) -> f32
def nss_rate(beta0: f32, beta1: f32, beta2: f32, beta3: f32, tau1: f32, tau2: f32, t: f32) -> f32
def discount_factor[n](curve: YieldCurve[n], t: f32) -> f32
```

All three pillar interpolators hold the end rates flat outside the pillars:
a `t` before the first pillar reads the first rate, and a `t` after the
last reads the last. One pillar gives a flat curve: `spline_rate_at` of a
one-pillar curve at 4% reads `0.04` everywhere, and a two-pillar spline is
the straight line between them (`0.04` midway between 3% and 5%). A curve
with no pillars can be built and reads rate `0.0` and discount factor
`1.0` at every `t`.

- `rate_at` interpolates the pillar rates linearly in `t` (using
  `Nautilus.Interpolation.linear_interp_sorted`).
- `spline_rate_at` evaluates a natural cubic spline through the pillars
  (second derivative zero at both ends). It refits the spline on every
  call, so evaluating many maturities costs one fit each.
- `log_linear_rate_at` interpolates `ln(rate)` linearly and exponentiates,
  so it needs every pillar rate to be positive. A zero or negative pillar
  rate has no logarithm: a query in any interval that touches it returns
  NaN, without a failure. On rates `[-0.005, 0.01]` at times `[1, 2]`, both
  `t = 1.5` and `t = 2.0` return NaN. Use `rate_at` for curves that cross
  zero.
- `discount_factor` returns `exp(-rate_at(curve, t) * t)`.

`nss_rate` evaluates the Nelson-Siegel-Svensson form directly from its six
parameters, independent of any pillar set:

`r(t) = beta0 + beta1 * g(t / tau1) + beta2 * (g(t / tau1) - exp(-t / tau1)) + beta3 * (g(t / tau2) - exp(-t / tau2))`

with `g(x) = (1 - exp(-x)) / x`. `beta0` is the long rate and
`beta0 + beta1` the instantaneous short rate; at `t = 0` the function
uses the limit `g(0) = 1` and returns exactly `beta0 + beta1`. Supply
`tau1 > 0`, `tau2 > 0`, and `t >= 0`; nothing checks them. A zero `tau`
does not fail: at `t > 0` it makes `g` zero, so `tau1 = 0` silently drops
the `beta1` and `beta2` terms (the example parameters with `tau1 = 0` give
`0.04` at `t = 1`).

For example, on the three-pillar curve above:

```chelis
r = rate_at(curve, cast(1.5, f32))             // 0.035
s = spline_rate_at(curve, cast(1.5, f32))      // 0.03546875
l = log_linear_rate_at(curve, cast(1.5, f32))  // 0.034641013
early = rate_at(curve, cast(0.5, f32))         // 0.03, flat before the first pillar
d = discount_factor(curve, cast(2.0, f32))     // 0.9231163 == exp(-0.08)
```

For example, the NSS rate tends to `beta0 + beta1` as the
maturity goes to zero and to `beta0` at long horizons:

```chelis
r = nss_rate(cast(0.04, f32), cast(-0.02, f32), cast(0.01, f32), cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(0.0, f32))
// 0.02 (beta0 + beta1)
r30 = nss_rate(cast(0.04, f32), cast(-0.02, f32), cast(0.01, f32), cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(30.0, f32))
// 0.039666668, approaching beta0
```

## Bootstrapping

```chelis
def bootstrap_zero_from_par[n](times: tensor[n, f32], par_yields: tensor[n, f32]) -> YieldCurve[n]
```

`bootstrap_zero_from_par` builds a zero curve from par yields of bonds
paying one coupon per year. It treats pillar `i` as the bond whose coupons
fall on pillars `0..i`, each paying the full annual coupon `c_i`, so the
pillars must be the consecutive coupon dates 1, 2, 3, ... years. The
discount factor at pillar `i` is

`P_i = (1 - c_i * (P_0 + ... + P_{i-1})) / (1 + c_i)`

and the zero rate is `-ln(P_i) / t_i`. The times enter only that last
division. Nothing checks the spacing, and no rate is interpolated for a
missing coupon date: pillars `[0.5, 1.0]` at 5% are read as two annual
coupons and return rates `[0.097580194, 0.09758029]` instead of about 5%.
For semiannual or gapped instruments use `bootstrap_multi` below. A
`P_i <= 0` gives a NaN rate. Times must be strictly increasing. For example:

```chelis
times = to_tensor([cast(1.0, f32), cast(2.0, f32)])
pars = to_tensor([cast(0.05, f32), cast(0.06, f32)])
curve = bootstrap_zero_from_par(times, pars)
// rates [0.048790097, 0.058554675]; the two-year par bond reprices to 1.0
```

### Instrument bootstrap

```chelis
type Instrument =
  | Deposit { tenor: f32, rate: f32 }
  | ZeroCoupon { tenor: f32, price: f32 }
  | ParSwap { tenor: f32, par_rate: f32, payments_per_year: i64 }

def deposit(tenor: f32, rate: f32) -> Instrument
def zero_coupon(tenor: f32, price: f32) -> Instrument
def cur_par_swap(tenor: f32, par_rate: f32, payments_per_year: i64) -> Instrument
def instrument_validate(inst: Instrument) -> bool
def bootstrap_multi(instruments: List[Instrument]) -> (List[f32], List[f32])
def bootstrap_multi_curve[n](instruments: List[Instrument], times_template: tensor[n, f32]) -> YieldCurve[n]
```

`bootstrap_multi` solves one continuously compounded zero rate per
instrument, in list order, and returns the pillar times and rates.
`bootstrap_multi_curve` wraps the same result as a `YieldCurve`.

`times_template` supplies the `n` in `YieldCurve[n]`; its values are ignored.
Its length must equal the instrument count. A mismatch raises a runtime `fail`
naming `Shoals.Curves.bootstrap_multi_curve` and reporting both counts, for
example `template has 3 entries for 2 instruments`.

- A deposit is simple interest: `DF(t) = 1 / (1 + rate * t)`.
- A zero-coupon price is the discount factor at its tenor.
- A par swap's fixed leg pays `par_rate / payments_per_year` on each date
  `k / payments_per_year` for `k = 1..N`, where `N = tenor * payments_per_year`,
  and the solved pillar satisfies `par_rate * annuity + DF(tenor) = 1`.
  Discount factors at coupon dates between pillars come from the curve being
  built under the `rate_at` convention: zero rates are linear between pillars
  and flat outside them. A bootstrapped curve therefore reprices each input
  swap through `discount_factor`.

`instrument_validate` rejects a non-finite tenor or quote, a non-positive
tenor, a deposit rate at or below `-1` or whose `1 + rate * tenor` is not
positive, a zero-coupon price outside `(0, 1]`, a non-positive
`payments_per_year`, and a swap tenor that is not a whole number of payment
periods. The bootstrap raises a runtime `fail` naming
`Shoals.Curves.bootstrap_multi` when an instrument is invalid, or when any
instrument's tenor does not exceed every earlier pillar (instruments must be
listed in strictly increasing tenor). It never snaps a schedule or re-sorts
pillars.

`bootstrap_multi` returns finite zero rates or raises a runtime `fail`.
This contract applies to the instrument bootstrap; `bootstrap_zero_from_par`
can return a NaN rate for a non-positive par price.

The instrument bootstrap searches `[-0.5, 2.0]` using `Nautilus.Roots.brent`.
If the solver returns NaN, Shoals reports the instrument's tenor and quote,
the repricing residuals at both endpoints, and one of three diagnostics:

- a quote whose zero rate lies outside the bracket leaves the residual the
  same sign at both endpoints, and fails with *no zero rate for this
  instrument in the search bracket `[-0.5, 2.0]`*;
- a non-finite endpoint residual fails with *the repricing residual is not
  finite over the search bracket*. A long-dated swap can overflow
  `exp(0.5 * tenor)` at about 177 years; `instrument_validate` does not cap
  maturity. Caller-supplied NaN earlier pillars can also cause this through
  `fd_bump_pillar_rate` and the gradient entry points. A root may exist even
  though this bracket cannot be searched in f32;
- a failed solve with finite, sign-changing endpoint residuals reports *did
  not converge*. The solver allows one hundred iterations.

For example, a gapped annual strip:

```chelis
insts = [
  deposit(cast(0.5, f32), cast(0.041, f32)),
  deposit(cast(1.0, f32), cast(0.042, f32)),
  cur_par_swap(cast(2.0, f32), cast(0.0435, f32), cast(1, i64)),
  cur_par_swap(cast(5.0, f32), cast(0.0452, f32), cast(1, i64)),
  cur_par_swap(cast(10.0, f32), cast(0.0468, f32), cast(1, i64))
]
rates = bootstrap_multi(insts).1
// 10y zero rate ~0.0460236
```

### Quote sensitivities

```chelis
def bootstrap_grad_at_solution(instruments: List[Instrument]) -> List[f32]
def bootstrap_grad_full_jacobian[m](paths_template: &tensor[m, f32], instruments: List[Instrument]) -> tensor[m, m, f32]
```

Both bootstrap the instruments as `bootstrap_multi` does and differentiate
the solved zero rates with respect to the quotes by the implicit function
theorem, over the same coupon schedule and interpolation. Index `i` is the
`i`-th instrument in list order, which is also the `i`-th pillar. The quote
is the deposit rate, the zero-coupon price, or the swap par rate, so the
units are zero-rate change per unit change of that quote.

- `bootstrap_grad_at_solution` returns the diagonal: `d z_i / d q_i` with
  the earlier pillars held fixed, one entry per instrument.
- `bootstrap_grad_full_jacobian` returns the `m x m` matrix with entry
  `[i, j] = d z_i / d q_j`, row-major. It is lower triangular, because a
  pillar depends only on its own and earlier quotes, and its diagonal is the
  list above. `paths_template` supplies `m`; its values are ignored.

```chelis
insts = [
  deposit(cast(1.0, f32), cast(0.04, f32)),
  cur_par_swap(cast(2.0, f32), cast(0.045, f32), cast(1, i64)),
  cur_par_swap(cast(3.0, f32), cast(0.05, f32), cast(1, i64))
]
diag = bootstrap_grad_at_solution(insts)
// [0.9615385, 0.9809815, 1.0079565]
tmpl = to_tensor([cast(0.0, f32), cast(0.0, f32), cast(0.0, f32)])
jac = bootstrap_grad_full_jacobian(tmpl, insts)
// rows [0.9615385, 0.0, 0.0], [-0.021743337, 0.9809815, 0.0],
//      [-0.016273007, -0.033038095, 1.0079565]
```

A `paths_template` whose length differs from the instrument count raises a
runtime `fail` reporting both counts, and an invalid instrument fails with
the bootstrap's diagnostic; neither returns a NaN-filled Jacobian. FRAs and
futures are not instruments here, and the solve is sequential rather than
joint; see [Scope and limitations](scope.md).

### Basis spreads

```chelis
def curve_basis_from_pillars[n](times: tensor[n, f32], spreads: tensor[n, f32]) -> CurveBasis[n]
def basis_pillars[n](basis: CurveBasis[n]) -> (tensor[n, f32], tensor[n, f32])
def basis_spread_at[n](basis: CurveBasis[n], t: f32) -> f32
def discount_factor_with_basis[n, m](domestic: YieldCurve[n], basis: CurveBasis[m], t: f32) -> f32
```

A `CurveBasis` holds spreads as continuously compounded decimals added to a
zero rate (`0.001` is 10 basis points). `curve_basis_from_pillars` applies
the same strictly-increasing check as the curve constructors.
`basis_spread_at` interpolates the spreads linearly, flat outside the
pillars, exactly as `rate_at` does. `discount_factor_with_basis` returns
`exp(-(rate_at(domestic, t) + basis_spread_at(basis, t)) * t)`; the two
curves may have different pillars.

```chelis
basis = curve_basis_from_pillars(to_tensor([cast(1.0, f32), cast(5.0, f32)]), to_tensor([cast(0.001, f32), cast(0.003, f32)]))
s3 = basis_spread_at(basis, cast(3.0, f32))                 // 0.0019999999
dfb = discount_factor_with_basis(curve, basis, cast(2.0, f32))  // 0.92035115 == exp(-(0.04 + 0.0015) * 2)
```

These functions do not calibrate a basis curve against a domestic curve or
solve basis-swap quotes.

## Sensitivity shifts

```chelis
def parallel_shift[n](curve: YieldCurve[n], delta: f32) -> YieldCurve[n]
def key_rate_shift[n](curve: YieldCurve[n], pillar_index: i64, delta: f32) -> YieldCurve[n]
def twist[n](curve: YieldCurve[n], short_delta: f32, long_delta: f32) -> YieldCurve[n]
def butterfly[n](curve: YieldCurve[n], wing_delta: f32, body_delta: f32) -> YieldCurve[n]
def scale_rates[n](curve: YieldCurve[n], factor: f32) -> YieldCurve[n]
```

`parallel_shift` adds the same `delta` to every pillar rate.
`key_rate_shift` adds `delta` only to the pillar at the zero-based
`pillar_index`, leaving the others fixed. An index that is negative or past
the last pillar matches nothing and returns the curve unchanged, without a
failure. `twist` interpolates a shift linearly in maturity
from `short_delta` at the shortest pillar to `long_delta` at the longest;
at the midpoint the applied shift is the average of the two. `butterfly`
adds `w * wing_delta + (1 - w) * body_delta` at a pillar at time `t`, where
`w = |t - t_mid| / (t_max - t_mid)` and `t_mid` is the midpoint of the
first and last pillar times. The shift is therefore `wing_delta` at the two
end pillars, `body_delta` at the time midpoint (whether or not a pillar sits
there), and linear in time between. On a single-pillar curve `butterfly`
adds `body_delta` and `twist` adds `short_delta`. `scale_rates` multiplies
every rate by `factor`.

On flat zero pillars at 1 to 5 years, `butterfly(curve, 0.01, -0.01)` gives
`[0.01, 0.0, -0.01, 0.0, 0.01]` and `twist(curve, 0.01, -0.01)` gives
`[0.01, 0.005, 0.0, -0.005, -0.01]`.

For example, a parallel shift lifts every pillar by the same
amount and a key-rate shift moves only the chosen pillar:

```chelis
shifted = parallel_shift(curve, cast(0.001, f32))      // every rate +10bp
kr = key_rate_shift(curve, cast(1, i64), cast(0.005, f32))  // only the 2y pillar +50bp
```
