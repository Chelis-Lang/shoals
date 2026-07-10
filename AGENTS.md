# Shoals Agent Contract

Canonical agent instructions for this repository. `CLAUDE.md` is a symlink
to this file so Claude-style and Codex-style entry points do not drift.

## Repo Identity

- Shoals is a downstream **shell repo** for the
  [Chelis](https://github.com/Chelis-Lang/chelis) language, scoped to
  numerical methods, statistics, and optimization.
- Upstream of truth: `Chelis-Lang/chelis`. The Chelis monorepo's
  `AGENTS.md` rules apply here **verbatim** unless explicitly overridden
  below. That contract covers spec-first development, negative-test
  parity, red-team protocol, documentation hierarchy, example-corpus
  policy, scripting-language policy (Python, never shell), and the
  shared local skill set.

## Toolchain

- `reef.toml` is the source of truth for the chelis / nautilus /
  coral / chelis-std pins and the Shoals package version. Don't
  duplicate any of those numbers anywhere else; tooling and CI read
  them from `reef.toml` directly.
- The Shoals package `version` track is independent of the compiler
  pin — don't align them.
- Compiler bumps must land in every Chelis shell repo in the same
  change set; don't bump unilaterally.
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

### Deferred conformance artifacts (contract §5/§6)

`tests_neg/` (negative-test parity) and `tests_blocked/` (expected-to-fail
upstream-blocker probes) with their runners are **deferred** for Shoals as of
2026-07-10. Trigger to land them: the **first shoals-side negative fixture or
mechanically-expressible blocked probe** (e.g. a shoals property that hits the
chelis#434 transcendental boundary or the depth-3 inlining cap in a way the
harness can express as a pinned-diagnostic reproducer). Until then the
UPSTREAM_BUGS entries are re-probed manually at each bump. Recorded on shoals#4.

## Characterization Contract (producer obligations)

Shoals is a **producer** for the Verified Model Characterization cross-repo
seam. The normative contract is
`c-note/docs/contracts/characterization_contract_v1.md` (frozen, additive-only);
C Note is the consumer. Shoals' local obligations:

- `docs/cnote-import-surface.json` is the invariant-surface manifest
  (`chelis-shell.invariant-surface/1.0`): reference models with kinds/domains,
  and invariants across three honest tiers (`proven` CRR lane, the
  `proven_modulo_contract` composites lane, the `fuzz_validated` direct-pricer
  lane) plus the `defective: true` in-region-break model. Every below-proven
  tier cites a `tier_upgrade_trigger` and a `dischargeability_probe`; tiers are
  grounded in the Phase-0 record (`c-note/fixtures/dischargeability/`). Published
  at release as `shoals-<ver>.invariants.json` (byte-identical).
- `scripts/contract_gate.py` (offline: manifest resolvability + pin freshness)
  and `scripts/prove_gate.py` (keystone: expected-tier enforcement against the
  pinned release binary; classifies from `proof_tier`+qualifiers, **never** the
  `composite_verdict` string; anti-vacuity via the prover goal string because
  `dependency_edges` do not cross import boundaries). Both run in CI and the
  local gate. The active canon is entirely SMT-tier (proven /
  proven_modulo_contract / disproved), every invariant observed to pass against
  the release binary. The direct-pricer positivity invariant is
  **deferred** (`deferred_invariants`, no expected tier): not characterizable at
  0.14.0 on either lane -- the proven lane is blocked by chelis#637 (free-variable
  abstraction discards the N(d1)/N(d2) coupling; chelis#434's envelope does not
  fix this), and the fuzz lane is intractable (one fuzz sample of one positivity
  property did not complete in 200s; `docs/issue_drafts/fuzz_sampler_transcendental_cost.md`,
  p08). It re-enters `invariants` only when a run demonstrates a tier (prove_gate
  carries the dormant fuzz machinery for that day).
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
2. Run the blocked-probe suite once it exists (deferred today); FIX-detected →
   execute the sidecar de-narrowing instructions and promote the probe;
   DRIFTED → investigate before re-citing.
3. Run `python3 scripts/audit_workarounds.py` (full mode); triage every
   CLOSED/MERGED-but-still-cited subject. No silent carryover.
4. Re-probe every `docs/UPSTREAM_BUGS.md` entry whose trigger names this
   release, **per-surface** — a changelog claim is not a verification. Re-prove
   the reproducer against the pinned binary.
5. Refresh `docs/CHELIS_SURFACE.md`: header versions (pinned / latest upstream /
   last-refreshed) and every `@pin` / `@upstream` marker.
6. Promote UPSTREAM_BUGS entries per the re-probe verdicts (→ §Archived, or back
   to §Tracking with the residue).
7. Run the complete local gate before pushing: `python3
   scripts/run_local_gate.py` (fmt + lint + `chelis reef build` + the fast
   `tests/` suite + the heavy `tests-manual/` suite) and
   `python3 scripts/audit_workarounds.py --pins-only`.

## Phase Spec

The owning spec section for this shell is checked in at
`spec/phase3l.md`, extracted verbatim from the Chelis monorepo's
`spec/design/chelis_phase3_plan.md` §3l. That file is the source of
truth for module scope, test plan, and acceptance oracle. Update this
repo's copy in the same change set as any monorepo-side changes to
the original section.

## Shared Local Skills

Project-local skills live in `agent-skills/`. `.claude/skills` and
`.codex/skills` are symlinks to that directory so both tool surfaces
load the same skill library. `.claude/commands/` and `.codex/commands/`
mirror each other. The shared skill set (`redteam-exec`, `spec-sync`,
`phase-gate`, `backend-numerics`, `example-corpus`, `cli-surface`) and
the `red-team` alias wired to `redteam-exec` are copied from the
monorepo and should stay behaviorally aligned with it. If a skill
diverges upstream, update this repo in the same change set.

## Scaffolding Drift Rule

All Chelis shell repos share the same scaffolding shape by design. Any
structural change to this repo (layout, CI workflow, agent surface,
reef manifest format) should be mirrored into the other shell repos in
the same change set, or explicitly flagged as a per-repo divergence
with a recorded reason.
