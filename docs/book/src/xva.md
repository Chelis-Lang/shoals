# XVA

Module: `Shoals.Xva`.

This module computes valuation-adjustment building blocks: survival and
default probabilities, expected positive and negative exposure, two-deal
netting, CVA and DVA on a time grid, and funding and capital adjustments.
It also has a hazard-curve CVA and a sampled wrong-way-risk estimator.
`Shoals.Csa`, at the end of this page, reduces exposure by posted
collateral. Times are years from the valuation date; exposures, CVA and the
other adjustments are in the currency of the exposures.

## Survival and default

```chelis
def survival_probability_constant_hazard(hazard: f32, t: f32) -> f32
def default_probability_in_interval(hazard: f32, t_start: f32, t_end: f32) -> f32
def discount_factor_constant_rate(r: f32, t: f32) -> f32
```

`survival_probability_constant_hazard` is `exp(-hazard * t)`, the
probability of surviving to time `t` under a constant nonnegative hazard rate.
It is one at time zero and does not increase with time. `default_probability_in_interval` is
the probability of defaulting in `[t_start, t_end]`, the difference of the
survival probabilities at the two endpoints. `discount_factor_constant_rate`
is `exp(-r * t)`. For example:

```chelis
s = survival_probability_constant_hazard(cast(0.02, f32), cast(1.0, f32))  -- exp(-0.02)
p = default_probability_in_interval(cast(0.03, f32), cast(0.0, f32), cast(5.0, f32))
-- p == 1 - survival(5.0)
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
pointwise, the netting of two deals under a single agreement. For example:

```chelis
exposures = to_tensor([cast(-10.0, f32), cast(5.0, f32), cast(-3.0, f32), cast(20.0, f32)])
epe = expected_positive_exposure(exposures)  -- (5 + 20) / 4 == 6.25
ene = expected_negative_exposure(exposures)  -- (-10 - 3) / 4
```

## CVA and DVA

```chelis
def cva_constant_hazard[n](time_grid: tensor[n, f32], epe: tensor[n, f32], hazard: f32, recovery: f32, discount_rate: f32) -> f32
def dva_constant_hazard[n](time_grid: tensor[n, f32], ene: tensor[n, f32], hazard_own: f32, recovery_own: f32, discount_rate: f32) -> f32
```

`cva_constant_hazard` sums one term per grid time `t_i`:

`CVA = (1 - recovery) * sum_i (S(t_{i-1}) - S(t_i)) * epe[i] * exp(-r * t_i)`

with `S(t) = exp(-hazard * t)` and `t_{-1} = 0`. The first interval
therefore starts at time zero, and each interval uses the exposure and the
discount factor at its end point `t_i`; nothing is interpolated or averaged
inside an interval. `epe[i]` is the expected positive exposure at `t_i`
and `r` is `discount_rate`. `dva_constant_hazard` is the symmetric debit
valuation adjustment, the same sum with `-ene[i]` in place of `epe[i]` and
the institution's own hazard and recovery.

With finite intermediate values, CVA is zero when hazard is zero, recovery is one, or
every exposure is zero. The example below uses exposures of 10, 15, and 12
at years 1, 2, and 3:

```chelis
time_grid = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
epe = to_tensor([cast(10.0, f32), cast(15.0, f32), cast(12.0, f32)])
cva = cva_constant_hazard(time_grid, epe, cast(0.05, f32), cast(0.4, f32), cast(0.03, f32))
-- 0.96757334
```

CVA is not generally increasing in hazard for a varying exposure profile.
Raising hazard moves default probability toward earlier intervals; a profile
with exposure concentrated later can therefore produce a smaller CVA.

A negative expected negative exposure yields a positive DVA, since the
institution gains on its own default.

## Funding, capital, and varying hazard

```chelis
def fva[n](time_grid: tensor[n, f32], epe: tensor[n, f32], funding_spread: f32, discount_rate: f32) -> f32
def kva[n](time_grid: tensor[n, f32], ead: tensor[n, f32], cost_of_capital: f32, regulatory_capital_weight: f32, discount_rate: f32) -> f32
def xva_cva_stochastic_hazard[n, m](time_grid: tensor[m, f32], epe: tensor[m, f32], hazards: HazardCurve[n], recovery: f32, discount_rate: f32) -> f32
def xva_cva_wwr_constant_hazard[n](rng_key: key, time_grid: tensor[n, f32], epe: tensor[n, f32], hazard: f32, recovery: f32, discount_rate: f32, rho: f32, n_paths: i64) -> f32
```

`fva` is `funding_spread` times the trapezoidal integral of
`exp(-r * t) * epe(t)` over the grid. `kva` is
`cost_of_capital * regulatory_capital_weight` times the same integral of
`ead`. Both integrate from the first grid point to the last, with no
contribution before the first point; start the grid at 0 to include it. On
the example grid, `fva` with a 1% spread is `0.24462284` and `kva` with
cost 0.1 and weight 0.08 is `0.19569828`.

`xva_cva_stochastic_hazard` is `cva_constant_hazard` with the survival
curve of a `Shoals.Cds.HazardCurve` in place of the constant hazard;
despite its name it draws no random paths. A one-pillar curve at hazard
0.05 reproduces the constant-hazard CVA above, `0.96757334`.

### Wrong-way risk

`xva_cva_wwr_constant_hazard` estimates CVA by simulation with a Gaussian
copula between exposure and default. For each of `n_paths` draws it takes
an exposure factor `z_e` and an independent `z_d`, sets the default time
`tau = -ln(1 - N(-rho * z_e + sqrt(1 - rho^2) * z_d)) / hazard`, and, if
`tau` falls before the last grid time, adds
`(1 - recovery) * epe(tau) * exp(0.5 * z_e - 0.125) * exp(-r * tau)`. Here
`epe(tau)` interpolates `epe` linearly in time (flat before the first grid
point), and `exp(0.5 * z_e - 0.125)` is a mean-one lognormal exposure shock
with a fixed volatility of 0.5. The estimate is the sum divided by
`n_paths`, which is independent of the grid length.

`rho` is the correlation in `[-1, 1]` between the exposure factor and early
default. Positive `rho` is wrong-way risk: high exposure comes with early
default. On the example above with 20,000 paths and seed 3, `rho = 0`
gives `0.95674473`, `rho = 0.5` gives `1.3768874`, and `rho = -0.5`
gives `0.6184209`.

## Input checks

`xva_cva_wwr_constant_hazard` requires `n_paths >= 1` and fails with a
diagnostic naming the received count otherwise. The remaining conditions
are caller obligations. Supply nonnegative, strictly
increasing times (a grid point at 0 adds nothing to CVA or DVA and starts
the FVA and KVA integrals at 0), `time_grid` and exposure tensors of the same length
(the type requires it for each call), `0 <= recovery <= 1`, a nonnegative
hazard. An invalid recovery has no diagnostic: a recovery above 1 gives
a negative CVA. These functions do not
model a general portfolio netting agreement; see the next section for
collateral.

## Collateralized exposure

```chelis
def csa_collateralized_exposure(exposure: f32, threshold: f32, mta: f32, independent_amount: f32, haircut: f32) -> f32
def csa_collateralized_exposure_path[n](exposures: tensor[n, f32], threshold: f32, mta: f32, independent_amount: f32, haircut: f32) -> tensor[n, f32]
```

Module: `Shoals.Csa`. Under a credit support annex, the exposure left after
collateral is computed from the positive part `E` of the exposure:

- `E <= threshold`: no collateral is called; the result is `E`.
- `E - threshold < mta`: the call is below the minimum transfer amount; the
  result is `E`.
- otherwise collateral `(E - threshold) * (1 - haircut)` is posted and the
  independent amount is subtracted: the result is
  `max(E - (E - threshold) * (1 - haircut) - independent_amount, 0)`.

The independent amount reduces exposure only in that third case. The
`_path` form applies the same rule to every entry:

```chelis
collateralized = csa_collateralized_exposure_path(to_tensor([cast(-3.0, f32), cast(1.5, f32), cast(2.3, f32), cast(10.0, f32)]), cast(2.0, f32), cast(0.5, f32), cast(1.0, f32), cast(0.02, f32))
-- [0.0, 1.5, 2.3, 1.1599998]
```
