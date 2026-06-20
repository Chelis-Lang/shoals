# S8 composite corpus + S7 binding cross-check — run + evidence

Authored artifacts:

- `properties/composites.ch` — `Shoals.Properties.Composites`, the shipped
  derivatives property corpus as composites against the chelis 0.8.0 contract
  mechanism.
- `tests/composites_binding.ch` — S7 binding cross-check, fast CI smoke (5 cells).
- `tests-manual/composites_binding_heavy.ch` — S7 binding, full 405-cell grid
  (nightly; added to `.github/workflows/nightly.yml` matrix).
- `scripts/manual_gates/phase3l_shoals_oracle_composite_corpus.py` — the gate
  that runs the corpus and checks every verdict.

## SMT binary note

`chelis prove`'s Tier B (SMT, cvc5) is an OPTIONAL build (`--features smt`, cvc5
linked via cvc5-rs). The stock `chelis` on PATH is not SMT-enabled. Point the
gate and any manual prove run at an SMT-enabled binary via `CHELIS_PROVE_BIN`.
The build used here: `chelis-prove-pipeline/target/release/chelis` (chelis 0.8.0,
SMT-enabled).

## Run the composite corpus

    CHELIS_PROVE_BIN=/path/to/smt/chelis \
        python scripts/manual_gates/phase3l_shoals_oracle_composite_corpus.py

Or directly (prove needs package context for the `Std.Contracts` import; run it
on the file inside the package, not a copy elsewhere):

    /path/to/smt/chelis prove properties/composites.ch \
        --tier smt-only --json --smt-timeout 20000

`prove` returns a NON-ZERO exit because the intentional edge probe
`put_call_parity_corrupted` is `failed`; the gate judges per-property and ignores
the aggregate exit code.

## Verdicts (raw evidence: `s8_composites_prove.ndjson`)

| property | status | composite_verdict | rests on |
|---|---|---|---|
| `put_call_parity_reflection` | passed | proven_modulo_fuzz_validated_contract | std.normal_cdf.reflection (+range) |
| `call_upper_bounded_by_spot` | passed | proven_modulo_fuzz_validated_contract | std.normal_cdf.range |
| `delta_in_unit_interval` | passed | proven_modulo_fuzz_validated_contract | std.normal_cdf.range |
| `put_call_parity_corrupted` | failed | failed | (edge: corrupted coupling, cvc5 counterexample) |
| `delta_unknown_contract` | unsupported | unsupported | (edge: unknown contract id) |

Each green carries: a base SMT proof (`proof_tier: smt`, `arith_model: real`)
with an established non-vacuity (cvc5 found a model of the assumption set), plus
the std contract discharged by fuzz (8192 samples, seed 3235848230, tol 1e-10,
status validated) with its own established non-vacuity SAT check. The corrupted
parity returns a concrete counterexample (a real refutation, not vacuous).

## Composite scoping (do not overstate)

These prove the STRUCTURE of each identity GIVEN a fuzz-validated contract on the
normal CDF. They are NOT "Black-Scholes proven". `erf`/`log` are not
cvc5-lowerable, so the link from the abstract symbol to the real `N` is
asserted-and-fuzz-validated, never machine-checked.

## No-arbitrage exclusions (backend-roadmap, not forced)

These refused value-level abstraction in the research and STAY OUT of the shipped
green corpus (documented, not forced through):

- Non-negativity `C >= 0` — not provable from local invariants on `N(d1)`,
  `N(d2)`; needs the moneyness coupling (`s` vs `k*disc`) that value-level
  abstraction discards. Even the sound monotonicity coupling `nd1 >= nd2` does
  not rescue it.
- Intrinsic lower bound `C >= S - K*disc` — needs the same moneyness coupling.
- Strike convexity (butterfly `>= 0`) — needs a density-convexity coupling among
  the abstracted `N(d2_i)` not expressible at the value level.

These are honest "unsupported via value-level abstraction" results; closing them
is a backend item (a coupling-aware abstraction), not a corpus authoring choice.

## S7 binding cross-check (raw: `s8_binding_test.txt`)

The composites are proven about `Std.Contracts.normal_cdf` (the certified f32
A&S normal CDF). The shipped `bs_call_scalar` uses the f64 lift of that SAME A&S
model (`Shoals.Pricing.erf64`/`n_cdf64`, byte-identical 7.1.26 coefficients), kept
f64 for Greek precision and the single-body invariant. The binding is the
cross-check, NOT a change to the pricer: a Black-Scholes price rebuilt from
`Std.Contracts.normal_cdf` (f32) agrees with `bs_call_scalar` within 1e-4 across
the grid. Measured worst cell: 2.67e-5 (f32-vs-f64 rounding of identical math,
amplified by the call's cancellation). Run:

    CHELIS_PROVE_BIN unused here; the binding runs under `chelis test`.
    /path/to/chelis test tests/composites_binding.ch --jobs 1 --timeout 600   # fast smoke
    /path/to/chelis test tests-manual/composites_binding_heavy.ch --jobs 1     # full grid
