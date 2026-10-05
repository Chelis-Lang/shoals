---
name: phase-gate
description: Use when deciding whether a Chelis phase is actually complete. Applies the repo’s completion standard, checks manual gates, examples, docs, and phase-specific acceptance criteria before any completion claim.
---

# Phase Gate

Use this skill when a phase is claimed complete or nearly complete.

## Acceptance Oracle

Before judging a phase, identify its single authoritative oracle:

- one command
- one named suite
- or one documented manual validation runner

Treat all other evidence as supporting material, not the completion decision itself.

## Completion Rule

Do not call the phase complete if any of these remain:

- broken default gate
- missing or ambiguous phase oracle
- hidden manual-only acceptance criteria not documented as such
- false-perfect machine-facing reports
- examples/docs whose meaning contradicts the actual implementation
<!-- shell-local:begin -->
<!-- shell-local:exclude:begin -->
<!-- ## Default Gate -->
<!-- ## Additional Required Checks -->
<!-- shell-local:exclude:end -->

## Shoals Default Gate

Run Shoals's own gate with the worktree Python 3.11 environment on PATH:

```sh
PATH="$PWD/.venv/bin:$PATH" python3 scripts/run_local_gate.py
PATH="$PWD/.venv/bin:$PATH" python3 scripts/run_local_gate.py --full
```

The `--full` form adds Shoals's nightly package, manual, proof, latency,
and release checks and is required for a pin bump. Inspect its terminal
verdict, applicable hosted CI on the exact head, and the phase's named
acceptance oracle before a completion claim.
<!-- shell-local:end -->
