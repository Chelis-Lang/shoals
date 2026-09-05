<!-- BEGIN CHELIS MANAGED BLOCK: chelis-surface-header chelis@0.18.6 (sha256:28011bed9ccb5778) -->
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

> **Pinned manifest:** Shoals 0.24.10; chelis 0.18.6 (chelis-std 0.4.0,
> bundled), Nautilus 0.7.43, Coral 0.7.40 · **Last refreshed:** 2026-08-29

The published Chelis `v0.18.6` tag resolves to commit
`cf49f85bf0d1bca2c87c88a3e459c446912189c0`. Release workflow `33232762790`
completed successfully; the publisher-authenticated Darwin arm64 archive
has SHA-256 `08580435570c6fd44716f4d5c64117e973e379808cefeaaa97c8faefa2588f6c`
and its extracted compiler payload has SHA-256
`1c88c737d7d3740eb4adbe7b50ea31d29ee64498b9d74b35664255ca16aea8d4`. Both were
re-derived from the downloaded asset here, and that payload hash is
byte-identical to the toolchain every measurement in this bump ran on. The
glibc-2.31 archive for the same tag has SHA-256
`fb9ef6701fbf0ef2532bcbafb213ca80c21d7b13da0b341b55c64ba89aa8e8fa`;
it is sidecar-verified but exercised by CI rather than this gate run.

**0.18.6 is the largest breaking cut since 0.18.0, and almost all of it is at
a machine boundary this shell does not touch.** Probed against the corpus
rather than reasoned about, one BREAKING change reaches Shoals and six do not.

*Reaches this shell.* **The exported stdlib surface is aligned with
`[05-OP-35]` (chelis#1293/chelis#1314).** `Std.Test` no longer exports
`assert_eq_int`, `assert_eq_bool`, `assert_eq_string`, or
`assert_eq_tensor_int64`; the replacement is one polymorphic
`assert_eq[q](actual, expected, label)`. Shoals imported two of them (`assert_eq_int`,
`assert_eq_bool`) at 26 call sites across 7 files, all migrated in this change
set along with those files' 7 `import Std.Test (...)` lists -- 33 token
occurrences in total. Confirmed as a measured
pair, not read off the changelog: the identical file runs `2 passed, 0 failed`
on 0.18.5 and fails on 0.18.6 with ``module `Std.Test` does not export
`assert_eq_int` for import into Probe.__Eval``. `assert_close` survives with a
widened signature (`[p_float]` rather than `f32`), which is a loosening and
needed no edit. `assert_shape` also changed shape (`List[int64]` extents rather
than a single `int64`) but Shoals never used it.

*Does not reach this shell, each checked against the corpus.* (1) The **C ABI
replacement** (`chelis_scalar` tagged carriers, `chelis_dtype`, dynamic-rank
tensor metadata, one-byte `bool`) matters only to a consumer compiling against
`chelis_runtime.h`; Shoals links no runtime and targets no HIP. (2) **`diagonal`
and `trace` returned out-of-bounds heap bytes** for every axis pair except
`(rank-2, rank-1)` (chelis#1349) — the corpus calls neither builtin at all;
`bootstrap_grad_diagonal` in `src/curves.ch` is a local `def` whose name merely
contains the word. (3) **`JsonBigInt(string)` is a new `Json` variant**, so a
previously exhaustive `match` over `Json` is not exhaustive now — Shoals has no
`Json` value, no `parse_json` call, and imports nothing from `Std.Io.Json`;
Coral fixed its own two `match` sites. (4) **`init/xavier::sample` and the
legacy JSON aliases are removed** — unused here. (5) **WireDag advances to
schema 6, exact-only** — Shoals *does* consume this, but through its own gate
rather than as a break; see the WireDag row below. (6) **HIP rejects `bool`
tensors** and **every on-disk cache is invalidated** — no HIP target, and cache
invalidation is automatic.

*Not a break, but it changed a pinned artifact.* **`sub` became a first-class
WireDag identity** ([05-OP-40], chelis#1306) instead of being reconstructed as
negate-then-add. Shoals pins the lowered Black-Scholes DAG byte-exactly in
`scripts/validate_bs_wire_root.py`, so this moved real numbers: 23 `sub` nodes
appear while `add`, `neg`, and `drop` each fall by exactly 23, every other op
kind is unchanged in count, and the DAG shrinks 1018 -> 972 nodes with the
entry root moving 535 -> 512 and its op changing `add` -> `sub`. Audited by
lowering the same `src/pricing.ch` under both binaries and comparing op-kind
histograms, not by accepting the new hash.

**0.18.2 is skipped.** The 0.24.6 / 0.18.2 candidate could not land: Nautilus
0.7.39 worked the chelis#759 float-to-integer trap around with `floor(...)`,
which has no compiled-lane expression identity, so Coral's native build broke
and its 0.7.36 release never happened. Chelis 0.18.3 ships `cast_trunc`
([05-OP-6]) and Nautilus 0.7.40 moves onto it.

**The sibling half of this chain is published.** Reef enforces exact
compiler-pin equality on dependencies, so this pin could not resolve against
Nautilus 0.7.42 / Coral 0.7.39 (both declare `=0.18.5`); the sibling releases
landed ahead of the Shoals 0.24.10 release and the cascade is closed.
**Nautilus 0.7.43** (`Chelis-Lang/nautilus#50`, merged as
`7e3451b4977922d0bda80883ba385c7da211fc9e`, tagged `v0.7.43`) has CHB
`c3e6fb6e2c3a397726df0cc53587d854ac48cab416c9dea80c9df717bfe0ef4d` and archive
`970fb4ff51e6dfdce3043bb6ad772a7df74fd4c05a0be2723d451b35ef7ddd05`;
**Coral 0.7.40** (`Chelis-Lang/coral#29`, merged as
`301305312186888856d6645eb7c898c27af28ff3`, tagged `v0.7.40`, itself declaring
`nautilus = "0.7.43"`) has CHB
`672297eb6bafcffb8f3c4ad867f59aecece8cf114747fbfe2a112f3346edc2f1` and archive
`a6416fa595b092b34f1d5483429f65b4e19927db833288a18919d5b497ecc08f`. All four
were re-derived from the downloaded assets and match their published sidecars,
and both declare `compiler = "=0.18.6"`.

The 0.24.10 gate ran against exactly those published artifacts, installed with
`chelis reef install --from-github` into an isolated registry
(`CHELIS_REEF_HOME` pointed away from the shared store). A downstream consumer
declaring `shoals = { version = "0.24.10" }` resolves the whole chain and
builds, which is the end-to-end check that matters for C Note. During
authoring, before the sibling releases existed, the same gate ran against
local builds of each sibling's PR head; those local hashes differ from the
published ones (Coral artifact bytes remain install-path dependent under
chelis#1002) and are deliberately **not** recorded here or in
`docs/cnote-import-surface.json`, whose retained-evidence list takes only
sidecar-verified published hashes.

The previous chain's published artifacts, retained for de-narrowing: Nautilus
0.7.42 from commit `85d88133b0aaf5fde3a0f425dca4a1e5fa1056de`, CHB
`f5ed24c05c4e20fdf6c72601e2e9dd68cf46a63730eb79d9189adc493704f028`, archive
`fcdf32e581d95a43b0c37d672ff241348f75f308179d0b03f6f79a5247506f95`; Coral 0.7.39
from commit `8da830db79a561c5e97fb4592f3fea2fbc492641`, CHB
`b54e8a410a3f747f0a02dc6fb8496d9fe868c288d6db1ffb2f634664f499835a`, archive
`38149dab1bceed366dc93bc62f6e3f46e21fe4d27af49510ca024bc66d16a77f`. All four
were re-derived from the downloaded assets here and match their published
sidecars.

The 0.24.10 candidate's `scripts/prove_gate.py` run consumes the 0.18.6 chain
above with its fuzz lane on (`PROVE_GATE_FUZZ=1`), green in 1m59s against
3m29s at 0.18.5 on the same machine. Its
Shoals#37 lanes observed both risk families at `fuzz_validated`: all six
properties accepted 25 constraint-directed samples at each seed 0, 1, and 2;
every corrupt control produced an in-domain witness; and the compiler summary
graph supplied every direct function edge, including the second CVaR edge in
both dominance relations.
Its Shoals#42 lane separately binds seven actual AD outputs and the displayed
price to their compiler-reported shared `bs_call_f64` body. Those records carry
runtime-oracle and multi-seed fuzz evidence; certified-box and global proof
remain explicit Shoals#42 deferrals.

The previous validated Chelis `v0.17.4` baseline resolves to commit
`0b0c92f9916163b05a483fba70473496923730e6`. Its downloaded
`linux-x86_64-glibc2.31` archive has SHA-256
`6b7f477d65b2dea4e85b5107a51ae5714a5113138a6791361b74205f9448a121`;
its `chelis` binary has SHA-256
`d08ebfe67fed11f4458251d47e732de3249d93a3d700c87991a39e219887cc7e`.
The publisher sidecar verified the archive before installation.
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

Rows marked `@pin` carry 0.18.6-chain evidence. `@upstream` remains a
later capability that is not shipped at this pin. Refresh this table at every pin bump
(`AGENTS.md` §Pin Bump Checklist). The authoritative depth reference for the
proof reachability map is
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
| Certified-envelope transcendental discharge (`erf`/`normal_cdf`/`exp`/`log`/`sqrt` subterms) | `@pin` | Shipped in 0.16.0 (**chelis#434, now CLOSED**): a soundly-boundable transcendental subterm is abstracted to a fresh variable over its Gappa/Arb-certified envelope hull and the goal discharges as **`proven_modulo_certified_envelope`** (strictly weaker than `proven_modulo_real_arithmetic`, disclosed in the verdict). Fail-closed on unboundable arguments. **Residual:** goals whose truth depends on the *coupling* between abstractions cannot reach an exact proven tier: direct BS/B76 call-price positivity and direct BS spot-monotonicity/delta, vega, rho, and gamma comparisons are observed only at `fuzz_validated`, while the direct intrinsic-lower-bound candidate remains `deferred_invariant` (**chelis#637**, open). See `UPSTREAM_BUGS.md`. |
| `erf` / bundled `n_cdf` via an abstract-subterm contract | `@pin` | `erf` is not directly cvc5-lowerable, but the bundled normal-CDF **contract** (`0 ≤ N ≤ 1`, reflection `N(-x)=1-N(x)`) is discharged at the SMT tier as an abstract subterm (`chelis-prove/src/contracts.rs`), which is what lets the abstracted derivatives structure prove. The contract is separately fuzz-validated against the real `n_cdf` (max abs err ≈ 2 ulp vs scipy, report §7) — that is an **`f32`** measurement: `research/proof-infra/oracle/compare_ncdf.py` uses `ULP_F32 = 2^-24 ≈ 5.96e-8` and `RESULTS.md` records the max as **1.22e-7 at x=0.75**. It is not a claim about `n_cdf64`, whose own measured bound is ~7.0e-8 — see the accuracy section below. The `f32` figure exceeds that because `f32` rounding adds to the A&S floor, not because the approximation is worse. |
| Algebraic `abs`, `min`, `max` lower to SMT | `@pin` | In `CVC5_LOWERABLE`, `QF_NRA` (algebraic, not transcendental). `min`/`max` lower to ITE. |
| Composite derivatives greens | `@pin` | `properties/composites.ch`: structure proven at Tier B for any `N` satisfying its contract, verdict `proven_modulo_fuzz_validated_contract`. This string is **legitimate here** (a real SMT base resting on a fuzz-validated contract); it was only a false-positive for **pure-fuzz** bases, fixed by chelis#435 (archived). Classify verdicts from `proof_tier`, never the string alone. |
| Economic / dynamic-programming greens | `@pin` | Markov simplex preservation, Bellman monotonicity/boundedness/contraction, PV/Gordon positivity & monotonicity discharge at SMT with **no** transcendental contract (report §6). Structurally more complete than a derivatives green. |
| Function-call inlining depth for SMT | `@pin` | Nested calls inline to `MAX_INLINE_DEPTH = 3` (`chelis-prove/src/tier_b_lower.rs`); deeper chains route to Tier C. No shoals goal hits this today; c-note probe `p07` pending (`UPSTREAM_BUGS.md`). |
| Beacon (large-scale concrete verification) | `@upstream` | `beacon_available=false` in the release binary; gated on `CHELIS_BEACON_BIN`. Shoals now provides the real-pricer `bs_call_wire_f64` tensor root (shoals#19); bounded-domain consumption remains Beacon#74. The 0.18.6 Beacon request envelope moves to schema 2 with a `wire_dag_v6_base64` field, so a Beacon deployment must upgrade in lockstep; there is no one-way read migration as there was for v5. |
| prove-side import resolution | `@pin` | `prove` resolves package imports, so a property targets the real exported function; standalone structural probes are self-contained (report §2). |
| Constraint-directed property sampling | `@pin` | Chelis 0.18.3 ships chelis#977 guard-directed generation. Shoals#37 requires and observes 25/25 accepted samples at each of seeds 0, 1, and 2 for both parametric and historical risk families; a starved or partially accepted run fails the gate. |
| Linked Nautilus quantile contract identity | `@pin` | Chelis 0.18.3 binds `std.quantile.monotonicity` only to the linker-owned `Nautilus.Stats.quantile_vec` (chelis#979). Shoals keeps historical wrapper claims at the observed `fuzz_validated` tier and never reconstructs the wrapper relation from source text. |

## Numeric & language primitives the domain uses

| Family | Status | Notes |
|---|---|---|
| Arithmetic `+ - * /`, comparisons | `@pin` | Lower to cvc5. Keep `/` out of SMT goals where possible; use multiplied-through polynomial form. |
| `if/then/else` | `@pin` | Lowers as ITE in `QF_NRA`. |
| `Option[T]`, `Some`/`None`, `match`; `@opaque` + `@invariant` | `@pin` | Opaque-invariant abstraction is the path from synthetic green to a green a quant recognizes (report §1, §3); producer obligations discharge at SMT. |
| `Std.Test` (`assert_close`, `assert_eq`) | `@pin` | The executable numeric suites under `tests/` and `tests-manual/`. **Changed at 0.18.6:** `assert_eq_int` / `assert_eq_bool` / `assert_eq_string` / `assert_eq_tensor_int64` are gone with no alias; use the polymorphic `assert_eq[q](actual, expected, label)`. `assert_close` widened from `f32` to `[p_float]` — a loosening, and its tolerance must now share the tensors' dtype in `assert_close_tensor` (unused here). |
| WireDag lowering (`chelis tide serve` `/lower`) | `@pin` | Schema **6** at this pin (was 5), exact-only with no legacy aliases (chelis#1287/chelis#1306). Shoals pins the lowered `bs_call_wire_f64` DAG byte-exactly in `scripts/validate_bs_wire_root.py`; the 0.18.6 direct-`sub` identity moved it to 972 nodes / entry root 512 / raw sha256 `0c85b5c0…fabe`. Re-audit that constant by op-kind histogram at every pin bump, never by accepting the new hash. |
| Front-end check throughput | `@pin` | Substantially faster at 0.18.6 (chelis#1316/chelis#1207/chelis#1205): on this corpus `chelis check src/modelfit.ch` 67.6s → 31.6s and the 3-line `src/core.ch` dependency-load floor 31.2s → 17.0s. **But `chelis test --batch-mode auto` regressed 2.6x on `tests/`** (3m01s → 7m54s); see `docs/UPSTREAM_BUGS.md` §Actively blocking. |
| `count` ([05-OP-29]), direct `sub` / `min_elem` ([05-OP-40]/[05-OP-41]), `stop_gradient` ([05-OP-42]) | `@upstream` | New at 0.18.6 but unused by this shell today. `stop_gradient` and relu's own adjoint are specified with `Unimplemented` backend cells (chelis#1312/chelis#1313) and are not usable at this pin. |
| chelis-std / nautilus / coral module surface | `@pin` | Pricing, distributions, RNG, curves, dates, vol surfaces per `src/` + `references/`. |

## Numerical accuracy of shell-authored kernels

What the kernels this shell authors actually guarantee. It exists because
dtype is not accuracy: an `f64` signature says how the arithmetic is evaluated,
not how good the approximation being evaluated is.

**Bounds here are ABSOLUTE.** Relative error on an option price is unbounded as
the price approaches zero — the same kernel that holds 7.8e-7 relative at the
money reaches 8.7e-4 at K=200 and worse on short-dated OTM strikes. A caller
who sets `rtol=1e-6` from an at-the-money observation will get silently wrong
answers on ordinary out-of-the-money strikes.

| Kernel | Approximation | Absolute bound | Notes |
|---|---|---|---|
| `erf64` (module-internal) | Abramowitz & Stegun 7.1.26 | **~1.4e-7** measured over x ∈ [0, 8] | Coefficients byte-identical to the `f32` `Nautilus.Special.erf`. The bound belongs to the coefficients, not the arithmetic, so **no dtype improves it**. The same coefficients evaluated in `f32` give ~4.6e-7, so `f64` buys ~3x — not the nine orders of magnitude the dtype suggests. |
| `n_cdf64` (module-internal) | `0.5 * (1 - erf64(-x/√2))` | **~7.0e-8** measured | Half `erf64`'s bound, by the factor in the expression. |
| `bs_call_f64`, `bs_put_f64`, `bs_call_scalar`, `bs_put_scalar`, `bs_call_f64_vector`, `bs_call_wire_f64`, `call_prices`, `put_prices`, `call_total`, `put_total`, and the AD Greeks | closed form over `n_cdf64` | **≲ (S + K·e^−rT) · 7.5e-8** | Follows from `n_cdf64`'s bound through the closed form. Observed 7.8e-7 *relative* at ATM/T=1 — that figure is one point, not a bound. |

**Not covered by the rows above, and inheriting the same A&S ceiling by their
own copies of the kernel:** `Shoals.Greeks`'s `analytic_delta_call` /
`analytic_delta_put` go through a local `n_cdf` over `Nautilus.Special.erfc`,
which is the `f32` path and therefore the ~4.6e-7 one. `analytic_vega_call` and
`analytic_gamma_call` use `n_pdf` and never touch `erf`, so no erf-derived
bound applies to them. `Shoals.PricingExtended`'s `n_cdf_ext` is a third copy
feeding the `bachelier_*`, `black_*`, `garman_kohlhagen_*`, `margrabe_*` and
`pe_*` pricers, and `references/blackscholes.ch` a fourth. Stating those is
tracked separately rather than folded in here.

**Why the `f64` variant exists.** To be callable from an `f64` `grad` path —
the `f32` package symbol could not be. It was never a precision claim.
Upstream nautilus#56 tracks the same bound on the `f32` original, and
chelis#902 would supply a canonical `erf` with a stated accuracy, which is the
fix that removes the ceiling rather than documenting it.

**Scope.** These are kernels this shell authors. Accuracy of chelis primitives
is upstream's, and upstream has no accuracy contract for shells to inherit —
chelis#1563 proposes one.

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
