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
```

Inspect the lean gate's terminal verdict and applicable fast hosted CI on
the exact head. `--full` opts into long local numerical, proof, benchmark and
runtime book checks; it is not required at pin bumps or before push, merge or
release. A numerical acceptance claim still names its executed oracle and
inputs; an optional check that was not run supplies no new evidence.
<!-- shell-local:end -->
