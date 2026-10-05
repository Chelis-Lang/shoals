# Chelis 0.18.13 pin evaluation

Shoals 0.24.14 selects the published Chelis 0.18.13 compiler. The dependency
chain is ordered: Nautilus 0.7.48 must be released before Coral 0.7.45, then
Shoals can build against both. The last published Nautilus 0.7.47 and Coral
0.7.44 packages target Chelis 0.18.12 and use shell format 5; the new compiler
requires shell format 6. Keep those published package entries in `reef.lock`
until compatible releases can be installed and the lock regenerated.

`chelis +0.18.13 reef conform bump 0.18.13` rewrote the compiler pin and all
three workflow pin pairs, then stopped while loading those old packages with
`invalid shell envelope: shell format version 5 is unsupported; expected 6`.
The explicit `chelis +0.18.13 reef conform sync`, conformance audit, offline
pin audit, and `conform bump-check --base origin/main` pass. The complete
`scripts/run_local_gate.py --full` reaches its `reef build` stage after passing
the pin guard, formatter, and lint; the package load stops it before tests or
proof gates can run.

## Release probes

| Surface | Chelis 0.18.13 observation | Next acceptance step |
|---|---|---|
| `Std.Datetime` | An isolated 0.18.13 package containing Shoals Date, HolidayCal, MarketData, and Tenor builds. Its corresponding tests report 128 passed, 0 failed; four date negative tests pass in `--expect neg` mode. | Repeat in the full sibling package chain. |
| Canonical `erf` and `erfc` (chelis#902) | The old expected-failure probe compiles, so it was promoted to `tests/canonical_erf.ch`; the positive test passes in the isolated package. | Compare the primitive with Shoals's Cody kernel over the f64 accuracy grid, Greek oracle, expiry cases, and proof records before replacing the kernel. |
| `chelis test` batching (shoals#111, upstream chelis#1391) | The upstream shard fix is included in 0.18.13, but the full Shoals suite cannot yet load its siblings. The old 0.18.11 timings do not predict a hosted 2-vCPU result. | Run both batch modes on matching source and the hosted suite before changing the budget. |
| Blocked probes | `tests_blocked/timeseries/rolling_f64_absent.ch` needs a compatible Nautilus release. | Run `chelis test tests_blocked/ --expect blocked`; follow each sidecar on FIX-detected or DRIFTED. |
| Proof, Greek, f64 accuracy, WireDag, release artifacts | These load the complete package chain or its generated lock. Their 0.18.12 receipts are retained in `chelis_0_18_12_migration.md` as prior evidence. | Run the full local gate, including `reef build`, proof and numeric oracles, latency, and two-registry determinism. Re-pin the WireDag response after the changed source and compiler are lowered. |

Other active entries in `docs/UPSTREAM_BUGS.md` retain their individual
triggers. The 0.18.13 release notes name no fix for chelis#1387, chelis#1002,
chelis#408, chelis#637, or chelis#846. The nested-gradient and masked-branch
guards (chelis#2825 and chelis#2103) remain until the full pricing and AD
probes execute on the compatible package chain. Nautilus's f64 approximation
and time-series gaps require the next Nautilus artifact to re-probe.
