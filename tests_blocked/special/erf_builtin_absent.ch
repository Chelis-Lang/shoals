module ShoalsBlockedErfF32Only
-- EXPECTED TO FAIL at this pin: the only `erf` reachable from a Shoals module
-- is `Nautilus.Special.erf`, which is f32-only, so an f64 path cannot call it.
-- That is why Shoals.Pricing hand-rolls `erf64`. That copy now evaluates
-- Cody's rational approximation (~2.7e-16); the duplication is what this probe
-- tracks, not the accuracy. `Nautilus.Special.erf` still carries Abramowitz-
-- Stegun 7.1.26's ~1.5e-7 bound -- see nautilus#56.
--
-- When this probe PASSES, an f64 path can call the package `erf` directly.
-- See the sidecar for the de-narrowing steps.
def probe(x: f64) -> f64 = erf(x)
