# Calibration

Module: `Shoals.ModelFit`.

This module supports least-squares model calibration: weighted squared and
absolute residuals, a vega-weighted variant, loss functions, bound
projection, and bounded optimization helpers for scalar and vector
parameters.

## Bound projection

```chelis
def clamp_to_bounds(x: f32, lo: f32, hi: f32) -> f32
```

`clamp_to_bounds` projects `x` into `[lo, hi]`, returning `lo` below the
range, `hi` above it, and `x` unchanged inside. For example,
`clamp_to_bounds(5.0, 0.0, 1.0) == 1.0`. It tests `x < lo` first and does
not check `lo <= hi`, so with inverted bounds a value below `lo` returns
`lo`: `clamp_to_bounds(0.5, 1.0, 0.0)` is `1.0`. A NaN `x` fails both tests and comes back NaN.

## Residuals

```chelis
def weighted_squared_residuals[n](observed: tensor[n, f32], predicted: tensor[n, f32], weights: tensor[n, f32]) -> tensor[n, f32]
def weighted_absolute_residuals[n](observed: tensor[n, f32], predicted: tensor[n, f32], weights: tensor[n, f32]) -> tensor[n, f32]
def vega_weighted_squared_residuals[n](observed: tensor[n, f32], predicted: tensor[n, f32], vegas: tensor[n, f32]) -> tensor[n, f32]
```

`weighted_squared_residuals` returns `weight * (observed - predicted)^2` per
point, and `weighted_absolute_residuals` returns `weight * |observed - predicted|`.
`vega_weighted_squared_residuals` uses the weight `1 / vega^2`, so points
with smaller vega receive more weight. A vega exactly equal to `0.0` gets
weight 0 and drops out. Any other vega, however small, is divided in full: a
vega of `0.001` multiplies its squared residual by a million, and a NaN vega
gives a NaN residual. Floor or exclude near-zero vegas before calling it.
For example:

```chelis
observed = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
predicted = to_tensor([cast(1.1, f32), cast(2.2, f32), cast(2.7, f32)])
weights = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
res = weighted_squared_residuals(observed, predicted, weights)
// [0.010000004, 0.040000018, 0.089999974]
v = vega_weighted_squared_residuals(observed, predicted, to_tensor([cast(0.0, f32), cast(0.001, f32), cast(2.0, f32)]))
// [0.0, 40000.01, 0.022499993]
```

## Loss

```chelis
def sse_loss[n](residuals: tensor[n, f32]) -> f32
```

`sse_loss` sums a residual tensor to a single sum-of-squared-errors value.
On the residuals above the loss is `0.01 + 0.04 + 0.09 == 0.14`.

## Levenberg-Marquardt step

```chelis
def lm_bounded_step_scalar(jtj: f32, jtr: f32, lambda: f32, current: f32, lo: f32, hi: f32) -> f32
```

`lm_bounded_step_scalar` takes one damped Gauss-Newton step on a scalar
parameter: it computes `step = jtr / (jtj + lambda)`, moves the current
value to `current - step`, and projects the result into `[lo, hi]`. The
damping `lambda` attenuates the step. If `jtj + lambda` is exactly
zero, the function uses a zero step before clamping. For example:

```chelis
step = lm_bounded_step_scalar(cast(1.0, f32), cast(0.0, f32), cast(0.001, f32), cast(0.5, f32), cast(0.0, f32), cast(1.0, f32))
// step == 0.5 (no residual, no move)
```

A proposed step that overshoots a bound is clamped to that bound, and a
larger `lambda` produces a smaller, more conservative move.

## Vector parameters

```chelis
def lm_bounded_nparam[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], features: &tensor[m, f32], observed: &tensor[m, f32], weights: &tensor[m, f32], theta0: tensor[n, f32], lo: &tensor[n, f32], hi: &tensor[n, f32], lambda0: f32, tol: f32, max_iters: i64, fd_eps: f32) -> (tensor[n, f32], f32, i64, bool, tensor[n, f32])
def bfgs_bounded_nparam[n, m](model: &tensor[n, f32] -> &tensor[m, f32] -> tensor[m, f32], features: &tensor[m, f32], observed: &tensor[m, f32], weights: &tensor[m, f32], theta0: tensor[n, f32], lo: &tensor[n, f32], hi: &tensor[n, f32], tol: f32, max_iters: i64, fd_eps: f32) -> (tensor[n, f32], f32, i64, bool, tensor[n, f32])
```

Both fit `n` parameters to `m` observations by minimizing
`sum(weights * (observed - model(theta, features))^2)`. The `model` callback
takes the parameter vector and the feature vector and returns one prediction
per observation. Every iterate is clamped into `[lo, hi]`, starting with
`theta0`. Derivatives are forward differences with step `fd_eps` in each
parameter, one extra `model` call per parameter per step.

- `lm_bounded_nparam` is Levenberg-Marquardt. It starts with damping
  `lambda0`, divides it by 3 after a step that lowers the loss and
  multiplies it by 3 after one that does not (bounded to `[1e-7, 1e7]`),
  and rejects any step that does not lower the loss.
- `bfgs_bounded_nparam` is BFGS from the identity matrix with an Armijo
  backtracking line search (up to 20 halvings).
- `multi_target_fit` has exactly the signature of `lm_bounded_nparam`
  (same arguments, same five-element result) and returns its result
  unchanged.

Each stops after `max_iters` steps, or earlier when an accepted step lowers
the loss by a relative amount below `tol` (BFGS also stops when the gradient
norm falls below `tol * max(1, |theta|)`). The result is
`(theta, loss, iterations, converged, at_bound)`. `converged` is `false`
when the iteration cap was reached. `at_bound` has a 1 for each parameter
within `1e-4` of `lo` or `hi`; a fit that ends on a bound has not found an
interior minimum.

None of these inputs is checked. Supply nonnegative `weights`,
`fd_eps > 0`, `tol >= 0`, `lambda0 > 0`, `lo <= hi` element by element, and
`max_iters >= 0`; `max_iters = 0` returns the clamped `theta0` with
`converged = false`. A negative weight rewards misfit at that point and a
zero `fd_eps` divides by zero.

## SABR starting points and two-stage fits

```chelis
def mf_sabr_smart_initializer[n](strikes: &tensor[n, f32], market_ivs: &tensor[n, f32], forward: f32, t: f32) -> tensor[4, f32]
def mf_sabr_multi_start_initializer[n](strikes: &tensor[n, f32], market_ivs: &tensor[n, f32], forward: f32, t: f32) -> tensor[5, 4, f32]
def sequential_pipeline_2stage[n1, m1, n2, m2](model1: &tensor[n1, f32] -> &tensor[m1, f32] -> tensor[m1, f32], features1: &tensor[m1, f32], observed1: &tensor[m1, f32], weights1: &tensor[m1, f32], theta1_0: tensor[n1, f32], lo1: &tensor[n1, f32], hi1: &tensor[n1, f32], stage1_to_stage2_features: &tensor[n1, f32] -> tensor[m2, f32], model2: &tensor[n2, f32] -> &tensor[m2, f32] -> tensor[m2, f32], observed2: &tensor[m2, f32], weights2: &tensor[m2, f32], theta2_0: tensor[n2, f32], lo2: &tensor[n2, f32], hi2: &tensor[n2, f32], lambda0: f32, tol: f32, max_iters: i64, fd_eps: f32) -> (tensor[n1, f32], tensor[n2, f32], f32, f32, i64, i64, bool, bool)
def sequential_pipeline_2stage_gradient[n1, m1, n2, m2](model1: &tensor[n1, f32] -> &tensor[m1, f32] -> tensor[m1, f32], features1: &tensor[m1, f32], observed1: &tensor[m1, f32], weights1: &tensor[m1, f32], theta1_0: &tensor[n1, f32], lo1: &tensor[n1, f32], hi1: &tensor[n1, f32], stage1_to_stage2_features: &tensor[n1, f32] -> tensor[m2, f32], model2: &tensor[n2, f32] -> &tensor[m2, f32] -> tensor[m2, f32], observed2: &tensor[m2, f32], weights2: &tensor[m2, f32], theta2_0: &tensor[n2, f32], lo2: &tensor[n2, f32], hi2: &tensor[n2, f32], lambda0: f32, tol: f32, max_iters: i64, fd_eps: f32, bump_eps: f32) -> tensor[n2, m1, f32]
```

`mf_sabr_smart_initializer` takes matching strike and market implied-vol
tensors (positive strikes, vols as decimals), the forward, and the maturity
`t` (accepted but not used). It returns a SABR starting point
`[alpha, beta, rho, nu]` with `beta = 0.5`, `alpha` the at-the-money vol
(the strike nearest the forward) times `sqrt(forward)`, and `rho` and `nu`
from the 90%/110% risk reversal and butterfly, clamped to `[-0.9, 0.9]` and
`[0.1, 3.0]`. With fewer than three strikes, or strikes that do not span the
forward, it returns `rho = 0` and `nu = 0.5`.
`mf_sabr_multi_start_initializer` returns a `5 x 4` tensor: five rows of
that point with `rho` replaced by -0.7, -0.3, 0, 0.3, and 0.7.

`sequential_pipeline_2stage` fits `model1` with `lm_bounded_nparam`, passes
the fitted stage-one parameters to the callback
`stage1_to_stage2_features`, which returns the `m2` features of the second
model, and fits `model2` on them with the same `lambda0`, `tol`,
`max_iters`, and `fd_eps`. It returns
`(theta1, theta2, loss1, loss2, iterations1, iterations2, converged1, converged2)`.
`sequential_pipeline_2stage_gradient` takes the same arguments, with
`theta1_0` and `theta2_0` borrowed (`&tensor`), plus `bump_eps`: it bumps
each stage-one observation by `bump_eps`, refits both stages, and returns
the `n2 x m1` forward-difference sensitivity of the stage-two parameters,
`m1` refits in all.
