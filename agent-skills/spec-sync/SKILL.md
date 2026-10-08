---
name: spec-sync
description: Use when changing Chelis language behavior, CLI behavior, or compiler semantics. Keeps code, tests, examples, and active specs in sync in one change set.
---

# Spec Sync

Use this skill whenever a change affects public language/compiler behavior.

## Required Sync Surfaces

- owning implementation files
- unit/integration/e2e tests
- executable examples in `examples/`
- active specs in `spec/`
- current-state docs such as `README.md` and the canonical reference when needed

## Repository Rules

- Prefer updating the owning active doc over adding new explanation docs.
- Do not treat `spec/design/archive/` as current guidance.
- If the change invalidates an example, either rewrite it to remain executable or move it
  to `examples/illustrative/`.
- If the change affects a completion claim, update the phase oracle docs and any current
  phase-status summary in the same change set.
<!-- shell-local:begin -->
<!-- shell-local:exclude:begin -->
<!-- ## Verification -->
<!-- shell-local:exclude:end -->

## Shoals Verification

After source and contract edits, run Shoals's gate with the worktree Python
3.11 environment on PATH:

```sh
PATH="$PWD/.venv/bin:$PATH" python3 scripts/run_local_gate.py
```

Require applicable fast hosted checks on the exact pushed head. `--full`
explicitly opts into long local numerical, proof, benchmark and runtime book
checks; it is not required at pin bumps or before push, merge or release.
Report numerical evidence only for the exact commands and inputs executed.
<!-- shell-local:end -->
