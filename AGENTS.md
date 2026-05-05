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

## Toolchain Pin

- `chelis v0.5.0` is the single supported compiler binary. `reef.toml`
  pins `compiler = "=0.5.0"`. Version bumps must land in every Chelis
  shell repo in the same change set — do not bump unilaterally.
- Do not vendor or build the Chelis compiler from source inside this
  repo. Consume the released tarball from the private
  `Chelis-Lang/chelis` releases. CI authenticates via the repo secret
  `CHELIS_RELEASE_TOKEN`, which must hold a PAT with `contents: read`
  on `Chelis-Lang/chelis`. Rotate with
  `gh secret set CHELIS_RELEASE_TOKEN --repo Chelis-Lang/shoals`.

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
