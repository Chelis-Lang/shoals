An optional local runner checks bounded Chelis properties for the Heston,
Longstaff-Schwartz, spread PDE, and jump-moment regressions at three seeds.
Every positive property must accept 25 samples, and every deliberately false
control must return a counterexample. Its optional expiry smoke selects only
LSM and spread expiry pairs at seed 0, with a 60-second ceiling per process.
The runner provides sampling evidence when executed; it is not a hosted or
release blocker, and adding it does not claim a completed three-seed run.
