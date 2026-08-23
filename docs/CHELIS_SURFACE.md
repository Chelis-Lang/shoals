<!-- BEGIN CHELIS MANAGED BLOCK: chelis-surface-header chelis@0.18.5 (sha256:28011bed9ccb5778) -->
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

> **Pinned manifest:** Shoals 0.24.9; chelis 0.18.5 (chelis-std 0.4.0,
> bundled), Nautilus 0.7.42, Coral 0.7.39 · **Last refreshed:** 2026-08-22

The published Chelis `v0.18.5` tag resolves to commit
`6602f01719f55b8d4c7f52ee70e7c7b58f136107`. Release workflow `32605821845`
completed successfully; the publisher-authenticated Darwin arm64 archive
has SHA-256 `0ff7b4e168d8b51277e05d44bfa658364630176d56d79c9cf8aceaea15335551`
and its extracted compiler payload has SHA-256
`bcf8da8bd2df9acb8816194f9251b26e23ec57527d4fc928bea6e1f6120628b2`. Both were
re-derived from the downloaded asset here, and that payload hash is
byte-identical to the toolchain every measurement in this bump ran on. The
glibc-2.31 archive for the same tag has SHA-256
`6b9b944ccd96b0053fc071de0ecfbb9e80e02a07a6a176e87056267ae8e0c26a`
(payload `fc544b9362c9ff0c244c03216a6e44fbf4d36665802d11b5cf3514d017c1e29a`);
it is sidecar-verified but exercised by CI rather than this gate run.

**Three front-end BREAKING changes ship in 0.18.5; none of them reaches this
shell, each probed rather than assumed.** (1) Polymorphic recursion is now a
check-time type error: Shoals' 7 self-recursive defs carrying a binder list
(all in `src/modelfit.ch`) bind *dimensions* on `tensor[n, f32]` shapes, not
type variables inside a larger constructed type, and every one still checks.
(2) An integer literal in a bare type position is now a parse error: the corpus
has none. (3) `>` evaluates its operands in authored order — it desugared to the
operand-swapped `cmplt(b, a)` and now targets `gt`: 346 of the corpus's 348 `>`
occurrences are `@property` SMT guards and the other 2 are pure property bodies
(`canonrisk.ch`, `canonriskhistorical.ch`), so no operand is effectful or
trapping and the reordering is unobservable here. That retarget also makes `>`
*borrow* both operands where `cmplt` consumed its second, which is a loosening
and cannot break existing source.

**0.18.2 is skipped.** The 0.24.6 / 0.18.2 candidate could not land: Nautilus
0.7.39 worked the chelis#759 float-to-integer trap around with `floor(...)`,
which has no compiled-lane expression identity, so Coral's native build broke
and its 0.7.36 release never happened. Chelis 0.18.3 ships `cast_trunc`
([05-OP-6]) and Nautilus 0.7.40 moves onto it.

**The sibling half of this chain is staged, not yet published.** Reef enforces
exact compiler-pin equality on dependencies, so Shoals cannot resolve against
Nautilus 0.7.41 / Coral 0.7.38 (both declare `=0.18.4`) once this pin moves. The
pins here name the versions the sibling bump PRs stage, each read off that PR's
own `reef.toml` at its head rather than guessed: **Nautilus 0.7.42**
(`Chelis-Lang/nautilus#43`, branch `bump/chelis-0.18.5`, head `c060cb9`) and
**Coral 0.7.39** (`Chelis-Lang/coral#27`, same branch name, head `d90ee05`,
which itself declares `nautilus = "0.7.42"`). Both declare
`compiler = "=0.18.5"`. Until those releases exist, every hosted reef leg on
this branch fails on the pin-equality check; that is the cascade, not a defect
in this change set. Local validation built both siblings from those exact heads
into an isolated private registry (`CHELIS_REEF_HOME` pointed away from the
shared store) and ran the gate against them — Coral needed no source edit
beyond its own manifest to build clean on 0.18.5. The published
sidecar-verified CHB and archive hashes for both siblings enter this document
at the release that consumes them, as every prior chain's did.

The previous chain's published artifacts, retained for de-narrowing: Nautilus
0.7.41 from commit `5bf6fd11ea4faa5bec0ca79e8974653b5e3158f8`, CHB
`e92a47020f5691b49e5b39aba0094c7e1ed2e39d9dce55a9a135fd34480cc083`, archive
`1bba785ccead8c38275f8daa111a27516b4f21d16eb3223c23dbb7bcb6a0a6f3`; Coral 0.7.38
from commit `53a40e781d869c19529ae2e4fcdad780f0a97f1b`, CHB
`a5be8783717b951db11f58beb9084a674ab86c7891cb847a6e74e4a04535e85e`, archive
`e68ac948c3539c3eba95283b49a907a753acc1de540a4a3840410ae79bf70854`.

The 0.24.7 release proof gate consumes this exact chain. Its
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

Rows marked `@pin` carry 0.18.5-chain evidence. `@upstream` remains a
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
| `erf` / bundled `n_cdf` via an abstract-subterm contract | `@pin` | `erf` is not directly cvc5-lowerable, but the bundled normal-CDF **contract** (`0 ≤ N ≤ 1`, reflection `N(-x)=1-N(x)`) is discharged at the SMT tier as an abstract subterm (`chelis-prove/src/contracts.rs`), which is what lets the abstracted derivatives structure prove. The contract is separately fuzz-validated against the real `n_cdf` (max abs err ≈ 2 ulp vs scipy, report §7). |
| Algebraic `abs`, `min`, `max` lower to SMT | `@pin` | In `CVC5_LOWERABLE`, `QF_NRA` (algebraic, not transcendental). `min`/`max` lower to ITE. |
| Composite derivatives greens | `@pin` | `properties/composites.ch`: structure proven at Tier B for any `N` satisfying its contract, verdict `proven_modulo_fuzz_validated_contract`. This string is **legitimate here** (a real SMT base resting on a fuzz-validated contract); it was only a false-positive for **pure-fuzz** bases, fixed by chelis#435 (archived). Classify verdicts from `proof_tier`, never the string alone. |
| Economic / dynamic-programming greens | `@pin` | Markov simplex preservation, Bellman monotonicity/boundedness/contraction, PV/Gordon positivity & monotonicity discharge at SMT with **no** transcendental contract (report §6). Structurally more complete than a derivatives green. |
| Function-call inlining depth for SMT | `@pin` | Nested calls inline to `MAX_INLINE_DEPTH = 3` (`chelis-prove/src/tier_b_lower.rs`); deeper chains route to Tier C. No shoals goal hits this today; c-note probe `p07` pending (`UPSTREAM_BUGS.md`). |
| Beacon (large-scale concrete verification) | `@upstream` | `beacon_available=false` in the release binary; gated on `CHELIS_BEACON_BIN`. Shoals now provides the real-pricer `bs_call_wire_f64` tensor root (shoals#19); bounded-domain consumption remains Beacon#74. |
| prove-side import resolution | `@pin` | `prove` resolves package imports, so a property targets the real exported function; standalone structural probes are self-contained (report §2). |
| Constraint-directed property sampling | `@pin` | Chelis 0.18.3 ships chelis#977 guard-directed generation. Shoals#37 requires and observes 25/25 accepted samples at each of seeds 0, 1, and 2 for both parametric and historical risk families; a starved or partially accepted run fails the gate. |
| Linked Nautilus quantile contract identity | `@pin` | Chelis 0.18.3 binds `std.quantile.monotonicity` only to the linker-owned `Nautilus.Stats.quantile_vec` (chelis#979). Shoals keeps historical wrapper claims at the observed `fuzz_validated` tier and never reconstructs the wrapper relation from source text. |

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
