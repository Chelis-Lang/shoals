# Chelis 0.18.12 pin: published chain and proof recapture

Shoals 0.24.14 candidate PR #95 remains a draft. Its compiler pin is
`=0.18.12`; the published Nautilus 0.7.47 and Coral 0.7.44 archives declare
that compiler pin, and Coral declares Nautilus 0.7.47. The official package
chain builds. The released compiler initially rejected Shoals's nested
second-order gradients (chelis#2825). Sequential conditional spelling in the
same scalar pricing kernel restores those exports: the Greek oracle and all
37 raw proof controls pass. Full release acceptance is pending.

Nautilus's published `v0.7.47` tag dereferences to commit
`76a66ae921cafeef538e1ff48ea53fdc253c1724`. Its downloaded CHB
`cd5c04ecfcd2445b7f7a7e0a997d721f20c85aac4524ae626571c3db96008603`
and archive
`dfe18e834c2d6e49282afd682e0452e51575c3d1dcefd4db3267098e98bba716`
matched both SHA-256 sidecar lines. The archived `reef.toml` and `reef.lock`
identify Nautilus 0.7.47, chelis-std 0.4.0, and compiler 0.18.12.
Comparing release archives 0.7.46 and 0.7.47 found no exported-name change
across the 25 source modules. The sampling exports in
`Nautilus.Distributions` now take a first `key`, matching Shoals's explicit
key calls. `Nautilus.Special.erf` is now generic over `Float`, and an isolated
package with the released Nautilus artifact and bundled chelis-std checked
the old f64 signature probe cleanly and passed
`tests/nautilus_erf_f64.ch`. The unimported canonical `erf` remains absent,
as `tests_blocked/special/canonical_erf_absent.ch` confirmed in that package.
The generated f32 mirror from `scripts/oracle_greeks_gate.py` passed all 19
published-kernel points in both that isolated package and the complete Shoals
package, covering both signs and both sides of the Taylor/A&S boundary.
Nautilus's f64 A&S approximation remains less accurate than Shoals's Cody
kernel; nautilus#74 tracks it, and Shoals retains the kernel.

Coral `v0.7.44` resolves to commit
`63d24a26d40f4f5f1718aa6f48982d0e63291cd2`. Its published CHB SHA-256 is
`5e69584d3e967aef72c6ae18b0204b00b155804876ece8d7feda604c6c0263b3`;
its archive SHA-256 is
`7cc0ed3ede5ab754615465704ec0f9bd01bb7ccabba10cb50770c6c78c3e3ba5`.
The downloaded assets matched the sidecar, and `reef verify-artifact` passed.
The installed Nautilus and Coral files in Shoals's isolated Reef registry
match all four published hashes. `chelis +0.18.12 reef build --no-auto-fetch`
builds Shoals 0.24.14. A fresh lowercase-coordinate registry and
`scripts/build_release_assets.py` produce a lock with canonical
`github://chelis-lang/...` origins and those same hashes. The post-repair
cross-registry release check produces byte-identical lock, CHB, and archive
payloads from a mixed-case-preseeded and a clean registry: SHA-256
`718429b9e0d26d2f36f186a3f7debf969a26f3af3dff3b4e34c4590247004c2c`,
`e7c3d5bd0baa5e760194fd064ebab12e45d6bfe3722e11f46f1905ae92545e60`,
and `14cce490643424e96cfc017f71436adec43833c49b856e7626476aeac3d524a8`,
respectively. These Shoals bytes are local candidates, not published assets.
A plain lowercase reinstall into a registry first populated with mixed-case
coordinates leaves mixed-case origins. The release builder instead uses a
fresh registry, discards the stale generated lock, and requires canonical
origins (chelis#1002). The two-registry determinism oracle tests that path.

The official Chelis tag resolves to
`c81d8188de6ebad032c1bb1c0a427eb0408feee3`; release workflow
`36769966221` completed successfully. The downloaded Darwin archive matched
its published SHA-256 sidecar at
`8cdcbf598c3f04e37a9a211e7abaa67fbaf6d4c135a34f00c1944b1e43b8e90d`.
Its extracted `bin/chelis` SHA-256 was
`b0df096e2b43eb28d4a40138fdcc2f8807d39bffeab5b2145e639f5b9d4d3351`,
byte-identical to the installed `chelis +0.18.12` binary.

`chelis +0.18.12 reef conform bump 0.18.12` updated the compiler pin,
workflow mirrors, and managed content. Its final package-resolution step
failed on the old Coral compiler pin. A subsequent `reef conform sync`
completed. The offline `reef conform audit` and origin-relative `bump-check`
passed. The root `AGENTS.md` block is generated from the tagged canonical
contract using seven documented heading exclusions in
[`agent-inheritance-exclusions.md`](agent-inheritance-exclusions.md); eight
shared skills are recorded in `agent-skills/UPSTREAM.toml`.

Standalone compiler probes with the released binary:

- Reusing a consumed key is rejected with `KeyReuse`. This establishes the
  checker rule independently of Shoals package resolution; the PR's
  `tests_neg/stochastic/` fixture still needs its in-package run.
- A self-contained depth-3 proof passes in the SMT lane; a depth-4 proof
  reports unsupported, consistent with the open chelis#846 cap. It does not
  establish Shoals' proof tiers.
- Imported `Std.Scalar.min/max` in a minimal package using the bundled
  chelis-std produced the same `vmap` output in Eval and compiled C. This
  supports the chelis#1582 closure on that shape; it does not justify changing
  the Shoals pricing kernel yet.
- A corrected standalone `vmap`/`if` example selected a finite result in
  Eval and C although the discarded series evaluated directly to `-inf`.
  This example does not reproduce chelis#2103. The issue remains open.
  The distinct nested-branch AD rejection (chelis#2825) is avoided by
  sequentializing two scalar kernel conditionals; that does not clear the
  older masked-select guard.
- An isolated conformance copy with one Shoals-only source citation and no
  blocked probe still failed row 12. The real tree passes row 12 because it
  has a blocked probe; chelis#1387 is not cleared by that PASS.

The initial package recapture returned `status=error`, `proof_tier=none`, and
empty qualifiers for gamma, volga, and vanna plus their corrupt controls:
the compiler rejected a generated logical `not` while lowering nested
gradients. A minimal nested-clamp square reproduces the same error at an
interior point. The sequential two-clamp form differentiates there; rewriting
the small-region clamp and erfc dispatcher as sequential selections lets all
four `tests-manual/greeks_secondorder.ch` cases pass. The source still calls
the same exported AD functions through `bs_call_f64`; no finite-difference
substitution is made. The complete Greek numeric oracle passes 15/15 groups
and 63 cells, including its 19-point Nautilus f32 mirror.

Post-repair raw `chelis prove --json` captures on all eight active property files used
`--tier smt-only --smt-timeout 20000` for structural/CRR/fixed-income files
and `--tier fuzz-only --samples 25 --seed 0` for sampled files. Each emitted
one summary with a complete compiler dependency graph. Reapplying the
manifest's exact property-to-model edges, control status and qualifiers,
precondition non-vacuity, and in-domain corrupt witnesses passes for all
37 active records. The seven actual-AD goals and their corrupt controls also
pass their exact checks at seeds 1 and 2 with five accepted samples each.
The six risk goals pass at seeds 0, 1, and 2 with 25 accepted samples each.

Post-repair raw NDJSON SHA-256 by `properties/<file>.ch` (exit 1 is expected
because the corrupt controls fail):

| File | Exit | SHA-256 |
| --- | ---: | --- |
| `canonadgreeks` | 1 | `606539f541c39c968f33b6694ff0e0cfd2f12f2fa718fcf0c726fca509061704` |
| `canonfixedincome` | 1 | `d50531bbca1748c3296ca87612c70b0bae9df1fe928b7f78fc10037d057f5a08` |
| `canongreeks` | 1 | `c8e529b4d85ec88ed13078260b7715763f72d3b0bf8f7ba9ba60a39d26ef0dd0` |
| `canonpricing` | 1 | `105a58e70b412d4c84a1e4da6003b65950a78fa127fc4e847b007ea692fe6457` |
| `canonrisk` | 1 | `6ccb8f46cb112be25b0865057ba439f7ed716f7549755d1b0d3fe7f4e429a3de` |
| `canonriskhistorical` | 1 | `20b95cd552326ff14f908127fcd9736f1621acc0ba40f0e367afeca6d481437d` |
| `canontrees` | 1 | `27b670645aa4ffce6a680dce19fe5f2e5a44d79ddb4205efc1662db259da349d` |
| `composites` | 1 | `7efb37e4a41ed1ba71ca840cf7367516c66b53376da0db8bc60cfa75bc6e95c1` |
The manifest records the observed 0.18.12 classifications for all 37
entries. `scripts/contract_gate.py` and all six adversarial risk-invariant
unit tests pass. Classification comes from `status`, `proof_tier`, and
`qualifiers`, with exact compiler attribution; a better-than-expected result
would require de-narrowing rather than a silent upgrade.

The exact Black-Scholes WireDag validator passes on two byte-identical cold
lowerings: schema 23, 1522 nodes, root 787, raw SHA-256
`ffa30f7050681f8cc95a3d994a34d3eb481bbe56585b14d7de5972f282a357c0`.
The node count, root, root type, and full op-kind histogram match the prior
capture; reachable loads and the copy-elided `sub` root pass the gate. Relative
to the pre-repair 0.18.12 response, only source spans changed: removing just
`span_id` and `merged_spans` makes the complete responses identical.

The full `scripts/prove_gate.py` passes its honesty, witness-domain,
dependency-graph, and metamorphic self-tests and its current-pin and
multi-seed checks. The corrected release builder's two-registry determinism
check passes. The `scripts/oracle_erf64_accuracy.py` sweep passes on 4,451
points per function using exact tagged f64 evaluator bits and a 60 dps
`mpmath` reference: worst observed absolute errors are
`3.367545353985726e-16` at x = -0.507001975 for `erf64` and
`1.9495914774441617e-16` at x = -0.7170090691949448 for `n_cdf64`.
Both published floors hold over this bounded grid; the separate left-tail
relative-accuracy limitation remains. Complete local and hosted gates
determine the remaining acceptance. Earlier release observations remain
historical evidence.
