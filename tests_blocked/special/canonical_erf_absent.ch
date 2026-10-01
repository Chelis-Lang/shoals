module ShoalsBlockedCanonicalErfAbsent
-- chelis#902: the language has no canonical erf primitive.
-- Nautilus.Special.erf is imported in the positive test instead.
def probe(x: f64) -> f64 = erf(x)
