# Track A results: derivatives SMT-reachability map

Binary: chelis 0.7.27 (smt-enabled) at
`/home/jeff/Documents/scratch/chelis/target/release/chelis`.
Run: `chelis prove derivatives/reachability.ch --tier smt-only --json --smt-timeout 20000`
Evidence: `runs/trackA_reachability_smt.ndjson`, `runs/trackA_capacity_smt.txt`,
`runs/trackA_contract_test.ndjson`.

Abstraction: each transcendental output is a bounded free parameter carrying its true
contract. `nd1=N(d1)`, `nd2=N(d2)`, `nd1c=N(-d1)`, `nd2c=N(-d2)` in `[0,1]`;
`disc=exp(-r t)` in `[0,1]`; `s,k >= 0`. Abstracted bodies are exactly the
`Shoals.Pricing` structure with the transcendentals lifted:
`C = s*nd1 - k*disc*nd2`, `P = k*disc*nd2c - s*nd1c`.

## Map

| property | bucket | proof_tier | goal amenability | invariants (all sound) |
|---|---|---|---|---|
| `a_upper_bound` C<=S | smt-proven | smt | polynomial (bilinear) | ranges of nd1,nd2,disc; s,k>=0 |
| `a_parity_reflection` C-P=S-K·disc | smt-proven | smt | polynomial (bilinear) | ranges + reflection nd1c=1-nd1, nd2c=1-nd2 |
| `a_delta_bounds` N(d1) in [0,1] | smt-proven | smt | linear | range of nd1 |
| `a_parity_naive` | smt-refuted | smt | polynomial | ranges only (no reflection) |
| `a_nonneg_naive` C>=0 | smt-refuted | smt | polynomial | ranges only |
| `a_nonneg_monotone` C>=0 + nd1>=nd2 | smt-refuted | smt | polynomial | ranges + monotone coupling |
| `a_intrinsic_naive` C>=S-K·disc | smt-refuted | smt | polynomial | ranges only |
| `a_strike_convex_naive` butterfly>=0 | smt-refuted | smt | polynomial (deg 2, 10 vars) | ranges only |

## Integrity checks

- Consistency (A5): `a_sat_upper_bound`, `a_sat_parity`, `a_sat_delta` each return
  `failed` (a model exists) => every proven green's invariant set is jointly
  satisfiable, not vacuous. Control: a contradictory set (`nd1>=0.5, nd1<=0.3`) instead
  `passed` (vacuous), confirming the check discriminates.
- Soundness-dependence (A4): `a_upper_bound_unsound` (nd1<=2.0) and
  `a_parity_unsound_reflection` (nd1c=1-2·nd1) both flip from passed to `failed`. The
  greens depend on the invariants being true, not on vacuity.
- Transcendental-free (A6): every proven goal contains only `+ - * /` over the bounded
  symbols. No exp/sqrt/log/erf in any structural goal, so each is decidable polynomial
  real arithmetic, not cvc5's heuristic transcendental extension.
- Capacity (A3): no structural probe timed out at 20s (cvc5 decided all, including the
  10-variable degree-2 butterfly). The capacity bucket is exercised by
  `cap_poly_upper_bound`: the SAME true goal is `passed` at 20000ms but
  `status:"unsupported"` (exit 2), never `failed`, at 1ms. A budget verdict is not a
  refutation. (cvc5's transcendental extension did prove `exp(x)>=1+x` and
  sqrt-monotonicity here; it succeeded but is heuristic, which is why the structural
  greens stay transcendental-free by construction.)

## Composite scoping (what the greens mean)

Each proven green proves the financial STRUCTURE given a contract on the transcendental.
It does not prove the shipped pricer (erf/log are not cvc5-lowerable). The contracts are
separately validated on the real implementation (`0.5*erfc(-x/sqrt2)` and `exp(-r t)`,
the exact expressions Shoals.Pricing uses) by the `contract/` sub-package grid tests
(`runs/trackA_contract_test.ndjson`, 3/3 pass): N in [0,1], reflection N(-x)=1-N(x), and
disc in [0,1]. So the honest headline is:

> Upper bound C<=S and put-call parity are proven at the SMT tier for any N satisfying
> 0<=N<=1 (and, for parity, reflection), and the real N is separately validated to
> satisfy those contracts.

## Soundness justifications for every invariant used in a green

- `0 <= N(d) <= 1`: N is a cumulative distribution function. Validated on real n_cdf.
- `N(-x) = 1 - N(x)`: symmetry of the standard normal. Validated on real n_cdf.
- `0 <= disc <= 1`: disc = exp(-r t), r,t >= 0 => r t >= 0 => exp(-r t) in (0,1]; the
  non-strict bound (what the greens use) also absorbs f32 underflow to 0. Validated.
- `nd1 >= nd2` (used only in the refuted `a_nonneg_monotone`): d1 = d2 + sigma·sqrt(t)
  >= d2 and N is increasing. True, but insufficient to prove non-negativity, which is
  the finding: the missing structure is the moneyness coupling that the abstraction
  removes.

## Negative-space finding

Non-negativity and the intrinsic lower bound are not provable from local invariants on
N(d1), N(d2): they need the relationship between d1, d2 and the moneyness (s vs k·disc),
which is exactly the transcendental structure the value-level abstraction discards. Even
the sound monotonicity coupling nd1>=nd2 does not rescue them. Strike convexity needs a
density-convexity coupling not expressible at the value level. These are honest
"unsupported via value-level abstraction" results, not solver failures.
