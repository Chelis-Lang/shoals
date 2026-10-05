# Scope and limitations

Shoals implements particular models and numerical methods. Check inputs against each function's assumptions; most constructors and pricers do not validate market data.

## Precision and pricing

Most public finance values are `f32`, including curve rates, risk measures, and money amounts. `Shoals.Pricing` also exports `f64` Black-Scholes kernels and a tensor-valued `bs_call_wire_f64`; the scalar `f32` prices are converted from the `f64` pricing body. The two `f64` entries use different normal-CDF approximations and agree within the bounded comparison exercised in `tests/pricing.ch`, not by exact identity. `n_cdf64` loses relative precision in the far negative tail. Use the price and sensitivity oracles for the domain you need.

Black-Scholes here assumes a non-dividend-paying underlying and positive spot, strike, volatility, and maturity. It has no dividend-yield input. `Shoals.Greeks` provides bump-based sensitivities, while `Shoals.Pricing` exports derivatives of its own displayed price. Their source tests compare representative points with analytic and finite-difference results; they do not certify every market input. The implied-vol solver in `Shoals.VolSurface` searches a fixed volatility bracket by default and returns a NaN sentinel when its strict sign-change test fails. Supply positive maturity and valid SVI/SABR parameters; the surface constructors do not enforce admissibility.

`Shoals.Dupire` evaluates the Dupire local-volatility formula by finite differences over a call surface and returns a `NaN` sentinel where the implied density is not positive; `du_is_local_vol_sentinel` tests for it. Its grid interpolator `du_cubic_log_moneyness_interp` requires **both** grid axes to be strictly increasing: it rejects `strikes` or `times` that are not, naming the axis and the first offending index, and it never re-sorts an axis or permutes `iv_grid` to match. A repeated value and a `NaN` among two or more entries are rejected by the same comparison; a one-row surface has no time pair to compare, so a lone `NaN` time is accepted and reads flat in time, and the same holds for a lone `NaN` strike on a one-column grid. `+inf` and `-inf` entries are also accepted, because they *are* strictly increasing: a `+inf` last grid time interpolates normally, while a `-inf` first grid time returns a bare `NaN` that `du_is_local_vol_sentinel` is not applied to and nothing traps. Non-finite entries are a separate question from ordering and this guard does not reach them.

## Curves and dates

`bootstrap_zero_from_par` assumes annual coupons and integer-year pillars. `bootstrap_multi` accepts deposits, zero-coupon bonds, and par swaps in strictly increasing tenor order; it solves one pillar at a time. Its swap dates are year fractions rather than calendar-rolled dates. Invalid instruments or order raise an error, and so does a quote whose zero rate falls outside the `[-0.5, 2.0]` search bracket, a residual that is not finite over it, a solve that does not converge, and a `paths_template` whose length does not match the instrument list; none of these returns a NaN sentinel (shoals#79). Widening the bracket is a separate question: a quote outside it is rejected, not re-solved. `Shoals.Curves` uses `f32` rates and maturities. Basis-curve helpers are also exported, but there is no general joint multi-curve solve.

`Shoals.Tenor.tenor_apply` and `Shoals.Date.schedule_from_tenor` use fixed 30-day months and 365-day years. `Shoals.Date.add_months` and `schedule_from_tenor_calendar` provide calendar-month stepping instead. The date-roll and business-day functions in `Shoals.Date` take the `Shoals.HolidayCal.Calendar` they roll against and treat a date as a business day only when it is neither a weekend nor a holiday in that calendar; pass `weekend_only_calendar()` for weekend-only behavior. Neither schedule generator rolls its stops against a calendar — compose a roll over the result when settlement dates are needed. `parse_tenor` accepts uppercase `ON`, `TN`, `SN`, and an integer followed by `D`, `W`, `M`, or `Y`; malformed strings fail.

`Shoals.Date.year_fraction` returns `f64`; the rest of `Shoals.Date` and all of `Shoals.Curves` remain `f32`, so a caller mixing them casts at the boundary. `ActActIcma` carries its own coupon period and frequency because ICMA is not computable from the accrual endpoints alone; a frequency below 1 or a non-positive coupon period traps rather than returning an infinity. The accrual endpoints themselves are not validated against that period. A result outside `[0, 1/frequency]` proves the accrual was invalid, but a result inside that range certifies nothing, so no assertion on the returned value substitutes for passing a correct accrual range. Nor is the period's length checked against the declared frequency.

`add_business_days` advances for positive counts and does not step backward
for a negative count. Use a positive `step_months` for either schedule
generator. `Shoals.Distributions` assumes valid distribution parameters,
including positive scales and degrees of freedom and an admissible
correlation; its constructors do not check them.

`hc_nyc_calendar()` and `hc_ldn_calendar()` contain 2025 dates. The year and multi-year constructors generate smaller fixed-rule New York and London lists; they are not complete bank-holiday services. Tokyo, Sydney, Frankfurt, and Hong Kong holiday predicates use separate annual rules. Hong Kong's table-backed dates cover 2025–2030; outside that range its predicate returns false. Verify regional observance rules before using a calendar for settlement.

`hc_us_federal_published()` and `hc_england_wales_published()` expose
Shoreleave's source-backed `BusinessCalendar` values. Their dates and weekmasks
come from published sources, and queries outside each source horizon fail.
The `*_published` rolls in `Shoals.Date` use that horizon-checked calendar.

## Simulation, risk, and valuation adjustments

Random draws require a seed. `Shoals.Stochastic.merton_jump_terminal` uses an aggregate Gaussian approximation to jump totals rather than drawing a compound Poisson process. Its correlated GBM helper covers two assets. `Shoals.Rng` has committed Sobol direction numbers for 32 dimensions; higher runtime dimensions use a fallback sequence up to the exposed limit. These choices matter for convergence studies.

`Shoals.Risk` computes Gaussian parametric or sample-based empirical VaR and expected shortfall from **losses** supplied by the caller. `Shoals.RiskExt.mc_var` and `mc_expected_shortfall` summarize supplied simulated losses; they do not generate paths. Use nonempty samples and confidence levels strictly between zero and one. Currency tags in `Shoals.CurrencyTag` are checked at runtime. Converting money requires an exchange rate from the caller.

The Gaussian parametric functions use a sample standard deviation with
one degree of freedom, so supply at least two losses for them.

`Shoals.Xva` has constant-hazard CVA/DVA, a hazard-curve CVA, funding and capital adjustment helpers, and a sampled constant-hazard wrong-way-risk estimator. Exposures and times are supplied by the caller. The time-grid methods assume increasing times, suitable exposure values and recovery rates, and do not model collateral. Pointwise netting handles two deals. `Shoals.Orderbook` sorts orders by price, without matching or quantity validation; best prices on an empty side and VWAP for an empty book use NaN sentinels.

## What the checks establish

`tests/` exercises fixed and sampled inputs. `properties/` contains predicates and selected `@property` checks. A `fuzz_validated` result is a seeded sample result, not an exhaustive proof. Some composite properties prove a formula under a separate normal-CDF contract; their sampled comparison with the shipped pricer does not make the two CDF implementations identical. See [Property specifications](properties.md) and the machine-readable `docs/cnote-import-surface.json` for the reported methods and bounds.
