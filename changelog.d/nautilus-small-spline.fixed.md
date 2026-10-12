With Nautilus 0.7.53, `spline_rate_at` preserves the natural cubic spline fit
when finite pillar spacings are below the former tridiagonal pivot floor. A
four-pillar curve with knots and rates scaled by 1e-31 now returns 2.2e-31 at
the midpoint, instead of the former 2.5e-31.
