# Risk

Module: `Shoals.Risk`.

This module computes value-at-risk and conditional value-at-risk (expected
shortfall) on a tensor of losses, both parametrically under a Gaussian
assumption and empirically from the loss sample. The convention is that the
input tensor holds losses, so a higher confidence selects a deeper point in
the loss tail.

## Parametric measures

```chelis
def parametric_var[n](losses: tensor[n, f32], confidence: f32) -> f32
def parametric_cvar[n](losses: tensor[n, f32], confidence: f32) -> f32
```

`parametric_var` fits a Gaussian to the sample mean and standard deviation
of the losses and returns `mu + sigma * z`, where `z` is the inverse normal
CDF at the confidence level (drawn from `Nautilus.Distributions`). The
standard deviation uses one degree of freedom. `parametric_cvar` returns
the Gaussian conditional value-at-risk, `mu + sigma * phi(z) / (1 - confidence)`,
the expected loss conditional on exceeding the VaR level.

## Historical measures

```chelis
def historical_var[n](losses: tensor[n, f32], confidence: f32) -> f32
def historical_cvar[n](losses: tensor[n, f32], confidence: f32) -> f32
def empirical_loss_quantile[n](losses: tensor[n, f32], q: f32) -> f32
```

`historical_var` is the empirical quantile of the loss sample at the
confidence level, computed by `Nautilus.Stats.quantile_vec`: sort the `n`
losses, take position `confidence * (n - 1)`, and interpolate linearly
between the two order statistics around it (the convention of NumPy's
default `quantile`). `historical_cvar` is the mean of all losses at or
above that quantile (the tail mean). `empirical_loss_quantile` is the same
quantile at an arbitrary level `q`.

On the integer losses `0..100`, the 95% historical VaR is `95` and the 95%
historical CVaR is the tail mean `97.5`. On `[1, 2, 3, 4]` the 50% quantile
sits halfway between 2 and 3: `2.5`. The
[extended risk](risk-extended.md) functions `mc_var` and
`mc_expected_shortfall` return exactly these two numbers.

## Invalid inputs

None of these functions fails on bad input; each returns a number, so
validate before calling.

| Input | Historical measures | Parametric measures |
|---|---|---|
| confidence outside `[0, 1]` | clamped to `[0, 1]`: at `1.5` the VaR of `0..100` is `100.0` | NaN |
| confidence exactly `0` or `1` | the sample minimum or maximum | VaR `-inf` at `0` and `inf` at `1` |
| empty sample | `0.0` | NaN (mean of nothing) |
| one loss | that loss | NaN: the standard deviation divides by `n - 1` |

Use a sample of at least two losses and a confidence strictly between zero
and one.
