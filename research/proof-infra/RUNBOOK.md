# RUNBOOK: reproducing the C Proof x Shoals reachability results

All results were produced with the SMT-enabled chelis 0.7.27 compiler. The stock
`chelis` on PATH (0.7.21) is NOT SMT-enabled; do not use it.

## Compiler

```
CH=/home/jeff/Documents/scratch/chelis/target/release/chelis
$CH --version            # chelis 0.7.27
```

If the binary is absent, rebuild it (cvc5 is linked via the cvc5-rs crate; no PATH dep):

```
cd /home/jeff/Documents/scratch/chelis
cargo build -p chelis-cli --features smt --release
```

Confirm the SMT tier is live (must print proof_tier:"smt"):

```
$CH prove research/proof-infra/_preflight.ch --tier smt-only --json
```

## How the prover is invoked

- Structural SMT proofs (Track A, C) and fuzz counterexamples (Track D) run on
  SELF-CONTAINED `.ch` files (no imports): `chelis prove <file> --tier <t> [...]`.
  `chelis prove` does NOT resolve package imports, even inside a built package.
- `--tier smt-only` reads the raw Tier-B verdict (passed / failed / unsupported).
- `--tier fuzz-only --samples N --seed S` surfaces concrete counterexample bindings.
- Numerical work that needs real Nautilus/Shoals code (Track A contract validation,
  Track B AD) runs in a sub-package via `chelis reef build` then `chelis test tests`.
  `eval`/`test` only accept files under a declared package root.

## Track A: derivatives reachability map

```
$CH prove research/proof-infra/derivatives/reachability.ch --tier smt-only --json --smt-timeout 20000
$CH prove research/proof-infra/derivatives/capacity.ch --tier smt-only --json --smt-timeout 20000
$CH prove research/proof-infra/derivatives/capacity.ch --only cap_poly_upper_bound --tier smt-only --json --smt-timeout 1
```
Expected: 3 passed (a_upper_bound, a_parity_reflection, a_delta_bounds), the rest
failed/refuted; the consistency witnesses `a_sat_*` failed (satisfiable); the
soundness-dependence probes `*_unsound*` failed (flipped). The capacity probe is
passed at 20000ms and unsupported (exit 2) at 1ms.

Composite contract validation (real n_cdf / disc) -- sub-package:

```
cd research/proof-infra/contract && $CH reef build && $CH test tests --json
```
Expected: 3/3 pass (range, reflection, disc range).

## Track C: economic-model reachability

```
$CH prove research/proof-infra/economic/reachability.ch --tier smt-only --json --smt-timeout 20000
```
Expected: 9 passed; `c_simplex_no_rowsum_edge` failed (edge); `c_sat_*` failed
(satisfiable); `c_simplex_unsound_rowsum` failed (flipped).

## Track B: AD Greeks (sub-package)

```
cd research/proof-infra/ad && $CH reef build
python3 research/proof-infra/ad/harness.py     # drives grad/vmap/grad(grad), validates vs oracle
```
See research/proof-infra/ad/RESULTS.md.

## Track D: counterexamples

```
$CH prove research/proof-infra/counterexample/businesswrong.ch --tier fuzz-only --samples 500 --seed 0 --json
```
Expected: d1/d2/d3 wrong models failed with counterexamples; *_fixed controls passed.

## Oracle cross-checks (QuantEcon + scipy)

```
research/proof-infra/oracle/.venv/bin/python research/proof-infra/oracle/econ_oracle.py
```
See research/proof-infra/oracle/RESULTS.md.
