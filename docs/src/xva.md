# XVA

Module: `Shoals.Xva`.

This module computes valuation-adjustment building blocks: survival and
default probabilities, expected positive and negative exposure, two-deal
netting, CVA and DVA on a time grid, and funding and capital adjustments.
It also has a hazard-curve CVA and a sampled wrong-way-risk estimator.

## Survival and default

```chelis
def survival_probability_constant_hazard(hazard: f32, t: f32) -> f32
def default_probability_in_interval(hazard: f32, t_start: f32, t_end: f32) -> f32
def discount_factor_constant_rate(r: f32, t: f32) -> f32
```

`survival_probability_constant_hazard` is `exp(-hazard * t)`, the
probability of surviving to time `t` under a constant hazard rate. It is one
at time zero and decreases with time. `default_probability_in_interval` is
the probability of defaulting in `[t_start, t_end]`, the difference of the
survival probabilities at the two endpoints. `discount_factor_constant_rate`
is `exp(-r * t)`. From `tests/xva.ch`:

```chelis
s = survival_probability_constant_hazard(cast(0.02, f32), cast(1.0, f32))  // exp(-0.02)
p = default_probability_in_interval(cast(0.03, f32), cast(0.0, f32), cast(5.0, f32))
// p == 1 - survival(5.0)
```

## Exposure and netting

```chelis
def expected_positive_exposure[n](exposures: tensor[n, f32]) -> f32
def expected_negative_exposure[n](exposures: tensor[n, f32]) -> f32
def netted_exposure_2_deals[n](deal_a: tensor[n, f32], deal_b: tensor[n, f32]) -> tensor[n, f32]
```

`expected_positive_exposure` is the mean over the sample of the positive
part of each exposure, and `expected_negative_exposure` is the mean of the
negative part. `netted_exposure_2_deals` adds two exposure tensors
pointwise, the netting of two deals under a single agreement. From
`tests/xva.ch`:

```chelis
exposures = to_tensor([cast(-10.0, f32), cast(5.0, f32), cast(-3.0, f32), cast(20.0, f32)])
epe = expected_positive_exposure(exposures)  // (5 + 20) / 4 == 6.25
ene = expected_negative_exposure(exposures)  // (-10 - 3) / 4
```

## CVA and DVA

```chelis
def cva_constant_hazard[n](time_grid: tensor[n, f32], epe: tensor[n, f32], hazard: f32, recovery: f32, discount_rate: f32) -> f32
def dva_constant_hazard[n](time_grid: tensor[n, f32], ene: tensor[n, f32], hazard_own: f32, recovery_own: f32, discount_rate: f32) -> f32
```

`cva_constant_hazard` aggregates the credit valuation adjustment over the
time grid: for each interval it multiplies the loss given default
(`1 - recovery`), the default probability in the interval, the expected
positive exposure, and the interval's discount factor, and sums the
contributions. `dva_constant_hazard` is the symmetric debit valuation
adjustment computed from the expected negative exposure and the
institution's own hazard and recovery.

From `tests/xva.ch`, the CVA is zero when there is no default risk, when
recovery is full (a recovery rate of one), or when the exposure is zero, and
it increases with the hazard rate:

```chelis
time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
epe = to_tensor([cast(10.0, f32), cast(15.0, f32), cast(12.0, f32)])
cva = cva_constant_hazard(time_grid, epe, cast(0.05, f32), cast(0.4, f32), cast(0.03, f32))
```

A negative expected negative exposure yields a positive DVA, since the
institution gains on its own default.

## Funding, capital, and varying hazard

```chelis
def fva[n](time_grid: tensor[n, f32], epe: tensor[n, f32], funding_spread: f32, discount_rate: f32) -> f32
def kva[n](time_grid: tensor[n, f32], ead: tensor[n, f32], cost_of_capital: f32, regulatory_capital_weight: f32, discount_rate: f32) -> f32
def xva_cva_stochastic_hazard[n, m](time_grid: tensor[m, f32], epe: tensor[m, f32], hazards: HazardCurve[n], recovery: f32, discount_rate: f32) -> f32
def xva_cva_wwr_constant_hazard[n](rng_key: key, time_grid: tensor[n, f32], epe: tensor[n, f32], hazard: f32, recovery: f32, discount_rate: f32, rho: f32, n_paths: i64) -> f32
```

`fva` multiplies the trapezoidal integral of discounted positive exposure
by a supplied funding spread. `kva` multiplies the discounted exposure at
default integral by supplied capital weight and cost. Both integrate
between supplied grid points, without a contribution before the first
point. `xva_cva_stochastic_hazard` uses a `Shoals.Cds.HazardCurve` to
compute interval survival changes; despite its name, it does not draw
random paths. `xva_cva_wwr_constant_hazard` samples correlated exposure
and default shocks; it takes an explicit key, which can be derived from a seed.

Supply increasing times, matching tensor lengths, valid recoveries, and
positive path counts where used. These functions do not model collateral
or a general portfolio netting agreement.
