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
explicit kind. `curve_kind` reads the kind back. From `tests/curves.ch` and
`tests/curves_ops.ch`:

```chelis
curve = yield_curve_from_pillars(
  to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)]),
  to_tensor([cast(0.03, f32), cast(0.04, f32), cast(0.045, f32)])
)
tagged = yield_curve_tagged(sofr(), to_tensor([cast(1.0, f32)]), to_tensor([cast(0.04, f32)]))
```

## Interpolation and discount factors

```chelis
def rate_at[n](curve: YieldCurve[n], t: f32) -> f32
def spline_rate_at[n](curve: YieldCurve[n], t: f32) -> f32
def log_linear_rate_at[n](curve: YieldCurve[n], t: f32) -> f32
def nss_rate(beta0: f32, beta1: f32, beta2: f32, beta3: f32, tau1: f32, tau2: f32, t: f32) -> f32
def discount_factor[n](curve: YieldCurve[n], t: f32) -> f32
```

`rate_at` interpolates the pillar rates linearly at maturity `t` (using
`Nautilus.Interpolation.linear_interp_sorted`). `spline_rate_at` uses a
cubic spline, and `log_linear_rate_at` interpolates in log-rate space and
exponentiates. `nss_rate` evaluates the Nelson-Siegel-Svensson functional
form directly from its six parameters, independent of any pillar set.
`discount_factor` returns `exp(-rate_at(curve, t) * t)`.

From `tests/curves.ch`, linear interpolation at the midpoint and the
discount factor at a pillar:

```chelis
r = rate_at(curve, cast(1.5, f32))         // r == 0.035
d = discount_factor(curve, cast(2.0, f32)) // d == exp(-0.08)
```

From `tests/curves_ops.ch`, the NSS rate tends to `beta0 + beta1` as the
maturity goes to zero and to `beta0` at long horizons:

```chelis
r = nss_rate(cast(0.04, f32), cast(-0.02, f32), cast(0.01, f32), cast(0.0, f32), cast(1.0, f32), cast(2.0, f32), cast(0.0, f32))
// r == 0.02 (beta0 + beta1)
```

## Bootstrapping

```chelis
def bootstrap_zero_from_par[n](times: tensor[n, f32], par_yields: tensor[n, f32]) -> YieldCurve[n]
```

`bootstrap_zero_from_par` builds a zero curve from a set of par yields in
the single-curve case, with one coupon per pillar at integer-year spacing.
The resulting curve reprices the par bonds to par. From `tests/curves.ch`:

```chelis
times = to_tensor([cast(1.0, f32), cast(2.0, f32)])
pars = to_tensor([cast(0.05, f32), cast(0.06, f32)])
curve = bootstrap_zero_from_par(times, pars)
// the two-year par bond reprices to 1.0
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

`times_template` carries only the result's extent: a list's length is not a
type-level value, so the template is what supplies the `n` in
`YieldCurve[n]`, and none of its *values* are read. It must therefore have
exactly one entry per instrument. A mismatch is a runtime `fail` naming
`Shoals.Curves.bootstrap_multi_curve` and reporting both counts (`template has
3 entries for 2 instruments`); previously it was accepted and the
returned value declared an extent it did not carry, so a consumer that
trusted `n` either trapped on a pillar that was never there or silently
missed one (shoals#113).

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

**The instrument bootstrap never returns a sentinel.** Every pillar
`bootstrap_multi` returns is a finite zero rate; everything else is a `fail`.
The qualifier is load-bearing and the unqualified sentence is false: the
`bootstrap_zero_from_par` above still answers a non-positive par price with a
`NaN` rate, unchanged, and shoals#76 had to narrow exactly this wording once
before for exactly that reason. The search bracket is
`[-0.5, 2.0]` and belongs to this module rather than to
`Nautilus.Roots.brent`, so when `brent` cannot return a rate it is this module
that says why. The three diagnostics classify that outcome, each reporting the
repricing residual at both endpoints and the offending instrument's tenor and
quote:

- a quote whose zero rate lies outside the bracket leaves the residual the
  same sign at both endpoints, and fails with *no zero rate for this
  instrument in the search bracket `[-0.5, 2.0]`*;
- a residual that is not finite at an endpoint fails with *the repricing
  residual is not finite over the search bracket*. Reachable two ways: a
  long-dated swap whose `exp(0.5 * tenor)` overflows `f32` — about 177 years
  and up, which `instrument_validate` does not bound — or, through
  `fd_bump_pillar_rate` and the gradient entry points, earlier pillars the
  caller supplied carrying a `NaN`. The clause is *the bracket cannot be
  searched*, not *there is no root*: a root may exist and be unreachable;
- a bracketed solve that exhausts its hundred iterations fails with *did not
  converge*. This is the residual case, reached only when neither of the
  above holds. No input is known to produce it, and nothing tests it; it
  exists so that the postcondition below is total.

Those are a total classification, so the postcondition is that
`bootstrap_multi` returns finite pillars or fails. `brent` is called first and
with the same arguments it has always had, and the endpoints are read only to
explain a `NaN` it has already returned — so every quote that solved before
still solves and returns the same rate.

Previously all three came back as a `NaN` pillar that `instrument_validate`
accepted and `rate_at`, `discount_factor` and the implicit-function-theorem
gradients then propagated, so a downstream price could be `NaN` far from the
instrument that caused it, and callers had to test `eq(z, z)` on every pillar
(shoals#79). Widening the bracket is a separate question and is not what
changed: a quote outside it is rejected, not re-solved.

From `tests/curves_bootstrap_schedule.ch`, a gapped annual strip:

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

`bootstrap_grad_at_solution` and `bootstrap_grad_full_jacobian` return the
implicit-function-theorem sensitivities of the solved zero rates to the
instrument quotes, over the same coupon schedule and interpolation. FRAs and
futures are not instruments here, and the solve is sequential rather than
joint; see [Scope and limitations](scope.md).

`bootstrap_grad_full_jacobian`'s `paths_template` carries only the result's
extent, exactly as `times_template` does for `bootstrap_multi_curve`, and must
likewise have one entry per instrument. Either mismatch direction is a runtime
`fail` reporting both counts (`template has 3 entries for 2 instruments`);
both previously returned a full matrix of `NaN`, which nothing distinguished
from a Jacobian whose entries were `NaN` for a numerical reason (shoals#79).
An invalid instrument likewise fails, through the bootstrap's own diagnostic,
rather than being reported as that matrix. Neither function uses a `NaN`
result as a signal any more.

### Basis spreads

`CurveBasis`, `curve_basis_from_pillars`, and `basis_spread_at` represent
and interpolate a spread curve. `discount_factor_with_basis` applies that
spread to a supplied domestic zero curve, and is the only function in this
section that reads a domestic curve.

No function here calibrates a basis curve against a domestic curve
(shoals#117). Build the spread curve from its pillars with
`curve_basis_from_pillars` — market basis quotes *are* those pillars — and
apply it with `discount_factor_with_basis`. There is deliberately no
separate quotes-to-curve entry point: without a basis-swap solve it would
be the same operation under a second name.

## Sensitivity shifts

```chelis
def parallel_shift[n](curve: YieldCurve[n], delta: f32) -> YieldCurve[n]
def key_rate_shift[n](curve: YieldCurve[n], pillar_index: i64, delta: f32) -> YieldCurve[n]
def twist[n](curve: YieldCurve[n], short_delta: f32, long_delta: f32) -> YieldCurve[n]
def butterfly[n](curve: YieldCurve[n], wing_delta: f32, body_delta: f32) -> YieldCurve[n]
def scale_rates[n](curve: YieldCurve[n], factor: f32) -> YieldCurve[n]
```

`parallel_shift` adds the same `delta` to every pillar rate.
`key_rate_shift` adds `delta` only to the pillar at `pillar_index`,
leaving the others fixed. `twist` interpolates a shift linearly in maturity
from `short_delta` at the shortest pillar to `long_delta` at the longest;
at the midpoint the applied shift is the average of the two. `butterfly`
applies `wing_delta` at the ends and `body_delta` in the middle, scaled by
distance from the midpoint. `scale_rates` multiplies every rate by `factor`.

From `tests/curves_ops.ch`, a parallel shift lifts every pillar by the same
amount and a key-rate shift moves only the chosen pillar:

```chelis
shifted = parallel_shift(curve, cast(0.001, f32))      // every rate +10bp
kr = key_rate_shift(curve, cast(1, i64), cast(0.005, f32))  // only the 2y pillar +50bp
```
