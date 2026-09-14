module ShoalsBlockedErfF32Only
import Nautilus.Special (erf)
-- EXPECTED TO FAIL at this pin: the only `erf` reachable from a Shoals module
-- is `Nautilus.Special.erf`, which is f32-only, so an f64 path cannot call it.
-- That is why Shoals.Pricing hand-rolls `erf64`. That copy now evaluates
-- Cody's rational approximation (>= 3.3675e-16); the duplication is what this probe
-- tracks, not the accuracy. `Nautilus.Special.erf` still carries Abramowitz-
-- Stegun 7.1.26's ~1.5e-7 bound -- see nautilus#56.
--
-- Chelis 0.18.9 no longer resolves a dependency-exported name unqualified, so
-- the symbol is now named through an explicit `import Nautilus.Special (erf)`.
-- The f32-only signature is still the blocker, not the import: nautilus 0.7.44
-- keeps `def erf(x: f32) -> f32`. Without the import 0.18.9 reports `unbound
-- variable: erf`; with it the probe reproduces the pinned `precision mismatch`
-- width refusal exactly as measured on 0.18.6.
--
-- When this probe PASSES, an f64 path can call the package `erf` directly.
-- See the sidecar for the de-narrowing steps.
def probe(x: f64) -> f64 = erf(x)
