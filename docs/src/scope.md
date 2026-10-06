# Scope and limitations

Shoals implements particular models and numerical methods. Check inputs against each function's assumptions; most constructors and pricers do not validate market data.

## Precision and pricing

Most public finance values are `f32`, including curve rates, risk measures, and money amounts. `Shoals.Pricing` also exports `f64` Black-Scholes kernels and a tensor-valued `bs_call_wire_f64`; the scalar `f32` prices are converted from the `f64` pricing body. The two `f64` entries use different normal-CDF approximations and agree within the bounded comparison exercised in `tests/pricing.ch`, not by exact identity. `n_cdf64` loses relative precision in the far negative tail. Use the price and sensitivity oracles for the domain you need.

Black-Scholes here assumes a non-dividend-paying underlying and positive spot, strike, volatility, and maturity. It has no dividend-yield input. `Shoals.Greeks` provides bump-based sensitivities, while `Shoals.Pricing` exports derivatives of its own displayed price. Their source tests compare representative points with analytic and finite-difference results; they do not certify every market input. The implied-vol solver in `Shoals.VolSurface` searches a fixed volatility bracket by default and returns a NaN sentinel when its strict sign-change test fails. Supply positive maturity and valid SVI/SABR parameters; the surface constructors do not enforce admissibility.

`Shoals.Dupire` evaluates the Dupire local-volatility formula by finite differences over a call surface and returns a `NaN` sentinel where the implied density is not positive; `du_is_local_vol_sentinel` tests for it. Its grid interpolator `du_cubic_log_moneyness_interp` requires **both** grid axes to be strictly increasing: it rejects `strikes` or `times` that are not, naming the axis and the first offending index, and it never re-sorts an axis or permutes `iv_grid` to match. A repeated value and a `NaN` among two or more entries are rejected by the same comparison; a one-row surface has no time pair to compare, so a lone `NaN` time is accepted and reads flat in time, and the same holds for a lone `NaN` strike on a one-column grid. `+inf` and `-inf` entries are also accepted, because they *are* strictly increasing: a `+inf` last grid time interpolates normally, while a `-inf` first grid time returns a bare `NaN` that `du_is_local_vol_sentinel` is not applied to and nothing traps. Non-finite entries are a separate question from ordering and this guard does not reach them.

## Curves and dates

`bootstrap_zero_from_par` assumes annual coupons and integer-year pillars. `bootstrap_multi` accepts deposits, zero-coupon bonds, and par swaps in strictly increasing tenor order; it solves one pillar at a time. Its swap dates are year fractions rather than calendar-rolled dates. Invalid instruments or order raise an error, and so does a quote whose zero rate falls outside the `[-0.5, 2.0]` search bracket, a residual that is not finite over it, a solve that does not converge, and a `paths_template` whose length does not match the instrument list; none of these returns a NaN sentinel (shoals#79). Widening the bracket is a separate question: a quote outside it is rejected, not re-solved. `Shoals.Curves` uses `f32` rates and maturities. Basis-curve helpers are also exported, but there is no general joint multi-curve solve.

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
[Holiday calendars](calendars.md) for which calendar replaces each removed
local list.

## Simulation, risk, and valuation adjustments

Random draws take an explicit key, which can be derived from a seed. `Shoals.Stochastic.merton_jump_terminal` uses an aggregate Gaussian approximation to jump totals rather than drawing a compound Poisson process. Its correlated GBM helper covers two assets. `Shoals.Rng` has committed Sobol direction numbers for 32 dimensions; higher runtime dimensions use a fallback sequence up to the exposed limit. These choices matter for convergence studies.

`Shoals.Risk` computes Gaussian parametric or sample-based empirical VaR and expected shortfall from **losses** supplied by the caller. `Shoals.RiskExt.mc_var` and `mc_expected_shortfall` summarize supplied simulated losses; they do not generate paths. Use nonempty samples and confidence levels strictly between zero and one. Currency tags in `Shoals.CurrencyTag` are checked at runtime. Converting money requires an exchange rate from the caller.

The Gaussian parametric functions use a sample standard deviation with
one degree of freedom, so supply at least two losses for them.

`Shoals.Xva` has constant-hazard CVA/DVA, a hazard-curve CVA, funding and capital adjustment helpers, and a sampled constant-hazard wrong-way-risk estimator. Exposures and times are supplied by the caller. The time-grid methods assume increasing times, suitable exposure values and recovery rates, and do not model collateral. Pointwise netting handles two deals. `Shoals.Orderbook` sorts orders by price, without matching or quantity validation; best prices on an empty side and VWAP for an empty book use NaN sentinels.

## What the checks establish

`tests/` exercises fixed and sampled inputs. `properties/` contains predicates and selected `@property` checks. A `fuzz_validated` result is a seeded sample result, not an exhaustive proof. Some composite properties prove a formula under a separate normal-CDF contract; their sampled comparison with the shipped pricer does not make the two CDF implementations identical. See [Property specifications](properties.md) and the machine-readable `docs/cnote-import-surface.json` for the reported methods and bounds.
