# Shoals AGENTS inheritance exclusions

Shoals inherits the complete pinned Chelis root agent contract except for
the exact headings selected outside the managed block in `AGENTS.md`.
These exclusions remove instructions that require the *compiler repository's*
files or issue queue. The Chelis language principles, quality standards,
red-team protocol, worktree rules, source style, and shared-skill pointers
remain inherited through filtered sections and toolchain-supported
shell-local skill blocks.

| Excluded root heading | Shoals guidance |
| --- | --- |
| `### Red Team Rounds` | Its worktree-status command exists only in Chelis. `AGENTS.md` §Shoals Review And Source and the `redteam-exec` shell-local block retain the review loop with an executable Shoals handoff. |
| `### Pull Request Lifecycle` | Chelis's `scripts/gate.py`, package-expansion dispatch, acknowledgements, and base-retarget workflows are compiler PR mechanics. Shoals `AGENTS.md` §Pin Bump Checklist and `scripts/run_local_gate.py` own its gate. |
| `## Spec Authority And Design Discipline` | Its numbered-chapter and numeric-census edit workflow belongs to compiler authors. `spec/shoals_quant_surface.md` owns Shoals library scope; Chelis numbered specs still control language semantics. |
| `## Change Hygiene` | Its release-assembly command, compiler CLI tests, and manual-gate document are monorepo-specific. Shoals keeps its own changelog, invariant, manual-test, and release checks. |
| `## Issue Tracking` | Chelis's labels and launch queue do not describe Shoals issues. Shoals `AGENTS.md` §Upstream Bugs and `docs/UPSTREAM_BUGS.md` own local triage and upstream citations. |
| `### Python And Scripts` | Its `.venv` invocation rule, sole permitted shell script, and CI planner apply to Chelis. The shell contract's uv rule and Shoals's own script entrypoints govern here. |
| `### Build And Gate Commands` | Chelis's Cargo, HIP, and `scripts/gate.py` commands do not gate this shell. Shoals `AGENTS.md` §Pin Bump Checklist and `scripts/run_local_gate.py` do. |
| `## Writing Chelis Source` | Its compiler-local spec path is absent here. `AGENTS.md` §Shoals Review And Source and the `example-corpus` shell-local block identify the applicable Surf checks and compiler spec authority. |
| `## The Chelis-Lang Repositories` | Its “This repository” identity means Chelis, so retaining it here would misidentify Shoals. Shoals `AGENTS.md` §Repo Identity states its role. |

The `redteam-exec`, `phase-gate`, and `spec-sync` skill blocks replace
compiler-only worktree and gate commands with Shoals commands. The
`example-corpus` block scopes its numbered-spec paths to the compiler
repository. `chelis reef conform sync` preserves these blocks and filters
their declared inherited sections; `conform audit` checks the result.
