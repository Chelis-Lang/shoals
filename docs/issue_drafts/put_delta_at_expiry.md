# `deltas_put` returns 0.0 at the strike at expiry, where the limit is -0.5

**Filing condition:** file against this repository (shoals) when shoals#101's
call-side fix merges. Not upstream — this is a Shoals defect.

## Problem

`Shoals.Pricing.deltas_put` has the same expiry defect shoals#101 fixed on the
call side, in its silently-wrong form rather than its NaN form. Measured at
chelis 0.18.11, spots `[100, 110, 90]`, `k = 100`, `r = 0.05`, `sigma = 0.2`:

| t | put delta |
|---|---|
| `1e-2` | `[-0.48604, -7.9e-7, -0.99999]` |
| `1e-4` | `[-0.49860, 0.0, -1.0]` |
| **`0`** | **`[0.0, 0.0, -1.0]`** |

At the strike the limit is **-0.5** (approached as `-0.486`, `-0.4986`), and the
function returns `0.0`. Below and above the strike (`-1.0` and `0.0`) are
already correct.

No `NaN` is involved, which is why shoals#101's measurements did not surface it:
the value is finite, plausible and wrong.

## Why it happens

Same mechanism as the call side. At `t = 0` the shoals#88 denominator floor
makes `d1` enormous, and the AD chain through the price body cannot produce the
`t -> 0` limit. `spec/shoals_quant_surface.md` §2.10.1 states the required
behaviour and carries a non-normative parenthetical pointing at this draft.

## Fix

Mirror the call-side treatment in `deltas_put`: branch on `eq(t, 0)` in the
wrapper — outside every `grad` and `vmap`, so no adjoint sees it — and return
the limits via `where`, not an arithmetic select. Put delta at expiry is `-1`
below the strike, `-0.5` at it, `0` above.

`tests/pricing_greeks_expiry.ch` is the place for the coverage, alongside the
call-side cells, including a mutation that proves the strike cell is pinned.

## Scope note

`deltas_put` is the only exported put sensitivity; `vegas_put`, `rhos_put` and
`thetas_put` do not exist on this surface, so no other put cell is affected.
