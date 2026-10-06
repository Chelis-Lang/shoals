# Stochastic processes

Module: `Shoals.Stochastic`.

This module generates sample paths and terminal draws for geometric
Brownian motion, an antithetic-variates terminal-mean estimator, Merton
lognormal jump-diffusion with a compensated drift, and a two-asset
correlated GBM driven by a two-by-two Cholesky factor. It also exports
Heston quadratic-exponential steps and terminal simulations and Kou
double-exponential jump helpers. Random draws take an explicit `key` argument;
`key_from_seed` provides a reproducible key. The path
length, or the number of terminal draws, is the length of a template
tensor you supply.

## Geometric Brownian motion

```chelis
def gbm_path[n](rng_key: key, template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> tensor[n, f32]
def gbm_terminal[n](rng_key: key, template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> tensor[n, f32]
def gbm_paths_antithetic_terminal_mean[n](rng_key: key, template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, t: f32) -> f32
```

`gbm_path` builds one log-Euler path of `n` steps from `s0` over horizon
`t`, with drift `mu` and volatility `sigma`. `gbm_terminal` instead returns
`n` independent terminal draws at time `t`.
`gbm_paths_antithetic_terminal_mean` pairs each draw with its antithetic
and returns the mean terminal value, which reduces variance.

From `tests/stochastic.ch`, a fifty-step path is strictly positive and
bit-exactly reproducible with a key derived from a fixed seed:

```chelis
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(50, i64))))
path = gbm_path(key_from_seed(7i64), template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
```

The terminal draws have mean near `s0 * exp(mu * t)` and variance near the
lognormal theory, both verified in the test suite at twenty thousand draws.

## Merton jump-diffusion

```chelis
def merton_compensated_drift(mu: f32, sigma: f32, lambda: f32, jump_mean: f32, jump_vol: f32) -> f32
def merton_sampler_log_jump_moment(lambda: f32, jump_mean: f32, jump_vol: f32, t: f32) -> f32
def merton_jump_terminal[n](rng_key: key, template: tensor[n, f32], jumps_template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, lambda: f32, jump_mean: f32, jump_vol: f32, t: f32) -> tensor[n, f32]
```

`merton_compensated_drift` computes the log drift for a compound-Poisson
model with normally distributed log jumps. It subtracts the diffusion
correction and the expected jump contribution
`lambda * (exp(jump_mean + 0.5 * jump_vol^2) - 1)`. This gives that model
an expected terminal value of `s0 * exp(mu * t)`. With `lambda` zero it
reduces to the plain GBM drift. From `tests/stochastic_extended.ch`:

```chelis
d = merton_compensated_drift(cast(0.05, f32), cast(0.2, f32), cast(0.0, f32), cast(-0.1, f32), cast(0.1, f32))
// d == 0.05 - 0.5 * 0.2 * 0.2
```

`merton_jump_terminal` samples that model. It draws the jump count from the
Poisson law the compensator names, enumerated over a finite slot table, and
aggregates the resulting lognormal jumps exactly: given `N` jumps the total
log jump is `Normal(N * jump_mean, N * jump_vol^2)`. Terminal prices are
positive and their mean is `s0 * exp(mu * t)` for either sign of `jump_mean`.
It takes two template tensors of the same length, one for the diffusion draws
and one for the aggregate jump draws; the uniform count draws are generated
internally at the same length.

One f32 limit is worth knowing and is not specific to this sampler. The mean
log offset of a compensated path is `lambda * t * (jump_mean + 1 - w)` with
`w = exp(jump_mean + 0.5 * jump_vol^2)`, and by Jensen that is at most zero for
every parameter — so the failure mode is one-sided. Whenever the gap is large
enough the whole terminal distribution sits below f32's smallest subnormal and
every path reads as `0.0`, even though the mean of the model is still
`s0 * exp(mu * t)`.

Either factor can open that gap, so it is the Jensen gap to watch and not any
one parameter. A large `jump_vol` does it: at `lambda = 1`, `jump_vol = 3.2`
the compensator is `-166.3`, and for the modal one-jump path at `s0 = 100` a
representable terminal value needs about an 18-sigma jump draw (that figure
moves with the jump count and with `s0`). But `jump_vol = 0` reaches it too,
through a large negative `jump_mean`: `lambda = 3000, jump_mean = -50` also
gives `0.0` on every path. And it is reachable well inside ordinary
parameters — `lambda = 200, jump_vol = 1.0, jump_mean = 0` at `s0 = 100` leaves
the large majority of paths at zero. The exact count is seed-dependent and is
not quoted here; the mechanism is not.

This is the distribution being unrepresentable in f32, not a defect in the
compensator. Every case above gives the identical result on the previous
implementation, from the identical drift, and the drift expression it comes
from is unchanged since Shoals 0.4.0.

`merton_sampler_log_jump_moment` returns `log E[exp(J)]` for that aggregate
log jump `J`, which is what `merton_jump_terminal` subtracts from the log
drift. Subtracting the sampled law's own exponential moment is what makes the
terminal mean exact, rather than subtracting a closed form that has to be kept
in step with the sampler by hand. It converges to
`lambda * t * (exp(jump_mean + 0.5 * jump_vol^2) - 1)`, so
`merton_compensated_drift(mu, sigma, lambda, jump_mean, jump_vol) * t` and
`(mu - 0.5 * sigma^2) * t - merton_sampler_log_jump_moment(lambda, jump_mean, jump_vol, t)`
agree to within the 1e-5 relative tolerance asserted in
`tests/stochastic_extended.ch`, over `lambda * t` from 0.3 to 20 and both signs
of `jump_mean`. That file pins both the agreement and the moment itself against
the closed form at those intensities and at three more that stress the f32
exponent range. The agreement is loosest at the small-`lambda * t` end of that
band, and outside it the two forms diverge further:
for a very small `lambda * t` the enumerated moment is a `log(1 + x)` with `x`
below f32 epsilon, and for a very small `jump_mean` it is the CLOSED form that
loses the digits, to cancellation in `exp(jump_mean) - 1`. The absolute
log-drift difference stays small either way.
The slot table is sized on `lambda * t * exp(jump_mean + 0.5 * jump_vol^2)`,
and an intensity whose table would exceed the slot cap is refused rather than
truncated. A negative `lambda * t` is refused too: it names no Poisson law.

From `tests/stochastic_extended.ch`:

```chelis
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
paths = merton_jump_terminal(key_from_seed(7i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.3, f32), cast(-0.1, f32), cast(0.15, f32), cast(1.0, f32))
```

## Two-asset correlated GBM

```chelis
def cholesky_2x2_lower(sigma_xx: f32, sigma_xy: f32, sigma_yy: f32) -> (f32, f32, f32)
def correlated_gbm_terminal_2d[n](rng_key: key, template_x: tensor[n, f32], template_y: tensor[n, f32], s0_x: f32, s0_y: f32, mu_x: f32, mu_y: f32, sigma_x: f32, sigma_y: f32, rho: f32, t: f32) -> (tensor[n, f32], tensor[n, f32])
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
out = correlated_gbm_terminal_2d(key_from_seed(13i64), template_x, template_y, cast(100.0, f32), cast(50.0, f32), cast(0.04, f32), cast(0.06, f32), cast(0.2, f32), cast(0.3, f32), cast(0.5, f32), cast(1.0, f32))
// out.0 is the X terminal tensor, out.1 the Y terminal tensor
```

## Other exported processes

`heston_qe_step`, `heston_qe_terminal`, and `heston_qe_paths_terminal`
implement a quadratic-exponential Heston step and keyed terminal draws.
These are model-specific approximations; use the corresponding source
tests and [Scope and limitations](scope.md) to check parameter assumptions.

## Kou jump-diffusion

```chelis
def sto_kou_compensator(p: f32, eta_up: f32, eta_dn: f32) -> f32
def sto_kou_jump_sample(p: f32, eta_up: f32, eta_dn: f32, u_branch: f32, e_size: f32) -> f32
def sto_kou_sampler_log_jump_moment(lambda_jump: f32, p: f32, eta_up: f32, eta_dn: f32, t: f32) -> f32
def sto_kou_jump_terminal[n](rng_key: key, paths_template: tensor[n, f32], jumps_template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, lambda_jump: f32, p: f32, eta_up: f32, eta_dn: f32, t: f32) -> tensor[n, f32]
```

The jump size `Y` is double-exponential: upward with probability `p` and
magnitude `Exp(eta_up)`, downward otherwise with magnitude `Exp(eta_dn)`.
`sto_kou_compensator` returns `zeta = E[exp(Y)] - 1`, which exists only for
`eta_up > 1`; below that the up-jump moment integral diverges and the function
returns a NaN sentinel.

`sto_kou_jump_terminal` samples the model. It draws the jump count `N` from an
enumerated Poisson law over a finite slot table, then adds the first `N` of
that path's pre-drawn double-exponential jumps, so the aggregate log jump is a
genuine compound Poisson sum. The table is sized on the exponentially tilted
mean `lambda_jump * t * (1 + zeta)`, and an intensity whose table would exceed
the slot cap is refused rather than silently truncated.

`sto_kou_sampler_log_jump_moment` returns `log E[exp(J)]` for that aggregate
log jump, which is exactly what `sto_kou_jump_terminal` subtracts from the log
drift. The terminal mean is therefore `s0 * exp(mu * t)` by construction. For
an untruncated Poisson count that moment equals `lambda_jump * t * zeta`
exactly, because `E[w^N] = exp(rate * (w - 1))` with `w = 1 + zeta`; the
function adds the enumeration correction so the identity survives truncation.

Two cautions, both load-bearing:

- The mean identity is exact, but `E[S_t^2]` is finite only for `eta_up > 2`.
  At `eta_up = 2` the terminal second moment diverges, so a Monte-Carlo
  terminal mean has no usable standard error there. Verify a drift against
  `sto_kou_sampler_log_jump_moment` rather than against a sample mean.
- Kou pays the slot bound harder than Merton does. Merton aggregates its `N`
  jumps in closed form as a single Gaussian, so a slot costs one table entry.
  Kou's jump sizes have no such form, so every slot is also a per-path draw
  and a fold step.
