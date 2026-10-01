# Distributions

Module: `Shoals.Distributions`.

This module adds finance-relevant densities and cumulatives on top of the
normal distribution from `Nautilus.Distributions` and the log-gamma special
function from `Nautilus.Special`: the lognormal density and cumulative, the
Student-t density and cumulative functions, and the bivariate-normal
density. It also exports wrappers around Nautilus's gamma, beta,
chi-squared, exponential, uniform, and Poisson distribution functions,
plus a Cholesky-based multivariate-normal sampler.

## Lognormal

```chelis
def lognormal_pdf(x: f32, mu: f32, sigma: f32) -> f32
def lognormal_cdf(x: f32, mu: f32, sigma: f32) -> f32
```

`lognormal_pdf` is the density of a lognormal whose log has mean `mu` and
standard deviation `sigma`, defined to be zero for non-positive `x`.
`lognormal_cdf` is the cumulative, also zero for non-positive `x`. From
`tests/distributions.ch`:

```chelis
p = lognormal_pdf(cast(1.0, f32), cast(0.0, f32), cast(1.0, f32))  // p ~ 0.398942
c = lognormal_cdf(cast(1.0, f32), cast(0.0, f32), cast(1.0, f32))  // c == 0.5
```

## Student-t

```chelis
def student_t_pdf(x: f32, nu: f32) -> f32
def student_t_cdf_exact(x: f32, nu: f32) -> f32
def student_t_cdf_approx(x: f32, nu: f32) -> f32
```

`student_t_pdf` is the Student-t density with `nu` degrees of freedom,
composed over `Nautilus.Special.log_gamma` for the normalizing constant. It
is symmetric about zero. `student_t_cdf_exact` delegates to
`Nautilus.Distributions.student_t_cdf`. `student_t_cdf_approx` is a
normal-based approximation. From `tests/distributions.ch`:

```chelis
p = student_t_pdf(cast(0.0, f32), cast(5.0, f32))  // p ~ 0.379607
```

## Bivariate normal

```chelis
def bvn_pdf(x: f32, y: f32, mu_x: f32, mu_y: f32, sigma_x: f32, sigma_y: f32, rho: f32) -> f32
```

`bvn_pdf` is the bivariate-normal density at `(x, y)` with means
`(mu_x, mu_y)`, standard deviations `(sigma_x, sigma_y)`, and correlation
`rho`. At the origin under independent unit normals it equals
`1 / (2 * pi)`. From `tests/distributions.ch`:

```chelis
p = bvn_pdf(cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(1.0, f32), cast(1.0, f32), cast(0.0, f32))
// p ~ 0.159155
```

Selected density and lognormal-CDF inputs are compared with textbook
references under the [property checks](properties.md).

## Additional distributions

The exported `_s` functions wrap Nautilus gamma, beta, chi-squared,
exponential, uniform, and Poisson calls. For example, `gamma_pdf_s`,
`gamma_cdf_s`, and `gamma_inv_cdf_s` take the same arguments as their
Nautilus counterparts. The sampling wrappers carry `Random` and need
`with seed(...)`. `dist_mvn_factor` computes a Cholesky factor from a
covariance tensor; `dist_mvn_sample_one` uses that lower factor to draw
one multivariate-normal sample. Supply a suitable positive-definite
covariance matrix.
