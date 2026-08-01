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
confidence level, computed by `Nautilus.Stats.quantile_vec`.
`historical_cvar` is the mean of all losses at or above that quantile (the
tail mean). `empirical_loss_quantile` is the raw empirical quantile at an
arbitrary level `q`, the same primitive `historical_var` uses.

The empirical measures are exercised through the
[extended risk](risk-extended.md) module, whose `mc_var` and
`mc_expected_shortfall` delegate to `historical_var` and `historical_cvar`.
On the integer losses `0..100`, the 95% historical VaR is `95` and the 95%
historical CVaR is the tail mean `97.5`.

## Characterized coherence

The release characterization keeps the two model families distinct. For both
the Gaussian parametric measures and empirical historical measures it observes
confidence monotonicity, expected-shortfall dominance over VaR, and positivity
on positive-loss inputs. These are `fuzz_validated` results over 25 accepted
constraint-directed samples at each deterministic seed 0, 1, and 2, not global
proofs. Every family has a corrupt twin with an in-domain counterexample, and
the gate accepts dependency identity only from the compiler summary graph. An
ES/VaR relation must report edges to both functions it calls.

For 0.24.5 these are release-gated observations against the official,
sidecar-verified Chelis 0.17.5, Nautilus 0.7.37, and Coral 0.7.34 artifacts.
