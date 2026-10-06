# Chelis 0.18.6 de-narrowing record

The published Chelis `v0.18.6` tag resolves to commit
`cf49f85bf0d1bca2c87c88a3e459c446912189c0`. Release workflow `33232762790`
completed successfully; the publisher-authenticated Darwin arm64 archive
has SHA-256 `08580435570c6fd44716f4d5c64117e973e379808cefeaaa97c8faefa2588f6c`
and its extracted compiler payload has SHA-256
`1c88c737d7d3740eb4adbe7b50ea31d29ee64498b9d74b35664255ca16aea8d4`. Both were
re-derived from the downloaded asset here, and that payload hash is
byte-identical to the toolchain every measurement in this bump ran on. The
glibc-2.31 archive for the same tag has SHA-256
`fb9ef6701fbf0ef2532bcbafb213ca80c21d7b13da0b341b55c64ba89aa8e8fa`;
it is sidecar-verified but exercised by CI rather than this gate run.

**0.18.6 is the largest breaking cut since 0.18.0, and almost all of it is at
a machine boundary this shell does not touch.** Probed against the corpus
rather than reasoned about, one BREAKING change reaches Shoals and six do not.

*Reaches this shell.* **The exported stdlib surface is aligned with
`[05-OP-35]` (chelis#1293/chelis#1314).** `Std.Test` no longer exports
`assert_eq_int`, `assert_eq_bool`, `assert_eq_string`, or
`assert_eq_tensor_int64`; the replacement is one polymorphic
`assert_eq[q](actual, expected, label)`. Shoals imported two of them (`assert_eq_int`,
`assert_eq_bool`) at 26 call sites across 7 files, all migrated in this change
set along with those files' 7 `import Std.Test (...)` lists -- 33 token
occurrences in total. Confirmed as a measured
pair, not read off the changelog: the identical file runs `2 passed, 0 failed`
on 0.18.5 and fails on 0.18.6 with ``module `Std.Test` does not export
`assert_eq_int` for import into Probe.__Eval``. `assert_close` survives with a
widened signature (`[p_float]` rather than `f32`), which is a loosening and
needed no edit. `assert_shape` also changed shape (`List[int64]` extents rather
than a single `int64`) but Shoals never used it.

*Does not reach this shell, each checked against the corpus.* (1) The **C ABI
replacement** (`chelis_scalar` tagged carriers, `chelis_dtype`, dynamic-rank
tensor metadata, one-byte `bool`) matters only to a consumer compiling against
`chelis_runtime.h`; Shoals links no runtime and targets no HIP. (2) **`diagonal`
and `trace` returned out-of-bounds heap bytes** for every axis pair except
`(rank-2, rank-1)` (chelis#1349) — the corpus calls neither builtin at all;
`bootstrap_grad_diagonal` in `src/curves.ch` is a local `def` whose name merely
contains the word. (3) **`JsonBigInt(string)` is a new `Json` variant**, so a
previously exhaustive `match` over `Json` is not exhaustive now — Shoals has no
`Json` value, no `parse_json` call, and imports nothing from `Std.Io.Json`;
Coral fixed its own two `match` sites. (4) **`init/xavier::sample` and the
legacy JSON aliases are removed** — unused here. (5) **WireDag advances to
schema 6, exact-only** — Shoals *does* consume this, but through its own gate
rather than as a break; see the WireDag row below. (6) **HIP rejects `bool`
tensors** and **every on-disk cache is invalidated** — no HIP target, and cache
invalidation is automatic.

*Not a break, but it changed a pinned artifact.* **`sub` became a first-class
WireDag identity** ([05-OP-40], chelis#1306) instead of being reconstructed as
negate-then-add. Shoals pins the lowered Black-Scholes DAG byte-exactly in
`scripts/validate_bs_wire_root.py`, so this moved real numbers: 23 `sub` nodes
appear while `add`, `neg`, and `drop` each fall by exactly 23, every other op
kind is unchanged in count, and the DAG shrinks 1018 -> 972 nodes with the
entry root moving 535 -> 512 and its op changing `add` -> `sub`. Audited by
lowering the same `src/pricing.ch` under both binaries and comparing op-kind
histograms, not by accepting the new hash.

**0.18.2 is skipped.** The 0.24.6 / 0.18.2 candidate could not land: Nautilus
0.7.39 worked the chelis#759 float-to-integer trap around with `floor(...)`,
which has no compiled-lane expression identity, so Coral's native build broke
and its 0.7.36 release never happened. Chelis 0.18.3 ships `cast_trunc`
([05-OP-6]) and Nautilus 0.7.40 moves onto it.

**The sibling half of this chain is published.** Reef enforces exact
compiler-pin equality on dependencies, so this pin could not resolve against
Nautilus 0.7.42 / Coral 0.7.39 (both declare `=0.18.5`); the sibling releases
landed ahead of the Shoals 0.24.10 release and the cascade is closed.
**Nautilus 0.7.43** (`Chelis-Lang/nautilus#50`, merged as
`7e3451b4977922d0bda80883ba385c7da211fc9e`, tagged `v0.7.43`) has CHB
`c3e6fb6e2c3a397726df0cc53587d854ac48cab416c9dea80c9df717bfe0ef4d` and archive
`970fb4ff51e6dfdce3043bb6ad772a7df74fd4c05a0be2723d451b35ef7ddd05`;
**Coral 0.7.40** (`Chelis-Lang/coral#29`, merged as
`301305312186888856d6645eb7c898c27af28ff3`, tagged `v0.7.40`, itself declaring
`nautilus = "0.7.43"`) has CHB
`672297eb6bafcffb8f3c4ad867f59aecece8cf114747fbfe2a112f3346edc2f1` and archive
`a6416fa595b092b34f1d5483429f65b4e19927db833288a18919d5b497ecc08f`. All four
were re-derived from the downloaded assets and match their published sidecars,
and both declare `compiler = "=0.18.6"`.

The 0.24.10 gate ran against exactly those published artifacts, installed with
`chelis reef install --from-github` into an isolated registry
(`CHELIS_REEF_HOME` pointed away from the shared store). A downstream consumer
declaring `shoals = { version = "0.24.10" }` resolves the whole chain and
builds, which is the end-to-end check that matters for C Note. During
authoring, before the sibling releases existed, the same gate ran against
local builds of each sibling's PR head; those local hashes differ from the
published ones (Coral artifact bytes remain install-path dependent under
chelis#1002) and are deliberately **not** recorded here or in
`docs/cnote-import-surface.json`, whose retained-evidence list takes only
sidecar-verified published hashes.

The previous chain's published artifacts, retained for de-narrowing: Nautilus
0.7.42 from commit `85d88133b0aaf5fde3a0f425dca4a1e5fa1056de`, CHB
`f5ed24c05c4e20fdf6c72601e2e9dd68cf46a63730eb79d9189adc493704f028`, archive
`fcdf32e581d95a43b0c37d672ff241348f75f308179d0b03f6f79a5247506f95`; Coral 0.7.39
from commit `8da830db79a561c5e97fb4592f3fea2fbc492641`, CHB
`b54e8a410a3f747f0a02dc6fb8496d9fe868c288d6db1ffb2f634664f499835a`, archive
`38149dab1bceed366dc93bc62f6e3f46e21fe4d27af49510ca024bc66d16a77f`. All four
were re-derived from the downloaded assets here and match their published
sidecars.

The 0.24.10 candidate's `scripts/prove_gate.py` run consumes the 0.18.6 chain
above with its fuzz lane on (`PROVE_GATE_FUZZ=1`), green in 1m59s against
3m29s at 0.18.5 on the same machine. Its
Shoals#37 lanes observed both risk families at `fuzz_validated`: all six
properties accepted 25 constraint-directed samples at each seed 0, 1, and 2;
every corrupt control produced an in-domain witness; and the compiler summary
graph supplied every direct function edge, including the second CVaR edge in
both dominance relations.
Its Shoals#42 lane separately binds seven actual AD outputs and the displayed
price to their compiler-reported shared `bs_call_f64` body. Those records carry
runtime-oracle and multi-seed fuzz evidence; certified-box and global proof
remain explicit Shoals#42 deferrals.

The previous validated Chelis `v0.17.4` baseline resolves to commit
`0b0c92f9916163b05a483fba70473496923730e6`. Its downloaded
`linux-x86_64-glibc2.31` archive has SHA-256
`6b7f477d65b2dea4e85b5107a51ae5714a5113138a6791361b74205f9448a121`;
its `chelis` binary has SHA-256
`d08ebfe67fed11f4458251d47e732de3249d93a3d700c87991a39e219887cc7e`.
The publisher sidecar verified the archive before installation.
The official Nautilus `v0.7.36` tag resolves to commit
`2c434a9dfefca79c371b4c66af62b121a47841d6`; its canonical CHB and archive
SHA-256 values are
`2db566d8b381fd4d49acef62f875420a59c397961954a7c27cb02b79cb3f12e4`
and `412e24ec26f1828db394f6bed6ef8f4a9c93a7b104e020a457c93ec0a5b96572`.
The official Coral `v0.7.33` tag resolves to commit
`7bda6af8210a4dc128147e64cdb82019d27308f3`; its canonical CHB and archive
SHA-256 values are
`a3e04e308eb7d35c34fe4d6075c7e7626c57a6a9957fc6cf9926467b5787ec6c`
and `fe41f1617b118eb1600d02518319a96780c77195cce4c836ec43776bd69e08b0`.

