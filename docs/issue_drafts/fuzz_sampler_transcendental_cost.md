# Draft: `prove --tier fuzz-only` is intractable over an f64 transcendental body (one sample does not complete in 200s)

**Filing condition:** file against `Chelis-Lang/chelis` if the fuzz-lane cost is
not already tracked upstream, OR fold into an existing prove-performance issue.
Related upstream evidence: c-note `docs/issue_drafts/reef_package_prove_load_time.md`.

## Summary

Fuzz-tier proving of a property whose goal calls a real transcendental pricing
body (Black-Scholes / Black-76, i.e. an f64 `erf`/`exp`/`log`/`sqrt` chain) does
not complete within any usable budget on the released 0.14.0 binary. A single
accepted fuzz sample of a single positivity property does not finish in 200s.
This makes the honest `fuzz_validated` lane for real transcendental pricers
un-gateable (Shoals defers those invariants; see
`docs/cnote-import-surface.json` `deferred_invariants`).

## Measurements (pinned 0.14.0 release binary, `--tier fuzz-only`)

- `properties/canonpricing.ch` (4 properties: bs/b76 positivity + corrupted
  twins), `--samples 5 --seed 0`: killed at **20 min** having emitted **zero**
  property verdicts.
- A single isolated `bs_call_scalar(...) >= 0.0` positivity property,
  `--samples 1 --seed 0`: killed at **200s** having emitted **zero** verdicts.

`--tier auto` is worse: it attempts an unbounded SMT lowering first (no
`--smt-timeout` applies to the auto escalation) before degrading to fuzz.

## Reproducer

```chelis
module M
import Shoals.Pricing (bs_call_scalar)
@property pos forall(s: f32, k: f32, r: f32, sigma: f32, t: f32)
  where (s > 0.0), (k > 0.0), (sigma > 0.0), (t > 0.0), (r >= 0.0):
  (bs_call_scalar(s, k, r, sigma, t) >= 0.0)
```

`chelis prove M.ch --json --tier fuzz-only --samples 1 --seed 0` (in a package
that exports `bs_call_scalar`) does not complete in 200s.

## Impact / ask

Each accepted fuzz sample evaluates the full interpreted f64 `erf`/`exp`/`log`/
`sqrt` chain; the per-sample cost (plus rejection sampling over the guard box)
makes the fuzz tier unusable for realistic transcendental finance bodies. A
compiled/JIT eval path for the fuzz sampler, or a cheaper sampling/rejection
strategy, would restore the honest fuzz lane. Note this is orthogonal to
chelis#637 (the *proven*-lane ceiling: free-variable abstraction cannot express
the N(d1)/N(d2) coupling) — even a fast fuzz lane only yields `fuzz_validated`,
not a proof.
