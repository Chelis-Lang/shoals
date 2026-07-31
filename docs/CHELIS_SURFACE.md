<!-- BEGIN CHELIS MANAGED BLOCK: chelis-surface-header chelis@0.17.4 (sha256:28011bed9ccb5778) -->
This file is a domain-scoped view of the canonical Chelis capability surface,
generated for the pinned toolchain. Each capability row is marked `@pin` (usable
at the current pin) or `@upstream` (lands at the next bump). **Read it before
designing around a suspected language gap** — most downstream over-narrowing
traces to not knowing the real surface. Regenerate with `chelis reef conform
sync` at every pin bump; the upstream source of truth is `docs/CHELIS_SURFACE.md`
in `Chelis-Lang/chelis`.
<!-- END CHELIS MANAGED BLOCK: chelis-surface-header -->

# Chelis Capability Surface for Shoals

What the Chelis language and the bundled chelis-std actually provide to the
quantitative-finance domain this shell touches — numerical methods, pricing,
Greeks, and the proof surface over them. **Read this before designing around a
suspected language gap.**

> **Pinned release:** chelis 0.17.4 (chelis-std 0.4.0, bundled;
> nautilus 0.7.36, coral 0.7.33) · **Latest installable upstream:** chelis
> 0.17.4 (published 2026-07-31) · **Last refreshed:** 2026-07-31

The official `v0.17.4` tag resolves to Chelis commit
`0b0c92f9916163b05a483fba70473496923730e6`. The downloaded
`linux-x86_64-glibc2.31` archive has SHA-256
`6b7f477d65b2dea4e85b5107a51ae5714a5113138a6791361b74205f9448a121`;
its `chelis` binary has SHA-256
`d08ebfe67fed11f4458251d47e732de3249d93a3d700c87991a39e219887cc7e`.
The release sidecar verifies the archive before installation.
The official Nautilus `v0.7.36` tag resolves to commit
`2c434a9dfefca79c371b4c66af62b121a47841d6`; its canonical CHB and archive
SHA-256 values are
`2db566d8b381fd4d49acef62f875420a59c397961954a7c27cb02b79cb3f12e4`
and `412e24ec26f1828db394f6bed6ef8f4a9c93a7b104e020a457c93ec0a5b96572`.
The official Coral `v0.7.33` tag resolves to commit
`7bda6af8210a4dc128147e64cdb82019d27308f3`; its canonical CHB and archive
SHA-256 values are
`a3e04e308eb7d35c34fe4d6075c7e7626c57a6a9957fc6cf9926467b5787ec6c`
and `fe41f1617b118eb1600d02518319a96780c77195cce4c836ec43776bd69e08b0`.

Rows are marked `@pin` (verified on the exact 0.17.4 release) or
`@upstream` (expected at a later bump). Refresh this table at every pin bump (`AGENTS.md` §Pin Bump
Checklist). The authoritative depth reference for the proof reachability map is
`research/proof-infra/report.md`; the source-of-truth for the cvc5-lowerable set
is chelis `crates/chelis-prove/src/tier_b.rs` (`CVC5_LOWERABLE`).

## Proof surface — `chelis prove` (the spine of the finance verification story)

`chelis prove [PATH] --tier auto|smt-only|fuzz-only|type-only [--json]`, three
tiers: **A** (type/dimension/linearity), **B** (SMT via cvc5 over the reals),
**C** (seeded fuzz with precondition/invariant rejection sampling).

| Capability | Status | Notes |
|---|---|---|
| SMT prove tier (cvc5) shipped in the **release** tarball | `@pin` | SMT is in the released binary as of chelis 0.11.0 (no from-source `--features smt` build needed at this pin). Tier B lowers to cvc5 over the **reals** (`QF_NRA`, or `QF_NRAT` when a transcendental is present); a green is a real-arithmetic fact, **not** an IEEE-`f32` statement. `arith_model:"real"`. |
| Transcendentals `exp`, `sqrt`, `sin`, `cos` lower to SMT | `@pin*` | These four **do** lower — cvc5 kinds `EXPONENTIAL`/`SQRT`/`SINE`/`COSINE`, selecting the `QF_NRAT` logic. *`QF_NRAT` is **incomplete**: cvc5 may return `unknown`, which chelis records as `unsupported` (solver capacity) and `--tier auto` degrades **honestly** to fuzz — never a false proven. Keep structural greens transcendental-free by construction where possible (report §3). |
| Certified-envelope transcendental discharge (`erf`/`normal_cdf`/`exp`/`log`/`sqrt` subterms) | `@pin` | Shipped in 0.16.0 (**chelis#434, now CLOSED**): a soundly-boundable transcendental subterm is abstracted to a fresh variable over its Gappa/Arb-certified envelope hull and the goal discharges as **`proven_modulo_certified_envelope`** (strictly weaker than `proven_modulo_real_arithmetic`, disclosed in the verdict). Fail-closed on unboundable arguments. **Residual:** goals whose truth depends on the *coupling* between two abstractions of the same quantity cannot reach an exact proven tier: direct BS/B76 call-price positivity is observed only at `fuzz_validated`, while the direct intrinsic-lower-bound candidate remains `deferred_invariant` (**chelis#637**, open). See `UPSTREAM_BUGS.md`. |
| `erf` / bundled `n_cdf` via an abstract-subterm contract | `@pin` | `erf` is not directly cvc5-lowerable, but the bundled normal-CDF **contract** (`0 ≤ N ≤ 1`, reflection `N(-x)=1-N(x)`) is discharged at the SMT tier as an abstract subterm (`chelis-prove/src/contracts.rs`), which is what lets the abstracted derivatives structure prove. The contract is separately fuzz-validated against the real `n_cdf` (max abs err ≈ 2 ulp vs scipy, report §7). |
| Algebraic `abs`, `min`, `max` lower to SMT | `@pin` | In `CVC5_LOWERABLE`, `QF_NRA` (algebraic, not transcendental). `min`/`max` lower to ITE. |
| Composite derivatives greens | `@pin` | `properties/composites.ch`: structure proven at Tier B for any `N` satisfying its contract, verdict `proven_modulo_fuzz_validated_contract`. This string is **legitimate here** (a real SMT base resting on a fuzz-validated contract); it was only a false-positive for **pure-fuzz** bases, fixed by chelis#435 (archived). Classify verdicts from `proof_tier`, never the string alone. |
| Economic / dynamic-programming greens | `@pin` | Markov simplex preservation, Bellman monotonicity/boundedness/contraction, PV/Gordon positivity & monotonicity discharge at SMT with **no** transcendental contract (report §6). Structurally more complete than a derivatives green. |
| Function-call inlining depth for SMT | `@pin` | Nested calls inline to `MAX_INLINE_DEPTH = 3` (`chelis-prove/src/tier_b_lower.rs`); deeper chains route to Tier C. No shoals goal hits this today; c-note probe `p07` pending (`UPSTREAM_BUGS.md`). |
| Beacon (large-scale concrete verification) | `@upstream` | `beacon_available=false` in the release binary; gated on `CHELIS_BEACON_BIN`. The tensor BS `WireDag` root Beacon needs is shoals#19 (parked). |
| prove-side import resolution | `@pin` | `prove` resolves package imports, so a property targets the real exported function; standalone structural probes are self-contained (report §2). |

## Numeric & language primitives the domain uses

| Family | Status | Notes |
|---|---|---|
| Arithmetic `+ - * /`, comparisons | `@pin` | Lower to cvc5. Keep `/` out of SMT goals where possible; use multiplied-through polynomial form. |
| `if/then/else` | `@pin` | Lowers as ITE in `QF_NRA`. |
| `Option[T]`, `Some`/`None`, `match`; `@opaque` + `@invariant` | `@pin` | Opaque-invariant abstraction is the path from synthetic green to a green a quant recognizes (report §1, §3); producer obligations discharge at SMT. |
| `Std.Test` (`assert_close`) | `@pin` | The executable numeric suites under `tests/` and `tests-manual/`. |
| chelis-std / nautilus / coral module surface | `@pin` | Pricing, distributions, RNG, curves, dates, vol surfaces per `src/` + `references/`. |

## Automatic differentiation (`grad`) — the Greek-set surface

| Capability | Status | Notes |
|---|---|---|
| `grad` reverse-mode AD in `eval` / host runtime | `@pin` | Differentiates the full Greek set through a real Black–Scholes body — including the normal-CDF path, since `erf` is a library function of differentiable primitives (report §5). Reverse-mode; scalar floating result required. |
| `grad(grad(...))` second order | `@pin*` | Gamma/volga/vanna via nested `grad`. *Host-lane caveats captured in report §5/§9: nested `grad(grad(named_fn))` is not host-lowered (use nested-lambda form); an f64-capture-across-grad-boundary bug (inline non-differentiated args as literals). |
| `vmap(grad(...))` batched sensitivities | `@pin` | True batched grad over a spot×vol grid, validated vs analytic `N(d1)` (report §5). |
| Host-lane list-combinator pricing body under `grad` | `@upstream` | The shipped per-spot `to_tensor(map(..., to_list(...)))` body does not lower under `grad` (rank-0 `sum`); identical pure-tensor-lane math differentiates fine. Graduation candidate: a tensor-lane grad-able BS body (ties to shoals#19). |

## Where to read more

In this shell:

- The proof reachability map, integrity discipline, and per-track evidence:
  `research/proof-infra/report.md` (+ `research/proof-infra/RUNBOOK.md`, `runs/`).
- The abstracted derivatives properties: `properties/composites.ch`.
- The real transcendental bodies (fuzz-tier): `references/blackscholes.ch`.
- The oracle backbone (QuantEcon / scipy): `research/proof-infra/oracle/`.
- Upstream blockers and the classification discipline: `docs/UPSTREAM_BUGS.md`.

In the chelis upstream repo (source-of-truth for the load-bearing rows above):

| Topic this shell touches | Upstream location |
|---|---|
| cvc5-lowerable intrinsic set (`exp/sqrt/sin/cos/abs/min/max`; `log` absent) | `crates/chelis-prove/src/tier_b.rs` (`CVC5_LOWERABLE`, `CVC5_TRANSCENDENTAL`) |
| The `log`-has-no-cvc5-term honest boundary (chelis#434) | `crates/chelis-prove/src/tier_b.rs` (`cannot_lower_reason`), `tests/transcendental_finance_lowering.rs` |
| Bundled normal-CDF contract discharge (`erf` abstract subterm) | `crates/chelis-prove/src/contracts.rs` |
| Function-call inlining depth cap | `crates/chelis-prove/src/tier_b_lower.rs` (`MAX_INLINE_DEPTH`) |
| Fuzz-base honesty taxonomy (chelis#435 fix) | chelis#445/#447 (in v0.14.0) |
| Tier B is over the reals (caveat) | `spec/design/chelis_property_spec.md` §Tier B SMT proofs are over the reals |
| `grad` reverse-mode AD, non-diff ops, host vs tensor lane | `spec/06-transformations.md` §2 |
| The downstream shell-repo contract this shell follows | `spec/design/shell_repo_contract.md` §3 |
