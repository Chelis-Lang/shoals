# Chelis 0.18.12 draft pin: compiler-only evidence

Shoals 0.24.14 candidate PR #95 remains a draft. Its compiler pin is
`=0.18.12`; its Nautilus 0.7.46 and Coral 0.7.43 dependencies still declare
`=0.18.11`. No Shoals package build, source test suite, blocked probe suite,
proof-tier receipt, or full local gate on the official chain is claimed here.

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
  This example does not reproduce chelis#2103. The issue remains open, and
  the guarded Shoals `erf64` path still needs its package and `grad` tests.
- An isolated conformance copy with one Shoals-only source citation and no
  blocked probe still failed row 12. The real tree passes row 12 because it
  has a blocked probe; chelis#1387 is not cleared by that PASS.

`docs/cnote-import-surface.json` retains the prior `chelis_pin`, 37 tier
expectations, and official 0.18.11-chain receipts while its `pkg_version` names
the distinct 0.24.14 candidate. Updating those tier records or the exact
Black-Scholes WireDag receipt requires observed results from compatible
published Nautilus and Coral packages. At that point rerun
in-package blocked and negative tests, the full local gate, proof and numeric
oracles, and the official-chain release checks before considering merge.

The default local gate passed its pin and corpus-format stages, then its
whole-corpus lint was stopped after it consumed sustained CPU without a
verdict. Independently, `reef build` fails immediately on Coral's exact old
compiler pin, and `contract_gate.py` fails on the intentionally unpromoted
CNote manifest. These are open draft limitations, not passing acceptance.
