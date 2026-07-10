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

None. The finance proof surface ships as documented in
`research/proof-infra/report.md`: the economic / dynamic-programming properties
reach the SMT tier with no transcendental contract; the derivatives structural
properties (`properties/composites.ch`: upper bound, put–call parity with
reflection, delta ∈ [0,1]) reach SMT as **composites** — structure proven for
any `N` satisfying its contract, with that contract separately fuzz-validated on
the real `n_cdf`. Nothing upstream blocks shipping the current surface; the real
transcendental pricing bodies degrade **honestly** to fuzz (never a false
proven — see chelis#434 below).

## Tracking

- **chelis#434 — the SMT tier cannot discharge a transcendental finance body
  (Black–Scholes positivity through `log`/`exp`/`sqrt`).** `log` has no
  cvc5 kind, so `chelis prove` cannot build a cvc5 term for any goal that
  inlines a real `normal_cdf`/`bs_call` body (`references/blackscholes.ch` and
  any property that targets the un-abstracted pricer). Minimal reproducer: the
  `normal_cdf(x)` body in the issue (uses `log`/`exp` via the rational
  approximation) as a `@property bs_call_positive` goal.
  - **State at pin 0.14.0 (re-probed):** the internal-message leak
    (`variable d1 has no declared cvc5 term`) is **fixed** — `--tier smt-only`
    now returns an honest `unsupported` **naming the transcendental (`log`)**,
    and `--tier auto` falls to `fuzz_validated`; it is **never** a false
    `proven`. Regression-locked upstream in
    `chelis-prove/tests/transcendental_finance_lowering.rs` (present at v0.14.0).
    `log`'s deliberate absence from the cvc5-lowerable set is
    `chelis-prove/src/tier_b.rs` (`CVC5_LOWERABLE`, with the `chelis#434`
    citation in the `cannot_lower_reason` doc comment).
  - **Why it stays open:** chelis#434 was rescoped upstream to the
    transcendental-**discharge capability** (faithfully proving BS positivity
    through a `log`/`exp`/`sqrt` envelope — the WS-7/Beacon work), which is
    **not** delivered at 0.14.0. Complementary to the shipped `erf`
    abstract-subterm contract path, which is what makes `properties/composites.ch`
    green.
  - **Affected surface:** every `properties/` goal that would inline a real
    `bs_call`/`normal_cdf` body; `references/blackscholes.ch`.
  - **Workaround:** abstract the transcendental to a bounded free parameter
    carrying its contract (`nd1 = N(d1) ∈ [0,1]`, reflection `N(-x)=1-N(x)`,
    `disc = exp(-r t) ∈ [0,1]`) so the goal is polynomial and lowers; validate
    the contract on the real `n_cdf` separately (fuzz + the scipy oracle). This
    is exactly the method in `properties/composites.ch` and the report §3–§4.
  - **Re-probe trigger:** any chelis release note naming transcendental /
    `log`/`exp`/`sqrt` SMT discharge, a certified transcendental envelope, or
    Beacon transcendental support. Re-probe by proving `bs_call_positive` on the
    un-abstracted body per-surface, not by reading the changelog.

- **Depth-3 SMT function-call inlining cap (constraint; probe pending).** The
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

- **chelis#435 — `prove --json` emitted `proven_modulo_fuzz_validated_contract`
  on a pure-fuzz result.** A property that was itself only fuzz-validated, whose
  sole "contract" was also fuzz-discharged, reported a `composite_verdict`
  string implying an SMT proof resting on a fuzz-validated contract.
  - **Resolution:** CLOSED, fixed upstream by chelis#445/#447 (the fuzz-base
    honesty taxonomy), both ancestors of v0.14.0; regression-locked in
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
    #435 and stays in place: a `proven_modulo_*` string is trusted only when
    `proof_tier == "smt"`. Nothing to re-probe.
