# Stochastic processes

Module: `Shoals.Stochastic`.

This module generates sample paths and terminal draws for geometric
Brownian motion, an antithetic-variates terminal-mean estimator, Merton
lognormal jump-diffusion with a compensated drift, and a two-asset
correlated GBM driven by a two-by-two Cholesky factor. It also exports
Heston quadratic-exponential steps and terminal simulations and Kou
double-exponential jump helpers. The random functions
carry the `Random` effect and run inside a `with seed(...)` block. The path
length, or the number of terminal draws, is the length of a template
tensor you supply.

## Geometric Brownian motion

```chelis
def gbm_path[n](template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> tensor[n, f32] ! { Random }
def gbm_terminal[n](template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> tensor[n, f32] ! { Random }
def gbm_paths_antithetic_terminal_mean[n](template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> f32 ! { Random }
```

`gbm_path` builds one log-Euler path of `n` steps from `s0` over horizon
`t`, with drift `mu` and volatility `sigma`. `gbm_terminal` instead returns
`n` independent terminal draws at time `t`.
`gbm_paths_antithetic_terminal_mean` pairs each draw with its antithetic
and returns the mean terminal value, which reduces variance.

From `tests/stochastic.ch`, a fifty-step path is strictly positive and
bit-exactly reproducible under a fixed seed:

```chelis
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(50, i64))))
path = with seed(7i64) { gbm_path(template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32)) }
```

The terminal draws have mean near `s0 * exp(mu * t)` and variance near the
lognormal theory, both verified in the test suite at twenty thousand draws.

## Merton jump-diffusion

```chelis
def merton_compensated_drift(mu: f32, sigma: f32, lambda: f32, jump_mean: f32, jump_vol: f32) -> f32
def merton_jump_terminal[n](template: tensor[n, f32], jumps_template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, lambda: f32, jump_mean: f32, jump_vol: f32, t: f32) -> tensor[n, f32] ! { Random }
```

`merton_compensated_drift` returns the drift adjustment that keeps the
expected terminal value at `s0 * exp(mu * t)` once jumps are added: it
subtracts the diffusion correction and the expected jump contribution
`lambda * (exp(jump_mean + 0.5 * jump_vol^2) - 1)`. With `lambda` zero it
reduces to the plain GBM drift. From `tests/stochastic_extended.ch`:

```chelis
d = merton_compensated_drift(cast(0.05, f32), cast(0.2, f32), cast(0.0, f32), cast(-0.1, f32), cast(0.1, f32))
// d == 0.05 - 0.5 * 0.2 * 0.2
```

`merton_jump_terminal` draws terminal prices under lognormal jump-diffusion.
The jump component is aggregated as a single Gaussian per path (the
aggregate-jump approximation), so it takes two template tensors of the same
length, one for the diffusion draws and one for the jump draws. The terminal
prices are positive and their mean stays near `s0 * exp(mu * t)` because of
the compensated drift:

```chelis
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
paths = with seed(7i64) {
  merton_jump_terminal(template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.3, f32), cast(-0.1, f32), cast(0.15, f32), cast(1.0, f32))
}
```

## Two-asset correlated GBM

```chelis
def cholesky_2x2_lower(sigma_xx: f32, sigma_xy: f32, sigma_yy: f32) -> (f32, f32, f32)
def correlated_gbm_terminal_2d[n](template_x: tensor[n, f32], template_y: tensor[n, f32], s0_x: f32, s0_y: f32, mu_x: f32, mu_y: f32, sigma_x: f32, sigma_y: f32, rho: f32, t: f32) -> (tensor[n, f32], tensor[n, f32]) ! { Random }
```

`cholesky_2x2_lower` returns the lower-triangular Cholesky factor
`(l11, l21, l22)` of a two-by-two covariance matrix given as
`sigma_xx`, `sigma_xy`, `sigma_yy`. Reconstructing `L L^T` recovers the
covariance. From `tests/stochastic_extended.ch`:

```chelis
out = cholesky_2x2_lower(cast(4.0, f32), cast(2.0, f32), cast(3.0, f32))
// out == (2.0, 1.0, sqrt(2.0))
```

`correlated_gbm_terminal_2d` draws correlated terminal pairs for two assets
with correlation `rho`, returning a tuple of two terminal tensors. Each
marginal mean stays near `s0 * exp(mu * t)`:

```chelis
template_x = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
template_y = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
out = with seed(13i64) {
  correlated_gbm_terminal_2d(template_x, template_y, cast(100.0, f32), cast(50.0, f32), cast(0.04, f32), cast(0.06, f32), cast(0.2, f32), cast(0.3, f32), cast(0.5, f32), cast(1.0, f32))
}
// out.0 is the X terminal tensor, out.1 the Y terminal tensor
```

## Other exported processes

`heston_qe_step`, `heston_qe_terminal`, and `heston_qe_paths_terminal`
implement a quadratic-exponential Heston step and seeded terminal draws.
`sto_kou_compensator`, `sto_kou_jump_sample`, and `sto_kou_jump_terminal`
provide double-exponential jump calculations and seeded terminal draws.
These are model-specific approximations; use the corresponding source
tests and [Scope and limitations](scope.md) to check parameter assumptions.
