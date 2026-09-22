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
the FRTB-IMA expected shortfall fixed at the 97.5% level.

From `tests/riskext.ch`, on the integer losses `0..100`:

```chelis
losses = to_tensor(map(fn (i: i64) -> cast(cast(i, i32), f32), range(cast(0, i64), cast(101, i64))))
v = mc_var(losses, cast(0.95, f32))                  // v == 95.0
es = mc_expected_shortfall(losses, cast(0.95, f32))  // es == 97.5 (mean of 95..100)
```

Expected shortfall dominates VaR at the same confidence, and a stricter
confidence selects a deeper quantile.

## Scenario PnL grid

```chelis
def scenario_pnl_grid[m](base_value: f32, scenario_shifts: tensor[m, f32], pnl_per_unit_shift: f32) -> tensor[m, f32]
```

`scenario_pnl_grid` applies a linear PnL sensitivity to a tensor of scenario
shifts: each output entry is `base_value + pnl_per_unit_shift * shift`. From
`tests/riskext.ch`:

```chelis
shifts = to_tensor([cast(-0.02, f32), cast(-0.01, f32), cast(0.0, f32), cast(0.01, f32), cast(0.02, f32)])
pnls = scenario_pnl_grid(cast(100.0, f32), shifts, cast(50.0, f32))
// the zero-shift entry is 100.0, the +0.02 entry is 101.0
```

## Kupiec backtest

```chelis
def kupiec_pof_statistic_simple(num_violations: i64, total_observations: i64, expected_rate: f32) -> f32
```

`kupiec_pof_statistic_simple` is the Kupiec proportion-of-failures
likelihood-ratio statistic for VaR backtesting. It compares the observed
exception rate `num_violations / total_observations` to the expected rate.
When the observed rate equals the expected rate the statistic is zero; when
it is far from expected the statistic grows. From `tests/riskext.ch`:

```chelis
stat = kupiec_pof_statistic_simple(cast(5, i64), cast(100, i64), cast(0.05, f32))
// stat == 0.0 at observed == expected
```
