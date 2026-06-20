# Track C results: economic-model SMT reachability

Binary: chelis 0.7.27 (smt-enabled). Evidence: `runs/trackC_reachability_smt.ndjson`.
Run: `chelis prove economic/reachability.ch --tier smt-only --json --smt-timeout 20000`.

All goals are polynomial/linear with NO transcendental. There is nothing to abstract, so
these greens carry no contract caveat: they are structurally complete, unlike the
derivatives greens.

## Map (9 smt-proven, all proof_tier:smt)

| property | meaning | amenability |
|---|---|---|
| `c_simplex_preserve_2` | 2-state stochastic matrix maps the simplex to itself (q>=0, sum=1) | polynomial |
| `c_simplex_sum_3` | 3-state: row-stochastic preserves total mass = 1 | polynomial |
| `c_bellman_monotone` | V<=W => TV<=TW (Bellman monotonicity) | polynomial |
| `c_bellman_bounded` | r,V bounded => TV bounded | polynomial |
| `c_bellman_contraction` | -beta*d <= TV0-TW0 <= beta*d (contraction modulus beta) | polynomial |
| `c_pv_positive` | PV of a nonneg finite dividend stream is nonneg | polynomial |
| `c_pv_monotone` | PV monotone in dividends | polynomial |
| `c_gordon_positive` | Gordon p=d/(r-g)>0 for d>0, r>g (cvc5 handles division) | nonlinear/rational |
| `c_gordon_monotone` | Gordon price monotone in dividend | nonlinear/rational |

## Integrity checks

- Edge (C4): `c_simplex_no_rowsum_edge` drops the row-sum=1 constraint and the
  sum-preservation property is `failed` (refuted). The green depends on
  row-stochasticity.
- Soundness-dependence (A4): `c_simplex_unsound_rowsum` (rows sum to 1.5) flips
  sum-preservation to `failed`.
- Consistency (A5): `c_sat_simplex`, `c_sat_bellman` both `failed` (a model exists) =>
  invariant sets are jointly satisfiable, not vacuous.
- Transcendental-free (A6): every goal is polynomial/rational over the parameters. No
  exp/sqrt/log/erf. The Gordon greens use real division, which cvc5 discharges in NRA.

## Sound invariants (all exact, no contract caveat)

- Row-stochasticity: entries >= 0, each row sums to 1. Definitional for a Markov chain.
- Probability vector on the simplex: entries >= 0, sum = 1. Definitional.
- Discount factor beta in [0,1]: standard.
- r > g for Gordon growth: the convergence condition of the model.

## Positioning

The economic side yields 9 SMT-proven structural properties with no transcendental
contract, versus 3 on the derivatives side that each require a separately-validated
contract on N. This is the central finding: C Proof's strongest "proven" story is
economic-model and dynamic-programming structure (Markov simplex preservation, Bellman
monotonicity / boundedness / contraction, asset-pricing positivity and monotonicity), not
option Greeks. QuantEcon cross-check of the underlying numerics is recorded separately
(see oracle/).
