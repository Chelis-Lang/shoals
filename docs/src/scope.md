# Scope and limitations

Shoals implements particular models and numerical methods. Check inputs against each function's assumptions; most constructors and pricers do not validate market data.

## Precision and pricing

Most public finance values are `f32`, including curve rates, risk measures, and money amounts. `Shoals.Pricing` also exports `f64` Black-Scholes kernels and a tensor-valued `bs_call_wire_f64`; the scalar `f32` prices are converted from the `f64` pricing body. The scalar kernels use Chelis's `standard_normal_cdf`, which retains relative precision in the negative tail. `bs_call_wire_f64` evaluates caller-supplied Abramowitz-Stegun coefficients, so it agrees with the scalar path within a bounded tolerance, not by exact identity. Use the price and sensitivity oracles for the domain you need.

Black-Scholes here assumes a non-dividend-paying underlying and positive spot, strike, volatility, and maturity. It has no dividend-yield input. `Shoals.Greeks` provides bump-based sensitivities, while `Shoals.Pricing` exports derivatives of its own displayed price. The implied-vol solver in `Shoals.VolSurface` searches a fixed volatility bracket by default and returns a NaN sentinel when its strict sign-change test fails. Supply positive maturity and valid SVI/SABR parameters; the surface constructors do not enforce admissibility.

`Shoals.Dupire` evaluates local volatility by finite differences over a call
surface. It returns a NaN sentinel where the implied density is not positive;
`du_is_local_vol_sentinel` tests for it.

`du_cubic_log_moneyness_interp` requires strictly increasing `strikes` and
`times`. A failure names the axis and first offending index. The function
does not sort axes or permute `iv_grid`. Duplicate values and NaN entries in
an axis of length two or more fail the comparison. A single-entry axis has
no adjacent pair to check, so a lone NaN is accepted and reads flat on that
axis. The ordering guard also admits infinities when adjacent comparisons
pass: a final `+inf` time interpolates normally, while an initial `-inf` time
returns NaN without a trap or a call to `du_is_local_vol_sentinel`.
Validate finiteness separately.

## Curves and dates

`bootstrap_zero_from_par` assumes annual coupons and integer-year pillars. `bootstrap_multi` accepts deposits, zero-coupon bonds, and par swaps in strictly increasing tenor order; it solves one pillar at a time. Its swap dates are year fractions rather than calendar-rolled dates. Invalid instruments or order raise an error, as do quotes outside the `[-0.5, 2.0]` search bracket, non-finite residuals, failures to converge, or a `paths_template` whose length does not match the instrument list. `Shoals.Curves` uses `f32` rates and maturities. Basis-curve helpers are also exported, but there is no general joint multi-curve solve.

`Shoals.Cds` uses `f32` elapsed year times. Its hazard-curve constructor and
bootstrap reject non-increasing pillars, and the curve is opaque so a caller
cannot bypass that check with a record literal. See [Credit default swaps](cds.md).

`Shoals.Tenor` tenors are `Std.Datetime` periods, so a month is a calendar month; applying one, and every schedule, takes an explicit `DayOverflow` policy. ON, TN, and SN are business-day tenors, and spot lags count in one calendar and roll in another. `Shoals.Schedule` steps from a fixed anchor with explicit stub and end-of-month arguments and rolls its dates only when given a calendar. `parse_tenor` accepts only a positive count followed by uppercase `D`, `W`, `M`, or `Y`; anything else fails.

`Shoals.Date.year_fraction` returns an exact rational `YearFraction`, converted to `f64` or `f32` by one correctly rounded step; `Shoals.Curves` remains `f32`, so a caller mixing them converts at the boundary. A convention's extra inputs are required fields of its variant: ACT/ACT ICMA takes the reference period and frequency and fails on an accrual outside that period, 30E/360 ISDA takes the maturity, 30/360 US the end-of-month flag, and BUS/252 a business calendar. ACT/ACT AFB is not provided.

`Shoals.Distributions` assumes valid distribution parameters,
including positive scales and degrees of freedom and an admissible
correlation; its constructors do not check them.

Shoals has no holiday tables of its own. Business calendars are
`Std.Datetime.Business.BusinessCalendar` values from Shoreleave (US federal,
NYSE, SIFMA, England and Wales, Japan Bank, New South Wales, Hong Kong, and
TARGET); their dates and weekmasks come from published sources, and queries
outside each horizon fail. There is no Frankfurt exchange calendar. See
[Holiday calendars](calendars.md) for which calendar fits each
market.

## Simulation, risk, and valuation adjustments

Random draws take an explicit key, which can be derived from a seed. `Shoals.Stochastic.merton_jump_terminal` draws a compound Poisson jump count over a finite enumerated slot table sized on `lambda * t * exp(jump_mean + 0.5 * jump_vol^2)`, and refuses an intensity whose table would exceed the slot cap; `Shoals.Stochastic.sto_kou_jump_terminal` approximates its jump count by thinning a fixed number of slots. Its correlated GBM helper covers two assets. `Shoals.Rng` has committed Sobol direction numbers for 32 dimensions; higher runtime dimensions use a fallback sequence up to the exposed limit. These choices matter for convergence studies.

`Shoals.Risk` computes Gaussian parametric or sample-based empirical VaR and expected shortfall from **losses** supplied by the caller. `Shoals.RiskExt.mc_var` and `mc_expected_shortfall` summarize supplied simulated losses; they do not generate paths. Use nonempty samples and confidence levels strictly between zero and one. Currency tags in `Shoals.CurrencyTag` are checked at runtime. Converting money requires an exchange rate from the caller.

The Gaussian parametric functions use a sample standard deviation with
one degree of freedom, so supply at least two losses for them.

`Shoals.Xva` has constant-hazard CVA/DVA, a hazard-curve CVA, funding and capital adjustment helpers, and a sampled constant-hazard wrong-way-risk estimator. Exposures and times are supplied by the caller. The time-grid methods assume increasing times, suitable exposure values and recovery rates, and do not model collateral. Pointwise netting handles two deals. `Shoals.Orderbook` sorts orders by price, without matching or quantity validation; best prices on an empty side and VWAP for an empty book use NaN sentinels.

## What the mathematical claims establish

Shoals documents assumptions for its models and formulas. A result checked at
selected inputs is evidence for those inputs, not an exhaustive proof. Some
properties are proved over the reals under stated assumptions; that does not
establish floating-point behavior for every execution. See
[Property specifications](properties.md) for the property types and
their limits.
