# Introduction

Shoals is a quantitative-finance library for the
[Chelis](https://github.com/Chelis-Lang/chelis) programming language. It
is available as a Reef package under the `Shoals` module prefix. It provides
closed-form option pricers, Greeks, Monte Carlo engines, yield-curve and
volatility-surface tooling, risk measures, date and calendar arithmetic,
an order book, and a small set of finance-specific distributions.

The library is written entirely in Chelis. Numerical primitives that are
not finance-specific (the normal distribution, special functions,
statistics, interpolation) come from `Nautilus`, and the date type comes
from `Std.Datetime`.

## Modules

- **Pricing.** Black-Scholes call and put, vectorized price tensors, and a
  Monte Carlo engine driven by explicit random keys.
- **Greeks.** Finite-difference first- and second-order Greeks, analytic
  Greek references for cross-checking, and pathwise / likelihood-ratio
  estimators for the digital payoff family.
- **Extended pricers.** Bachelier (normal underlying), Black (forward),
  Garman-Kohlhagen (FX), Margrabe and Stulz (exchange), and digital options.
- **Volatility surface.** SVI total-variance parameterization, implied
  vol, surface shifts, a SABR approximation, and a bisection implied-vol solver.
- **Stochastic processes.** Geometric Brownian motion paths and terminals,
  antithetic variates, Merton and Kou jump-diffusion, Heston
  quadratic-exponential simulation, and correlated two-asset GBM.
- **Risk.** Parametric and historical value-at-risk and conditional VaR.
- **Extended risk.** Monte Carlo VaR and expected shortfall, an FRTB-IMA
  expected-shortfall helper, a scenario PnL grid, and the Kupiec
  proportion-of-failures, Christoffersen, and Acerbi-Szekely backtests.
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
- **Distributions.** Lognormal, Student-t, and bivariate-normal densities,
  gamma, beta, chi-squared, exponential, uniform, and Poisson wrappers, and
  a multivariate-normal sampler.
- **Calibration.** Weighted residuals, sum-of-squared-errors loss, and
  bounded Levenberg-Marquardt and BFGS fits.
- **XVA.** Exposure aggregation, netting, CVA and DVA, plus funding and
  capital adjustment helpers.
- **Currency-tagged money.** Runtime-tagged `Money` with same-currency
  arithmetic.

- **Lattices, PDEs, and early exercise.** CRR, Tian, Jarrow-Rudd, and
  trinomial trees (`Shoals.Trees`), Crank-Nicolson and ADI finite
  differences (`Shoals.Pde`), Longstaff-Schwartz (`Shoals.Lsm`), and
  fixed-coupon bond prices (`Shoals.FixedIncome`).
- **Rate and volatility models.** One- and two-factor Hull-White
  short-rate models (`Shoals.HullWhite`), the LIBOR market model and HJM drift
  (`Shoals.LiborMarketModel`), SABR paths (`Shoals.SabrPaths`), Heston
  Fourier pricers (`Shoals.Heston`), and Dupire local volatility
  (`Shoals.Dupire`).
- **Credit default swaps.** Hazard curves, CDS legs, and a par-spread
  bootstrap (`Shoals.Cds`).
- **Quasi-random points.** Sobol and Halton sequences and variance-reduction
  estimators (`Shoals.Rng`), in the stochastic-processes chapter.
- **Collateral.** CSA threshold, minimum transfer, and haircut
  (`Shoals.Csa`), in the XVA chapter.

Each module chapter gives its public functions with their signatures, input
domains, and failure behavior.

## Comparisons and supported domains

The [Reference oracles](references.md) and
[Property specifications](properties.md) chapters describe
comparisons with standard formulas and finance relationships. The
[Scope and limitations](scope.md) chapter summarizes the supported
models and numerical domains.

## Start with a pricing call

Start with [Getting started](getting-started.md) for the build commands and
a first pricing call, then read
[Working with tensors and keys](conventions.md) for tensor
ownership and reproducible random calls. Each module chapter includes its public
functions and examples.
