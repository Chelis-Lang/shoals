# `Nautilus.Special` is f32-only, so an f64 caller cannot reach `erf`/`erfc`

**Filing condition:** file against `Chelis-Lang/nautilus` when someone is in a
position to act on it. Parked rather than filed because the narrowing it
describes is already disclosed downstream and no shoals work is blocked on the
answer.

## The barrier

Every entry point in `Nautilus.Special` is declared at `f32`. A caller on an
`f64` path cannot use them:

```chelis
def probe(x: f64) -> f64 = erf(x)
-- precision mismatch: expected f32, got f64
```

`tests_blocked/special/erf_builtin_absent.ch` in shoals is that probe.

## What it costs downstream

`Shoals.Pricing` needs an `erf` on an `f64` grad path, so it carries `erf64`:
`erf64`, which since this shell's issue 61 evaluates Cody's rational
approximation (~2.7e-16) rather than the byte-identical Abramowitz & Stegun
7.1.26 coefficients it originally copied. Two copies of one approximation in two
repositories, and a third in `Shoals.PricingExtended`, a fourth in
`references/blackscholes.ch`.

The duplication is the cost being reported here. The approximation's ~1.5e-7
bound is a separate matter and is nautilus#56.

## Not nautilus#12

`nautilus#12` is the same shape for `Nautilus.LinAlg` and is sometimes reached
for as though it covered this. It does not: its body is entirely `src/linalg.ch`,
and closing it would give f64 LinAlg while leaving `Nautilus.Special` f32-only.
A shoals revision cited `nautilus#12` here and thereby wrote a de-narrowing
instruction that could never execute.

## Relationship to chelis#902

`chelis#902` would give the language a canonical `erf`/`erfc`/`norm_cdf`/
`norm_ppf` surface with a stated accuracy. That supersedes this: a shell would
call the language's `erf` and neither the signature barrier nor the duplicated
coefficients would remain. This issue is worth filing anyway, because it is
cheap to fix independently and chelis#902 is a spec-gap requiring normative
atoms before any implementation.

## Suggested direction

Widen `Nautilus.Special` to the float dtypes its callers use, or make the
entry points dtype-polymorphic if the module's conventions allow it. Widening
the signature does not change what the approximation computes; a caller
gaining `f64` access to these coefficients gets `f64` arithmetic over an
approximation still bounded at ~1.5e-7, which is nautilus#56's subject and
should not be conflated with this.
