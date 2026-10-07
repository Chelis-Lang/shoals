# Shoals Agent Contract

Canonical agent instructions for this repository. `CLAUDE.md` is a symlink
to this file so Claude-style and Codex-style entry points do not drift.

## Repo Identity

<!-- BEGIN CHELIS MANAGED BLOCK: agents-inheritance chelis@0.19.1 (sha256:577cc2c2f590f4d1) -->
# Chelis Agent Contract

Keep this file concise and relevant to every agent working in this repository.
Each added token is read tens of thousands of times. State a rule once, link the
document that owns the detail, and put the explanation in that document, not here.

`CLAUDE.md` is a symlink to this file so Claude-style and Codex-style entry points do
not drift.

## What Chelis Is

Chelis is a numerical computing language for code that agents write and people
supervise. Tensors carry named dimensions and precision in their type; the compiler
checks shapes, precision, effects, and ownership before anything runs, and `chelis
prove` checks the properties an author states, naming the method behind each result.
The bet is that numerical code an agent can reason about, and a person can review
through its types and properties, beats code whose mistakes first surface at run time.
Chelis is general purpose within numerical computing; the worked examples come from
quantitative finance. Differentiation and machine-learning programs are research
directions, not the definition of the language. It is not a systems language, a web
framework, a deep-learning framework, or a general scripting replacement for Python.
`spec/00-context.md` and `spec/design/chelis_canonical_reference.md` own the full
statement; their specifics may lag, their intent does not. When a tradeoff
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

[`docs/investigations/agent_contract_rationale.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.1/docs/investigations/agent_contract_rationale.md)
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
- Every follow-up message to a running subagent, and every message to a peer session,
  ends by asking the recipient to acknowledge it and confirm what it will do. No
  acknowledgement by the recipient's next reply means the message was not received:
  resend it, consolidated.
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

## Pointers

- **Shared skills** live in `agent-skills/`; `.claude/skills` and `.codex/skills` are
  symlinks to that one authored tree, `.claude/commands/` and `.codex/commands/` stay byte-identical, and the
  `red-team` alias is wired to `redteam-exec` with its fresh-round and verify modes. The
  set: `redteam-exec`, `spec-sync`, `phase-gate`, `backend-numerics`, `example-corpus`,
  `cli-surface`, `packaging-install`, `issue-resolution`. Shells also receive
  `chelis-std`, the downstream-authoring skill authored at
  `packages/chelis-std/SKILL.md`.
- **Toolchain and packaging.** `chelisup` is the installer and pin-resolving `chelis`
  shim; `chelis reef setup` is the orchestrator. Use the
  [`packaging-install` skill](agent-skills/packaging-install/SKILL.md) for any change
  there. One trap it enforces at compile time: `reef setup` subprocesses the real
  `chelisup` binary, never `chelisup::install::install` in-process, because that helper
  copies `current_exe()` over the shim. Design:
  [`spec/design/chelis_packaging_and_install.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.1/spec/design/chelis_packaging_and_install.md).
- **Downstream shells** inherit this complete contract through a stamped managed block
  and must satisfy [`spec/design/shell_repo_contract.md`](https://github.com/Chelis-Lang/chelis/blob/v0.19.1/spec/design/shell_repo_contract.md),
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
<!-- ### Red Team Rounds -->
<!-- ### Pull Request Lifecycle -->
<!-- ## Spec Authority And Design Discipline -->
<!-- ## Change Hygiene -->
<!-- ## Issue Tracking -->
<!-- ### Python And Scripts -->
<!-- ### Build And Gate Commands -->
<!-- ## Writing Chelis Source -->
<!-- ## The Chelis-Lang Repositories -->
<!-- shell-local:exclude:end -->

- Shoals is a downstream **shell repo** for the
  [Chelis](https://github.com/Chelis-Lang/chelis) language, for quantitative
  finance: pricing, risk, stochastic models, and related numerical methods.
  [`spec/shoals_quant_surface.md`](spec/shoals_quant_surface.md) owns its scope.
- Retained Chelis root `AGENTS.md` sections apply here. The selectors above
  omit compiler-repository mechanics; Shoals's sections below and the
  [shell contract](https://github.com/Chelis-Lang/chelis/blob/main/spec/design/shell_repo_contract.md)
  own its pin, gate, and issue workflow. Chelis numbered specs still govern
  language semantics.

## Shoals Review And Source

- A pull request gets a red-team round before merge. Keep the reporting reviewer
  through local repair verification, and leave repairs unpushed until that
  reviewer is satisfied. The retained `redteam-exec` skill supplies the round
  protocol; its shell-local block supplies Shoals's worktree handoff.
- Before handing over a worktree, record `git rev-parse HEAD` and
  `git status --porcelain --untracked-files=all` there. Resolve the worktree
  and any shared target to physical absolute paths with `realpath`, then scan
  every open handle under each with `lsof -nP -x f +D <absolute-path>`.
  Inspect stdout, stderr, and exit status, including exit 1; a holder,
  unresolved path, or uncertain scan means busy. The
  `redteam-exec` shell-local handoff section owns the full procedure.
- Load the retained `example-corpus` skill before writing any `.ch` source.
  Follow the pinned compiler's `chelis fmt --check` and `chelis lint --check`
  and Shoals's executable tests. Chelis language rules live in the compiler
  repository; Shoals's library scope lives in `spec/shoals_quant_surface.md`.
  The skill's shell-local block identifies its compiler-only path references.

## Toolchain

- `reef.toml` is the source of truth for the chelis / nautilus /
  coral / shoreleave / chelis-std pins and the Shoals package version. The required
  literal compiler workflow pins mirror it and are checked offline.
- The Shoals package `version` track is independent of the compiler
  pin — don't align them.
- Coordinate compiler bumps across shell repos in their own pin PRs;
  do not merge a shell before its compatible published dependencies exist.
- Don't vendor or build the Chelis compiler from source. Consume its
  published release tarball. CI uses the toolchain install action.
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
  a `dischargeability_probe`; these expectations are grounded in
  `c-note/fixtures/dischargeability/`. Published at release as
  `shoals-<ver>.invariants.json` (byte-identical).
- `scripts/contract_gate.py` (offline: manifest resolvability + pin freshness)
  and `scripts/prove_gate.py` (keystone: expected-tier enforcement against the
  pinned release binary; classifies from `proof_tier`+qualifiers, **never** the
  `composite_verdict` string). Direct attribution
  requires an exact linker-owned `dependency_graph` edge by package, module,
  source file, kind, and name. Structural composites require the observed edge
  to `chelis-std:Std.Contracts.normal_cdf` and deliberately do not claim an
  edge to `bs_call_scalar`. Metamorphic substitution is the complementary
  semantic anti-vacuity check. Both gates run in CI and the
  local gate. Every active invariant is observed against the release binary.
  The direct Black-Scholes and Black-76 call-price positivity family and the
  direct Black-Scholes spot-monotonicity/delta, vega, rho, and gamma comparisons
  run at `fuzz_validated` with corrupted twins. The Greek family uses three
  deterministic seeds. Promotion to `proven` remains blocked by chelis#637
  because free-variable abstraction discards the coupled pricing subterms.
  Shoals#37 supplies distinct parametric inverse-CDF and historical
  empirical-quantile VaR/ES families, each covering confidence monotonicity,
  ES dominance, and positivity over 25 accepted samples at seeds 0, 1, and 2.
  Shoals#42 supplies a separate actual-AD consistency family: seven records
  call the exported first- and second-order Greek vectors and the displayed
  price, with compiler-owned edges from both to their shared price body. The
  direct intrinsic-bound and inline `grad`-in-property sign
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
   The README reads versions from `reef.toml`; review its prose for stale
   release claims, without adding a second version list.
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
   contract gate + oracle/release static tests + the offline accuracy-floor
   transcription check; the origin-relative bump check
   remains CI-only). At a pin bump, run it **once with `--full`** to add the
   nightly stages (fast `tests/` suite, heavy `tests-manual/` suite,
   prove gate, the accuracy-floor measurement leg, the AD-Greeks oracle, and
   the chelis#924 cold/warm package-prove latency oracle) —
   day-to-day pushes rely on nightly CI for those. The latency oracle installs
   the just-built Shoals candidate, requires cold <=20s and warm <=5s, and
   requires byte-identical NDJSON from both completed processes.

   `--full` needs the oracle reference dependency once per environment. The
   accuracy-floor measurement leg **fails** rather than skips without it
   (shoals#64), so an absent mpmath cannot be mistaken for a pass.

   **Install it into a virtualenv, not the system Python.** A bare
   `python3 -m pip install` exits with `error: externally-managed-environment`
   on a Homebrew or Debian/Ubuntu interpreter (PEP 668), which is most
   workstations:

   ```sh
   uv venv --python 3.11
   uv pip install -r scripts/requirements-oracle.txt
   .venv/bin/python scripts/run_local_gate.py --full
   ```

   Run `run_local_gate.py --full` through that interpreter, because its
   measurement stage invokes `python3` and a bare `python3` will not see the
   venv. CI installs to the runner's Python instead, which works because the
   GitHub `ubuntu-latest` image ships `/etc/pip.conf` with
   `break-system-packages = true`.

   **A pin bump is exactly when the measurement leg matters.** It evaluates the
   compiled kernel through `chelis eval --json`. An unrecognised
   `schema_version` fails loudly and names the decoder to teach.

## Quant Scope

`spec/phase3l.md` records Shoals' local module scope, test plan, and
acceptance oracle. Read it with the current shell
contract and Chelis language specs. Reconcile it when the upstream plan or
Shoals' accepted scope changes; do not assume the local text is a byte-for-byte
copy of the current monorepo section.

## Shared Local Skills

Shared skills live in `agent-skills/`, materialized from the pinned
toolchain by `chelis reef conform sync` and recorded in `UPSTREAM.toml`.
The nine shared skills are `redteam-exec`, `spec-sync`, `phase-gate`,
`backend-numerics`, `example-corpus`, `cli-surface`, `packaging-install`,
`issue-resolution`, and `chelis-std`. `.claude/skills` and `.codex/skills` are symlinks
to that directory; both commands directories mirror each other, including
the `red-team` alias wired to `redteam-exec`.

## Scaffolding Drift Rule

All Chelis shell repos share the same scaffolding shape by design. Any
structural change to this repo (layout, CI workflow, agent surface,
reef manifest format) should be mirrored into the other shell repos in
the same change set, or explicitly flagged as a per-repo divergence
with a recorded reason.

## Book

`docs/book/` is the user-facing book for this shell. chelis.ch mirrors it
page for page (https://chelis.ch/docs/shoals/), and the chelis.ch text is
canonical: book pages are rendered from the site by the website's
`scripts/sync_books.py`, so edit prose on the site and re-render, or make the
same edit in both places in the same change.

The reader is an engineer, or an AI coding agent, writing Chelis code against
this shell. They know the domain but not this repo's internals or history, and
they want to call the API correctly the first time. Every page teaches: what the
API does, a runnable example with its real output, the contract (inputs, domain,
shapes, precision, errors) and the pitfalls.

Never in the book: issue or PR numbers, repo-internal paths (`spec/`, `src/`
internals, `scripts/`, `tests/`, maintainer docs), maintainer or CI commands,
contributor history, process talk (gates, red teams, agent instructions),
status words (planned, not yet, stub, phase, milestone), "see the source" in
place of documentation, em-dashes, and the word "load-bearing".
`scripts/check_book.py` enforces the mechanical part in CI.

A change that alters user-visible behavior says so in its changelog entry.
The book documents the latest release: the chelis.ch page and this book take
the change when that release is documented.
