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
`tests_blocked/` (deferred — see the trigger in `AGENTS.md` §Pin Bump
Checklist); items that cannot be probed in-package are re-probed manually here.

Suspected chelis bugs are filed in `Chelis-Lang/chelis` and cited as
`chelis#NNN` (own-repo items as `shoals#NNN`), **never by a prose name**, so a
mechanical staleness audit (`scripts/audit_workarounds.py`) can find them.
`scripts/audit_workarounds.py` (full mode) flags any `chelis#NNN` cited here or
in code that is CLOSED upstream but not sitting in §Archived.

## Actively blocking

- **None actively blocking.** The finance proof surface ships as documented in
  `research/proof-infra/report.md`: the economic / dynamic-programming properties
  reach the SMT tier with no transcendental contract; the derivatives structural
  properties (`properties/composites.ch`: upper bound, put–call parity with
  reflection, delta ∈ [0,1]) reach SMT as **composites** — structure proven for
  any `N` satisfying its contract, with that contract separately fuzz-validated on
  the real `n_cdf`. Nothing upstream blocks shipping the current surface; the real
  transcendental pricing bodies degrade **honestly** to fuzz (never a false
  proven — the coupled-subterm goals stay deferred, see chelis#637 below).

## Tracking

- **chelis#637 — the certified-envelope discharge cannot express
  coupled-subterm dependencies (`N(d1)`/`N(d2)`): BS positivity / intrinsic
  lower bound unreachable by free-variable abstraction.** The 0.16.0
  envelope path (chelis#434, §Archived) abstracts each transcendental
  subterm to an INDEPENDENT fresh variable over its certified hull, so the
  quantitative coupling `bs_call = s·N(d1) − k·e^{−rt}·N(d2)` (with
  `d2 < d1`) is discarded and the residual is falsifiable in-abstraction:
  cvc5 answers SAT-in-abstraction and the honest verdict is
  `deferred_invariant`/`unsupported`, never a proof.
    - **State at pin 0.16.1 (re-probed):** the direct-pricer positivity
      invariant stays **deferred** (`deferred_invariants` in
      `docs/cnote-import-surface.json`, dischargeability lane p08); the
      identical intrinsic-lower-bound invariant PROVES on the CRR
      risk-neutral anchor (`properties/canontrees.ch`
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

- **chelis#659 — fuzz-tier proving cannot complete a single sample over a
  real f64 transcendental body within any usable budget.** A single
  accepted fuzz sample of one BS positivity property exceeds 200s on the
  release binary, so the honest `fuzz_validated` lane for the real
  transcendental pricers is un-gateable (this is why there is NO nightly
  canon fuzz gate — see the comment in `.github/workflows/nightly.yml`).
  Filed 2026-07-10 from the measurements in
  `docs/issue_drafts/fuzz_sampler_transcendental_cost.md`; sibling
  chelis#644 (fixed sampler domain box) starves realistic-magnitude
  guards.
    - **State at pin 0.16.1 (re-probed):** still open upstream; no
      0.15.x/0.16.x release note touches the fuzz sampler cost. The
      direct-pricer positivity invariant stays in `deferred_invariants` on
      the fuzz lane too (`AGENTS.md` §manifest).
    - **Not expressible as a `tests_blocked/` probe** (a probe would hang the
      suite, not fail it; see `tests_blocked/README.md` §cannot-be-probed).
    - **Re-probe trigger:** any release note naming fuzz sampler cost /
      budget / per-property domains (chelis#644), or a chelis#659 close.
      Re-probe with a bounded `chelis prove --tier fuzz-only` run on p08.

- **i64 `mod`-path precision drift — the integer `mul`/`add` that build the
  operand compute in f64 and lose precision above the 53-bit mantissa
  (chelis#680; class META chelis#695).** Builtin `mod(big_i64, m)` returns a
  wrong result once the operand exceeds f64's 53-bit mantissa (~9e15): the
  Park-Miller-shaped update
  `mod(1103515245·1406938949 + 12345, 2147483647)` returns 178065920
  instead of the exact 178066070 (re-verified at the 0.16.1 bump). The `mod`
  reduction itself is exact via `checked_int_binop`; the loss is upstream of
  it, in the f64 `mul` that forms the operand — the
  integer-arithmetic-in-f64 class chelis#680 tracks (read chelis#695 first).
  Previously carried here unfiled, deferring to the school shell's pinned
  probe of the same drift class; now cited to chelis#680.
    - **Affected surface / workaround:** `Shoals.Rng` hand-rolls `i64_mod`
      (`sub`/`mul`/`floor_div`) for the Sobol/xor bit walks instead of
      calling the builtin — the hand-roll stays until the upstream path is
      exact.
    - **Probe:** `tests_blocked/runtime/mod_big_i64_precision.ch` (run by
      `chelis test tests_blocked/ --expect blocked` in CI; FIX-detected =
      follow the sidecar's de-narrowing instructions).
    - **Re-probe trigger:** any chelis release touching the i64 `mod`
      runtime or the integer-arithmetic-in-f64 path chelis#680 (the probe
      re-probes mechanically on every CI run).

- **Depth-3 SMT function-call inlining cap (constraint; unfiled — draft
  `docs/issue_drafts/tier_b_inline_depth_cap.md`; probe pending).** The
  Tier-B lowerer inlines nested function calls only to a fixed depth —
  `MAX_INLINE_DEPTH = 3` in `chelis-prove/src/tier_b_lower.rs` (present at
  v0.14.0). A goal whose discharge needs a call chain deeper than three
  inlinings routes to Tier C rather than lowering. No shoals property is known
  to hit this today (the composites goals inline one level). This is a documented
  capacity limit, not a filed bug: **the c-note-side probe `p07` will pin its
  exact behavior — probe pending.** If a shoals property is authored that needs
  deeper inlining and hits the cap, file upstream and cite the issue here in the
  same change set (narrowing-citation rule). Re-probe trigger: `p07` landing, or
  any release note on Tier-B inlining depth.

## Parked

- **shoals#19 — expose a tensor Black–Scholes entry as a `WireDag` root for
  Beacon.** Beacon's real Black–Scholes seam is blocked because `bs_call_scalar`
  is a scalar host function, not a tensor `WireDag` root (post-`chelis#449` the
  root-count probe still reports zero roots for the scalar entry). Acceptance
  (from shoals#19): a producer-clean, vectorized elementwise BS tensor entry
  that becomes a Chelis `WireDag` root; computes the same pricing core as
  `Shoals.Pricing.bs_call_scalar` over tensor inputs; no scalar-lane `vmap` /
  host-only scalar plumbing that leaves zero roots; preserves the real `erf64`
  A–S implementation and branch structure; carries a numerics-equivalence
  regression against the scalar pricer. Parked because it depends on the tensor
  BS body work, not on a further upstream fix. Re-probe trigger: the tensor BS
  entry landing, or Beacon becoming available in a release
  (`beacon_available=false` in the release binary; `CHELIS_BEACON_BIN`-gated).

## Archived

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
  - **Residual (live tracker chelis#637, §Tracking):** the flagship BS
    positivity / intrinsic-lower-bound goals are structurally unreachable by
    independent-subterm abstraction (the `N(d1)`/`N(d2)` coupling is
    discarded), so the direct-pricer invariants stay deferred and
    `properties/canonpricing.ch` keeps `fuzz_validated` as its expected
    tier. Code citations at those narrowing sites now cite chelis#637.
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
