# Scope and limitations

This chapter is the honest account of where the Shoals surface stops. It
describes the boundaries of what the library does, so you know what to build
on top of and what to reach for elsewhere. Everything here is drawn from the
source in this checkout.

## Numerical precision

Every numeric quantity in Shoals is a 32-bit float (`f32`). Prices, rates,
volatilities, exposures, and intermediate sums all carry single-precision
rounding. The test tolerances reflect this: closed-form prices are checked to
around a thousandth, and Monte Carlo convergence is checked to a couple of
percent. If you need tighter agreement than single precision supports, that
is outside what these functions provide.

## Pricing and Greeks

- The Black-Scholes pricers assume a non-dividend-paying underlying. There is
  no dividend yield or borrow argument.
- The Greeks in `Shoals.Greeks` are finite-difference estimates that take an
  explicit bump size, plus analytic references for the call's delta, vega,
  gamma, and the put delta. There is no analytic theta or rho exposed in that
  module; the textbook theta and rho live among the
  [reference oracles](references.md).
- The gradient-derived sensitivity paths in `Shoals.Pricing` differentiate the
  displayed price through `grad`: one f64 normal CDF sits behind both the price
  and every Greek, so a Greek is the automatic-differentiation derivative of the
  price the same module returns. First-order: `deltas_call`, `deltas_put`,
  `vegas_call`, `rhos_call`, `thetas_call`. Second-order (via nested grad on
  chelis 0.10.1): `gammas_call`, `volgas_call`, `vannas_call`. All are validated
  against the analytic and finite-difference oracles by
  `scripts/oracle_greeks_gate.py` and carry in-suite `Std.Test` standing
  assertions (the heavy second-order grad assertions live in
  `tests-manual/greeks_secondorder.ch`). The finite-difference Greeks in
  `Shoals.Greeks` remain a separate, independently exercised oracle.

## Curves

- `bootstrap_zero_from_par` handles the single-curve case with one coupon per
  pillar at integer-year spacing. A multi-instrument bootstrap that solves
  deposits, FRAs, futures, and swaps together in one joint solve is not part
  of this surface.
- The day-count year fraction is available in `Shoals.Date`, but the curve
  interpolators take maturities directly as `f32` year fractions; they do not
  consult a calendar.

## Dates, tenors, and calendars

- Month and year tenors use fixed thirty-day and three-hundred-sixty-five-day
  approximations. `tenor_apply` and `schedule_from_tenor` therefore do
  calendar-day arithmetic, not calendar-aware month stepping, and a generated
  schedule lands on thirty-day multiples rather than on month-end dates.
- Tenors are constructed programmatically (`days_n`, `weeks_n`, `months_n`,
  `years_n`, and the overnight family). Parsing a tenor from a string is not
  part of this surface.
- The bundled holiday tables are New York and London for the 2025 calendar
  year. Other centers and years are not included; build a `Calendar` from your
  own holiday list with `empty_calendar` and the constructors, or combine
  calendars with `joint_calendar`.
- The business-day rolling in `Shoals.Date` skips weekends only; it does not
  consult a holiday calendar. Holiday-aware business-day logic is in
  `Shoals.HolidayCal` through `is_business_day`, which you apply yourself.

## Stochastic processes

- The Merton jump-diffusion terminal uses an aggregate-jump Gaussian
  approximation: the total jump contribution over the horizon is drawn as a
  single Gaussian per path rather than as a compound Poisson sum of discrete
  jumps.
- Correlation across assets is supported for the two-asset case through a
  two-by-two Cholesky factor. There is no general n-asset correlated draw.

## Risk

- The Monte Carlo VaR and expected shortfall in `Shoals.RiskExt` are computed
  from the empirical loss distribution and delegate to the historical
  measures in `Shoals.Risk`. They summarize a loss sample you supply; they do
  not run the simulation that produces it.

## Currency

- `Shoals.CurrencyTag` supports US dollars, pounds sterling, and euros.
  Same-currency addition and subtraction are checked at runtime and fail on a
  currency mismatch rather than converting implicitly. Cross-currency
  arithmetic goes through `convert` with a rate you provide.

## XVA

- The credit model is a constant hazard rate. Term-structured hazard,
  wrong-way risk, and collateral are not modeled. Netting is the pointwise
  sum of two deals.

## Property checks

The functions in `properties/` are written as plain boolean functions that
the test suite calls on fixed input grids. They state the invariants the
library is expected to satisfy and confirm them on those grids. They are not
randomized or exhaustively searched within this checkout; treat them as a
specification of intended behavior, checked at the sampled points the tests
use.
