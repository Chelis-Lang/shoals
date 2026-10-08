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

`gbm_path` builds one path of `n` steps from `s0` over horizon `t`, with
drift `mu` and volatility `sigma`, by summing exact log increments
`(mu - sigma^2 / 2) * dt + sigma * sqrt(dt) * z` with `dt = t / n`. Entry
`i` is the price at time `(i + 1) * t / n`: the result excludes `s0` and
its last entry is the price at `t`. `gbm_terminal` instead returns `n`
independent draws of the price at `t`.
`gbm_paths_antithetic_terminal_mean` pairs each draw with its antithetic
and returns the mean terminal value, which reduces variance.

For a fifty-step path, repeated calls with keys derived from the same seed
and the same inputs produce the same values:

```chelis
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(50, i64))))
path = gbm_path(key_from_seed(7i64), template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
-- 50 entries; the last, the price at t = 1, is 125.43696
```

A four-step path from the same key, at times 0.25, 0.5, 0.75, and 1.0:

```chelis
four = gbm_path(key_from_seed(7i64), to_tensor([cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32)]), cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32))
-- [91.785385, 100.61438, 121.286125, 100.84691]
```

The terminal draws have theoretical mean `s0 * exp(mu * t)`; a finite sample
varies around that value. None of the GBM functions checks its inputs:
supply `s0 > 0` (its logarithm is taken), `sigma >= 0`, and `t >= 0`. An
empty template gives an empty result from `gbm_path` and `gbm_terminal`, and
NaN (zero divided by zero) from `gbm_paths_antithetic_terminal_mean`.

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
reduces to the plain GBM drift:

```chelis
d = merton_compensated_drift(cast(0.05, f32), cast(0.2, f32), cast(0.0, f32), cast(-0.1, f32), cast(0.1, f32))
-- d == 0.05 - 0.5 * 0.2 * 0.2
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
every parameter, so the failure mode is one-sided. Whenever the gap is large
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
parameters: `lambda = 200, jump_vol = 1.0, jump_mean = 0` at `s0 = 100` leaves
the large majority of paths at zero. This is the distribution being
unrepresentable in f32, not a defect in the compensator.

`merton_sampler_log_jump_moment` returns `log E[exp(J)]` for that aggregate
log jump `J`, which is what `merton_jump_terminal` subtracts from the log
drift. Subtracting the sampled law's own exponential moment is what makes the
terminal mean exact. It converges to
`lambda * t * (exp(jump_mean + 0.5 * jump_vol^2) - 1)`, so
`merton_compensated_drift(mu, sigma, lambda, jump_mean, jump_vol) * t` and
`(mu - 0.5 * sigma^2) * t - merton_sampler_log_jump_moment(lambda, jump_mean, jump_vol, t)`
agree to within a 1e-5 relative tolerance over `lambda * t` from 0.3 to 20
and both signs of `jump_mean`. Outside that band the two forms diverge
further: for a very small `lambda * t` the enumerated moment is a
`log(1 + x)` with `x` below f32 epsilon, and for a very small `jump_mean` it
is the closed form that loses the digits, to cancellation in
`exp(jump_mean) - 1`. The absolute log-drift difference stays small either
way.

The jump count is drawn from a table of the counts `0, 1, ..., S - 1` with
`S = trunc(x + 7 * sqrt(x) + 12)`, where
`x = lambda * t * max(1, exp(jump_mean + 0.5 * jump_vol^2))`. The table
holds at most 4096 counts. A larger intensity raises a runtime `fail`
(*merton jump intensity is too large to enumerate the jump count exactly*)
rather than truncating the law; at `jump_vol = 0.1` and `jump_mean = 0` the
limit is reached near `lambda * t = 3600`. Both `lambda` and `t` must
be finite and non-negative, for the moment function as well as the
sampler. Zero intensity or zero horizon gives a zero log jump moment.
A non-finite product or `jump_mean + 0.5 * jump_vol^2` also fails.
`merton_sampler_log_jump_moment(5000.0, 0.0, 0.1, 1.0)` fails with:

```text
Shoals.Stochastic: merton jump intensity is too large to enumerate the jump count exactly; lambda * t * exp(jump_mean + 0.5 * jump_vol^2) must leave the slot bound at or below 4096
```

A 5000-path sample:

```chelis
template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
paths = merton_jump_terminal(key_from_seed(7i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(0.3, f32), cast(-0.1, f32), cast(0.15, f32), cast(1.0, f32))
-- sample mean 104.80676; model mean 100 * exp(0.05) = 105.127
```

## Two-asset correlated GBM

```chelis
def cholesky_2x2_lower(sigma_xx: f32, sigma_xy: f32, sigma_yy: f32) -> (f32, f32, f32)
def correlated_gbm_terminal_2d[n](rng_key: key, template_x: tensor[n, f32], template_y: tensor[n, f32], s0_x: f32, s0_y: f32, mu_x: f32, mu_y: f32, sigma_x: f32, sigma_y: f32, rho: f32, t: f32) -> (tensor[n, f32], tensor[n, f32])
```

`cholesky_2x2_lower` returns the lower-triangular Cholesky factor
`(l11, l21, l22)` of a two-by-two covariance matrix given as
`sigma_xx`, `sigma_xy`, `sigma_yy`: `l11 = sqrt(sigma_xx)`,
`l21 = sigma_xy / l11`, `l22 = sqrt(sigma_yy - l21^2)`. Reconstructing
`L L^T` recovers the covariance. The inputs are not checked: a matrix that is
not positive definite gives NaN through the square root of a negative
number (`(1.0, 2.0, NaN)` for `(1, 2, 1)`), and `sigma_xx = 0` divides by zero:

```chelis
out = cholesky_2x2_lower(cast(4.0, f32), cast(2.0, f32), cast(3.0, f32))
-- out == (2.0, 1.0, sqrt(2.0))
```

`correlated_gbm_terminal_2d` draws correlated terminal pairs for two assets
with correlation `rho`, returning a tuple of two terminal tensors. The Y
shock is `rho * z_x + sqrt(1 - rho^2) * z`; a `|rho|` above 1 is not
rejected but treated as `sqrt(1 - rho^2) = 0`. Each marginal mean stays
near `s0 * exp(mu * t)`:

```chelis
template_x = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
template_y = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
out = correlated_gbm_terminal_2d(key_from_seed(13i64), template_x, template_y, cast(100.0, f32), cast(50.0, f32), cast(0.04, f32), cast(0.06, f32), cast(0.2, f32), cast(0.3, f32), cast(0.5, f32), cast(1.0, f32))
-- out.0 is the X terminal tensor, out.1 the Y terminal tensor
-- sample means 104.01002 and 52.85399; model means 104.081 and 53.092
```

## Heston

```chelis
def heston_qe_step(log_s: f32, v: f32, min_v: f32, mu: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, dt: f32, z_v: f32, z_indep: f32, u: f32) -> (f32, f32, f32)
def heston_qe_terminal(rng_key: key, s0: f32, v0: f32, mu: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, t: f32, n_steps: i64) -> (f32, f32, f32)
def heston_qe_paths_terminal[n](rng_key: key, paths_template: tensor[n, f32], s0: f32, v0: f32, mu: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, t: f32, n_steps: i64) -> (tensor[n, f32], tensor[n, f32], tensor[n, f32])
```

These simulate the Heston model `dS = mu * S dt + sqrt(v) * S dW1`,
`dv = kappa * (theta - v) dt + sigma * sqrt(v) dW2`, `corr(dW1, dW2) = rho`,
stepping the variance with Andersen's quadratic-exponential (QE) scheme at
the switching value `psi_c = 1.5`. `v0` and `theta` are variances (`0.04` is a
20% volatility), `kappa` the mean-reversion speed, and `sigma` the volatility
of variance.

- `heston_qe_step` advances one step of length `dt` from log price `log_s`
  and variance `v`. It takes its random inputs explicitly: `z_v` drives the
  variance, `z_indep` is an independent normal mixed in for the price
  shock `rho * z_v + sqrt(1 - rho^2) * z_indep`, and `u` is a uniform used
  in the QE exponential branch. It returns
  `(next_log_s, next_v, min(min_v, next_v))`.
- `heston_qe_terminal` runs `n_steps` steps of `t / n_steps` from `s0`,
  `v0` and returns `(S_T, v_T, minimum variance on the path)`.
- `heston_qe_paths_terminal` does the same for each entry of
  `paths_template` and returns the three quantities as tensors.

The price step uses the variance at the start of the step and the drift
`mu - v / 2`, so `E[S_T]` is close to `s0 * exp(mu * t)` with a
discretization bias that shrinks with `dt`. Variances never go negative. The
module does not check the Feller condition, `|rho| <= 1`, or `n_steps > 0`.

```chelis
hpt = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(2000, i64))))
hes = heston_qe_paths_terminal(key_from_seed(11i64), hpt, cast(100.0, f32), cast(0.04, f32), cast(0.05, f32), cast(1.5, f32), cast(0.04, f32), cast(0.5, f32), cast(-0.7, f32), cast(1.0, f32), cast(50, i64))
-- mean S_T 104.77467, mean v_T 0.041197665
```

## Kou double-exponential jumps

```chelis
def sto_kou_compensator(p: f32, eta_up: f32, eta_dn: f32) -> f32
def sto_kou_jump_sample(p: f32, eta_up: f32, eta_dn: f32, u_branch: f32, e_size: f32) -> f32
def sto_kou_sampler_log_jump_moment(lambda_jump: f32, p: f32, eta_up: f32, eta_dn: f32, t: f32) -> f32
def sto_kou_jump_terminal[n](rng_key: key, paths_template: tensor[n, f32], jumps_template: tensor[n, f32], s0: f32, mu: f32, sigma: f32, lambda_jump: f32, p: f32, eta_up: f32, eta_dn: f32, t: f32) -> tensor[n, f32]
```

Each log jump is up with probability `p`, exponential with rate `eta_up`
(mean size `1 / eta_up`), and otherwise down with rate `eta_dn`.

- `sto_kou_compensator` is `E[exp(Y)] - 1 =
  p * eta_up / (eta_up - 1) + (1 - p) * eta_dn / (eta_dn + 1) - 1`. The
  function requires `eta_up > 1`, including when `p = 0`; at
  `eta_up <= 1` it returns NaN. For `p > 0` that bound is necessary for a
  finite expectation. At `p = 0` the upward component is unused, but the
  function still applies the same bound. At `p = 0.4`, `eta_up = 10`,
  `eta_dn = 5` it is `-0.055555522`.
- `sto_kou_jump_sample` maps a uniform `u_branch` and a unit exponential
  `e_size` to one jump: `e_size / eta_up` if `u_branch < p`, else
  `-e_size / eta_dn`.
- `sto_kou_sampler_log_jump_moment` is `log E[exp(J)]` for the aggregate
  log jump `J` the sampler draws over `[0, t]`, computed from the same
  enumerated count table.
- `sto_kou_jump_terminal` draws one Poisson jump count per path at
  intensity `lambda_jump` and adds that many sampled jumps. It subtracts
  `sto_kou_sampler_log_jump_moment` from the log drift, so the terminal
  mean is `s0 * exp(mu * t)` exactly, whatever the table size. The number
  of paths is the length of `paths_template`; `jumps_template` must have
  the same length and its values are not used.

The count table follows the Merton rule above with
`w = 1 + sto_kou_compensator(p, eta_up, eta_dn)` as the jump multiplier:
`S = trunc(x + 7 * sqrt(x) + 12)` counts with
`x = lambda_jump * t * max(1, w)`, at most 4096, so each path draws at
least 12 jump sizes. Both `lambda_jump` and `t` must be finite and
non-negative, for the moment function as well as the sampler. Zero
intensity or zero horizon gives a zero log jump moment. A larger count
bound, a non-finite product, or `eta_up <= 1` raises a runtime `fail`
(for `eta_up <= 1`: *kou jump parameters must be finite; ... which
requires eta_up > 1*); the table is never truncated. The terminal mean is finite for `eta_up > 1`, but
`E[S_T^2]` is finite only for `eta_up > 2`, so for `1 < eta_up <= 2` a
sample variance does not converge.

```chelis
kpt = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
kjt = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(5000, i64))))
kou = sto_kou_jump_terminal(key_from_seed(5i64), kpt, kjt, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.4, f32), cast(10.0, f32), cast(5.0, f32), cast(1.0, f32))
-- 5000 paths: sample mean 104.68485; model mean 105.127
```

## Quasi-random points and variance reduction

Module: `Shoals.Rng`.

```chelis
def sobol_points[total](n_points: i64, n_dims: i64) -> tensor[total, f32]
def halton_points[total](n_points: i64, n_dims: i64) -> tensor[total, f32]
def sobol_point_runtime_at(d_idx: i64, point_idx: i64) -> f32
def sobol_dim_runtime[n](d_idx: i64, template: tensor[n, f32]) -> tensor[n, f32]
def halton_value(i: i64, base: i64) -> f32
def antithetic_terminal_mean[n](payoffs_plus: tensor[n, f32], payoffs_minus: tensor[n, f32]) -> f32
def control_variate_terminal_mean[n](target_payoffs: tensor[n, f32], control_payoffs: tensor[n, f32], control_known_mean: f32, regression_coef: f32) -> f32
def stratified_terminal_mean[n](strata_means: tensor[n, f32]) -> f32
```

`sobol_points` and `halton_points` return `n_points` points in `[0, 1)` of
`n_dims` coordinates each, flattened point by point, so `total` is
`n_points * n_dims` and coordinate `d` of point `i` is entry
`i * n_dims + d`. `total` is not an argument: the length is set by the two
runtime counts, so read the result through `to_list` as in the example
below, or index it directly. The Sobol sequence starts at the origin and supports up
to 32 dimensions. The Halton sequence uses the `d`-th prime as the base of
dimension `d` (2, 3, 5, ...), up to 50 dimensions, and starts at index 1, so
no point sits at the origin.

```chelis
sob = to_list(sobol_points(cast(4, i64), cast(2, i64)))
-- [0.0, 0.0, 0.5, 0.5, 0.25, 0.75, 0.75, 0.25]
hal = to_list(halton_points(cast(4, i64), cast(2, i64)))
-- [0.5, 0.33333334, 0.25, 0.6666667, 0.75, 0.11111111, 0.125, 0.44444445]
```

`sobol_point_runtime_at(d, i)` and `sobol_dim_runtime(d, template)` read one
dimension at runtime. Dimensions 0 to 31 are Sobol; from 32 they fall back
to a Halton sequence in base `prime_table()[d mod 50]`, so dimensions in
that range that differ by a multiple of 50 are identical:
`sobol_point_runtime_at(32, 5)` and `sobol_point_runtime_at(82, 5)` are both
`0.04379562`. Keep a quasi-Monte Carlo study at 32 dimensions or fewer.

The three estimators average payoffs you have already computed.
`antithetic_terminal_mean` is the mean of `(plus + minus) / 2` over paired
draws. `control_variate_terminal_mean` is the mean of
`target - regression_coef * (control - control_known_mean)`; for example
targets `[10, 12]`, controls `[5, 7]`, known mean `5.5`, and coefficient 1
give `10.5`. `stratified_terminal_mean` is the plain mean of per-stratum
means, which is correct for equal-probability strata.

See [Scope and limitations](scope.md) for the simulation
assumptions shared across modules.
