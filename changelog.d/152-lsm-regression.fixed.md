Repair Longstaff-Schwartz American-put continuation regression (shoals#152):
centered/scaled `f64` polynomial QR replaces raw `f32` normal-equation
inversion, and rank-deficient observations fit a lower-degree polynomial.
The pricer includes immediate exercise and expiry, and rejects invalid inputs
with explicit diagnostics. Public regression coefficients retain their
original `1, x, x²` meaning. Numerical and sampled checks do not promise
samplewise monotonicity or an exact European lower bound.
