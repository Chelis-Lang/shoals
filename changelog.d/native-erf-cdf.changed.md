Use Chelis's correctly rounded `erf` and `erfc` builtins in Shoals callers
and make `Shoals.Pricing.erf64` a compatibility wrapper. Route `n_cdf64`
through Chelis's `standard_normal_cdf` so left-tail probabilities retain
relative precision, including below x = -8.
