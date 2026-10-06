**BREAKING: every path sampler in `Shoals.Stochastic` refuses a time horizon
that is not finite and non-negative** (shoals#139). A negative `t` previously
returned NaN for every path value with no diagnostic. `t = 0` and `t = -0.0`
remain admitted and still return s0.
