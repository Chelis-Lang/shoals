module ShoalsBlockedErfF32Only
-- EXPECTED TO FAIL at this pin: the only `erf` reachable from a Shoals module
-- is `Nautilus.Special.erf`, which is f32-only, so an f64 path cannot call it.
-- That is why Shoals.Pricing hand-rolls `erf64` -- and why the hand-rolled copy
-- carries Abramowitz-Stegun 7.1.26's ~1.5e-7 bound, which no wider cast
-- improves, since the bound belongs to the coefficients.
--
-- When this probe PASSES, an f64 path can call the package `erf` directly.
-- See the sidecar for the de-narrowing steps.
def probe(x: f64) -> f64 = erf(x)
