# Shoals Quant Finance Surface

Companion to `spec/phase3l.md`. Extends the Phase 3l baseline
(pricing, risk, curves, stochastic, orderbook — Shoals's v0.0.1
starting surface, originally shipped under the v0.7.x version track
that has since been reset) with the full quant finance functional
surface and the structural commitments required for the verified-AD-
for-quant-finance application of the Chelis trust stack.

This document is forward-looking. The current Shoals release implements
the baseline in `phase3l.md`; the milestones in
`docs/plan-quant-surface.md` build out the surface below. Land any
edits here together with the matching update to the chelis monorepo
`spec/design/chelis_phase3_plan.md` (Shoals shell scoping rules).

---

## 1. Workload anchors

The surface is sized to the workloads quant teams actually run, not an
aspirational list. The intended consumers are derivatives desks doing:

- **Pricing and risk on derivatives.** Compute a derivative price plus
  partial derivatives (Greeks) with respect to market parameters. Used
  for hedging, P&L attribution, capital, regulatory reporting.
- **XVA (X-valuation adjustment).** CVA, DVA, FVA, KVA. Each is a
  Monte Carlo computation; gradients with respect to market parameters
  drive hedging of the XVA itself.
- **Calibration.** Fit model parameters to observed market prices.
  Gradient-driven optimization across many products, run daily or
  intraday.
- **Sensitivity analysis.** First-order Greeks (delta, vega, rho,
  theta), second-order (gamma, vanna, volga), cross-partials, bucket
  sensitivities per curve tenor or surface pillar.
- **Backtesting and historical simulation.** Apply models to historical
  data; evaluate calibrations; statistical tests for model validation.
- **Value-at-risk and expected shortfall.** Parametric, historical,
  Monte Carlo. Sometimes sensitivity-based (delta-gamma) for
  approximation.

All share the same shape: model functions with parameters, evaluated
via numerical methods (MC, PDE, transform), with gradients with respect
to parameters as primary output beyond the values themselves.

## 2. Module surface

The baseline modules (`Shoals.Pricing`, `Shoals.Risk`, `Shoals.Curves`,
`Shoals.Stochastic`, `Shoals.Orderbook`) are extended; new modules are
added for foundational types that don't fit into the baseline. Every
new export ships at `alpha` stability per the cross-cutting Chelis
convention until the corresponding acceptance oracle is green.

### 2.1 `Shoals.Distributions` (new module; extends `Nautilus.Distributions`)

Pricing models rely on stochastic processes which rely on distributions
and RNG. Surface required:

- **Univariate distributions:** normal, lognormal, Student-t, gamma,
  beta, chi-squared, exponential, Poisson, uniform. Each with `pdf`,
  `cdf`, `inv_cdf`, `sample`. AD must flow through `pdf` and `cdf`
  with respect to distribution parameters (mean, variance, shape).
- **Multivariate distributions:** multivariate normal with Cholesky
  decomposition for correlated sampling. Multivariate Student-t for
  fat-tailed correlation.

Coverage gap vs Nautilus: Nautilus ships `normal_cdf`, `normal_pdf`,
`normal_inv_cdf`, `gamma_cdf` and special functions. Shoals adds the
remaining families and the multivariate cases; non-finance-specific
extensions migrate back to Nautilus when stable.

### 2.2 `Shoals.Rng` (new module)

- **Pseudo-random generators:** Mersenne Twister, PCG64, accessed
  through the `Random` effect with `withSeed` handlers.
- **Low-discrepancy sequences:** Sobol with Joe-Kuo direction numbers
  (committed dimension floor: 1024-D; the Joe-Kuo `new-joe-kuo-6.21201`
  table extends to 21201-D and the implementation should not impose a
  ceiling below the table size), Halton (committed dimension floor:
  50-D; primes table extended on demand). Critical for variance
  reduction in quasi-Monte Carlo pricing, especially many-asset
  baskets, long-horizon path-dependent products, and XVA exposure
  simulation where path × time × deal dimensionality compounds quickly.
- **Variance reduction combinators:** antithetic variates (exists in
  baseline), control variates, importance sampling, stratified
  sampling. Each is a function over a path-generation thunk; gradients
  through them compose cleanly because the underlying paths remain
  pathwise-differentiable.

The AD property required: differentiating a Monte Carlo expectation
produces a Monte Carlo expectation of gradients (pathwise method) when
the payoff is smooth, with likelihood-ratio dispatch when it isn't.
This is exposed through `Shoals.Greeks` (§2.11) rather than as a
single-function discipline.

### 2.3 `Shoals.Date` (new module)

Date arithmetic, day count, schedule generation:

- **Day-count conventions:** ACT/360, ACT/365, 30/360 variants, ACT/ACT
  (ISDA, ISMA), Business/252.
- **Business-day rolling:** following, modified following, preceding,
  modified preceding, end-of-month.
- **Schedule generation:** swap schedules, bond coupon schedules,
  arbitrary tenor-stepped sequences with stub-period handling.
- **Year-fraction computation:** between two dates under any
  convention.

Type-system rule: `Date` is `Discrete` (§3.1); the type checker rejects
`grad(..., wrt=(some_date))`. Date inputs feed into differentiable
computations through year-fraction conversions; the resulting `f64` is
`Differentiable`.

### 2.4 `Shoals.HolidayCal` (new module)

- **Built-in calendars:** NYC, LDN, TYO, SYD, FRA, HKG, joint
  calendars (NYC ∩ LDN, etc.).
- **User-extensible calendar registry:** customer-supplied calendars
  registered by name; `Shoals.Date` rolling and schedule-generation
  functions look up calendars by name.

### 2.5 `Shoals.Tenor` (new module)

- **Tenor parsing:** "3M", "1Y", "30Y", "ON" parsed into integer-day
  shifts relative to a reference date. Standard in IR products.

### 2.6 `Shoals.MarketData` (new module)

- **Quote types:** `Bid`, `Ask`, `Mid`, `Last` with freshness/validity
  metadata. The type system makes it impossible to confuse a `Quote`
  (carrying metadata) with a `f64`.
- **Tick data:** time-stamped quote streams; `Coral` dataframes the
  canonical column-store representation.
- **OHLCV bars:** aggregation of ticks into bars.
- **Reference data:** instrument definitions, exchange information,
  calendar references.
- **Market data snapshots:** point-in-time view of all market data
  needed for a pricing run. Required for reproducibility.

### 2.7 `Shoals.Curves` (extended)

Baseline ships linear / cubic interpolation, discount factors, and
single-curve par-bond bootstrap. Extensions:

- **Multi-curve framework:** OIS discounting, IBOR forwards (where
  applicable), SOFR/SONIA/€STR risk-free rate curves, cross-currency
  basis curves.
- **Curve operations:** parallel shift, key-rate shifts, twist,
  butterfly. The building blocks of bucket sensitivities.
- **Multi-instrument bootstrap:** given a set of market instruments
  (deposits, FRAs, swaps, futures) with prices, solve for the implied
  curve. Nonlinear root-find; gradient through the solve via implicit
  differentiation. A par swap carries its payment frequency explicitly; its
  fixed leg is valued over that coupon schedule, with discount factors at
  intermediate coupon dates read from the curve being built under the same
  interpolation the curve exposes, so the result reprices every input
  instrument. The gradient differentiates that same valuation. An instrument
  the valuation cannot represent (a tenor that is not a whole number of
  periods, or instrument tenors that are not strictly increasing) is rejected
  loudly rather than
  approximated.
- **Curve-derivative type:** the gradient of a price with respect to
  a `Curve` is a `Curve`-shaped object (per-pillar sensitivities), not
  an ad-hoc tensor. The type system carries this shape so downstream
  consumers preserve dimension labelling.

Interpolation methods to add beyond baseline: log-linear (standard for
discount factors), monotone cubic (Hyman, Steffen), Nelson-Siegel /
Svensson parametric forms.

### 2.8 `Shoals.VolSurface` (new module)

- **Surface representation:** strike × maturity grid; the canonical
  named-dimension shape is `tensor[strike, maturity, f32]`.
- **Interpolation:** SABR (Hagan analytic for short-maturity ATM),
  SVI (Gatheral parameterization), Heston-based (calibrated process),
  cubic in log-moneyness × maturity. Each interpolator is a typed
  surface that supports the same arithmetic ops as a tensor of the
  same shape.
- **Surface arithmetic:** parallel shifts, smile shifts, term-structure
  shifts. Each shift is differentiable in its scaling parameter.
- **Local volatility:** Dupire formula. Requires second-order
  derivatives of implied vol with respect to strike and time — depends
  on upstream higher-order AD (§3.4). **Doc-string and SKILL.md
  contract:** until that upstream theorem lands, users can evaluate
  local volatility (it's a well-defined formula on a smooth surface)
  but cannot differentiate through it for sensitivities. The doc
  string and SKILL.md entry for `local_vol_dupire` carry this warning
  explicitly so consumers don't silently chain it into a `grad(...)`
  computation that produces an incorrect gradient.
- **Implied volatility solver:** given option price, solve for implied
  vol. Inverse problem; implicit differentiation is the natural way to
  compute gradients of implied vol with respect to price (and on
  through to gradients with respect to underlying parameters).

### 2.9 `Shoals.Stochastic` (extended)

Baseline ships GBM with log-Euler path generation and antithetic
terminal-mean estimation. Extensions cover the SDE zoo quant finance
needs:

- **Local volatility processes:** GBM with state-dependent vol
  (Dupire-derived or piecewise-constant).
- **Stochastic volatility:** Heston (Andersen QE / full-truncation
  Euler — naive Euler fails Heston's positivity), SABR (path-level
  simulation, Hagan analytic for short maturity), Bates (Heston + jumps),
  Variance Gamma. Heston QE acceptance ships against a pinned stress
  configuration that exercises a Feller-condition violation:
  `kappa = 0.5`, `theta = 0.04`, `sigma = 1.0` (vol-of-vol),
  `rho = -0.9`, `v0 = 0.04`, `T = 5y`, `dt = 1/52`, 100k paths.
  Under these parameters `2*kappa*theta = 0.04 < sigma^2 = 1.0`, so
  variance can hit zero; QE must keep simulated variance non-negative
  and the characteristic-function price must agree with the MC price
  within MC noise.
- **Jump processes:** Merton lognormal jumps, Kou double-exponential
  jumps, abstract Lévy templates.
- **Interest-rate models:** Hull-White one-factor and two-factor
  (Gaussian short-rate), Libor Market Model with shifted-lognormal
  drift correction, HJM framework with the no-arbitrage drift.
- **Multi-asset correlated processes:** correlated Brownian motions
  for basket / quanto / spread products. Cholesky-based correlation
  injection from `Shoals.Distributions`.

Each simulator is differentiable with respect to model parameters
(volatility, mean reversion, correlation, jump intensity, jump-size
distribution parameters). The positivity-preserving schemes (Heston QE
in particular) preserve differentiability through the truncation /
reflection logic in a defined way; the alternative is to emit a
likelihood-ratio Greek (§2.11).

### 2.10 `Shoals.Pricing` (extended)

Baseline ships Black-Scholes call/put closed-form and Monte Carlo over
GBM paths. Extensions:

- **Closed-form solutions:** Bachelier (normal-distributed
  underlying — standard for negative-rate environments), Black
  (forward-priced — standard for caplets/floorlets), Garman-Kohlhagen
  (FX with two interest rates), Margrabe (exchange option), Magrabe-
  Stulz (exchange under stochastic correlation).
- **Tree methods:** Cox-Ross-Rubinstein binomial, Tian, Jarrow-Rudd
  binomial; trinomial trees. American exercise via backward induction
  with the early-exercise comparison. AD through trees uses
  pathwise-where-smooth + likelihood-ratio at the exercise boundary.
- **PDE methods:** Crank-Nicolson with Rannacher smoothing at the
  payoff discontinuity; ADI for two-dimensional problems (multi-asset
  or local vol + stochastic vol). **AD approach (spec-pinned):** the
  PDE solver differentiates via reverse-mode AD through the
  time-stepping loop, with the linear solve at each step replaced by
  an implicit-differentiation hook that emits adjoint(A) * v rather
  than re-solving inside the backward pass. This avoids the cost
  blow-up of naive AD-through-iterative-solve and is the same
  pattern used in Calcify's PDE engine when targeting Chelis. Forward
  mode is available where the user wants single-parameter sensitivity
  curves over time.
- **Monte Carlo with regression:** Longstaff-Schwartz for American /
  Bermudan options. Polynomial regression in the continuation value
  with documented basis-function choices. **AD approach
  (spec-pinned):** the regression coefficients at each exercise step
  are treated as outputs of an implicit problem (least-squares fit);
  gradients flow through them via implicit differentiation at the
  normal-equations optimum. AD does not differentiate through the
  full LSM algorithm including the regression refit — that path is
  numerically unstable when the exercise boundary moves with the
  parameter. Pathwise differentiation applies in the regions of state
  space where the optimal-exercise policy is locally constant;
  likelihood-ratio Greeks are emitted on the policy boundary
  (`Shoals.Greeks` §2.11 dispatch).
- **Fourier methods:** Heston pricing via characteristic functions
  with Lewis or Lipton inversion; Carr-Madan FFT pricing.

Each pricer is AD-compatible if the underlying primitives are; the
challenges are at discontinuities (early exercise, digital payoffs).
Shoals's API exposes pathwise and likelihood-ratio dispatch
explicitly (§2.11).

### 2.11 `Shoals.Greeks` (new module)

Quant teams need Greeks in specific patterns, not just "AD works". The
module is structured to make the patterns explicit:

- **First-order:** delta (spot), vega (vol), rho (rate), theta (time).
  Standard reverse-mode AD with respect to each parameter.
- **Second-order:** gamma (delta-spot), volga (vega-vol), vanna
  (delta-vol). Requires `grad(grad(...))` or `hessian(...)`. Alpha
  until upstream higher-order AD (§3.4) lands.
- **Cross-Greeks:** dDelta/dRate, dVega/dRate, etc. Mixed partials.
- **Bucket sensitivities:** delta per tenor of the rate curve, vega
  per pillar of the vol surface. Vector-valued gradients whose shape
  matches the underlying curve/surface (returned as
  `Curve[Differentiable[f64]]` / `Surface[Differentiable[f64]]`).
- **Pathwise vs likelihood-ratio dispatch:** smooth payoffs use the
  pathwise method (AD through MC paths); discontinuous payoffs
  (digital options, knock-out triggers, hard barriers) require
  likelihood-ratio Greeks because the path-derivative is undefined at
  the discontinuity. The module exposes `pathwise_greek` and
  `lr_greek` constructors; pricers that ship with mixed payoffs
  combine them per-component.
- **Reverse vs forward mode:** the module discloses per-function which
  mode is recommended:
  - Calibration (many parameters, scalar loss) → reverse.
  - Sensitivity grid (one parameter, many output time-buckets) →
    forward.
  - Mixed (vmap over portfolio of pricers × reverse over each) → both.

### 2.12 `Shoals.XVA` (new module)

XVA has its own structure that doesn't compress into a pricer-shaped
function. The module surface:

- **Exposure simulation:** generate `tensor[path, time, deal, f32]`
  exposures across counterparty paths. Memory and compute are the
  primary engineering concern; the differentiable surface is the
  expected-positive-exposure profile.
- **Netting and collateral:** compute netted exposure across CSA
  agreements. Threshold, minimum-transfer-amount, independent-amount
  handling. Variation and initial-margin haircut models.
- **Default modeling:** credit curves (CDS-implied survival
  probabilities), default probability term structure, stochastic and
  deterministic recovery rates.
- **XVA aggregation:** integrate exposure with default probabilities
  to compute CVA / DVA / FVA / KVA. Wrong-way risk via correlated
  default and exposure paths.
- **XVA sensitivities:** gradients with respect to market parameters.
  Production today uses bumping (finite differences) because AD
  through the full XVA computation is fragile. Replacing bumping with
  AD-correct sensitivities is the highest-value verified-AD outcome
  on the Shoals surface.

### 2.13 `Shoals.ModelFit` (new module)

- **Loss functions:** weighted least squares (vega-weighted is the
  standard for vol surfaces), weighted absolute differences, mixed.
- **Optimizers:** bound-constrained Levenberg-Marquardt (extends
  `Nautilus.CurveFit.lm_scalar_1param`), bound-constrained BFGS,
  sequential quadratic programming for inequality-constrained
  calibration.
- **Multi-target calibration:** fit one model to many products at
  once (e.g., SABR across an entire vol smile, or Heston to a strike
  × maturity grid).
- **Sequential calibration pipeline:** fit curves → surfaces → exotic
  parameters in a chained sequence where each stage's gradients flow
  into the next via implicit differentiation at the optimum.

### 2.14 `Shoals.Risk` (extended)

Baseline ships parametric/historical VaR and CVaR. Extensions:

- **Monte Carlo VaR:** simulate portfolio paths and quantile the loss
  distribution.
- **Expected shortfall:** under Basel FRTB conventions (97.5% ES) in
  addition to the existing 95%/99% VaR.
- **Scenario analysis:** PnL across a parameter grid (stress
  scenarios). Used for risk reporting.
- **Stress testing:** specific historical-replay scenarios (2008,
  COVID, rate-hike shocks).
- **Backtesting infrastructure:** Kupiec proportion-of-failures,
  Christoffersen conditional-coverage tests; ES backtests
  (Acerbi-Szekely). The implementation targets Basel FRTB-IMA
  (Internal Models Approach) requirements specifically — the 250-day
  rolling VaR / ES backtest window, the green / yellow / amber zone
  classification thresholds, and the model-eligibility ES backtest at
  97.5% — so regulated banks can use the same module surface in
  production.
- **Sensitivity-based VaR:** delta-gamma approximation using bucket
  sensitivities from `Shoals.Greeks`. Used when full revaluation is
  too expensive.

### 2.15 `Shoals.Indicators` (new module)

Technical indicators over `List[f64]` price and volume series. The module
exists because the indicator families below were absent from the whole
ecosystem (shoals#83) while being the most frequently hand-written
components measured in the Chelis-Lang/Voyage benchmark captures: true
range / ATR 179 programs, EMA recursion 125, RSI 111, "Wilder" smoothing
105, Bollinger 97, MACD 45, crossovers 30.

**The point of this module is not saved effort; it is that the
conventions disagree silently.** The same measurements found 100 of 115
hand-written EMAs seeding at the first price where TA-Lib seeds at the
SMA of the first window, about 105 programs calling their smoothing
"Wilder" while using `alpha = 2/(n+1)` rather than Wilder's `1/n`, and
ATR appearing in at least three variants. None of those disagreements
raises an error. They just produce different numbers. Every function in
this module therefore names its convention in its signature, and no
convention has a default.

#### 2.15.1 Convention types

Conventions are closed ADTs, not strings or integers, so an unhandled
convention is a type error rather than a silent fallback:

- `EmaSeed`: `SeedFirstValue` seeds the recursion at the first valid
  input and reports no warm-up beyond its input's own
  (pandas `ewm(..., adjust=False)`). `SeedSma` seeds at the arithmetic
  mean of the first `n` valid inputs and reports `n - 1` further
  warm-up entries (TA-Lib `EMA`).
- `Alpha`: `AlphaSpan` is `2 / (n + 1)` (pandas `span=n`).
  `AlphaWilder` is `1 / n` (Wilder 1978; TA-Lib `RMA`).
- `Smoothing` selects the averaging kernel for the derived indicators
  that admit more than one in the wild: `SmoothWilder` is
  `SeedSma` + `AlphaWilder`, `SmoothEma` is `SeedFirstValue` +
  `AlphaSpan`, and `SmoothSimple` is the rolling arithmetic mean over
  `n`. These are exactly the three ATR variants the measurements found.
- `Ddof`: `DdofPopulation` divides the rolling variance by `n`
  (TA-Lib `STDDEV`, and what Bollinger bands are defined against).
  `DdofSample` divides by `n - 1` (pandas `.std()` default). This pair
  is a distinct silent-drift axis from the smoothing ones: a Bollinger
  band computed with `DdofSample` is wider than the published
  definition at every point, and nothing reports it.

#### 2.15.2 Warm-up is represented, not filled

Every series-valued export returns `List[Option[f64]]` of exactly the
input length. Entries that no valid computation covers are `None`;
valid entries are `Some(v)`. Index `i` of the output corresponds to
index `i` of the input with no offset.

This is the structural form of the requirement, chosen over a flat
`List[f64]` plus a `valid_from` count and over a shortened list. A
`valid_from` field is ignorable, so a caller that drops it reads
warm-up filler as real data; a shortened list moves the alignment
burden to the caller, which is exactly where the measured off-by-one
and look-ahead defects appear (nautilus#85). `Option[T]` is `@pin` in
`docs/CHELIS_SURFACE.md`.

Warm-up lengths are part of the contract and are stated per function in
`src/indicators.ch`. No export reads any input index greater than its
own output index -- for the whole surface, not only where it is pinned.
Two properties check it executably rather than by inspection, by perturbing
only the last input and requiring every earlier output to be unchanged;
they cover `ema` and `rsi`. The committed suite does not pin the rest.
Review evidence for the unpinned exports belongs in the pull request record,
not here.

#### 2.15.3 Rolling layer (on loan from Nautilus)

`ind_rolling_sum`, `ind_rolling_mean`, `ind_rolling_std`,
`ind_rolling_min`, `ind_rolling_max`, `ind_shift` and `ind_diff` are
generic time-series primitives, not finance. They belong in Nautilus and
are requested there as nautilus#85. They live here, under an `ind_`
prefix that marks them as the borrowed layer, because the rolling family exists in exactly one place in the ecosystem and that copy does not serve `List[f64]`:
`Coral.Window` has `rolling_sum`, `rolling_mean`, `rolling_std`,
`rolling_min` and `rolling_max`, but only on `tensor[n, f32]`, and Coral is
not a compiled lane (coral#26). `Nautilus.TimeSeries` is not a second copy —
it has no rolling family at any width, only exponential smoothing and
AR/ARMA prediction (nautilus#70, shoals#72). `ind_shift` and `ind_diff`
duplicate nothing: neither package has a shift, lag or diff. Delete this
layer and re-export from Nautilus when nautilus#85 lands.

The rolling reductions re-sum each window rather than carrying a running
total. That is `O(n * w)` where a running total is `O(n)`, and it is the
deliberate choice: a running total accumulates cancellation error across
the whole series, and an indicator library whose whole purpose is that
the numbers agree with a named reference should not trade that away for
a constant factor at the window sizes these indicators use (`n` is 9, 12,
14, 20 or 26 in every convention cited here).

#### 2.15.4 Indicator surface

Each entry names the reference definition it matches. Where a reference
is ambiguous, the ambiguity is a convention argument rather than a
choice made inside the function.

- **`sma(xs, n)`** — rolling arithmetic mean. Warm-up `n - 1`.
- **`ema(xs, n, seed, alpha)`** — the exponential recursion
  `out[i] = a * xs[i] + (1 - a) * out[i-1]`, with `a` from `alpha` and
  the recursion's start from `seed`. Both pandas and TA-Lib are
  reachable; neither is the default.
- **`rma(xs, n)`** — Wilder's smoothing, defined as
  `ema(xs, n, SeedSma, AlphaWilder)`. Named separately because it is
  what "Wilder" means, and because naming it removes the most common
  measured error.
- **`true_range(high, low, close)`** — `max(h - l, |h - prev_c|,
  |l - prev_c|)` (Wilder 1978). Warm-up 1: the first bar has no
  previous close, and that is a `None`, not `h - l`.
- **`atr(high, low, close, n, smoothing)`** — `smoothing` applied to
  `true_range`. All three measured variants are reachable and named.
- **`rsi(close, n, smoothing)`** — `100 * g / (g + l)` for smoothed gain
  `g` and smoothed loss `l`, which is Wilder 1978's `100 - 100/(1 + RS)`
  rearranged. `SmoothWilder` is the published definition. **No movement at
  all reads 0**, guarding the sum exactly as TA-Lib's `ta_RSI.c` does; a
  monotone rise still reads 100, because there the sum is positive.
- **`macd(close, fast, slow, signal, seed, alpha)`** — returns
  `(line, signal_line, histogram)` in one pass so the three cannot
  drift apart. `line = ema(fast) - ema(slow)`,
  `signal_line = ema(line, signal)`, `histogram = line - signal_line`.
  Appel's original uses 12/26/9 with `AlphaSpan`.
- **`bollinger(close, n, k, ddof)`** — returns `(lower, mid, upper)`
  with `mid = sma(close, n)` and the bands at `mid -/+ k * sigma`
  (Bollinger 1980s; `n = 20`, `k = 2`, `DdofPopulation`).
- **`stochastic(high, low, close, k_n, d_n, smoothing)`** — returns
  `(k, d)`. `k = 100 * (c - min(low, k_n)) / (max(high, k_n) -
  min(low, k_n))`; `d` is `k` smoothed over `d_n` (Lane). A zero range
  is a defined case and is specified in the module, not left to
  division by zero. The module tests the range for exact zero; TA-Lib
  tests a scaled epsilon, so the two disagree on a sub-epsilon residue.
  See the note at the site.
- **`adx(high, low, close, n)`** — returns `(plus_di, minus_di, adx)`.
  Directional movement, Wilder-smoothed, then `DX` and `ADX = rma(DX)`
  (Wilder 1978). Wilder's smoothing is not a convention argument here
  because ADX is defined with it.
- **`donchian(high, low, n)`** — returns `(lower, mid, upper)`, the
  rolling low, midpoint and high over `n`.
- **`cumulative_vwap(price, volume)`** and
  **`rolling_vwap(price, volume, n)`** — volume-weighted average price,
  from the start of the series and over a rolling window.
- **`crossover(a, b)`** / **`crossunder(a, b)`** — `List[Option[bool]]`,
  true at `i` when `a` crosses `b` between `i-1` and `i`. `None`
  wherever either input is `None` at `i` or `i-1`, so a crossing is
  never reported out of a warm-up.

#### 2.15.5 Tensor-accepting forms

Every function in §2.15.3 and §2.15.4 has a tensor-accepting form, named by
prepending `tensor_` to the list name with no exceptions, so the name is
derivable by rule. They take `tensor[n, f64]` and return exactly what their
list counterparts return.

**The return type stays `List[Option[f64]]`.** §2.15.2 requires a
representation a caller cannot misread, and that is two requirements: the
absence marker must be **undroppable** and it must be **distinguishable** from
a computed value. They exclude different candidates, and both are needed.

Undroppable excludes every *sibling* channel — a scalar count, a parallel
validity tensor, a record field, a tuple component — since each can be
projected away, which is §2.15.2's drop hazard restated.
`(tensor[n, f64], tensor[n, bool])` is admissible to the type system and falls
here.

Distinguishable excludes an *in-element sentinel*. A NaN fill has no sibling to
drop, so the first requirement does not reach it; it is excluded because it
cannot be told apart from a computed value and propagates silently. **A
NaN-filled `tensor[n, f64]` return is rejected on this ground and not on the
other.**

A tensor element is a precision type, so absence in a tensor return must
either sit in a sibling or be a sentinel. Both are excluded, so no tensor
return satisfies §2.15.2, and `tensor[n, Option[f64]]` does not exist in any
case. The tensor admitted here is therefore the input.

`crossover` and `crossunder` consume masked series, so their tensor forms take
each side's warm-up as a required parameter, which cannot be dropped. That
closes the drop hazard and not the wrong-value one: an out-of-range warm-up is
an out-of-domain input and traps under §2.15.6.

The 1:1 correspondence between the two surfaces is a contract invariant and is
enforced mechanically, not by inspection.

#### 2.15.6 Out-of-domain inputs trap

A window or period below 1, and a multi-series call whose inputs have
unequal lengths, are domain errors and `fail(...)`. They are not
narrowings and carry no issue citation: there is no correct number to
return, and returning an all-`None` series would report "no data" for
what is a caller bug. `tests_neg/` covers each trap.

## 3. AD as a property — structural commitments

The functional surface is only half the verified-AD-for-quant-finance
story. The other half is the structural commitments that make the
verified claim available to consumers.

### 3.1 Type-level differentiability annotations

Each Shoals function annotates the differentiability of each parameter:

- `Differentiable[f64]` — gradient flows through this parameter.
- `Discrete[T]` (or just `Date`, `i64`, `String`, etc.) — gradient
  does not flow.
- `Curve[Differentiable[f64]]` — gradient returns a curve-shaped
  per-pillar sensitivity object.
- `Surface[Differentiable[f64]]` — gradient returns a surface-shaped
  per-pillar sensitivity object.

Illustrative signature:

```chelis
sig price_european:
  &spot: Differentiable[f64] ->
  &strike: Discrete[f64] ->
  &vol: Differentiable[f64] ->
  &rate: Differentiable[f64] ->
  &time: Differentiable[f64] ->
  Differentiable[f64]
```

This is forward-compatible with the upstream Chelis Phase D5
(Differentiability typing). Until D5 ships, Shoals expresses the
discipline through in-code conventions (parameter naming, doc strings,
explicit `wrt=` arguments at call sites); when D5 ships, Shoals
migrates to the type-checked annotations as a mechanical refactor.

### 3.2 Library-level AD correctness profile

Each differentiable Shoals function falls into exactly one of three
buckets, recorded in the SKILL.md API table and the in-source doc
string:

- **Composed (`AD: composed`):** the function is built entirely from
  primitives that are themselves verified-AD-correct (either by
  upstream LaCaDiLE proof, or by being deeper composition over such
  primitives). The verified-AD property holds by construction. No
  per-function proof obligation.
- **Unproven primitive (`AD: unproven-primitive`):** the function is a
  leaf — a specific RNG step, a specific Sobol direction-number table,
  a specific solver inner loop, a specific characteristic-function
  inversion contour. AD correctness is assumed (and FD-cross-checked
  in the property suite) but not proven. Each unproven primitive is
  enumerated in the Shoals trust manifest.
- **Type-system-unsupported (`AD: unsupported`):** the function
  contains control flow, effects, or higher-order patterns that the
  upstream AD theorems don't yet cover. Marked alpha with an explicit
  pointer to the upstream blocker (chelis D1 / D3 / higher-order /
  linearity / etc.).

Promotion from `unproven-primitive` to `composed` happens when the
underlying leaf gets a LaCaDiLE proof. Promotion from `unsupported`
happens when the relevant upstream theorem closes. The annotations
are durable; they don't decay silently because the SKILL.md table is
exercised by the milestone red-team checklist.

### 3.3 Process-pricer AD pairing matrix

The Stochastic (§2.9) × Pricing (§2.10) cross-product is enumerated
explicitly so that AD discipline at the process-pricer integration
point is decided in the spec, not negotiated at merge time when M4
and M5 packets parallelize.

Each cell of the matrix is one of:

- **`P` (pathwise):** AD flows through the path-generation loop
  using the pathwise method. Valid when the payoff is smooth in the
  parameters being differentiated.
- **`L` (likelihood-ratio):** AD flows via the score function of
  the distribution. Used when the payoff has a discontinuity (digital,
  barrier, knock-out) and the pathwise derivative is undefined at
  the discontinuity.
- **`P/L` (dispatched):** the API exposes both; the user selects via
  `pathwise_greek(...)` or `lr_greek(...)`. The default is `P` when
  the payoff is detectably smooth at type level, `L` otherwise.
- **`A` (analytic/transform):** AD goes through a closed-form or
  characteristic-function expression directly, not through path
  generation. Heston FFT is the canonical case.
- **`IFT` (implicit-function theorem):** the pricer involves a solve
  (American boundary, implicit-vol root-find); AD goes through the
  optimality conditions, not through the iterative solver.
- **`—`:** combination is not supported by Shoals; calling it is a
  type or stability error.

| Process \ Pricer | Closed-form | Tree | PDE | MC (path) | LSM | Fourier |
|---|---|---|---|---|---|---|
| GBM | A | P/L | P (adjoint PDE) | P/L | IFT+P | A |
| Local vol | — | P | P (adjoint PDE) | P | IFT+P | — |
| Heston | — | — | P (adjoint PDE, 2-D ADI) | P/L | IFT+P | A |
| SABR | A (Hagan) | — | — | P | — | A |
| Jump-diffusion (Merton/Kou) | A | — | — | P/L | IFT+L | A |
| Hull-White 1F/2F | A | P | P (adjoint PDE) | P | IFT+P | A |
| LMM | — | — | — | P | IFT+P | — |
| HJM | — | — | — | P | IFT+P | — |
| Multi-asset GBM | A (Margrabe) | — | P (adjoint ADI) | P/L | IFT+P | — |

Cells marked `—` aren't shipped in Shoals v0.x; they're noted so a
later milestone can extend deliberately rather than backfill
ad hoc. Cells that depend on upstream theorems (any `P/L` involving
`Random` effect composition, any IFT involving control-flow AD)
carry the `AD: unsupported` annotation per §3.2 until the upstream
work closes.

### 3.4 Higher-order AD

Second-order Greeks (gamma, volga, vanna) require second-order AD.
Local volatility (Dupire) requires second-order AD of implied vol
with respect to strike and time. Some exotic Greek patterns require
third- or fourth-order.

Shoals exposes `grad(grad(...))` and `hessian(...)` patterns whose
runtime correctness depends on the upstream higher-order AD theorem.
Until that theorem closes, Shoals's second-order Greek functions are
alpha and gated behind finite-difference cross-checks in the property
suite.

### 3.5 AD through Chelis effects

Quant finance code uses effects:

- **`Random`** for Monte Carlo paths. Pathwise differentiation must
  compose with the seed-tracking effect handler so that gradient
  estimates inherit reproducibility.
- **`Raises`** for numerical failures (square root of negative
  variance, divergent root-find). AD must thread through error
  paths without losing the gradient when the function falls back to
  a finite value.
- **`State`** for cached intermediate values during sequential
  calibration.

Shoals's API surface declares its AD compatibility profile per
effect. Runtime correctness depends on the upstream Chelis Phase D3
(effect-aware AD) theorem.

### 3.6 Linearity-AD interaction

chelis-std tensors carry linearity discipline. Functions that consume
tensors with linear semantics need AD that handles linearity
correctly. Shoals's tensor-shaped surface (curves, surfaces, paths)
inherits linearity from chelis-std. The interaction is upstream-owned
(Chelis Phase 2 linearity × AD).

### 3.7 Reverse-mode and forward-mode

Each Shoals exported function documents its preferred AD mode in the
SKILL.md table:

- **Calibration loss:** reverse (many parameters → scalar loss).
- **Sensitivity grid:** forward (single parameter → many outputs).
- **Per-portfolio Greeks:** `vmap` over the portfolio dimension,
  reverse inside each pricer.
- **XVA gradients:** reverse over market parameters, with `vmap` over
  paths.

## 4. Upstream dependencies

The verified half of the verified-AD claim depends on upstream Chelis
and LaCaDiLE work. Shoals can build the functional surface ahead of
these; the "verified" label flips on per-module as the upstream
theorems close.

| Dep | Upstream owner | Shoals consequence |
|---|---|---|
| Control-flow AD (chelis D1) | chelis monorepo | American exercise, path triggers, regression-based Bermudans become verifiably differentiable |
| AdjointTyping theorem | LaCaDiLE | First-order AD becomes a verified language property |
| Higher-order AD theorem | LaCaDiLE | Second-order Greeks become verifiably correct |
| Effect-AD theorem (chelis D3) | chelis monorepo + LaCaDiLE | AD through `Random` / `Raises` / `State` becomes verified |
| Linearity-AD theorem | chelis monorepo + LaCaDiLE | AD through linear tensors becomes verified |

Until each closes, the corresponding Shoals modules ship at alpha
with their AD path covered by finite-difference cross-checks in
`properties/` rather than by upstream-proof inheritance.

## 5. Acceptance oracle extensions

The baseline `phase3l_shoals_oracle` (BS + MC European call, seed
reproducibility) is one of a family of oracles. The extended surface
ships with additional oracles, each a separate manual gate at the
chelis-cli side:

- `phase3l_shoals_oracle_multi_curve_bootstrap` — multi-curve OIS +
  SOFR bootstrap reproduces market instruments within 1bp.
- `phase3l_shoals_oracle_vol_surface_round_trip` — implied-vol solver
  round-trip on SVI / SABR surfaces.
- `phase3l_shoals_oracle_heston_qe` — Heston QE scheme preserves
  variance positivity; characteristic-function and MC prices agree.
- `phase3l_shoals_oracle_xva_smoke` — CVA on a netted two-deal
  portfolio matches an analytic benchmark.
- `phase3l_shoals_oracle_calibration_smoke` — Constrained LM fits
  SABR to a 5-strike smile within tolerance.
- `phase3l_shoals_oracle_greeks_bucket` — per-pillar curve delta sums
  to the parallel-shift delta.
- `phase3l_shoals_oracle_es_backtest` — Kupiec and Christoffersen
  tests on empirical ES with a known data-generating process.

Default per-PR scope remains `chelis test tests/`; the oracles are
manual gates exercised at milestone exits.

## 6. Test plan extensions

The baseline test plan in `phase3l.md` covers BS, MC, parametric VaR,
linear/cubic curve, GBM, and orderbook invariants. Extension tests
follow the same shape (correctness + reproducibility + property
agreement). The new module additions each carry:

- A reference implementation under `references/` (textbook formula).
- Property functions under `properties/` comparing optimized `src/`
  output to the reference.
- Tests under `tests/` exercising the property bodies as ordinary
  `Test` functions until `chelis fuzz` ships first-class `@property`
  support.

## 7. Effort

The surface is bounded but substantial — volume, not novelty. Each
pricer is a function; each calibration is an optimizer; each curve is
a data structure with operations. See `docs/plan-quant-surface.md`
for the milestone breakdown, work-packet allocation, and red-team
exit checkpoints.
