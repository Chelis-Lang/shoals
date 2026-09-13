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

> **0.18.6 release status (2026-08-29):** the published Chelis tag points
> to `cf49f85bf0d1bca2c87c88a3e459c446912189c0`; its authenticated Darwin arm64
> archive is `08580435570c6fd44716f4d5c64117e973e379808cefeaaa97c8faefa2588f6c`
> and its extracted compiler payload is
> `1c88c737d7d3740eb4adbe7b50ea31d29ee64498b9d74b35664255ca16aea8d4`, which is
> byte-identical to the toolchain every re-probe below ran on. The
> glibc-2.31 archive for the same tag is
> `fb9ef6701fbf0ef2532bcbafb213ca80c21d7b13da0b341b55c64ba89aa8e8fa`, verified
> against its sidecar but exercised by CI rather than this gate run.
>
> **The sibling half of the chain is published and the cascade is closed.**
> Reef enforces exact compiler-pin equality on dependencies, so the hosted reef
> legs could not pass until Nautilus 0.7.43 and Coral 0.7.40 existed as
> releases; both landed ahead of the Shoals 0.24.10 release. Their
> sidecar-verified CHB hashes are
> `c3e6fb6e2c3a397726df0cc53587d854ac48cab416c9dea80c9df717bfe0ef4d` and
> `672297eb6bafcffb8f3c4ad867f59aecece8cf114747fbfe2a112f3346edc2f1`; see
> `docs/CHELIS_SURFACE.md` for the archive hashes and release commits. Coral
> artifact bytes remain install-path dependent under chelis#1002, so the
> published values -- not any local rebuild -- stay the authoritative ones.
> The 0.18.5 chain's sibling releases likewise now exist and their
> sidecar-verified hashes were folded into
> `docs/cnote-import-surface.json`'s retained-evidence list, closing the gap
> PR #52 recorded.
>
> **0.18.6 is the first pin at which Shoals carries actively-blocking
> entries again**, and both are 0.18.6 regressions rather than latent gaps:
> the conformance audit now reads an own-repo citation as an upstream blocker,
> and `chelis test --batch-mode auto` slowed 2.6x on this suite. Both are
> measured below against a 0.18.5-vs-0.18.6 pair, not read off the changelog.
> Every §Tracking entry was re-probed against the 0.18.6 binary and none moved;
> archived paragraphs retain their historical pin evidence. The keystone
> `scripts/prove_gate.py` self-audit is green at this pin with its fuzz lane on
> (`PROVE_GATE_FUZZ=1`), holding all 37 manifest invariants at their expected
> tiers -- Shoals#37's six risk invariants again observed 25/25
> constraint-directed samples at seeds 0, 1, and 2 with in-domain corrupt
> witnesses and exact compiler-owned function edges, including both additional
> CVaR dependencies. Of the 0.18.6 BREAKING changes, the only one that reached
> this shell is the exported-stdlib cut: `Std.Test` no longer exports
> `assert_eq_int` / `assert_eq_bool`, and 26 call sites across 7 files moved to
> the polymorphic `assert_eq` (33 token occurrences with those files' `import
> Std.Test (...)` lists). `tests_blocked/` remains empty -- neither new
> entry is expressible as an expected-to-fail `.ch` probe (one is a
> conformance-audit verdict, the other a wall-clock measurement).

## Actively blocking

- **chelis#1387 --
  `chelis reef conform audit` row 12 (`tests-blocked`, §5) reads an own-repo
  citation as an upstream blocker.** chelis#1270 widened `scan_citations` to
  recognize a registry sibling's `<repo>#NNN` and a shell's own `<self>#NNN`.
  `check_tests_blocked` was not widened with it and still computes
  `has_blocker = dir_has_ch(tests_blocked) || !collect_citations_in_dir("src").is_empty()`,
  so any citation in `src/` demands a `tests_blocked/` probe.
    - **Affected surface / narrowing:** Shoals had exactly one such citation --
      `src/pricing.ch:72` names `shoals#19` in the Beacon-seam design comment.
      **Amended 2026-09-05:** `src/pricing.ch` now also cites `chelis#902` and
      `nautilus#56`, which are genuine upstream citations covered by the entry
      above and by `tests_blocked/special/erf_builtin_absent.ch`, so row 12's
      demand is satisfied on their account rather than evaded.
      `shoals#19` is an own-repo issue, already resolved, and already carried in
      §Archived below, which is why row 9 (`staleness-audit`) correctly PASSES
      on its coverage. **There is no narrowing.** Because that line is a section
      header recording which work produced the helpers below it -- not a citation
      of anything blocked -- it now reads `(shoals issue 19)`. The reference and
      its meaning are preserved; what is dropped is the `#NNN` form's claim to be
      a narrowing citation owing coverage. No probe was invented and no evidence
      was deleted. The guard defect itself is filed as chelis#1387 and stands:
      a shell citing an own-repo issue that IS live would still be stuck, since
      row 12 accepts only a `.ch` probe, not the can't-be-probed note row 9 takes.
    - **Measured 0.18.5-vs-0.18.6 pair (2026-08-29):** on the unmodified tree,
      the 0.18.5 binary reports row 12 `NA` ("no open upstream blocker with an
      expressible reproducer") and `conform audit` exits 0; the 0.18.6 binary
      reports row 12 `FAIL` ("an upstream blocker is cited but tests_blocked/
      has no probe") and exits 1. Rewriting that one token to
      `(shoals issue 19)` and changing nothing else flips 0.18.6 back to `NA`
      and exit 0, which localizes the cause to the token rather than to any
      other edit in this change set.
    - **Not expressible as a `tests_blocked/` probe:** the failing surface is a
      `chelis reef conform audit` row verdict, not a compile or eval
      diagnostic, so `chelis test --expect blocked` cannot express it. It is
      re-probed by running `chelis reef conform audit` at every pin bump.
    - **Re-probe trigger:** the assigned `chelis#NNN` closing, or any release
      note naming `chelis-conformance` citation scanning or the §5 row.
      **Amended 2026-09-05:** `tests_blocked/` is no longer empty, so row 12
      now reads `PASS` on the unmodified tree whether or not this defect is
      fixed, and the old "require row 12 `NA`" criterion can no longer
      discriminate. Re-probe by moving `tests_blocked/special/` aside and
      re-running `chelis reef conform audit`: with the directory empty and the
      `src/` citations still present, row 12 reads `NA` if fixed and `FAIL` if
      not. Restore the directory afterwards. Then replace this draft path with
      the issue number everywhere it is cited.

- **chelis#1391 --
  `chelis test --batch-mode auto` regressed 2.6x on this suite.** On one quiet
  10-core machine with warm caches, `chelis test tests/ --timeout 1200
  --suite-timeout 1500 --jobs auto` over the same 43 files and 371 tests went
  from **3m01s** (0.18.5, 4m27s user) to **7m54s** (0.18.6, 9m37s user, stable
  across four runs). `--batch-mode file` is now more than twice as fast as the
  default on this suite (3m44s vs 7m54s), inverting what the batching
  optimization is for. This is not a general front-end slowdown -- the opposite
  is true at file scale on the identical corpus and machine, where
  `chelis check src/modelfit.ch` improved 67.6s -> 31.6s and six individual
  `chelis test <file>.ch` runs came out within noise.
    - **Affected surface / narrowing:** the nightly `chelis test (tests/ fast
      unit suite)` step, budgeted `--suite-timeout 1500` under
      `timeout-minutes: 30`. The narrowing is a budget raise at that step only
      (`--suite-timeout 2400`, `timeout-minutes: 45`), cited at the site. The
      tested configuration is deliberately unchanged: switching the step to
      `--batch-mode file` would be the faster fix locally, but that is a change
      of what CI exercises and no measurement exists for the 2-vCPU hosted
      runner, so it is not made here.
    - **Not expressible as a `tests_blocked/` probe:** the failing surface is
      wall-clock, not a diagnostic; an expected-to-fail `.ch` cannot express
      it. It is re-probed by timing the suite under both `--batch-mode` values
      at every pin bump.
    - **Re-probe trigger:** the assigned `chelis#NNN` closing, or any release
      note naming `chelis test` batching, `BatchScope`, or front-end scaling at
      compilation-unit size. Re-time both batch modes on the same machine and
      require `auto` to beat `file` again before lowering the nightly budget
      back.

- **Nothing blocks shipping the current proof surface.** The finance proof
  surface ships as documented in `research/proof-infra/report.md`: the economic
  / dynamic-programming properties reach the SMT tier with no transcendental
  contract; the derivatives structural properties
  (`properties/composites.ch`: upper bound, put–call parity with reflection,
  delta ∈ [0,1]) reach SMT as **composites** — structure proven for any `N`
  satisfying its contract, with that contract separately fuzz-validated on the
  real `n_cdf`. The real transcendental pricing bodies degrade **honestly** to
  fuzz (never a false proven — the coupled-subterm goals stay deferred, see
  chelis#637 below). Both entries above are tooling defects, not semantic ones.

## Tracking

- **chelis#1464 — `vmap`/`grad` evaluate untaken `if` branches, so every
  `erf64` core must be total.** `spec/06-transformations.md` §2.10.1 states that
  untaken branches contribute nothing and are not evaluated. The implementation
  lowers a scalar `if` under `vmap`/`grad` to a masked select that evaluates
  BOTH arms, so a core that returns a non-finite value outside its own region
  poisons the arm that was actually selected (`0 * NaN = NaN`).
    - **Affected surface / narrowing:** `erf64_core_small` and
      `erf64_core_erfc_mid` clamp their argument at entry, and
      `erf64_core_erfc_tail` clamps its LOWER end. `abs_f64` uses the `abs`
      intrinsic rather than a hand-rolled `if`, and `erf64` guards NaN with
      `eq(x, x)`. The clamps never bind on the region the dispatcher routes to
      each core, so no returned value changes.
    - **The rule, since two revisions got it wrong:** a clamp is an `if`, so
      under masked select it is safe only when its UNTAKEN arm has a finite
      VALUE **and** a finite DERIVATIVE over the domain totality is claimed
      for. The derivative half was missing from an earlier revision:
      `if c then k else sqrt(x)` has a finite untaken value at x = 0 and an
      infinite derivative, satisfies the weaker rule, and still NaNs under
      `grad` because the adjoint multiplies that derivative by the 0 mask.
      Measured at this pin; the shipped kernel is safe under the stronger
      rule, since every untaken arm is a constant or the bare operand. A bounded constant is sufficient but
      NOT necessary -- an earlier revision of this line said "bounded
      constant", which would condemn regions 1 and 2, whose clamps take the
      operand itself as an untaken arm and are demonstrably safe over the
      finite domain. The tail's lower clamp has the constant `1.0`; an upper
      clamp would take the operand, which is +inf at ax = +inf, so one added
      "for uniformity" REMOVED that branch's totality at the single point
      where it had more than regions 1 and 2. It is deleted, and its absence
      is unpinned: re-adding it leaves every test green, because the suite
      claims nothing at +inf.
    - **Scope of the guarantee:** total over the FINITE f64 domain, not over
      all of f64. `+/-inf` still poisons a sibling arm wherever an untaken arm
      is unbounded. `min`/`max` would close that but are unavailable at this
      pin: they type-check under vmap and then fail at eval with `missing
      required input min`, measured at 0.18.6. Filed as
      [`chelis#1582`](https://github.com/Chelis-Lang/chelis/issues/1582). Not
      chelis#377 (that one needs a top-level-binding capture; this reproducer
      captures nothing), so the residual is upstream-blocked rather than
      unfixed.
    - **Why the clamp is at every core, not at the observed failure:** an
      earlier revision guarded only the two divisions in region 3. Regions 1
      and 2 do not divide -- both are `P(y)/Q(y)` Horner chains with positive
      coefficients, so numerator and denominator both overflow to `+inf` and
      `inf/inf = NaN`. Guarding the sites a review named, rather than the
      class, let the same defect survive two repairs: measured, the f64 vector
      price returned NaN at sigma = 1e-60 and the AD gamma at sigma = 1e-40, a
      representable f32 subnormal.
    - **State at pin 0.18.6 (2026-09-07):** OPEN upstream. Pinning is
      per-clamp and was previously misstated as uniform: reverting the region-1
      or region-2 clamp fails the subnormal-sigma cases; reverting the tail's
      LOWER clamp fails the zero-`d` cases instead. The NaN guard is pinned by
      the non-finite-input cases: removing it fails
      `test_non_finite_input_propagates_rather_than_saturating` on the
      negative-spot assertion.
    - **The `abs` intrinsic is NOT pinned, and cannot be.** An earlier revision
      of this entry claimed it was. Swapping `abs(x)` for a hand-rolled
      `if lt(x, 0) then neg(x) else x` changes no observable output: measured
      through `bs_call_f64_vector` (the vmap lane) at an infinite sigma and at
      a negative spot, and through scalar `bs_call_f64`, both spellings return
      NaN in every cell, and the full suite is unchanged. The two differ only
      at a non-finite argument, and every path that reaches `abs_f64` with one
      ends in NaN regardless. The intrinsic is kept because it is the
      structurally simpler form -- one fewer `if` for the masked select to
      duplicate -- not because a test defends it.

- **nautilus#56 / chelis#902 — no f64-callable `erf`, so this shell carries its
  own kernel.** `Nautilus.Special` is f32-only, so a Shoals f64 grad path
  cannot call its `erf`; `Shoals.Pricing` therefore hand-rolls one. The
  duplication is the narrowing. The accuracy problem that came with it is
  fixed: `erf64` now evaluates Cody's rational approximation at a worst
  observed absolute error of >= 3.3675e-16 (~1.52 ulp, measured at 60 dps by
  `scripts/oracle_erf64_accuracy.py`; a floor, since the error is jagged at ulp
  scale and a grid finds only the worst point it samples), replacing the
  Abramowitz & Stegun 7.1.26 coefficients it had copied from the f32 sibling
  at ~1.4e-7.
    - **Affected surface / narrowing:** a second implementation of `erf` lives
      in this repo and must be maintained and measured here. `Shoals.Greeks`,
      `Shoals.PricingExtended` and `references/blackscholes.ch` all
      `import Nautilus.Special (erfc)`: they are **call sites, not copies**,
      and no file under `src/` or `references/` carries the A&S constants.
      `pricing_wire_erf_f64` remains, its coefficients caller-supplied tensor
      parameters. The duplication is wider than one kernel
      per repository: `src/pricing.ch` holds Cody's and the wire A&S form, and
      `research/proof-infra/ad/src/bs.ch` and
      `research/proof-infra/graduation/src/probe.ch` each hard-code the A&S
      f64 literals again. They are now different algorithms -- Cody's in the
      shipped kernel, A&S in the research probes and upstream -- so it is
      drift, not redundancy.
    - **State at pin 0.18.6 (re-probed 2026-09-12):** nautilus#56 CLOSED,
      nautilus#59 and chelis#902 OPEN. The probe still blocks:
      `tests_blocked/special/erf_builtin_absent.ch` reports `precision
      mismatch: expected f32, got f64` — the package `erf` resolves and refuses
      the width. nautilus#56 closing does not unblock it, because the f32-only
      signature is nautilus#59's subject. The three repairs are disjoint:
      nautilus#56 is the f32 original's own bound and changes coefficients, not
      the signature; nautilus#59 removes the reason to duplicate but leaves the
      bound wherever A&S is still used; chelis#902 supplies a canonical `erf`
      and removes both. None is a chelis arithmetic defect.
    - **The f32-only signature is filed as nautilus#59.** nautilus#12 is the LinAlg
      signature barrier and does not cover `Nautilus.Special`; citing it would
      make the de-narrowing branch unexecutable, since closing it would not
      yield an f64 `erf`.
    - **Re-probe trigger:** the blocked probe passing, either issue closing, or
      **any nautilus pin bump past 0.7.43**. The pin clause is the load-bearing
      one: nautilus#57 already switched `Special.erf` to a 4-term series below
      0.25 on main with no tag yet carrying it, so the kernel this shell mirrors
      in `scripts/oracle_greeks_gate.py::_erf_as_f32` changes at the next
      release, not at any issue transition.
      Follow that probe's sidecar; which repair landed decides whether this
      kernel is deleted in favour of a callable one or merely re-pointed.

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
    - **State at pin 0.18.6 (2026-08-29):** still OPEN upstream and the 0.18.6
      changelog names no origin canonicalization, so the narrowing stays. The
      adversarial pair (`scripts/check_release_artifact_determinism.py`) could
      not be re-run at this pin: it installs both dependencies from published
      GitHub releases, and Nautilus 0.7.43 / Coral 0.7.40 do not exist yet. It
      runs at the release gate that consumes them, which is where its verdict
      has always been taken.
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
    - **State at pin 0.18.6 (2026-08-29):** still OPEN upstream, and the 0.18.6
      changelog names no evaluator BFGS resource work. Not locally
      reproducible by construction -- the failure is specific to a constrained
      2-vCPU hosted runner and the fixture passes locally -- so the exclusion
      and its `scripts/test_release_workflow.py` lock are unchanged.
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
    - **State at pin 0.18.6 (re-probed 2026-08-29):** unchanged, measured
      per-surface rather than read off the changelog. `chelis prove
      properties/canonpricing.ch --json --tier smt-only --smt-timeout 20000
      --package .` against the 0.18.6 release binary returns `unsupported` /
      `property does not lower to Tier B (smt-only)` at `proof_tier=smt` for
      all 12 records -- `bs_call_price_nonneg`, `b76_call_price_nonneg`,
      `bs_call_monotone_in_s`, `bs_call_vega_sign`, `bs_call_rho_sign`,
      `bs_call_gamma_sign` and each corrupted twin. No direct property is
      reported proven, so the manifest tiers stay `fuzz_validated` and the
      green `scripts/prove_gate.py` run at this pin confirms it.
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
    - **State at pin 0.18.6 (re-probed 2026-08-29):** the cap is unchanged and
      was measured against both binaries with one disposable source, not
      inferred. A depth-3 goal chain (`goal -> level3 -> level2 -> level1`) is
      `passed` at `proof_tier=smt`; the otherwise identical depth-4 chain is
      `unsupported` with `property does not lower to Tier B (smt-only)`.
      Identical verdicts on 0.18.5 and 0.18.6. Command:
      `chelis prove <probe>.ch --json --tier smt-only --smt-timeout 20000`.
      Still gates nothing on the current Shoals surface.

## Parked

No parked entries.

## Archived

- **chelis#1200 — `_ = f(x)` marked `x` consumed when `f` destructured a record
  parameter (0.18.4 regression; RESOLVED on 0.18.5).** A `_ =` wildcard discard
  desugared with the `destructure: true` marker, opening the Linearity-F2
  destructure-consume scope over the rest of the enclosing body; any later reuse
  of a variable that a record-destructuring callee consumed was a hard
  `UseAfterConsume` instead of receiving the implicit Copy a named binding gets.
  In Shoals this failed `tests/curves_basis.ch` (through
  `Curves.basis_spread_at`) at the 0.18.4 bump.
    - **0.18.5 re-probe (2026-08-22, before/after against both binaries):** the
      reproducer `tests_blocked/linearity/wildcard_discard_consume.ch` checks
      with ``UseAfterConsume: variable `b` (from a destructured binding) was
      already consumed by call to `blocked_tag_of` at surf:308..325; later use
      at surf:343..344 is invalid`` on the 0.18.4 release binary and clean
      (`errors: []`, score 1) on 0.18.5. Both runs used
      `chelis +<ver> check wildcard_discard_consume.ch` on the identical file,
      so this is a measured pair rather than a changelog reading. Fixed upstream
      by [chelis#1208](https://github.com/Chelis-Lang/chelis/pull/1208)
      (resolve Linearity-F2 per binding, not per block region) and further
      hardened by [chelis#1254](https://github.com/Chelis-Lang/chelis/pull/1254)
      (resolve linearity alias chains by binding generation, not name).
    - **De-narrowing executed in the same change set:** the blocked probe went
      FIX-DETECTED and was promoted to `tests/wildcard_discard_consume.ch`; the
      4 cited `asserted_N` bindings in `tests/curves_basis.ch` were reverted to
      `_ =`, restoring the pre-0.18.4 form byte-for-byte apart from the v0.19
      canonical float respelling. `src/` never carried a workaround, so nothing
      there had to be reverted. `tests_blocked/` is empty again; see its README.

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
  by `Shoals.Pricing.bs_call_wire_f64`: a pure f64 tensor-DAG entry evaluating
  A-S 7.1.26 from caller-supplied coefficients -- NOT the scalar kernel, which
  moved to Cody's approximation under this shell's issue 61 -- with no host/vmap
  bridge and representative scalar-equivalence coverage. Migrating it is still
  open; see the erf entry above. The executable
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
