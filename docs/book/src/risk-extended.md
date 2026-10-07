# Extended risk

Module: `Shoals.RiskExt`.

This module layers Monte Carlo risk measures, a regulatory expected-
shortfall helper, a scenario PnL grid, and a backtest statistic on top of
the empirical measures in [`Shoals.Risk`](risk.md). The Monte Carlo VaR and
expected shortfall are computed from the empirical loss distribution, so
they delegate to the historical measures.

## Monte Carlo VaR and expected shortfall

```chelis
def mc_var[n](losses: tensor[n, f32], confidence: f32) -> f32
def mc_expected_shortfall[n](losses: tensor[n, f32], confidence: f32) -> f32
def expected_shortfall_frtb_975[n](losses: tensor[n, f32]) -> f32
```

`mc_var` and `mc_expected_shortfall` take a simulated loss tensor and return
the empirical VaR and expected shortfall at the confidence level, delegating
to `historical_var` and `historical_cvar`. `expected_shortfall_frtb_975` is
`mc_expected_shortfall(losses, 0.975)`: the plain empirical tail mean at the
97.5% level that FRTB-IMA uses. It applies no liquidity-horizon scaling, no
stressed-period calibration, and no aggregation across risk classes; supply
losses already at the horizon you report.

For example, on the integer losses `0..100`:

```chelis
losses = to_tensor(map(fn (i: i64) -> cast(cast(i, i32), f32), range(cast(0, i64), cast(101, i64))))
v = mc_var(losses, cast(0.95, f32))                  -- v == 95.0
es = mc_expected_shortfall(losses, cast(0.95, f32))  -- es == 97.5 (mean of 95..100)
```

On the same sample `expected_shortfall_frtb_975(losses)` is `99.0`, the mean
of the losses at or above the 97.5% quantile `97.5`. These functions
summarize supplied losses; they do not generate paths. Quantile
interpolation and the behavior on an empty sample or a confidence outside
`(0, 1)` are those of the historical measures in [Risk](risk.md).

## Scenario PnL grid

```chelis
def scenario_pnl_grid[m](base_value: f32, scenario_shifts: tensor[m, f32], pnl_per_unit_shift: f32) -> tensor[m, f32]
```

`scenario_pnl_grid` applies a linear PnL sensitivity to a tensor of scenario
shifts: each output entry is `base_value + pnl_per_unit_shift * shift`, the
position value in that scenario. Pass `base_value = 0` to get the PnL
alone. For example:

```chelis
shifts = to_tensor([cast(-0.02, f32), cast(-0.01, f32), cast(0.0, f32), cast(0.01, f32), cast(0.02, f32)])
pnls = scenario_pnl_grid(cast(100.0, f32), shifts, cast(50.0, f32))
-- the zero-shift entry is 100.0, the +0.02 entry is 101.0
```

## Kupiec backtest

```chelis
def kupiec_pof_statistic_simple(num_violations: i64, total_observations: i64, expected_rate: f32) -> f32
```

`kupiec_pof_statistic_simple` is the Kupiec proportion-of-failures
likelihood-ratio statistic for VaR backtesting. With `x` violations in `T`
observations, observed rate `x / T`, and expected rate `p`, it returns
`-2 * (ln L(p) - ln L(x / T))` where `ln L(q) = x * ln(q) + (T - x) * ln(1 - q)`.
Compare it with a chi-squared critical value with one degree of freedom
(3.841 at 95%). Terms with a zero count are taken as zero, so the edge cases
are defined:

```chelis
stat = kupiec_pof_statistic_simple(cast(5, i64), cast(100, i64), cast(0.05, f32))
-- -0.0: observed rate equals expected
none = kupiec_pof_statistic_simple(cast(0, i64), cast(250, i64), cast(0.01, f32))
-- 5.025163: no violations, -2 * 250 * ln(0.99)
ten = kupiec_pof_statistic_simple(cast(10, i64), cast(250, i64), cast(0.01, f32))
-- 12.9554825: above 3.841, rejects the 99% VaR
empty = kupiec_pof_statistic_simple(cast(0, i64), cast(0, i64), cast(0.05, f32))
-- 0.0: no observations
```

`expected_rate` must lie strictly between 0 and 1: at 0 or 1 a logarithm
is `-inf` and the statistic is infinite or NaN. Counts are not checked
against each other; pass `0 <= num_violations <= total_observations`.

## Other backtests

| Function | Returns |
|---|---|
| `re_christoffersen_cc[n](losses: tensor[n, f32], var_forecasts: tensor[n, f32], alpha: f32) -> (f32, bool)` | Christoffersen conditional-coverage statistic: Kupiec on the exceptions (`loss > var`) plus the first-order independence statistic, and whether it exceeds 5.991, the 95% chi-squared critical value with two degrees of freedom. `alpha` is the expected exception rate. |
| `re_frtb_ima_zone_at_day(n_exceptions_window: i64) -> i64` | FRTB traffic-light zone for a 250-day exception count: 0 (green) up to 4, 1 (amber) up to 9, 2 (red) from 10. |
| `re_frtb_ima_zone_rolling[n, m](loss_series: tensor[n, f32], var_forecasts: tensor[n, f32]) -> tensor[m, i64]` | the zone for each complete 250-day window ending at day 250, 251, and so on. The result has `m = n - 249` entries for `n >= 250` and is empty below 250 observations. |
| `re_acerbi_szekely_es_z1[n](losses: tensor[n, f32], var_forecasts: tensor[n, f32], es_forecasts: tensor[n, f32], alpha: f32) -> f32` | Acerbi-Szekely Z1: one minus the mean of `loss / es` over exception days; 0 with no exceptions. `alpha` is accepted and not used. |
| `re_acerbi_szekely_es_z2[n](losses: tensor[n, f32], var_forecasts: tensor[n, f32], es_forecasts: tensor[n, f32], alpha: f32) -> f32` | Acerbi-Szekely Z2: one minus the sum of `loss / es` over exception days divided by `T * alpha`, where `alpha` is the VaR tail probability (0.025 for a 97.5% ES); 0 when `T * alpha` is 0. |

All series are matched `tensor[n, f32]` in time order, losses positive; the
shared `n` makes unequal lengths a type error. An exception is a day with
`loss > var`. An exception day whose ES forecast is exactly 0 contributes 0
to the `loss / es` sum but still counts as an exception. Nothing else is
checked: `alpha` must lie strictly between 0 and 1. Under
a correct model both Z statistics are near 0; negative values indicate
underestimated risk.
