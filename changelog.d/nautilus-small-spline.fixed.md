With Nautilus 0.7.53, `spline_rate_at` on a four-pillar curve with knots and
rates scaled by 1e-31 returns 2.2e-31 at the midpoint, instead of the former
2.5e-31 caused by a substituted tridiagonal pivot.
