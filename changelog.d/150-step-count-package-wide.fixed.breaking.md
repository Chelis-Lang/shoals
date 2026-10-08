**BREAKING: `Shoals.HullWhite`, `Shoals.SabrPaths`, `Shoals.LiborMarketModel`
and `Shoals.Trees` refuse a step count below 1** (shoals#150), on the same
reasoning as the two `Shoals.Stochastic` entry points above. With
`n_steps <= 0` the step range was empty, so `hw1f_path` and `hw2f_path`
returned `r0` and `(x0, y0)`, both SABR samplers returned `f0`, and `lmm_path`
returned the initial forward curve -- at every path, for a horizon over which
the process really did evolve.

`Shoals.Trees` failed harder, and is the reason the fix reaches beyond the
Heston pair. Its ten pricers form `dt = t / n_steps`, so a zero step count
divides the horizon by zero; the non-finite step poisons the lattice's up and
down log-moves and the terminal node prices collapse to a flat `0.0`
regardless of moneyness -- not the intrinsic value. Measured at
s0 = 100, r = 0.05, q = 0, sigma = 0.2, t = 1.0: a K = 90 call priced at
`0.0` against 16.69197 at `n_steps = 64` and an intrinsic of 10, and a K = 110
American put priced at `0.0` against 11.964398. A negative count already
aborted there, but with `index 0 out of bounds for list of len 0`, which names
an index rather than the violated precondition; the guard replaces that leaked
error with a diagnostic naming the step count.

Each module carries its own check so its diagnostic names the module a caller
invoked, following `ind_require_period`'s precedent in `Shoals.Indicators`.

In `Shoals.Trees` the guard sits where `n_steps` enters the computation rather
than at each pricer's entry, because every pricer short-circuits a sub-floor
`sigma` to a deterministic forward price that takes no step count and returned
14.389351 at `n_steps` 0, 64 and -8 alike. A sub-floor volatility therefore
still prices at any step count, and `tests/step_count_parity.ch` pins that so
a later tightening cannot quietly take it away.

`Shoals.Lsm.lsm_american_put` takes a step count and is deliberately
unchanged: it already fails loudly at `n_steps <= 0` and returns no plausible
wrong number.

Four other count families are NOT covered by this change and still return a
plausible number below their documented domain; they are tracked in
shoals#166. `Shoals.Pde`'s time-step count `n_t` is the
same mechanism: `pde_european_call_cn` at `s0 = 100`, `K = 90`, `t = 1.0`
returns `10.015209` at both `n_t = 0` and `n_t = -8`, against `16.730183` at
`n_t = 20`, and `pde_american_put_cn` at `K = 110` returns `9.984791` at
`n_t = 0` against `11.933073`. `Shoals.Heston`'s quadrature panel count
`n_panels` behaves likewise: `heston_call_lewis_panels` returns `100.0`, the
spot, at `n_panels = 0` against `23.196457` at 20, and
`heston_call_carr_madan_panels` returns `0.0` against `16.986883`. Two more
are the same shape: `cds_pv` returns `0.05308778` at a payment frequency of
`0` and of `-4`, against `0.009123858` at `4`, and
`xva_cva_wwr_constant_hazard` returns `-0.0` at `n_paths = -8` against
`0.24702658` at `64`. `Shoals.Pde` also returns a call price above the spot,
`107.19469`, at a space grid of `n_x = 2`, below its documented minimum of 3.
All are left for separate work rather than folded in here.
