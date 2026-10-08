**BREAKING: `Shoals.Stochastic.heston_qe_terminal` and `heston_qe_paths_terminal`
refuse a step count below 1** (shoals#150). With `n_steps <= 0` the step range
was empty, so the evolution fold returned its initial state and both samplers
returned s0 and v0 unchanged -- measured 100.00001 against s0 = 100 at
`t = 1.0`, with `n_steps = 64` returning 146.3306 -- for a horizon over which
the process really did evolve. The diagnostic names the received step count.

`n_steps = 0` is refused rather than documented as the identity. It is a
resolution parameter, not a modelled quantity, and zero resolution is
unspecified rather than degenerate; `n_steps = 1` is a crude discretisation
that still draws, while `n_steps = 0` draws nothing. This differs from
`t = 0`, which stays admitted because s0 genuinely is the terminal value of a
zero-length evolution, so refusing `n_steps < 1` takes no reachable correct
answer away: a caller who wants s0 passes a zero horizon with any valid step
count and still gets it.

The horizon guard added in shoals#139 did not and could not reach this: it
validates `t`, which is legal here. A finiteness check on the derived `dt` is
not a substitute either. Adding one would catch `n_steps = 0`, where `dt` is
`+inf`, but not a negative count, where `t / -8` is finite and the empty step
range still returns the initial state silently. Guarding `n_steps` itself
covers both.
