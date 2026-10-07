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

The horizon guard added in shoals#139 did not and could not reach this. It
validates `t`, which is legal here, and `dt = t / n_steps` is `+inf` at
`n_steps = 0` but has no consumer that ever runs, so a finiteness check on
`dt` would surface nothing.
