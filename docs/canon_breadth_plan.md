# Canon Breadth Plan

Filed: 2026-07-22. Implements the plan from `shoals_canon_plan.md`.

## Problem Statement

The canon's verification coverage sits on a small fixed-size lattice and a
fixed-period bond. Greek signs are sampled or uncovered on the transcendental
pricers; VaR has no invariant; general-size claims need induction that doesn't
exist yet; the reference models look like teaching examples, not desk-scale
instruments. This plan extends the canon in 5 workstreams — each with a
fresh-context red-team pass — to address that buyer gap.

## Workstreams

### 1. Greek Sign Invariants (proven, CRR anchor)

Author `properties/canongreeks.ch` with vega-sign (monotone in vol width),
disc-sensitivity (monotone in disc — the rho analog), and gamma-sign (convexity
in spot) on `tr_crr_call_2step`. All pure arithmetic + ITE, expected to
discharge at Tier B (proven over the reals). Each ships corrupted twin +
guards_satisfiable + manifest entry.

### 2. Black-Scholes Direct Greek Comparisons (fuzz-validated)

The former spot-monotonicity, vega-sign, rho-sign, and gamma-sign stubs are
active against the real `bs_call_scalar` body at `fuzz_validated`. Satisfying
and corrupted controls run over three deterministic seeds. Their upgrade to a
global proven tier remains deferred to chelis#637 (relational / BoxRange
abstraction); the separate grad-in-property candidate remains deferred.

### 3. VaR / Quantile Coherence (fuzz_validated)

Author `properties/canonrisk.ch` with VaR-monotonicity, CVaR-dominance, and
VaR-nonneg invariants targeting `src/risk.ch`. Tier classification is honest:
if fuzz completes they enter active invariants; if intractable they go deferred
with trigger "chelis-std quantile primitive".

Current verdict for shoals#37: active at `fuzz_validated`. The parametric
inverse-CDF and historical empirical-quantile families are distinct. Each
covers confidence monotonicity, ES dominance, and positivity against the real
exported bodies over 25 accepted constraint-directed samples at seeds 0, 1,
and 2. Corrupt twins fail with in-domain witnesses. The release gate consumes
only compiler-owned dependency edges and requires both function edges in each
ES/VaR relation; no dependency is reconstructed from source text.

Evidence boundary: the 0.24.4 release gate reproduces these observations
against the official, sidecar-verified Chelis 0.17.5 / Nautilus 0.7.37 /
Coral 0.7.34 chain. The `fuzz_validated` tier is sampled characterization and
does not promote either family to a global proof.

### 4. General-Size Promotion Stubs (deferred)

Author `properties/canongeneral.ch` naming the fold-based
`tr_binom_european_call_generic` and a new `fi_bond_general`. Deferred with
trigger "induction tier". Author `fi_bond_general` in `src/fixedincome.ch`.

### 5. Model Realism Demos (demos/, no proof claim)

Author `demos/realism.ch` with 200-step CRR, 60-period bond, 10K-path MC —
practitioner-scale characterization demos asserting convergence to known
references. Update `docs/src/demos.md`.

## Discipline

- Each invariant references the model's output function (anti-vacuity).
- Each ships a satisfying control and a violating control with a real in-domain
  witness.
- Each tier claim is backed by a dischargeability probe against the shipped
  shell corpus.
- Nothing carries a tier the gate cannot confirm.
- Release evidence runs against published chelis and published shell artifacts.
  Local pre-release probes may inform preparation, but are labeled candidate
  evidence and never satisfy the release acceptance gate.

## Verification

After each workstream: `chelis reef build`, `python3 scripts/contract_gate.py`,
and a fresh-context red-team pass.
