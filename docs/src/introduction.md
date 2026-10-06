# Introduction

Shoals is a quantitative-finance library for the
[Chelis](https://github.com/Chelis-Lang/chelis) programming language. It
ships as a reef package under the `Shoals` module prefix and gives you
closed-form option pricers, Greeks, Monte Carlo engines, yield-curve and
volatility-surface tooling, risk measures, date and calendar arithmetic,
an order book, and a small set of finance-specific distributions.

The library is written entirely in Chelis. Numerical primitives that are
not finance-specific (the normal distribution, special functions,
statistics, interpolation) come from the upstream `Nautilus` library, and
the standard date type comes from `Std.Datetime`. Shoals layers the finance
semantics on top: Black-Scholes, the FX and forward pricers, SVI vol
surfaces, sensitivity operators on curves, XVA aggregators, and so on.

## What is in the box

The chapters introduce the main modules and point to their source tests:

- **Pricing.** Black-Scholes call and put, vectorized price tensors, and a
  Monte Carlo engine driven by explicit random keys.
- **Greeks.** Finite-difference first- and second-order Greeks, analytic
  Greek references for cross-checking, and pathwise / likelihood-ratio
  estimators for the digital payoff family.
- **Extended pricers.** Bachelier (normal underlying), Black (forward), 
  Garman-Kohlhagen (FX), and Margrabe (exchange).
- **Volatility surface.** SVI total-variance parameterization, implied
  vol, surface shifts, a SABR approximation, and a bisection implied-vol solver.
- **Stochastic processes.** Geometric Brownian motion paths and terminals,
  antithetic variates, Merton jump-diffusion, and correlated two-asset GBM.
- **Risk.** Parametric and historical value-at-risk and conditional VaR.
- **Extended risk.** Monte Carlo VaR and expected shortfall, an FRTB-IMA
  expected-shortfall helper, a scenario PnL grid, and the Kupiec
  proportion-of-failures backtest statistic.
- **Yield curves.** Linear, spline, log-linear, and Nelson-Siegel-Svensson
  interpolation, discount factors, a single-curve par bootstrap, a
  deposit/zero-coupon/par-swap instrument bootstrap with IFT sensitivities, curve-kind
  metadata, and sensitivity operators.
- **Dates, tenors, schedules.** Exact-rational day-count conventions,
  calendar-month tenors, business-day money-market tenors and spot lags,
  and anchored coupon schedules, over `Std.Datetime` and Shoreleave market
  calendars.
- **Market data.** Quote, bar, and snapshot record types.
- **Order book.** A price-priority limit order book with best bid and ask,
  spread, and volume-weighted average price.
- **Distributions.** Lognormal, Student-t, and bivariate-normal densities.
- **Calibration.** Weighted residuals, sum-of-squared-errors loss, and a
  bound-clamped Levenberg-Marquardt step.
- **XVA.** Exposure aggregation, netting, CVA and DVA, plus funding and
  capital adjustment helpers.
- **Currency-tagged money.** Runtime-tagged `Money` with same-currency
  arithmetic.

Additional modules under `src/` cover lattice and PDE pricing,
fixed-income models, collateral agreements, credit curves, local
volatility, Longstaff–Schwartz exercise, and specialized stochastic
processes. Their exported definitions and `tests/` or `tests-manual/`
files give their exact signatures and numerical domains.

## Verification

Shoals carries two top-level directories of comparison code:

- `references/` holds textbook-formula implementations for selected
  quantities (Black-Scholes, its Greeks, Vasicek, historical VaR, vanilla
  Monte Carlo, distributions, and day-count conventions).
- `properties/` holds checks for finance relationships such as put-call
  parity, finite-difference Greek agreement, Monte Carlo reproducibility,
  and comparisons with textbook formulas. Tests exercise selected inputs.

The [Reference oracles](references.md) and
[Property specifications](properties.md) chapters describe both. The
[Scope and limitations](scope.md) chapter is the honest account of where
the surface stops.

## How to read this book

Start with [Getting started](getting-started.md) for the build commands and
a first pricing call, then read
[Working with tensors and effects](conventions.md) to understand the small
number of Chelis idioms the examples lean on. After that the module
chapters stand on their own and can be read in any order.
