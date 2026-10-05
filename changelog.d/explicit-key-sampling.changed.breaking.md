Shoals stochastic, Monte Carlo pricing, distribution-sampling, and XVA exports
now consume an explicit affine key as their first argument. Callers construct a
key with `key_from_seed` and split it for separate draws; the retired `Random`
effect and `with seed` handler are removed.
