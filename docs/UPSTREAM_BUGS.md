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

> **0.18.13 candidate status (2026-10-05):** The compiler pin and managed
> conformance content have been updated. Nautilus 0.7.48 and Coral 0.7.45
> remain unpublished, so package-context tests and proof gates cannot yet run
> against a matching release chain. The 0.18.12 observations below are
> historical evidence for the preceding candidate.
>
> **0.18.12 pin status (2026-10-01):** The official Chelis 0.18.12 /
> Nautilus 0.7.47 / Coral 0.7.44 package chain builds. An initial nested AD
> compiler error (chelis#2825) is avoided by sequential scalar conditionals:
> all four second-order Greek cases, all 37 raw proof controls, and the Greek
> numeric oracle and the 4,451-point-per-function f64 accuracy sweep pass.
> The full local gate is pending; the candidate is not yet an accepted release. Receipts are in
> [`chelis_0_18_12_migration.md`](chelis_0_18_12_migration.md).

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
      **Amended 2026-10-01:** `src/pricing.ch` also cites chelis#902 and
      nautilus#74. The canonical `erf` absence probe was promoted to
      `tests/canonical_erf.ch` at the 0.18.13 pin; the remaining narrowing is
      Shoals's retained Cody kernel, pending a compatible chain comparison.
      The resolved nautilus#59 signature probe
      was promoted to a positive test.
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
    - **0.18.12 standalone re-probe:** an isolated copy with only a
      `shoals#19` source citation and no `tests_blocked/` produces row 12
      `FAIL` again. This does not change the real tree's PASS verdict.

- **shoals#111 -- the nightly `tests/` suite exceeds its hosted budget.**
  The earlier compiler batching regression is chelis#1391, fixed upstream by
  chelis#3058 and included in the 0.18.13 pin. The hosted Shoals suite still
  needs a fresh complete run before the raised budget can be retired. On one quiet
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
    - **Re-probe 2026-10-04 on Chelis 0.18.11 — still blocking at that pin.**
      chelis#1391 is CLOSED upstream, fixed by **chelis#3058**
      (`04612253c`, batching sharded at `MAX_BATCH_FILES = 4`). The
      `=0.18.11` pin still had the regression. Re-timed per the trigger at head `69e1e59` on
      the release binary, the current 49 files and 549 tests, one 10-core
      machine, both legs back to back: `--batch-mode auto` 1113s wall / 1218s
      child CPU (1.09 cores), `--batch-mode file` 341s wall / 1264s child CPU
      (3.71 cores) — **3.27x the wall for +3.8% CPU**, both legs
      `549 passed, 0 failed`. `auto` does not beat `file`, so the budget does
      not come back down.

      The CPU parity is the part that carries: identical work, 3.27x the
      wall, so this is a scheduling outcome. `--batch-mode auto` collapses
      files into batches, which leaves `--jobs` almost no test-file workers to
      schedule; chelis#3058's own message says the merged unit "ran in one
      subprocess whatever `--jobs` said: the setting reached only the files
      that had been demoted out of the batch". That fix both caps batch size
      and extends `--jobs` to shard concurrency. The ratio is larger than the
      2.12x recorded above, but that pair differs in file count, test count
      and compiler release at once and isolates no cause.

      No hosted measurement of `--batch-mode file` exists, on this suite or
      any other, and none is projected here: 10-core parallelism does not
      transfer to a 2-vCPU runner. shoals#111 owns measuring it, which one
      `workflow_dispatch` settles.

      Shoals#111 owns the remaining hosted timeout and a measured
      `--batch-mode file` comparison on the 2-vCPU runner. Keep the raised
      budget until that issue's suite measurement shows it can be lowered.

- **The last accepted proof surface remains the 0.18.11 chain.** The finance
  surface there is documented in `research/proof-infra/report.md`: the economic
  / dynamic-programming properties reach the SMT tier with no transcendental
  contract; the derivatives structural properties
  (`properties/composites.ch`: upper bound, put–call parity with reflection,
  delta ∈ [0,1]) reach SMT as **composites** — structure proven for any `N`
  satisfying its contract, with that contract separately fuzz-validated on the
  real `n_cdf`. The real transcendental pricing bodies degrade **honestly** to
  fuzz (never a false proven — the coupled-subterm goals stay deferred, see
  chelis#637 below). Both entries above are tooling defects, not semantic ones.

## Tracking

- **chelis#2825 — nested gradients reject a compiler-generated logical
  `not` in a nonlinear nested clamp.** A standalone copy of Shoals's scalar
  Cody kernel reproduced the 0.18.12 `grad: not is non-differentiable` error.
  A minimal nested two-branch clamp squared fails at an interior point, while
  sequential selections evaluate its second derivative. Shoals now spells
  the small-region clamp and erfc dispatcher sequentially. This preserves the
  scalar price and exported nested-gradient path: all four second-order test
  cases, their raw proof control pairs at seeds 0, 1, and 2, and the Greek
  oracle pass. The upstream nested-clamp bug remains open; keep the source
  spelling and re-probe the reproducer on a compiler release that changes AD
  lowering. The reproducer and diagnostic are in chelis#2825.

- **chelis#2103 — untaken arithmetic under `vmap`/`grad` can poison a
  selected result, so every
  `erf64` core must be total.** `spec/06-transformations.md` §2.10.1 states that
  untaken branches contribute nothing and are not evaluated. On the prior
  package chain, masked lowering of scalar `if` under `vmap`/`grad` let a
  non-finite untaken core poison the selected result (`0 * NaN = NaN`).
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
      is unbounded. Imported `Std.Scalar.min/max` were unavailable under
      `vmap` at 0.18.6 (chelis#1582). That issue is now closed: a standalone
      0.18.12 package using bundled chelis-std passes both Eval and compiled C
      for imported `min/max`. Whether changing Shoals' clamps is safe remains
      untested against the compatible Nautilus/Coral chain.
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
    - **0.18.12 standalone re-probe:** a corrected `vmap`/`if` example
      returns a finite selected value in Eval and C even though its discarded
      series evaluates to `-inf` directly. This one shape does not reproduce
      poisoning; chelis#2103 remains open, and Shoals pricing and `grad` paths
      cannot be cleared before a compatible package-chain gate. chelis#1464
      closed for the distinct taken-`fail` case.
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

- **nautilus#74 / chelis#902 — Shoals still carries a separate f64 `erf`
  kernel.** Nautilus 0.7.47 exports `erf[prec: Float]`, so
  nautilus#59's signature barrier is gone. Its A&S rational arm retains
  approximately 1.4e-7 absolute error at f64, while `Shoals.Pricing.erf64`
  uses Cody's approximation with a measured worst-observed floor of
  >= 3.3675e-16. Shoals keeps that kernel for accuracy. The absence of a
  Chelis 0.18.13 adds correctly rounded `erf` and `erfc` primitives. The
  broader special-function request chelis#902 remains open.
    - **Executed on the partial 0.18.12 chain (2026-10-01):** Nautilus 0.7.47's
      sidecar-verified release source declares the generic export, with no
      exported-name changes from 0.7.46. The old f64 call probe checks clean
      and `tests/nautilus_erf_f64.ch` passes in an isolated package containing
      only released Nautilus and bundled chelis-std. The f32 Taylor/A&S
      branches have the same coefficients as 0.7.46; the full Shoals mirror
      and numeric gates await Coral's compatible release.
    - **Narrowing:** `src/pricing.ch` retains its own Cody kernel; `erf_t` and
      Shoals's tensor-wire and research bodies remain separate approximations.
      The former canonical-absence probe is promoted to
      `tests/canonical_erf.ch`. Compare the new primitive against the current
      kernel, including Greek and expiry behavior, before replacing it.
    - **Re-probe trigger:** a nautilus#74 or chelis#902 resolution, or a
      Nautilus pin changing the `Special.erf` kernel. Re-run the generated
      f32 mirror, measure f64 accuracy, and only de-narrow when the replacement
      meets Shoals's measured contract.

- **chelis#1002 — Reef preserves caller-provided GitHub owner casing in
  `remote_origin`, making lock and package bytes registry-history-dependent.**
  Reproduced against the 0.18.1 release binary on 2026-08-01 with identical
  Shoals source and identical official Nautilus 0.7.38 / Coral 0.7.35 assets:
  a registry installed through `Chelis-Lang/...` and a fresh registry resolved
  through `chelis-lang/...` emitted different `reef.lock`, CHB, and archive
  bytes solely because the origin strings differed in case.
    - **Affected surface / narrowing:** every Shoals workflow and Python
      installer uses canonical lowercase `chelis-lang/...` coordinates.
      `scripts/build_release_assets.py` resolves both dependencies in a
      fresh registry using those coordinates, discards a stale generated lock
      before the build, and rejects a non-canonical replacement. A lowercase
      reinstall into a mixed-case preseeded registry did not rewrite its
      origins on Chelis 0.18.12. `scripts/check_release_artifact_determinism.py`
      compares two isolated Reef homes: one preseeded through mixed-case
      manual installs and one clean, requiring byte-identical lock, CHB, and
      archive payloads. This does not claim the compiler is fixed.
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

- **nautilus#70 / nautilus#85 — `Nautilus.TimeSeries` is f32-and-tensor-only,
  so `Shoals.Indicators` carries its own rolling and lag layer.** nautilus
  0.7.46 declares
  `ts_ewma_series[n](values: &tensor[n, f32], alpha: f32, initial: f32) -> tensor[n, f32]`
  — the nearest thing in the ecosystem to a rolling-series primitive. An f64
  `List[f64]` indicator path cannot call it at any argument.
    - **Affected surface / narrowing:** `Shoals.Indicators` ships
      `ind_rolling_sum`, `ind_rolling_mean`, `ind_rolling_std`,
      `ind_rolling_min`, `ind_rolling_max`, `ind_shift` and `ind_diff`
      (shoals#83). These are generic time-series primitives, not finance; the
      `ind_` prefix marks them as a borrowed layer. No Shoals-facing behaviour
      is narrowed — the layer is complete for the indicators built on it. The
      cost is duplication, and it is narrower than it first looks: the rolling
      family exists in exactly ONE other place in the ecosystem, so
      `ind_rolling_*` is the SECOND implementation, and `ind_shift` / `ind_diff`
      duplicate nothing at all — no package has a shift, lag or diff at any
      width or shape. Measured 2026-10-01: zero defs matching
      rolling|window|shift|lag|diff among nautilus 0.7.46's `src/` DEFINITIONS
      and exports (a bare substring sweep also hits `gauss_laguerre_10` and
      `smoke_sde_diff`, which ARE definitions but are not members of the
      rolling/shift/lag/diff family), and
      `Coral.Window` exporting exactly `rolling_sum`, `rolling_mean`,
      `rolling_std`, `rolling_min`, `rolling_max`, `ewm`.
    - **Why the one existing copy does not serve, and why Nautilus is not a
      second copy:** `Nautilus.TimeSeries` is
      f32 and tensor-shaped, per the declaration above. `Coral.Window` has
      rolling sum, mean, std, min, max and `ewm` already, but is f32-only AND
      not a compiled lane (coral#26).
    - **The INPUT shape converged; the RETURN shape and the warm-up
      representation did not.** shoals#83's tensor forms take
      `tensor[n, f64]`, so the duplication is closer than it was on the
      argument side. Three differences remain, measured against
      `coral-0.7.43` as pinned: `Coral.Window` is f32 throughout (the package
      contains no `f64` at all -- `src/frame.ch` is `FloatCol(tensor[n, f32])`);
      it RETURNS `tensor[n, f32]` where these return `List[Option[f64]]`; and
      it fills the warm-up with `nan_f32()` (`src/window.ch` lines 34, 39, 44, 49 -- 4 fill sites; the other four `nan_f32` tokens there are its definition, a degenerate-window guard, and two propagation sites in the min/max folds) where
      these carry an `Option` mask -- the very representation
      `spec/shoals_quant_surface.md` §2.15.5 exists to require. It also offers
      no `Ddof` choice (sample only) and no shift or diff.
      **A previous revision of this bullet said the remaining difference was
      dtype alone and that the narrowing was therefore wider. That
      over-corrected.** The risk it created is concrete: a future bump could
      retire the borrowed layer believing only width separates it, and lose
      the mask.
    - **The layer's export footprint doubled from 7 to 14** with those tensor
      forms, so §2.15.3's commitment to delete it when nautilus#85 lands now
      covers 14 exports. The deletion stays mechanical -- each tensor form is a
      one-line `to_list` delegation -- but the count is recorded here so the
      bump that retires the layer is not surprised by it.
    - **Executable probe:** `tests_blocked/timeseries/rolling_f64_absent.ch`,
      keyed on `ts_ewma_series` because it EXISTS. A probe naming a
      not-yet-written `rolling_mean` would keep failing after nautilus#85
      landed under any other name, and that false negative is
      indistinguishable from "still blocked".
    - **The two fixes are disjoint, and the probe only detects one.** An f64
      signature on `Nautilus.TimeSeries` (nautilus#70) flips the probe but does
      NOT retire the layer: the Nautilus surface is exponential and
      tensor-shaped, and `ind_rolling_min`, `ind_rolling_max`, `ind_shift` and
      `ind_diff` have no counterpart there at any width. nautilus#85 —
      rolling-window and lag primitives on `List[f64]` — is what retires the
      layer, and it can land while the probe still fails. Re-probe trigger:
      any Nautilus release whose notes touch `TimeSeries` widths or close
      nautilus#85. The probe's sidecar carries the branch-by-branch
      de-narrowing steps.
    - **State at pin 0.18.11 / nautilus 0.7.46 (measured 2026-10-01):** the
      declaration was read out of the pinned package
      (`nautilus-0.7.46.tar.zst`, `src/timeseries.ch:13`), not off a changelog.
      The probe reports `tensor precision mismatch: f32 vs f64`. Both
      nautilus#70 and nautilus#85 are OPEN and unassigned.

## Archived

- **shoals#79 — `Shoals.Curves` answered a failed bootstrap with a silent `NaN`.**
  Resolved in this shell by failing loudly at the precondition instead: a quote
  whose zero rate falls outside the module's `[-0.5, 2.0]` search bracket, a
  repricing residual that is not finite over it, a non-converged solve, a
  non-finite tenor or quote, a deposit whose `1 + rate * tenor` is not positive,
  and a `paths_template` whose length does not match the instrument list all
  raise a diagnostic carrying the measured values. `tests_neg/curves/` covers
  nine cases and `tests/curves_bootstrap_ift_full.ch` the positive side. The
  `did not converge` diagnostic is **not** covered: it is the residual arm of
  the classification, no input is known to reach it, and claiming coverage for
  it would be false.
  Recorded here because §4's narrowing-coverage scanner reads the `shoals#79`
  and `shoals#113` citations in `src/curves.ch`, and neither is a narrowing:
  both comments explain a design decision that outlives the fix.
    - **Nothing is narrowed and nothing is worked around.** The bracket is this
      module's own choice, not a limit imposed by `Nautilus.Roots.brent`, so
      stating its precondition is a contract this shell owns. Whether the
      bracket should be *wider* is a separate question and deliberately
      untouched: a quote outside it is rejected, not re-solved.
    - **The `shoals#113` citation is a precedent, not a dependency.** It names
      the shape that issue's merged resolution chose for the sibling
      `bootstrap_multi_curve` at `3ddd518` — read the precondition, fail with
      both measured counts — which this change applies to
      `bootstrap_grad_full_jacobian`.
    - **One upstream observation, filed nowhere and not blocking.** Under
      `chelis eval --file`, a residual that is not finite anywhere makes
      `brent_rec` recurse to its hundred-iteration budget and the lane aborts
      with `fatal runtime error: stack overflow` rather than returning the NaN
      that `chelis test` returns from the same call. Measured at 0.18.11 with
      `brent(fn (z) -> 0.0/0.0, -0.5, 2.0, 1e-7, 100)`; the same-sign case
      returns NaN without recursing, so the two differ. **Shoals reaches
      this**, deliberately: an earlier revision of this change examined the
      endpoints before calling `brent` and so avoided the recursion, but doing
      that reordered `brent`'s own endpoint-root acceptance and broke a quote
      that solved on `130d235` (`cur_par_swap(200.0, 6.3890557, 1)`, a root
      sitting exactly on an endpoint beside a non-finite one). Preserving the
      solver's behaviour was worth more than routing around the eval lane, so
      the classification happens after the call. Owner undetermined: whether
      the abort is recursion depth or that lane's stack size decides whether it
      belongs to nautilus or to chelis, and that is unmeasured.

- **shoals#101 — three exported Greeks were `NaN` at expiry and call delta was silently wrong at the strike.** Resolved
  in this shell by supplying the `t = 0` limits in closed form in the Greek
  wrappers; `tests/pricing_greeks_expiry.ch` covers all nine cells and the
  finiteness predicate. Recorded here because §4's narrowing-coverage scanner
  reads the `shoals#101` citations in `src/pricing.ch`, and those comments explain
  two narrowings that outlive the fix, only one of which the pin bump will
  dissolve.
    - **The theta half is chelis#2640 and does dissolve.** The shoals#88
      denominator clamp's untaken arm is `sigma*sqrt(t)`, whose `t`-derivative is
      `+inf` at `t = 0`; `grad` of that clamp wrt `t` is NaN at `t = 0` and `0.1`
      at `t = 1`, measured. That is the chelis#2640 case, fixed upstream at
      0.18.12 and not present at this pin. When the pin reaches 0.18.12, re-probe
      whether `thetas_call`'s AD path produces `-r*k` and `0` directly.
    - **The second-order half does NOT dissolve, and is not an upstream defect.**
      With the denominator floored, `d(d1)/ds` is `1e298`; squaring it overflows
      to `+inf`, which multiplies an underflowed second-order factor to give
      `0 * inf = NaN`. That is IEEE arithmetic on our own floored value, so the
      closed forms for gamma and vanna stay needed at every pin.
    - **`where` is load-bearing here, not stylistic.** The gamma limit is `+inf`
      at the strike, so a hand-rolled arithmetic select computes `0 * inf = NaN`
      for every other lane: measured, `where(...)` gives `[inf, 0, 0]` where
      `mask*inf + (1-mask)*0` gives `[inf, NaN, NaN]`. A test fails if the select
      is rewritten as arithmetic. Do not simplify it.

- **chelis#2640 — `grad` through a scalar `if` returns NaN when the untaken
  branch has a non-finite DERIVATIVE, so every `erf64` core must be total.**
  `spec/06-transformations.md` §2.10.1 states that untaken branches contribute
  nothing and are not evaluated. The adjoint multiplies the untaken arm's
  derivative by the zero mask, so an arm with an unbounded derivative poisons the
  result even though it was not selected.
    - **Resolution:** CLOSED upstream 2026-09-27, resolved by chelis#2586
      (`e65735e8c`), whose witness returns a finite gradient and whose eval/C
      untaken-arm gradient oracle passes. **This shell is pinned at 0.18.11,
      which does not contain that fix**, so every narrowing below still binds.
      Re-probe at the pin bump to 0.18.12 or later and simplify whatever the fix
      makes unnecessary; needing the pin to catch up is the only reason this
      entry is archived rather than active.
    - **This entry previously cited chelis#1464, which was wrong twice over.**
      That issue is "Transforms mask a taken scalar-if `fail` branch as zero" --
      a *taken* `fail` arm lowering to a zero `Const` -- a different mechanism,
      and it is CLOSED. The value-level story that citation carried
      (`0 * NaN = NaN` poisoning the selected arm) does not reproduce at 0.18.11:
      measured, `vmap(if eq(x,0) then 7.0 else div(x,x))` over `[0.0, 2.0]` is
      `[7.0, 1.0]`, and a hand-rolled `if` absolute value returns `inf` at `+inf`
      exactly as the `abs` intrinsic does. It may have reproduced at an older
      pin; it does not now. The DERIVATIVE rule below is what binds, and that one
      is measured at this pin.
    - **Affected surface / narrowing:** `erf64_core_small` and
      `erf64_core_erfc_mid` clamp their argument at entry, and
      `erf64_core_erfc_tail` clamps its LOWER end. `erf64` guards NaN with
      `eq(x, x)`. The clamps never bind on the region the dispatcher routes to
      each core, so no returned value changes. They are retained on the
      derivative rule below and on in-region numerical correctness: a core
      evaluated outside its own Cody region returns a wrong number, which is a
      reason to clamp independent of any transform. `abs_f64` uses the `abs`
      intrinsic, which is the better spelling on its own merits; the claim that a
      hand-rolled `if` would return NaN at `+inf` is withdrawn as unmeasured --
      it returns `inf`, exactly as the intrinsic does.
    - **The rule, since two revisions got it wrong:** a clamp is an `if`, so
      under masked select it is safe when its UNTAKEN arm has a finite
      DERIVATIVE over the domain totality is claimed for. This entry asks for a
      finite VALUE as well, and that half is conservative margin rather than a
      measured requirement at this pin: an untaken arm with an infinite or NaN
      value but a finite derivative differentiates cleanly (measured). Keeping
      the stronger form can only retain a clamp that is not needed; it cannot
      license removing one that is. The derivative half was missing from an earlier revision:
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
      all of f64. An unbounded untaken arm does not poison the selected arm's
      VALUE at this pin (measured); the exposure is its derivative, per the rule
      above. `min`/`max` would close that but are unavailable at this
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

- **shoals#88 — Black-Scholes returned NaN with no remaining uncertainty, in
  both the scalar and the WireDag lane.** Resolved in this shell by flooring
  `sigma*sqrt(t)` in `d1_64` and `pricing_wire_d1_f64`; `tests/pricing_expiry.ch`
  covers it. Recorded here because §4's narrowing-coverage scanner reads the
  `shoals#88` citations in `src/pricing.ch`, and those comments explain a
  deliberate narrowing that outlives the fix: the guard **must** stay a clamp on
  the denominator and may not become a branch on the price. The binding reason is
  the **derivative** rule in the chelis#2640 entry above, not the value rule --
  measured at this pin the rejected branch returns the correct price at every
  lane, and only its delta is NaN, because the adjoint multiplies the untaken
  arm's infinite derivative by the zero mask. Anyone who checks only the price
  will conclude the clamp is unnecessary. The hazard does not need `vmap` either:
  it reproduces under plain `grad`. The wire lane additionally cannot use a branch at all: its
  selectors are arithmetic, so it hand-rolls `abs` out of a select and the first
  `+/-inf` reaching it computes `0 * neg(inf)` -- IEEE arithmetic in this shell's
  own select, not an upstream defect. The scalar floor may be revisited when the
  pin reaches 0.18.12 and chelis#2640's fix lands here; the wire floor is
  independent of any upstream state, because that lane must stay producer-clean
  for the WireDag seam and so has no `if` available to it. Until then both are
  load-bearing. The re-pinned WireDag receipt
  (`scripts/validate_bs_wire_root.py`, root 859 / 1665 nodes) reflects the
  floor and involved no compiler change.

- **nautilus#59 — `Nautilus.Special.erf` refused f64 callers.** The
  0.18.11 / Nautilus 0.7.46 probe reported `precision mismatch: expected f32,
  got f64`. Nautilus 0.7.47's sidecar-verified package declares
  `def erf[prec: Float](x: prec) -> prec`; the identical call shape checks
  clean against the released package and the promoted Shoals test passes in
  an isolated Nautilus-only package. This closes the signature barrier, not
  the approximation gap, which is tracked by nautilus#74 above. The old
  blocked probe was replaced by the positive test in this pin change.

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
