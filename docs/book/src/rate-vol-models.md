# Rate and volatility models

Modules: `Shoals.HullWhite`, `Shoals.LiborMarketModel`, `Shoals.SabrPaths`,
`Shoals.Heston`, `Shoals.Dupire`.

These modules simulate short-rate and forward-rate models, simulate the SABR
forward, price European options under Heston by Fourier integration, and
extract Dupire local volatility from a call or implied-volatility surface.
Rates are continuously compounded decimals, volatilities are annualized,
and times are years. The simulators take an explicit `key` (see
[Working with tensors and keys](conventions.md)), and a
`paths_template` whose length sets the number of paths; its values are
ignored. None of these functions validates its parameters: supply
positive volatilities, mean-reversion speeds, maturities, and spots or
forwards, `|rho| <= 1`, and `n_steps >= 1`. Outside that domain the result
is NaN or a meaningless number, not a failure.

## Hull-White short rates

```chelis
def hw1f_step(r: f32, a: f32, theta_bar: f32, sigma: f32, dt: f32, z: f32) -> f32
def hw1f_path[n](rng_key: key, paths_template: tensor[n, f32], r0: f32, a: f32, theta_bar: f32, sigma: f32, t: f32, n_steps: i64) -> tensor[n, f32]
def hw1f_bond_price(t: f32, t_maturity: f32, r0: f32, a: f32, sigma: f32) -> f32
def hw2f_step(x: f32, y: f32, a: f32, b: f32, sigma1: f32, sigma2: f32, rho: f32, dt: f32, z1: f32, z2: f32) -> (f32, f32)
def hw2f_path[n](rng_key: key, paths_template: tensor[n, f32], x0: f32, y0: f32, a: f32, b: f32, sigma1: f32, sigma2: f32, rho: f32, t: f32, n_steps: i64) -> (tensor[n, f32], tensor[n, f32])
```

The one-factor model is `dr = a * (theta_bar - r) dt + sigma dW`, with a
constant mean-reversion level `theta_bar`.

- `hw1f_step` is one Euler step:
  `r + a * (theta_bar - r) * dt + sigma * sqrt(dt) * z`.
- `hw1f_path` runs `n_steps` such steps of `t / n_steps` from `r0` and
  returns the short rate at `t` on each path, not the whole path.
- `hw1f_bond_price` is the zero-coupon bond price at time `t` for maturity
  `t_maturity`, given short rate `r0` at `t`, in the case `theta_bar = 0`:
  `exp((tau - B) * sigma^2 / (2 * a^2) - sigma^2 * B^2 / (4 * a) - B * r0)`
  with `tau = t_maturity - t` and `B = (1 - exp(-a * tau)) / a`. It has no
  `theta_bar` input, so it does not price bonds for a model reverting to a
  nonzero level. `a` must be nonzero.

```chelis
p = hw1f_bond_price(cast(0.0, f32), cast(5.0, f32), cast(0.03, f32), cast(0.1, f32), cast(0.01, f32))
-- 0.8899547
r1 = hw1f_step(cast(0.03, f32), cast(0.1, f32), cast(0.04, f32), cast(0.01, f32), cast(0.25, f32), cast(1.0, f32))
-- 0.03525
```

From `r0 = 0.03` toward `theta_bar = 0.04` with `a = 0.1`,
`sigma = 0.01`, 2000 paths of 50 steps over 5 years have a mean terminal
rate of `0.03410908`, against the model mean
`0.04 + (0.03 - 0.04) * exp(-0.5) = 0.0339`.

The two-factor model is the additive Gaussian form
`dx = -a * x dt + sigma1 dW1`, `dy = -b * y dt + sigma2 dW2`,
`corr(dW1, dW2) = rho`, with `r = x + y + phi(t)`. `hw2f_step` is one Euler
step, mixing `z2` into the second shock as `rho * z1 + sqrt(1 - rho^2) * z2`;
`hw2f_path` returns the two factors at `t` on each path. Neither adds the
deterministic shift `phi(t)`: fit it to your curve and add it yourself.

## LIBOR market model and HJM

```chelis
def lmm_step[k](forwards: tensor[k, f32], taus: tensor[k, f32], sigmas: tensor[k, f32], corr: tensor[k, k, f32], dt: f32, normals: tensor[k, f32]) -> tensor[k, f32]
def lmm_path[k, n](rng_key: key, paths_template: tensor[n, f32], forwards0: tensor[k, f32], taus: tensor[k, f32], sigmas: tensor[k, f32], corr: tensor[k, k, f32], t: f32, n_steps: i64, forward_idx: i64) -> tensor[n, f32]
def hjm_no_arb_drift[k](sigmas: tensor[k, f32], taus: tensor[k, f32]) -> tensor[k, f32]
def step_hjm[k](forwards: tensor[k, f32], drifts: tensor[k, f32], sigmas: tensor[k, f32], dt: f32, normals: tensor[k, f32]) -> tensor[k, f32]
```

`lmm_step` advances `k` simple forward rates `L_i`, each over an accrual
period `taus[i]` with lognormal volatility `sigmas[i]`, by one step under
the terminal measure:

`L_i <- L_i * exp((mu_i - sigma_i^2 / 2) * dt + sigma_i * sqrt(dt) * (C z)_i)`

with `mu_i = -sigma_i * sum_{j > i} tau_j * L_j * sigma_j * corr[i, j] / (1 + tau_j * L_j)`,
`C` the Cholesky factor of `corr`, and `z` the independent standard
`normals` you pass. The last forward has zero drift. `corr` must be a
positive-definite correlation matrix; otherwise the factor, and every
forward, is NaN.

`lmm_path` runs `n_steps` steps of `t / n_steps` from `forwards0` on each
path and returns forward number `forward_idx` (zero-based) at `t`. Use
`0 <= forward_idx < k`. With `n_steps <= 0` no step is taken and every path
returns `forwards0[forward_idx]`.

```chelis
fwd = to_tensor([cast(0.03, f32), cast(0.035, f32)])
taus = to_tensor([cast(0.5, f32), cast(0.5, f32)])
sigs = to_tensor([cast(0.2, f32), cast(0.2, f32)])
corr = reshape(to_tensor([cast(1.0, f32), cast(0.9, f32), cast(0.9, f32), cast(1.0, f32)]), [cast(2, i64), cast(2, i64)])
stepped = lmm_step(copy(fwd), copy(taus), copy(sigs), copy(corr), cast(0.25, f32), to_tensor([cast(0.5, f32), cast(-0.5, f32)]))
-- [0.03137598, 0.035643026]
```

With 500 paths of 10 steps over half a year, the terminal-measure
martingale `L_1` has a sample mean of `0.035088044` against its start of
`0.035`.

`hjm_no_arb_drift` returns the discrete HJM drift for deterministic
forward volatilities: entry `i` is
`sigmas[i] * sum_{j <= i} taus[j] * sigmas[j]`. For three forwards with
volatility 0.01 and unit periods it is `[0.0001, 0.0002, 0.00029999999]`.
`step_hjm` adds `drifts * dt + sigmas * sqrt(dt) * normals` to each forward,
one independent normal per forward.

## SABR paths

```chelis
def sabr_qe_step(f: f32, alpha: f32, beta: f32, rho: f32, nu: f32, dt: f32, z_f: f32, z_alpha: f32) -> (f32, f32)
def sabr_path_terminal(rng_key: key, f0: f32, alpha0: f32, beta: f32, rho: f32, nu: f32, t: f32, n_steps: i64) -> (f32, f32)
def sabr_paths_terminal[n](rng_key: key, paths_template: tensor[n, f32], f0: f32, alpha0: f32, beta: f32, rho: f32, nu: f32, t: f32, n_steps: i64) -> (tensor[n, f32], tensor[n, f32])
```

The SABR model `dF = alpha * F^beta dW1`, `d alpha = nu * alpha dW2`,
`corr(dW1, dW2) = rho`. Despite its name, `sabr_qe_step` is a log-Euler
step, not a quadratic-exponential one:

- `ln F` moves by `-alpha^2 * F^(2 beta - 2) * dt / 2 + alpha * F^(beta - 1) * sqrt(dt) * (rho * z_alpha + sqrt(1 - rho^2) * z_f)`;
- `alpha` moves exactly, by the factor `exp(-nu^2 * dt / 2 + nu * sqrt(dt) * z_alpha)`.

Both `F` and `alpha` are floored at `1e-10`, so a forward never reaches
zero; the model's absorbing barrier at zero is not reproduced. The two
`_terminal` functions run `n_steps` steps and return `(F_T, alpha_T)`, for
one path or for each path. With `f0 = 0.03`, `alpha0 = 0.035`,
`beta = 0.5`, `rho = -0.2`, `nu = 0.4`, 2000 paths of 50 steps over one
year have a mean `F_T` of `0.029831063`. For SABR implied volatilities see
[Volatility surface](volsurface.md).

## Heston Fourier pricers

```chelis
def heston_charfn(u: (f32, f32), s0: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, t: f32) -> (f32, f32)
def heston_call_carr_madan(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, alpha: f32, u_max: f32) -> f32
def heston_call_carr_madan_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, alpha: f32, u_max: f32, n_panels: i64) -> f32
def heston_call_lipton_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, u_max: f32, n_panels: i64) -> f32
def heston_call_lewis_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, u_max: f32, n_panels: i64) -> f32
```

The argument order is `(s0, k, t, r, ...)`, with maturity before the rate,
unlike the Black-Scholes pricers. The model parameters are as in
[Stochastic processes](stochastic.md): `v0` and `theta` are
variances, `kappa` the mean-reversion speed, `sigma` the volatility of
variance, `rho` the correlation. There is no dividend yield.

`heston_charfn` is the characteristic function `E[exp(i * u * ln S_T)]`
under the risk-neutral drift `r`, with complex `u` and the result passed as
`(real, imaginary)` pairs. It uses the rotation-stable form of the
complex logarithm (the "little Heston trap").

Each pricer integrates over `[0, u_max]` with 10-point Gauss-Legendre
rules, one rule over the whole range for `heston_call_carr_madan` and one
per panel for the `_panels` forms, and clamps a negative result to 0.
Supply `u_max > 0` large enough that the integrand has decayed (100 in the
examples), `n_panels >= 1` (each panel is one 10-point rule, so the panel
width `u_max / n_panels` should stay a few units), and for Carr-Madan a
damping `alpha > 0` for which `E[S_T^(alpha + 1)]` is finite; 1.5 is
typical. `n_panels = 0` integrates nothing and returns a meaningless price.
`heston_call_carr_madan_panels` is the Carr-Madan damped transform with
damping `alpha` (1.5 is typical); `heston_call_lipton_panels` is the
two-probability form `s0 * P1 - k * exp(-r * t) * P2`. Each `_panels` call
has a put partner, `call + k * exp(-r * t) - s0` clamped at 0, with the
same arguments:

```chelis
def heston_put_carr_madan_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, alpha: f32, u_max: f32, n_panels: i64) -> f32
def heston_put_lipton_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, u_max: f32, n_panels: i64) -> f32
def heston_put_lewis_panels(s0: f32, k: f32, t: f32, r: f32, v0: f32, kappa: f32, theta: f32, sigma: f32, rho: f32, u_max: f32, n_panels: i64) -> f32
```

```chelis
cm = heston_call_carr_madan_panels(cast(100.0, f32), cast(100.0, f32), cast(1.0, f32), cast(0.05, f32), cast(0.04, f32), cast(1.5, f32), cast(0.04, f32), cast(0.5, f32), cast(-0.7, f32), cast(1.5, f32), cast(100.0, f32), cast(20, i64))
-- 10.055485
lp = heston_call_lipton_panels(cast(100.0, f32), cast(100.0, f32), cast(1.0, f32), cast(0.05, f32), cast(0.04, f32), cast(1.5, f32), cast(0.04, f32), cast(0.5, f32), cast(-0.7, f32), cast(100.0, f32), cast(20, i64))
-- 10.055477
```

`heston_call_lewis_panels` and `heston_put_lewis_panels` agree with the
other two only when the strike equals the forward `s0 * exp(r * t)`. With
the inputs above they return `12.281982` for the call. At
`k = 105.12711`, the forward, the Lewis call is `7.030327` and the Lipton
call `7.024296`. Away from the forward, use the Carr-Madan or Lipton
forms.

## Dupire local volatility

```chelis
def du_local_vol_from_call_closure(call_fn: f32 -> f32 -> f32, r: f32, q: f32, k_query: f32, t_query: f32, fd_eps_k: f32, fd_eps_t: f32) -> f32
def du_local_vol_from_iv_surface(iv_surface_fn: f32 -> f32 -> f32, s0: f32, r: f32, q: f32, k_query: f32, t_query: f32, fd_eps_k: f32, fd_eps_t: f32) -> f32
def du_cubic_log_moneyness_interp[n_k, n_t](strikes: &tensor[n_k, f32], times: &tensor[n_t, f32], iv_grid: &tensor[n_t, n_k, f32], forward: f32, k_query: f32, t_query: f32) -> f32
def du_bs_call_q(s: f32, k: f32, r: f32, q: f32, sigma: f32, t: f32) -> f32
def du_forward(s0: f32, r: f32, q: f32, t: f32) -> f32
def du_local_vol_sentinel() -> f32
def du_is_local_vol_sentinel(x: f32) -> bool
```

`du_local_vol_from_call_closure` takes call prices as a function
`call_fn(k, t)` and evaluates Dupire's formula at `(k_query, t_query)`:

`sigma_loc^2 = (dC/dT + (r - q) * K * dC/dK + q * C) / (K^2 * d2C/dK2 / 2)`

with central differences of step `fd_eps_k` in strike and `fd_eps_t` in
time (the lower time point is floored at `1e-4`). Where
`d2C/dK2 < 1e-10` (no positive implied density) or the ratio is negative,
it returns the NaN sentinel; test for it with `du_is_local_vol_sentinel`.

`du_local_vol_from_iv_surface` does the same from an implied-volatility
function `iv_surface_fn(m, t)`, where `m = ln(K / F(t))` is log-moneyness
against the forward `du_forward(s0, r, q, t) = s0 * exp((r - q) * t)`; it
prices calls with `du_bs_call_q`, the Black-Scholes call with dividend yield
`q`. A flat 20% surface returns its own volatility:

```chelis
flat = du_local_vol_from_iv_surface(fn (m: f32, t: f32) -> cast(0.2, f32), cast(100.0, f32), cast(0.05, f32), cast(0.0, f32), cast(100.0, f32), cast(1.0, f32), cast(1.0, f32), cast(0.01, f32))
-- 0.20001782
```

`du_cubic_log_moneyness_interp` reads an implied volatility from a grid:
row `j` of `iv_grid` holds the vols at `times[j]` across `strikes`. It fits a
natural cubic spline in `ln(K / forward)` along each row, then interpolates
linearly in time, flat outside the first and last times. One `forward`
serves every row. Strikes and times must be strictly increasing; see
[Scope and limitations](scope.md) for the ordering check and its
edge cases.

```chelis
sk = to_tensor([cast(80.0, f32), cast(100.0, f32), cast(120.0, f32)])
ts = to_tensor([cast(0.5, f32), cast(1.0, f32)])
grid = reshape(to_tensor([cast(0.25, f32), cast(0.2, f32), cast(0.18, f32), cast(0.24, f32), cast(0.2, f32), cast(0.19, f32)]), [cast(2, i64), cast(3, i64)])
iv = du_cubic_log_moneyness_interp(sk, ts, grid, cast(100.0, f32), cast(90.0, f32), cast(0.75, f32))
-- 0.21845599
```
