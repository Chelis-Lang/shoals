# Tier-B SMT lowering inlines nested function calls only to `MAX_INLINE_DEPTH = 3`

**UNFILED** (a documented capacity limit, not yet a bug). Filing condition: a
Shoals `properties/` goal is authored that needs a call chain deeper than three
inlinings and consequently routes to Tier C instead of lowering to Tier B. Until
then this is a tracked constraint, cited from `docs/UPSTREAM_BUGS.md` §Tracking
by this draft path (contract §4). When filed, replace this path with the
assigned `chelis#NNN`. The c-note-side probe `p07` is expected to pin the exact
behavior upstream.

## Summary

The Tier-B lowerer inlines nested function calls only to a fixed depth,
`MAX_INLINE_DEPTH = 3` (`crates/chelis-prove/src/tier_b_lower.rs`, enforced in
the inliner's recursion guard; present at v0.14.0 and unchanged through the
pinned release). A proof goal whose discharge requires a call chain deeper than
three inlinings does not lower to Tier B; it routes to Tier C instead.

## Impact on Shoals

No Shoals property hits this today — the `properties/composites.ch` structural
goals inline one level. The cap is recorded as a forward-looking constraint so
that, if a deeper-inlining property is later authored, the de-narrowing trigger
is already documented rather than discovered by surprise. It gates nothing on
the current surface.

## Reproducer (shape)

A property goal that applies `f3` where `f3` calls `f2` calls `f1` calls `f0`
(four levels of nested user-function application at the goal site) is expected to
route to Tier C rather than lower to Tier B, whereas an otherwise-identical
three-level chain lowers. A minimal witness has not been authored (no Shoals
surface needs it yet); pinning that behavior upstream is the c-note `p07` probe's
job.

## Ask

Either raise or make configurable the `MAX_INLINE_DEPTH` bound, or document it as
an intentional Tier-B capacity limit with a clean Tier-C fallback diagnostic, so
a downstream author can distinguish a depth-cap route from an
unsupported-construct route.

## Re-probe trigger

`p07` landing, or any chelis release note touching Tier-B inlining depth.
