# Chelis 0.18.6 upstream status record

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

