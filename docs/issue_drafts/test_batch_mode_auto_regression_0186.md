# `chelis test --batch-mode auto` regressed 2.6x on a 43-file suite at 0.18.6

**Filing condition:** file against `Chelis-Lang/chelis` with the measurements
below. Replace this path with the assigned `chelis#NNN` at every site that cites
it.

**Area:** `area:perf`, `area:cli`
**Introduced in:** 0.18.6 (regression against 0.18.5)
**Impact:** `Chelis-Lang/shoals`' nightly `chelis test tests/` step is budgeted
`--suite-timeout 1500` under `timeout-minutes: 30`; the local wall for that
command went from 3m01s to 7m54s, so the hosted budget is now at risk.

## Measurement

Same 43 files, same 371 tests, same machine (10-core Apple silicon, quiet:
load average 3.0, no other build or test process running), caches warm on both
sides (each figure reproduced; the 0.18.6 `auto` figure is stable at
7m51s-7m55s across four runs). Shoals `tests/` at its 0.18.5 tree under the
0.18.5 toolchain, and at its 0.18.6 tree under the sidecar-verified 0.18.6
release toolchain (payload
`1c88c737d7d3740eb4adbe7b50ea31d29ee64498b9d74b35664255ca16aea8d4`).

Command: `chelis test tests/ --timeout 1200 --suite-timeout 1500 --jobs auto`,
with `--batch-mode` as shown.

| `--batch-mode` | 0.18.5 real | 0.18.5 user | 0.18.6 real | 0.18.6 user |
|---|---|---|---|---|
| `auto` (default) | 3m01s | 4m27s | **7m54s** | **9m37s** |
| `file` | 1m56s | 15m16s | 3m44s | 20m41s |

Two things stand out:

1. **The optimization now costs more than it saves.** `--batch-mode file` is
   more than twice as fast as `--batch-mode auto` at 0.18.6 (3m44s vs 7m54s).
   At 0.18.5 the ordering was the intended one for CPU (`auto` burns 4m27s of
   CPU where `file` burns 15m16s).
2. **It is real compute, not I/O.** `auto`'s user time rises 4m27s -> 9m37s,
   2.2x, on a single-threaded batch worker.

This is not a general front-end slowdown; the opposite is true at file scale.
On the identical corpus and machine, single-module `chelis check` improved about
2x at 0.18.6 (`src/modelfit.ch` 67.6s -> 31.6s, the 3-line `src/core.ch`
dependency-load floor 31.2s -> 17.0s), and sequential single-file `chelis test`
of six individual files came out within noise of 0.18.5. The regression appears
only when ~36 files are merged into one batched compilation unit.

## What likely changed

chelis#1261 rebuilt batch admission around a shared `BatchScope`. With
`CHELIS_TEST_EXPLAIN_BATCHING=1`, 7 of the 43 files demote at 0.18.6, all on
declared-vs-declared collisions over two local test helpers (`abs_f32`,
`to01`). So the 0.18.6 batch is at most the same size as 0.18.5's and probably
smaller, yet takes about 2.6x as long — the per-unit cost went up rather than
the unit count.

Worth checking against chelis#1207 / chelis#1316 / chelis#1205: those three made
independent-binding scaling, SCC planning, and nested lowering linear at file
scale, and this is the same work at a much larger unit size.

## Not reproduced upstream

This was measured downstream on a real shell suite, not reduced to a minimal
in-repo case. A synthetic N-file batch sweep is the obvious next step and is not
done here.
