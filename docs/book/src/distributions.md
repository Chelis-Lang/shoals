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
`lognormal_cdf` is the cumulative, also zero for non-positive `x`. Supply
`sigma > 0`; it is not checked, and `sigma <= 0` returns NaN or an
infinity. For example:

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
`Nautilus.Distributions.student_t_cdf`. `student_t_cdf_approx` is
`N(x * sqrt(1 - 2 / (4 * nu - 1)))`, a rescaled standard normal CDF. It
is cheap but it keeps normal tails, so it understates tail probability at low
`nu`:

| `x` | `nu` | `student_t_cdf_approx` | `student_t_cdf_exact` |
|---:|---:|---:|---:|
| 2 | 5 | 0.97074187 | 0.9490303 |
| 2 | 30 | 0.9763231 | 0.9726874 |
| 3 | 3 | 0.9966722 | 0.97116554 |

At `nu = 5` the approximation puts 2.9% in the tail beyond `x = 2`, where
the exact value is 5.1%. Use `student_t_cdf_exact` for any tail
quantity, such as a VaR or a p-value. Supply `nu > 0`; nothing checks it.
The approximation also needs `nu > 0.75`, below which its square root is
of a negative number and it returns NaN. For example:

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
`1 / (2 * pi)`. Supply `sigma_x > 0`, `sigma_y > 0`, and `|rho| < 1`; at
`|rho| = 1` the density divides by zero and returns an infinity or NaN. For example:

```chelis
p = bvn_pdf(cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(0.0, f32), cast(1.0, f32), cast(1.0, f32), cast(0.0, f32))
// p ~ 0.159155
```

Selected density and lognormal-CDF inputs are compared with textbook
references under the [property checks](properties.md).

## Other distributions

These pass straight through to `Nautilus.Distributions`. All arguments are
`f32`; a sampler fills a tensor the length of `template` from `rng_key`.
Scales, rates, shapes, and degrees of freedom must be positive and
`lo < hi`. Only the beta functions (NaN for `a <= 0` or `b <= 0`) and the
Poisson functions (NaN for `lambda < 0`) check their parameters; the others
return whatever the formula gives. Outside the support the densities return
0, not NaN: gamma, chi-squared, and exponential for `x < 0`, beta outside
`[0, 1]`, uniform outside `[lo, hi]`, and the Poisson pmf for `k < 0` or a
non-integer `k`. The exponential and uniform CDFs return 0 below the support
and 1 above it, and the Poisson CDF is 0 for `k < 0`. Inverse CDFs take `q`
in `[0, 1]`.

| Family | Functions | Parameters |
|---|---|---|
| Gamma | `gamma_pdf_s(x, shape, scale)`, `gamma_cdf_s(x, shape, scale)`, `gamma_inv_cdf_s(q, shape, scale)`, `gamma_sample_s(rng_key, template, shape, scale)` | shape-scale form: mean `shape * scale` |
| Beta | `beta_pdf_s(x, a, b)`, `beta_cdf_s(x, a, b)` | `a > 0`, `b > 0`, else NaN |
| Chi-squared | `chi_squared_pdf_s(x, df)`, `chi_squared_cdf_s(x, df)`, `chi_squared_inv_cdf_s(q, df)`, `chi_squared_sample_s(rng_key, template, df)` | gamma with shape `df / 2`, scale 2 |
| Exponential | `exponential_pdf_s(x, rate)`, `exponential_cdf_s(x, rate)`, `exponential_inv_cdf_s(q, rate)`, `exponential_sample_s(rng_key, template, rate)` | mean `1 / rate` |
| Uniform | `uniform_pdf_s(x, lo, hi)`, `uniform_cdf_s(x, lo, hi)`, `uniform_inv_cdf_s(q, lo, hi)`, `uniform_sample_s(rng_key, template, lo, hi)` | on `[lo, hi]` |
| Poisson | `poisson_pmf_s(k, lambda)`, `poisson_cdf_s(k, lambda)` | `k` is an `f32` count; a non-integer `k` has mass 0 |

The gamma, chi-squared, and exponential inverse CDFs return NaN for `q`
outside `[0, 1]` and `+inf` at `q = 1`; `uniform_inv_cdf_s` is
`lo + q * (hi - lo)` for any `q`.
`gamma_inv_cdf_s` starts from the Wilson-Hilferty estimate and takes 80
Newton steps. The gamma and chi-squared samplers use Marsaglia-Tsang
rejection, which is valid for `shape >= 1` (`df >= 2`); a draw with no
accepted candidate among its 64 is NaN.

## Multivariate normal

```chelis
def dist_mvn_factor[d](sigma: &tensor[d, d, f32]) -> tensor[d, d, f32]
def dist_mvn_sample_one[d](rng_key: key, template: tensor[d, f32], mu: tensor[d, f32], sigma_lower: tensor[d, d, f32]) -> tensor[d, f32]
```

`dist_mvn_factor` returns the lower-triangular Cholesky factor `L` of a
`d x d` covariance, with `L * L^T = sigma`; it reads the lower triangle.
`dist_mvn_sample_one` draws `d` standard normals `z` and returns
`mu + L * z`, one sample per call; split the key for further samples.

```chelis
cov = reshape(to_tensor([cast(4.0, f32), cast(2.0, f32), cast(2.0, f32), cast(3.0, f32)]), [cast(2, i64), cast(2, i64)])
lower = dist_mvn_factor(cov)  // [[2.0, 0.0], [1.0, 1.4142135]]
x = dist_mvn_sample_one(key_from_seed(1i64), to_tensor([cast(0.0, f32), cast(0.0, f32)]), to_tensor([cast(1.0, f32), cast(2.0, f32)]), lower)
// [1.3352878, 1.6313807]
```

The factorization does not check its input. A covariance that is not
positive definite takes the square root of a negative pivot and returns NaN
entries instead of failing: the factor of `[[1, 2], [2, 1]]` is NaN in all four entries.
Test the factor for NaN before sampling.
