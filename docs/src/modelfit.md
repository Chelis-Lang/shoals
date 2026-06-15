# Calibration

Module: `Shoals.ModelFit`.

This module supports least-squares model calibration: weighted squared and
absolute residuals, a vega-weighted variant for volatility fitting, a
sum-of-squared-errors loss, bound projection, and a single bound-clamped
Levenberg-Marquardt step on a scalar parameter.

## Bound projection

```chelis
def clamp_to_bounds(x: f32, lo: f32, hi: f32) -> f32
```

`clamp_to_bounds` projects `x` into `[lo, hi]`, returning `lo` below the
range, `hi` above it, and `x` unchanged inside. From `tests/modelfit.ch`,
`clamp_to_bounds(5.0, 0.0, 1.0) == 1.0`.

## Residuals

```chelis
def weighted_squared_residuals[n](observed: tensor[n, f32], predicted: tensor[n, f32], weights: tensor[n, f32]) -> tensor[n, f32]
def weighted_absolute_residuals[n](observed: tensor[n, f32], predicted: tensor[n, f32], weights: tensor[n, f32]) -> tensor[n, f32]
def vega_weighted_squared_residuals[n](observed: tensor[n, f32], predicted: tensor[n, f32], vegas: tensor[n, f32]) -> tensor[n, f32]
```

`weighted_squared_residuals` returns `weight * (observed - predicted)^2` per
point, and `weighted_absolute_residuals` returns `weight * |observed - predicted|`.
`vega_weighted_squared_residuals` weights each squared residual by the
inverse square of the point's vega, so points with smaller vega receive more
weight (and a zero vega contributes no weight). From `tests/modelfit.ch`:

```chelis
observed = to_tensor([cast(1.0, f32), cast(2.0, f32), cast(3.0, f32)])
predicted = to_tensor([cast(1.1, f32), cast(2.2, f32), cast(2.7, f32)])
weights = to_tensor([cast(1.0, f32), cast(1.0, f32), cast(1.0, f32)])
res = weighted_squared_residuals(observed, predicted, weights)
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
damping `lambda` attenuates the step, and a zero `jtr` leaves the parameter
in place. From `tests/modelfit.ch`:

```chelis
step = lm_bounded_step_scalar(cast(1.0, f32), cast(0.0, f32), cast(0.001, f32), cast(0.5, f32), cast(0.0, f32), cast(1.0, f32))
// step == 0.5 (no residual, no move)
```

A proposed step that overshoots a bound is clamped to that bound, and a
larger `lambda` produces a smaller, more conservative move.
