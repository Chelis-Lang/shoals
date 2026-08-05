# Shoals Upstream Bugs

Tracked upstream chelis issues and capability gaps that affect Shoals, per the
[downstream shell repo contract](../../c-note/docs/shell_repo_contract.md) §4.
The reachability map these entries lean on — what the proof stack can and cannot
discharge for finance at this pin — is `research/proof-infra/report.md`; keep
entries consistent with it.

Re-probe cadence: **actively-blocking** entries are re-probed at every chelis
release; **tracking** entries at every release for the capability they gate (a
changelog claim is not a verification — re-probe the reproducer per-surface);
**parked** entries when their gating dependency ships or a concrete need
appears; **archived** entries are historical and are not re-probed. Where a
blocker is mechanically expressible it graduates to an executable probe under
`tests_blocked/`; items that cannot be probed in-package are re-probed manually
here.

Suspected chelis bugs are filed in `Chelis-Lang/chelis` and cited as
`chelis#NNN` (own-repo items as `shoals#NNN`), **never by a prose name**, so a
mechanical staleness audit (`scripts/audit_workarounds.py`) can find them.
`scripts/audit_workarounds.py` (full mode) flags any `chelis#NNN` cited here or
in code that is CLOSED upstream but not sitting in §Archived.

> **0.18.3 release status (2026-08-04):** the published Chelis tag points
> to `29700dd73c0e35b672bdd384493054b3107ce308`; its authenticated Darwin arm64
> archive is `cc8737adf8c21040432d94b96635ef48895bd7ac8cdf94bd7696046c44bc7371`
> and its extracted compiler payload is
> `3a14b0d7e0a46a49c9b25f3dc61573d5972a91b411021672e09b8e3e0e9e1eba`. The
> glibc-2.31 archive for the same tag is
> `36789e3a260c61b5082bc8842ba7b975899796ddf17c7b971815a2ed112904a3` (payload
> `ea0ba326b190366f905445b4996c3993fe6c5cc7214f14cf5d862a615b78badf`), verified
> against its sidecar but exercised by CI rather than this gate run.
>
> **This bump skips 0.18.2: 0.18.1 → 0.18.3.** The 0.24.6 / 0.18.2 candidate
> could not land — Nautilus 0.7.39 worked the chelis#759 float-to-integer trap
> around with `floor(...)`, which has no compiled-lane expression identity, so
> Coral's native build broke and its 0.7.36 release never happened. Chelis
> 0.18.3 ships `cast_trunc` ([05-OP-6]) and Nautilus 0.7.40 moves onto it.
>
> Nautilus 0.7.40 is published from commit `c8466b29ffbe4ebc4126363db8c62a06a5b10e7f`; its sidecar verifies CHB
> `2ba0d478f55d5b270801ada1b51d8dbc75a4d721a24bb8aa42f6f663b0e19bad` and archive `a881f0b96a908a8356b720bfe21e6bde724bea204310e51957b452ad3740a47c`. Coral 0.7.37 is published from commit `8e38cd42aeb5e45d7ad5f92ed61143e1c121fb8b`;
> its sidecar verifies CHB `b8c41f1b563c2d460c764fb4373a26c7c0c622bd905c6d39a9284349f9a224de` and archive `5358b34994df4637dfce7e0deb48d78c6c61ddb807ef50a25261427093973de9`. Both were installed
> through `chelis reef install --from-github` and the full gate was re-run
> against them. Note the Coral artifact bytes are install-path dependent under
> chelis#1002, so these published values -- not any local rebuild -- are the
> authoritative ones.
>
> **chelis#680 is FIXED at this pin and moved to §Archived.** Its
> `tests_blocked/` probe went FIX-DETECTED, was promoted to
> `tests/mod_big_i64_precision.ch`, and `Shoals.Rng`'s internal bit-walk call
> sites moved back onto the builtin `mod`. `tests_blocked/` is now empty; see
> its README. Every other active entry below was re-probed against the 0.18.3
> binary and this dependency chain and did not move; archived paragraphs retain
> their historical pin evidence. Shoals#37's six risk invariants observed 25/25
> constraint-directed samples at seeds 0, 1, and 2 with in-domain corrupt
> witnesses and exact compiler-owned function edges, including both additional
> CVaR dependencies.

## Actively blocking

- **`_ = f(x)` marks `x` consumed when `f` destructures a record parameter
  (0.18.4 regression)** -- `chelis#1200`
  ([Chelis-Lang/chelis#1200](https://github.com/Chelis-Lang/chelis/issues/1200)).
  A `_ =` wildcard discard desugars with the `destructure: true` marker,
  opening the Linearity-F2 destructure-consume scope over the rest of the
  enclosing body; any later reuse of a variable that a record-destructuring
  callee consumed is a hard `UseAfterConsume` instead of receiving the
  implicit Copy a named binding gets. In Shoals this failed
  `tests/curves_basis.ch` (through `Curves.basis_spread_at`) at the 0.18.4
  bump.
    - **Minimal reproducer:** `tests_blocked/linearity/wildcard_discard_consume.ch`.
    - **Workaround:** bind, do not discard. 4 sites in
      `tests/curves_basis.ch` rewritten to `asserted_N` bindings, each
      carrying a `-- chelis#1200:` citation. `src/` needed no change.
    - **Re-probe trigger:** every pin bump and the release resolving
      chelis#1200. On pass, revert the cited bindings to `_ =` where the
      name is unused and archive this entry.

- **None other actively blocking.** The finance proof surface ships as documented in
  `research/proof-infra/report.md`: the economic / dynamic-programming properties
  reach the SMT tier with no transcendental contract; the derivatives structural
  properties (`properties/composites.ch`: upper bound, put–call parity with
  reflection, delta ∈ [0,1]) reach SMT as **composites** — structure proven for
  any `N` satisfying its contract, with that contract separately fuzz-validated on
  the real `n_cdf`. Nothing upstream blocks shipping the current surface; the real
  transcendental pricing bodies degrade **honestly** to fuzz (never a false
  proven — the coupled-subterm goals stay deferred, see chelis#637 below).

## Tracking

- **chelis#1002 — Reef preserves caller-provided GitHub owner casing in
  `remote_origin`, making lock and package bytes registry-history-dependent.**
  Reproduced against the 0.18.1 release binary on 2026-08-01 with identical
  Shoals source and identical official Nautilus 0.7.38 / Coral 0.7.35 assets:
  a registry installed through `Chelis-Lang/...` and a fresh registry resolved
  through `chelis-lang/...` emitted different `reef.lock`, CHB, and archive
  bytes solely because the origin strings differed in case.
    - **Affected surface / narrowing:** every Shoals workflow and Python
      installer uses canonical lowercase `chelis-lang/...` coordinates.
      `scripts/build_release_assets.py` deliberately reinstalls both
      dependencies immediately before building and rejects a non-canonical
      generated lock. `scripts/check_release_artifact_determinism.py` release-
      gates two fresh isolated Reef homes: one adversarially preseeded through
      mixed-case manual installs and one clean, requiring byte-identical lock,
      CHB, and archive payloads. This does not claim the compiler is fixed.
    - **Re-probe trigger:** a Chelis release naming GitHub origin
      canonicalization or a chelis#1002 close. Repeat the adversarial pair
      without the reinstall workaround; remove the narrowing only when input
      casing no longer affects registry metadata or release bytes.

- **chelis#408 — the `modelfit_bfgs_heavy` BFGS path kills a constrained
  2-vCPU GitHub-hosted runner.** The Rosenbrock 500-iteration path with a
  per-step finite-difference Jacobian and CG solve repeatedly ends in runner
  shutdown/lost communication with no Chelis diagnostic, including with
  `--jobs 1` and a 1500-second per-test budget. The same fixture passes
  locally in roughly 170–200 seconds, so this is not a failed numerical
  assertion and must not be represented as one.
    - **Affected surface / narrowing:** the weekly hosted and release-equivalent
      local heavy matrices exclude only `tests-manual/modelfit_bfgs_heavy.ch`;
      all other reviewed manual shards remain present. The exclusion is locked
      by `scripts/test_release_workflow.py`.
    - **Re-probe trigger:** a chelis#408 close or a Chelis release naming
      evaluator BFGS resource usage, worker memory, or constrained-host
      supervision. Re-enable the exact fixture on a 2-vCPU hosted runner and
      require a complete test report before removing the exclusion.

- **chelis#637 — the certified-envelope discharge cannot express
  coupled-subterm dependencies (`N(d1)`/`N(d2)`): exact BS price and Greek
  properties are unreachable by free-variable abstraction.** The 0.16.0
  envelope path (chelis#434, §Archived) abstracts each transcendental
  subterm to an INDEPENDENT fresh variable over its certified hull, so the
  quantitative coupling `bs_call = s·N(d1) − k·e^{−rt}·N(d2)` (with
  `d2 < d1`) is discarded and the residual is falsifiable in-abstraction:
  cvc5 answers SAT-in-abstraction and the honest verdict is
  `deferred_invariant`/`unsupported`, never a proof.
    - **State at pin 0.18.1 (re-probed 2026-08-01):** still blocked on the
      SMT surface. Running
      `chelis prove properties/canonpricing.ch --json --tier smt-only
      --smt-timeout 20000 --package .` with the 0.18.1 release binary returns
      `unsupported` / `property does not lower to Tier B (smt-only)` for the
      real-pricer properties, including `bs_call_price_nonneg`; no direct
      property is reported proven. Price positivity and the direct Greek
      comparisons therefore remain fuzz-validated on the active lane and
      deferred on the proven lane. The identical intrinsic-lower-bound
      invariant remains proven on the CRR risk-neutral anchor
      (`properties/canontrees.ch`
      `crr_rn_call_intrinsic_lower_bound`) — the teaching exemplar of the
      genuine-vs-deferred split (`src/trees.ch`).
    - **Affected surface:** every `properties/` goal that would inline a real
      `bs_call`/`normal_cdf` body and whose truth depends on subterm
      coupling; `properties/canonpricing.ch` (expected tier stays
      `fuzz_validated`); `references/blackscholes.ch`.
    - **Workaround:** unchanged — abstract the transcendental to a bounded
      free parameter carrying its contract (`nd1 = N(d1) ∈ [0,1]`, reflection
      `N(-x)=1-N(x)`, `disc = exp(-r t) ∈ [0,1]`) so the goal is polynomial
      (`properties/composites.ch`, report §3–§4); or re-anchor the invariant
      on a rational-arithmetic pricer (`properties/canontrees.ch`).
    - **Not expressible as a `tests_blocked/` probe** (prove-verdict surface;
      see `tests_blocked/README.md` §cannot-be-probed) — re-probed by
      `scripts/prove_gate.py` and manually at every bump.
    - **Re-probe trigger:** any chelis release note naming coupled-subterm /
      relational abstraction, whole-expression `BoxRange` interval
      evaluation, or a chelis#637 close. Re-probe by proving
      `bs_call_positive` on the un-abstracted body per-surface, not by
      reading the changelog.

- **chelis#846 — Depth-3 SMT function-call inlining cap (capacity limit).**
  The Tier-B lowerer inlines nested function calls only to a fixed depth. The
  cap remains observable in the 0.18.1 release binary (re-probed 2026-08-01
  with a disposable two-property source): a depth-3 identity
  `level3(x) == x + 3` is `passed` at `proof_tier=smt`, while the otherwise
  identical depth-4 identity `level4(x) == x + 4` is `unsupported` with
  `property does not lower to Tier B (smt-only)`. Command:
  `chelis prove /tmp/shoals-846-0181.ch --json --tier smt-only
  --smt-timeout 20000`. No Shoals property is known to hit this today (the
  composites goals inline one level); it gates nothing on the current surface.
  Filed 2026-07-23 as a forward-looking capacity limit — the residual of the
  now-closed chelis#425 (which made nested goal-site calls inline at all); the
  ask is to make the cap configurable, emit a distinct depth-cap diagnostic, or
  document it with a clean Tier-C fallback contract. The c-note-side probe `p07`
  is expected to pin the exact behavior upstream — probe pending. If a shoals
  property is later authored that needs deeper inlining and hits the cap, add a
  `tests_blocked/` probe citing chelis#846 in the same change set
  (narrowing-citation rule). Re-probe trigger: `p07` landing, a chelis#846
  close, or any release note on Tier-B inlining depth.

## Parked

No parked entries.

## Archived

- **chelis#680 — i64 `mod`-path precision drift (class META chelis#695;
  RESOLVED on 0.18.3).** Builtin `mod(big_i64, m)` used to return a wrong
  result once the operand exceeded f64's 53-bit mantissa (~9e15): the
  Park-Miller-shaped update `mod(1103515245·1406938949 + 12345, 2147483647)`
  returned `178065916` on the 0.18.1 release binary instead of the exact
  `178066070`. The `mod` reduction itself was always exact via
  `checked_int_binop`; the loss was upstream of it, in the f64 `mul` forming
  the operand — the integer-arithmetic-in-f64 class chelis#680 tracked.
    - **0.18.3 re-probe (2026-08-04, per verb and per surface):** exact on the
      eval lane (`chelis eval` → `178066070`) **and** on the compiled-C lane
      (`chelis build` → link → run → `178066070`), matching exact integer
      arithmetic. Confirmed against the 0.18.1 binary in the same session to
      establish the before/after pair rather than trusting a changelog claim.
    - **De-narrowing executed in the same change set:** the blocked probe
      `tests_blocked/runtime/mod_big_i64_precision.ch` went FIX-DETECTED and was
      promoted to `tests/mod_big_i64_precision.ch`; the internal `Shoals.Rng`
      bit-walk call sites (`bit_at_i64`, `i64_xor_32` ×3,
      `sobol_value_from_slice`, `rng_sobol_runtime_fallback_base`) moved from
      the hand-rolled `i64_mod` back onto the builtin `mod`. The exported
      `i64_mod` shim is **retained for one release** for downstream
      compatibility, per the sidecar's instructions.
    - **Residual caveat recorded at the shim:** `i64_mod` is a FLOORED modulo
      (`sub(n, mul(p, floor_div(n, p)))`) whereas builtin `mod` is truncated —
      `mod(-7, 2) = -1` versus `i64_mod(-7, 2) = 1`. They agree only for
      `n >= 0`. Every in-repo call site passes non-negative operands (bit-walk
      values, sample indices, dimension indices), which is why the swap is
      behavior-preserving; `tests/rng.ch` and `tests/rng_sobol_1024.ch` produce
      identical results before and after.

- **shoals#19 — real Black-Scholes tensor `WireDag` producer seam.** Resolved
  by `Shoals.Pricing.bs_call_wire_f64`: a pure f64 tensor-DAG entry with the
  same A-S coefficients and branch structure as `bs_call_f64`, no host/vmap
  bridge, and representative scalar-equivalence coverage. The executable
  `scripts/validate_bs_wire_root.py` gate lowers the real source with Chelis
  0.17.5 and observes a non-empty named root. Beacon's bounded-domain consumer
  and report contract remain tracked by Beacon#74.

- **chelis#924 — Reef package-graph preparation added ~111s to a trivial
  Shoals consumer proof.**
  - **Resolution:** CLOSED upstream and re-probed against the 0.17.5 release
    binary on 2026-08-01. The release oracle installed official Nautilus
    v0.7.37 and Coral v0.7.34 assets plus the exact Shoals 0.24.4 candidate
    into a fresh isolated Reef registry and XDG cache. Its trivial consumer
    property completed in **0.430s cold** and **0.229s warm** (limits: 20s /
    5s). Both completed processes
    returned `passed` at `proof_tier=smt`, and their NDJSON was byte-identical
    (`sha256:8b7d667da7915b0696acf7321c5f9dec078f26ebf6defbe1f3705a4dbc3d294a`).
    Command: `CHELIS_BIN=~/.local/share/chelis/0.17.5/bin/chelis python3
    scripts/check_package_prove_latency.py`.

- **chelis#659 — fuzz-tier proving could not complete a single sample over a
  real f64 transcendental body within a usable budget.**
  - **Resolution observed at pin 0.17.4 (2026-07-31):** the performance
    obstruction is fixed even though the upstream issue was still open when
    re-probed. Running
    `chelis prove properties/canonpricing.ch --json --tier fuzz-only
    --samples 1 --seed 0 --package .` completed all four real-pricer
    properties in under one second. A 25-sample run completed in **20.499s**:
    `bs_call_price_nonneg` and `b76_call_price_nonneg` passed at
    `proof_tier=fuzz`, while both corrupted twins failed with in-domain
    counterexamples after 2 and 4 samples respectively.
  - **De-narrowing required:** remove the obsolete “fuzz is intractable”
    narrowing at its manifest/workflow/documentation sites and promote the
    real-pricer invariants only with an explicit observed fuzz tier and an
    appropriate release-gate sample budget. This archive records the compiler
    capability result; it does not itself claim that the downstream
    de-narrowing has landed.

- **chelis#434 — the SMT tier cannot discharge a transcendental finance body
  (Black–Scholes positivity through `log`/`exp`/`sqrt`).** `log` had no cvc5
  kind, so no goal inlining a real `normal_cdf`/`bs_call` body could be built
  as a cvc5 term; after the 0.14.0-era message-leak fix the failure was an
  honest `unsupported` naming `log`, with `--tier auto` falling to
  `fuzz_validated`.
  - **Resolution:** CLOSED, shipped in v0.16.0 as the certified
    special-function envelope discharge: a soundly-boundable
    `erf`/`normal_cdf`/`exp`/`log`/`sqrt` subterm is abstracted to a fresh
    variable over its Gappa/Arb-certified envelope hull and the goal
    discharges as **`proven_modulo_certified_envelope`** (a strictly weaker,
    disclosed verdict class; fail-closed on unboundable arguments).
    Re-probed at the 0.16.1 bump per-surface via `scripts/prove_gate.py`.
  - **Residual (live tracker chelis#637, §Tracking):** the flagship BS price
    and Greek goals are structurally unreachable by independent-subterm
    abstraction because their coupled pricing terms are discarded. Direct
    BS/B76 call-price positivity and direct BS spot-monotonicity/delta, vega,
    rho, and gamma comparisons are observed at `fuzz_validated`; the direct
    intrinsic-lower-bound candidate stays deferred. Code citations at those
    narrowing sites now cite chelis#637.
  - **Retained discipline:** the contract-abstraction method in
    `properties/composites.ch` (bounded free parameter + separately
    fuzz-validated contract) remains the canonical pattern for
    coupling-dependent goals regardless of the envelope capability.

- **chelis#435 — `prove --json` emitted `proven_modulo_fuzz_validated_contract`
  on a pure-fuzz result.** A property that was itself only fuzz-validated, whose
  sole "contract" was also fuzz-discharged, reported a `composite_verdict`
  string implying an SMT proof resting on a fuzz-validated contract.
  - **Resolution:** CLOSED, fixed upstream by chelis#445 (the fuzz-base honesty
    taxonomy: a pure-fuzz base reads `fuzz_validated`, never a contract-qualified
    proven verdict) and chelis#447 (the symmetric `DisprovedModuloRealArithmetic`
    side of that taxonomy), both ancestors of v0.14.0; regression-locked in
    `issue_435_pure_fuzz_base_reads_fuzz_validated_not_proven_modulo_contract`.
    A pure-fuzz base now reads `composite_verdict = fuzz_validated`. The genuine
    SMT-base + fuzz-contract case — which is exactly Shoals'
    `properties/composites.ch` (a real SMT-discharged structural goal resting on
    the fuzz-validated `N` contract) — legitimately still reads
    `proven_modulo_fuzz_validated_contract`.
  - **Retained discipline (not a workaround for a live bug):** any gate that
    consumes `prove --json` classifies a verdict from `proof_tier` +
    assumption-discharge tier, **never** by string-matching the
    `composite_verdict` token. This is correct-by-construction regardless of
    #435 and stays in place (`scripts/prove_gate.py` `classify_tier` + its
    honesty self-test): a `proven_modulo_*` string is trusted only when
    `proof_tier == "smt"`. Nothing to re-probe.

- **chelis#199 — control-flow AD (D1).** Referenced from
  `docs/plan-quant-surface.md` as a forward-looking capability the M5/M7/M8
  milestones "track". Triaged 2026-07-10: **CLOSED upstream** (control-flow AD
  landed), so the reference is historical, not a live blocker. No shoals surface
  is narrowed on it today; the plan-doc mention is a resolved roadmap pointer.
  `scripts/audit_workarounds.py` reports it `CLOSED [reference]` (informational,
  not a gate failure) since it is not the subject of an active UPSTREAM_BUGS
  entry.
