# Shoals Agent Contract

Canonical agent instructions for this repository. `CLAUDE.md` is a symlink
to this file so Claude-style and Codex-style entry points do not drift.

## Repo Identity

<!-- BEGIN CHELIS MANAGED BLOCK: agents-inheritance chelis@0.18.12 (sha256:ba2c4adc45022f00) -->
# Chelis Agent Contract

Keep this file concise and relevant to every agent working in this repository.
Each added token is read tens of thousands of times. State a rule once, link the
document that owns the detail, and put the explanation in that document, not here.

`CLAUDE.md` is a symlink to this file so Claude-style and Codex-style entry points do
not drift.

## What Chelis Is

Chelis is a functional language for AI research, built for a workflow where a coding
agent is the primary author and a human is the supervisor, and where the programs are
themselves AI systems: models, training loops, search spaces, learned functions. The
bet is that a type system, representation, and compilation model designed around AI
primitives from the start beat ones bolted onto Python or a systems language later. It
is not a general-purpose language, a systems language, a web framework, or a Python
replacement. `spec/00-context.md` and `spec/design/chelis_canonical_reference.md` own
the full statement; their specifics may lag, their intent does not. When a tradeoff
appears, apply these in order:

1. **Unambiguity over ergonomics.** The author is an agent. The friction a human feels
   spelling out every type, effect, dtype, and dimension is not worth a reading the
   compiler has to guess at.
2. **Composition over special cases.** A new capability composes existing primitives
   before it earns a new one.
3. **Inference over annotation.** Where the checker determines something uniquely, the
   author does not repeat it; intermediates carry no ascription.
4. **Machine generation first.** A convenience that exists only for a human typist is
   not a reason to add syntax, a default, or a fallback.
5. **Additive sugar only.** Every surface form desugars to the core; nothing in the
   surface has semantics the core lacks.
6. **Explicit over implicit.** No implicit broadcasting (`expand` only), no implicit
   precision promotion, no implicit currying or partial application, no silent
   narrowing at ingress, no hidden effects. Where intent cannot be determined uniquely,
   the compiler rejects.
7. **Small language, big library.** The compiler knows only the closed RISC primitive
   set and its derived built-ins; everything else is a library. The canonical reference
   §8.5 has the core/standard-library/external-library taxonomy.
8. **Future-proof without over-building.** Decide the rule fully now, implement what
   the phase needs, and never narrow a rule to what a lane implements today.

Two corollaries govern how the compiler itself is changed. Chelis is pre-compatibility
unless a controlling contract says otherwise, so prefer the structural design that
makes a defect class impossible over a smaller-blast-radius patch, a legacy default, a
versionless compatibility fallback, or phase deferral; close the class, not the
instance. And determinism is part of the contract: for fixed program text, compiler
build, target, and declared inputs, every check, evaluation, and build result is a
function of those inputs, and feedback that varies between identical runs is a defect.

## Quality Standards

### Spec-First Development

- Before writing implementation, write test stubs derived from the owning spec.
- Every spec requirement should have a corresponding test before the code exists.
- If the spec says "X is a type error," write the failing test before implementing
  the checker.

### Negative Test Parity

- For every test that checks something works, add the corresponding failure test.
- If you cannot name the failure case, the spec understanding is still weak.

### Do Not Trust Green

- Passing tests prove alignment with the tests, not necessarily with the spec.
- After green CI, check what active requirements still lack tests.
- Audit silent fallbacks, default values, empty error vectors, and `unwrap_or` paths.

## Review And Merge

### Red Team Rounds

Run every round through the [`redteam-exec` skill](agent-skills/redteam-exec/SKILL.md).
It carries the brief shape, the worktree-reuse rules, and the verify mode.

- Red team against the spec, the code, the tests, the examples, and the CLI behavior.
  Execute tests and commands; source inspection is not proof.
- Every pull request, documentation-only work included, gets at least one round before
  merge. A round is the whole live back-and-forth between one reviewer and the author,
  not a single review pass:
  1. A fresh local subagent reviews the exact head from an inline brief and reports
     its findings.
  2. The reviewer stays alive. The author repairs the findings in the worktree.
  3. The author hands the repair back, and the same reviewer verifies it and looks for
     similar issues the repair may have missed or introduced.
  4. Any further finding goes back to the author, and steps 2 and 3 repeat.
  5. The round ends only when that reviewer states it is satisfied.
  A reviewer that has reported is not finished; it is waiting for the fix. Ending the
  loop after the first report, or verifying a repair with a different reviewer, is not
  a round.
- A pull request gets at most three fresh rounds; a fourth needs the user's explicit
  approval. A prose-only pull request gets one, and a second needs the same approval.
  The pull request's round record is the counter. Verification by the standing reviewer
  does not count; the end-of-pull-request round does.
- A finding is in scope only when the pull request introduces it, worsens it, or claims
  to correct it. Discovery during review does not bring a pre-existing defect into scope.
- A confirmed in-scope P0 or P1 merits a fresh round after the current round finishes,
  within the cap. Unmigrated assertions, old comments, and minor documentation drift do
  not. A rebase does not by itself merit a round: send a hand-resolved intersection that
  stays within files the standing reviewer already read to that reviewer for focused
  verification, and use a fresh round only when the rebase introduces a new mechanism or
  touches files that reviewer did not read. A targeted review of substantial rebase
  overlap needs no permission and never counts toward the cap.
- For documentation and design reviews, severity follows contract impact. A wrong
  normative rule, or a plan that cannot close a named in-scope deliverable, is P0 or P1.
  A design document that misdescribes current `main`, or exposes a sequencing seam while
  the contract stays achievable, is P2 or P3 and is recorded as residual work, never
  promoted to a merge blocker. Wording, line-level accuracy of the pull request body,
  staleness against a sibling pull request's moving head, and anything whose fix would
  add text without a necessity sentence are out of scope.
- State a pull request's claim at the granularity its oracle proves. An unbounded
  universal claim invites sampling in every round and can never be closed.
- A finding class is the defect category, not its file, line, or wording instance.
  Every round record names the class of each finding. When two consecutive rounds
  report the same class, or replace a repaired finding with a different class, stop
  patching witnesses: change the representation, the oracle, the claim, or the brief
  before running another round.
- Repairs may correct, remove, or narrow the pull request's content. They must not add
  design scope, mechanisms, inventories, or promises merely to absorb a finding. When a
  correction would need that, reduce the claim and track the rest outside the pull
  request.
- Freshness is a property of the reviewer's context, not the filesystem. Hand a
  reviewer an existing worktree and its warm target only when it is at the exact review
  head, has a known clean baseline, and has no concurrent writer, and paste the output of
  `.venv/bin/python scripts/worktree_status.py` into the brief as the evidence. Unknown
  or not-clean means wait, and free is the probe's best answer rather than a proof: a
  run that takes no lease, `--fast` among them, is caught only by a scan of the
  processes it spawned. A reviewer whose probes mutate tracked source gets its own
  worktree, and you never edit a worktree a reviewer is reading.
- Before spawning a fresh round, retire only your own stale or failed subagent handles;
  a standing reviewer awaiting a fix is neither. If a spawn routes to remote
  infrastructure, errors, or comes back broken, retire it and retry until you have a
  working fresh local subagent, or state that red-team validation is blocked.

## Environment And Tooling

### Worktree And Branch Discipline

- The primary checkout (the main worktree in `git worktree list --porcelain`) is live
  developer state. Read-only queries are fine there; never switch branches, edit, build,
  or create scratch artifacts in it.
- Create a dedicated worktree before the first write of every task, including small
  documentation edits and throwaway probes, and give it its own `.venv` with
  `uv venv --python 3.11`; never copy or symlink another checkout's `.venv`.
- A worktree isolates the working tree, the index, and its HEAD reflog. The stash
  stack, `.git/info/exclude`, the hooks directory, and branch reflogs are shared by
  every worktree on the clone. Do not run `git stash` in a shared clone: to discard your
  own changes use `git checkout -- <paths>`; to park them, copy the files to task-owned
  scratch space or commit them on your branch.
- Do not repurpose an unrelated worktree because it appears idle. Reuse only for the
  same PR or immediate follow-up after checking ownership, exact head, status, and active
  processes. Never share a worktree with a reviewer while either of you writes to it.
- After a PR merges, remove its worktree and task-owned target with individual
  `git worktree remove <path>` and `cargo clean --target-dir <path>` commands, never a
  blanket loop, after confirming the PR is merged, nothing uncommitted is worth keeping,
  and no process owns the target. Squash merges mean "commits ahead of `origin/main`"
  proves nothing; compare patch ids when in doubt. Branch deletion is a separate decision.

## Subagents

[`docs/investigations/agent_contract_rationale.md`](docs/investigations/agent_contract_rationale.md)
holds the measurements behind these rules.

- Every subagent prompt names the delivery mechanism and the complete expected report.
  A report that is not sent through the platform's final-report channel has not been
  delivered. A subagent never ends its turn merely to wait for a background build or
  notification that cannot wake it: keep ownership through a synchronous wait, or return
  an honest partial result. A reviewer that has delivered its round report is not
  waiting; it stays available for the orchestrator to resume with the fix.
- CI is watched by at most one background waiter whose exit wakes the session, or by
  nobody. Never watch CI from a foreground sleep or poll loop.
- If an agent returns "waiting" or goes idle without the deliverable, resume it
  immediately with the exact missing items. Prefer a labelled partial report over
  silence or an overstated completion claim, and deduplicate repeated reports that
  race with a resume nudge.
- More than five subagents live at once under one orchestrator needs the user's
  explicit approval and a stated reason. Five is the widest fan-out measured working
  here, not a certified safe width, and it is a separate budget from the CPU one above.
- Every spawn names its model tier and says in one clause why that tier fits: the
  expensive tier for judgement whose errors are costly to detect, the cheap tier for
  mechanical work such as waiting on CI, polling, or transcribing a result. The
  orchestrator states its own context size in the message that announces a spawn.
- Every brief states a numeric report-length budget, and a numeric context budget except
  for red-team rounds. An agent that will exceed its context budget says so and returns
  what it has.
- A brief says which facts the orchestrator has already verified, against what head, and
  that the agent must not re-derive them, and it names what the agent still has to
  establish itself.
- A brief longer than a few paragraphs is a file passed by absolute path, stored where
  it outlives both the agent and the session, never in a per-session scratchpad.
  Inter-agent messages truncate silently near four kilobytes. "Inline" means
  self-contained, the opposite of "read `AGENTS.md`", not pasted into the spawn message.
- Reports come back the same way: the agent writes the report to a file and replies with
  the absolute path and a one-line summary. That reply is the delivery.
- A subagent that reuses a worktree restores its temporary probes and reports the final
  worktree status unless asked to retain them. Before a heavyweight cargo command it
  reports the exact command and expected weight to the orchestrator.

## Writing Chelis Source

Load the [`example-corpus` skill](agent-skills/example-corpus/SKILL.md) before writing
any `.ch`; it carries the Surf style rules, the parse-breaking spellings, and the Deep
AST contract. `spec/02-surf-syntax.md` §0.1 is the authority.

- `chelis build`, `check`, `validate`, and `eval --file` run `chelis fmt --check` and the
  blocking `chelis lint` rules before the front end; style failures block the build.
  `--allow-style-violations` is for emergency local builds only, never CI, and
  `CHELIS_STYLE_GATE_DISABLE=1` is reserved for the integration-test corpus. Run
  `chelis fmt --inplace <file>` and `chelis lint --check` before pushing.
- Type system: no implicit precision promotion, named tensor dimensions match by name,
  no implicit broadcasting (explicit `expand` only), integer literals default to `i32`
  and float literals to `f32`.
- `chelis build` emits C, a header, runtime artifacts, and compile flags; `--target hip`
  emits host code with embedded kernel strings. Neither invokes the native compiler.

## Pointers

- **Shared skills** live in `agent-skills/`; `.claude/skills` and `.codex/skills` are
  symlinks to that one authored tree, `.claude/commands/` and `.codex/commands/` stay byte-identical, and the
  `red-team` alias is wired to `redteam-exec` with its fresh-round and verify modes. The
  set: `redteam-exec`, `spec-sync`, `phase-gate`, `backend-numerics`, `example-corpus`,
  `cli-surface`, `packaging-install`, `issue-resolution`.
- **Toolchain and packaging.** `chelisup` is the installer and pin-resolving `chelis`
  shim; `chelis reef setup` is the orchestrator. Use the
  [`packaging-install` skill](agent-skills/packaging-install/SKILL.md) for any change
  there. One trap it enforces at compile time: `reef setup` subprocesses the real
  `chelisup` binary, never `chelisup::install::install` in-process, because that helper
  copies `current_exe()` over the shim. Design:
  [`spec/design/chelis_packaging_and_install.md`](spec/design/chelis_packaging_and_install.md).
- **Downstream shells** inherit this complete contract through a stamped managed block
  and must satisfy [`spec/design/shell_repo_contract.md`](spec/design/shell_repo_contract.md),
  shipped in the toolchain as `chelis reef conform`. Full inheritance is the default,
  but each shell decides which portions apply. Shell-owned additions stay outside the
  block and should remain when they are relevant and current. To omit an inherited
  section, put its exact ATX heading in a shell-owned span such as
  `<!-- shell-local:exclude:begin -->`,
  `<!-- ### Numeric Surface Discipline -->`, `<!-- shell-local:exclude:end -->`; sync
  removes that heading and its section, while deleting the selector restores it. The
  root `# Chelis Agent Contract` selector omits the entire inherited body.
  Contract changes land here first, editing the doc and the conformance
  `MANIFEST`/`REGISTRY` in lockstep. §7.1 of that doc is the audit a `conform bump` wave
  still owes after the mechanical starter runs.
<!-- END CHELIS MANAGED BLOCK: agents-inheritance -->

<!-- shell-local:exclude:begin -->
<!-- ### Pull Request Lifecycle -->
<!-- ## Spec Authority And Design Discipline -->
<!-- ## Change Hygiene -->
<!-- ## Issue Tracking -->
<!-- ### Python And Scripts -->
<!-- ### Build And Gate Commands -->
<!-- ## The Chelis-Lang Repositories -->
<!-- shell-local:exclude:end -->

The excluded compiler-repository headings and Shoals replacements are recorded
in [`docs/agent-inheritance-exclusions.md`](docs/agent-inheritance-exclusions.md).

- Shoals is a downstream **shell repo** for the
  [Chelis](https://github.com/Chelis-Lang/chelis) language, for quantitative
  finance: pricing, risk, stochastic models, and related numerical methods.
  [`spec/shoals_quant_surface.md`](spec/shoals_quant_surface.md) owns its scope.
- Retained Chelis root `AGENTS.md` sections apply here. The selectors above
  omit compiler-repository mechanics; Shoals's sections below and the
  [shell contract](https://github.com/Chelis-Lang/chelis/blob/main/spec/design/shell_repo_contract.md)
  own its pin, gate, and issue workflow. Chelis numbered specs still govern
  language semantics. For reviewer worktree readiness, use Shoals worktree
  status and process evidence; the inherited `scripts/worktree_status.py`
  example names a Chelis-only helper.

## Toolchain

- `reef.toml` is the source of truth for the chelis / nautilus /
  coral / chelis-std pins and the Shoals package version. The required
  literal compiler workflow pins mirror it and are checked offline.
- The Shoals package `version` track is independent of the compiler
  pin — don't align them.
- Coordinate compiler bumps across shell repos in their own pin PRs;
  do not merge a shell before its compatible published dependencies exist.
- Don't vendor or build the chelis compiler from source. Consume the
  released tarball from the private `Chelis-Lang/chelis` releases.
  CI authenticates via the repo secret `CHELIS_RELEASE_TOKEN`
  (a PAT with `contents: read` on `Chelis-Lang/chelis`). Rotate with
  `gh secret set CHELIS_RELEASE_TOKEN --repo Chelis-Lang/shoals`.
- The local debugging fallback for `chelis test` is `--jobs 1`. Don't
  reintroduce per-file matrix sharding or chelis source checkouts
  in CI unless a documented semantic reason appears.

## Capability Surface

Before designing around a suspected language gap, read
[`docs/CHELIS_SURFACE.md`](docs/CHELIS_SURFACE.md) — the inventory of what
chelis + chelis-std actually provide to the finance domain at the pinned
release, with `@pin` (usable today) / `@upstream` (next bump) markers. The
proof-reachability depth reference is `research/proof-infra/report.md`.

## Upstream Bugs

Tracked upstream chelis issues and capability gaps that affect Shoals live in
[`docs/UPSTREAM_BUGS.md`](docs/UPSTREAM_BUGS.md) (§Actively blocking / §Tracking
/ §Parked / §Archived, with a stated per-section re-probe cadence). File
suspected bugs upstream in `Chelis-Lang/chelis` and cite them as `chelis#NNN`
(own-repo items as `shoals#NNN`) at the narrowing site — **never by a prose
name**, so `scripts/audit_workarounds.py` can find them. Any narrowing (a
`fail(...)` guard the reference accepts, a held-out property, a fixed shape,
a forward-only surface) cites `chelis#NNN` / a draft / a dated deferral slot at
the site; an uncited narrowing is invisible to de-narrowing.

`scripts/audit_workarounds.py` (stdlib-only, per the scripting policy):

- `--pins-only` — offline pin-consistency guard: the `reef.toml` compiler pin
  MUST equal the literal `CHELIS_TAG` / `CHELIS_VERSION` env pins in every
  toolchain-installing workflow (`ci.yml`, `release.yml`, `nightly.yml`). This
  is the blocking `hard-rule-guard` CI job; it never touches the network. The
  literal pins exist so the guard has something to check offline — the
  reef-derived greps can't be evaluated without a checkout.
- full mode (default) — pins check plus a citation-staleness scan: asks GitHub
  whether each cited `chelis#NNN` is resolved and fails if a CLOSED/MERGED
  issue is the **subject** of an active UPSTREAM_BUGS entry. Offline-tolerant
  (skips the upstream check with a warning if `gh` is unavailable; never fails
  closed on the network). Run it at every pin bump, not per-PR.

### Conformance artifacts (contract §5/§6)

`tests_neg/` carries negative-test parity and `tests_blocked/` carries
expected-to-fail upstream-blocker probes. Both run in the local and hosted
gates. A blocked probe passing is FIX-detected: follow its `.expect`
de-narrowing instructions, promote it to a real test, and archive the cited
`docs/UPSTREAM_BUGS.md` entry in the same change set. Prove-verdict capability
gaps such as chelis#637 cannot be represented by `chelis test --expect`; the
canon proof gate re-probes those per surface instead.

## Characterization Contract (producer obligations)

Shoals is a **producer** for the Verified Model Characterization cross-repo
seam. The normative contract is
`c-note/docs/contracts/characterization_contract_v1.md` (frozen, additive-only);
C Note is the consumer. Shoals' local obligations:

- `docs/cnote-import-surface.json` is the invariant-surface manifest
  (`chelis-shell.invariant-surface/1.0`): reference models with kinds/domains,
  and an active invariant set spanning the SMT tiers (`proven` CRR lane, the
  `proven_modulo_contract` composites lane, and the `disproved`
  defective-model break) plus `fuzz_validated` direct-pricer positivity and
  Black-Scholes Greek-sign lanes, and the `defective: true` in-region-break
  model. Every below-proven active
  tier cites a `tier_upgrade_trigger` and
  a `dischargeability_probe`; tiers are grounded in the Phase-0 record
  (`c-note/fixtures/dischargeability/`). Published at release as
  `shoals-<ver>.invariants.json` (byte-identical).
- `scripts/contract_gate.py` (offline: manifest resolvability + pin freshness)
  and `scripts/prove_gate.py` (keystone: expected-tier enforcement against the
  pinned release binary; classifies from `proof_tier`+qualifiers, **never** the
  `composite_verdict` string). From Chelis 0.17.2 onward, direct attribution
  requires an exact linker-owned `dependency_graph` edge by package, module,
  source file, kind, and name. Structural composites require the observed edge
  to `chelis-std:Std.Contracts.normal_cdf` and deliberately do not claim an
  edge to `bs_call_scalar`. Goal-string inspection is only a pre-0.17.2
  compatibility oracle; metamorphic substitution remains the complementary
  semantic anti-vacuity check. Both gates run in CI and the
  local gate. Every active invariant is observed against the release binary.
  At 0.17.5 the direct Black-Scholes and Black-76 call-price positivity family
  and the direct Black-Scholes spot-monotonicity/delta, vega, rho, and gamma
  comparisons complete at `fuzz_validated` with corrupted twins. The Greek
  family runs over three deterministic seeds. Promotion to `proven` remains
  blocked by chelis#637 because free-variable abstraction discards the coupled
  pricing subterms. Shoals#37 adds distinct parametric inverse-CDF and
  historical empirical-quantile VaR/ES families, each covering confidence
  monotonicity, ES dominance, and positivity over 25 accepted samples at seeds
  0, 1, and 2. Shoals#42 adds a separate actual-AD consistency family: seven
  records call the exported first- and second-order Greek vectors and the
  displayed price, with compiler-owned edges from both to their shared price
  body. The 0.24.5 release gate reproduces that evidence against the
  official, sidecar-verified Chelis 0.17.5 / Nautilus 0.7.37 / Coral 0.7.34
  artifacts. The direct intrinsic-bound and inline `grad`-in-property sign
  invariants remain deferred until their own per-surface probes demonstrate a
  stable tier. That unsupported inline-`grad` claim is distinct from the active
  records that call already-exported AD sensitivity functions.
- Additive-only within schema major 1; renames/removals need a major bump and a
  relayed heads-up (the master agent relays between repos; shells never read
  each other's manifest).

## Pin Bump Checklist

A pin bump is a **de-narrowing event**, not a version edit — run all of this in
one change set (contract §7):

1. Update **every** pin location: `reef.toml` `compiler = "=X.Y.Z"` and the
   literal `CHELIS_TAG` / `CHELIS_VERSION` env pair in each toolchain-installing
   workflow. Verify with `python3 scripts/audit_workarounds.py --pins-only`.
   Install via the pinned toolchain (the shared install action reads the pin).
2. Run `chelis test tests_blocked/ --expect blocked`; FIX-detected →
   execute the sidecar de-narrowing instructions and promote the probe;
   DRIFTED → investigate before re-citing.
3. Run `python3 scripts/audit_workarounds.py` (full mode); triage every
   CLOSED/MERGED-but-still-cited subject. No silent carryover.
4. Re-probe every `docs/UPSTREAM_BUGS.md` entry whose trigger names this
   release, **per-surface** — a changelog claim is not a verification. Re-prove
   the reproducer against the pinned binary.
5. Refresh `docs/CHELIS_SURFACE.md`: header versions (pinned / latest upstream /
   last-refreshed) and every `@pin` / `@upstream` marker. When recording a
   sibling's release commit there, **dereference the tag** —
   `gh api repos/OWNER/REPO/git/ref/tags/TAG --jq .object.sha` returns the
   *commit* for a lightweight tag but the *tag object* for an annotated one,
   and the same command has produced both kinds of answer in this ecosystem
   (nautilus `v0.7.42` is lightweight, `v0.7.43` is annotated). A tag object
   recorded as a commit is a real git object that returns HTTP 422 from the
   commits API, so it survives review and fails only for the reader who
   chases it. Use `git rev-parse <tag>^{commit}`, or check `.object.type` and
   dereference via `git/tags/<sha>` when it is `tag`. Record the commit: it is
   what a reader chases and what downstream vendor reconstruction pins.
6. Promote UPSTREAM_BUGS entries per the re-probe verdicts (→ §Archived, or back
   to §Tracking with the residue).
7. Run the local gate before pushing: `python3 scripts/run_local_gate.py`
   (the per-PR CI mirror: pins audit + fmt + lint + `chelis reef build` +
   the `tests_neg/`/`tests_blocked/` expect suites + conform audit +
   contract gate + oracle/release static tests; the origin-relative bump check
   remains CI-only). At a pin bump, run it **once with `--full`** to add the
   nightly stages (fast `tests/` suite, heavy `tests-manual/` suite,
   prove gate, and the chelis#924 cold/warm package-prove latency oracle) —
   day-to-day pushes rely on nightly CI for those. The latency oracle installs
   the just-built Shoals candidate, requires cold <=20s and warm <=5s, and
   requires byte-identical NDJSON from both completed processes.

## Phase Spec

`spec/phase3l.md` records Shoals' local module scope, test plan, and
acceptance oracle from the Phase 3l plan. Read it with the current shell
contract and Chelis language specs. Reconcile it when the upstream plan or
Shoals' accepted scope changes; do not assume the local text is a byte-for-byte
copy of the current monorepo section.

## Shared Local Skills

Shared skills live in `agent-skills/`, materialized from the pinned
toolchain by `chelis reef conform sync` and recorded in `UPSTREAM.toml`.
The eight shared skills are `redteam-exec`, `spec-sync`, `phase-gate`,
`backend-numerics`, `example-corpus`, `cli-surface`, `packaging-install`,
and `issue-resolution`. `.claude/skills` and `.codex/skills` are symlinks
to that directory; both commands directories mirror each other, including
the `red-team` alias wired to `redteam-exec`.

## Scaffolding Drift Rule

All Chelis shell repos share the same scaffolding shape by design. Any
structural change to this repo (layout, CI workflow, agent surface,
reef manifest format) should be mirrored into the other shell repos in
the same change set, or explicitly flagged as a per-repo divergence
with a recorded reason.
