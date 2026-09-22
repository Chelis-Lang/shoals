# Chelis 0.18.11 migration

Shoals 0.24.13 pins the published Chelis 0.18.11 compiler, Nautilus 0.7.46,
and Coral 0.7.43. Workflow mirrors and separately synchronized conformance
artifacts carry the same compiler pin.

Maintained Surf uses canonical integer dtype spellings and `skip` for
list-prefix removal. `src/rng.ch` was migrated manually because the migrator
exhausted its default stack; the prime and Sobol tables are unchanged. The two
RNG test helpers explicitly declare their return dimension `[m]`. Documentation
examples and Python-generated Surf use the same vocabulary; historical research
snapshots remain unchanged.

The published compiler builds the package against the new dependencies. The
Black–Scholes WireDag advances from schema 13 to 15, root 773 to 787, and 1494
to 1522 nodes: 14 extra copies and 14 extra drops; `cmp_lt` becomes `compare`
with predicate `lt`. Copy-elided input dataflow, operation parameters,
precisions, and all 15 named loads match the previous pin. Internal symbolic
dimension names differ, so this is not a shape-equivalence claim. Two independent
cold lowerings reproduce the new byte-exact receipt. The validator rejects
legacy, missing, and changed comparison predicates.

The frozen CNote manifest retains all 37 invariant IDs, all previous per-pin
expectations, and their tier values; 0.18.11 expectations are added without
promotion. A successful proof gate must observe those expectations.

The Nautilus f32 `erf` oracle mirror now includes the published Taylor branch
below `|x|=0.25`; generated checks cover 19 points across signs and the cutoff.
The existing `f64` erf blocked probe still rejects as expected. The workaround
citation audit finds no closed active-subject issue requiring removal. The full
pin-bump gate, including numerical tests, proof receipts, latency, and
cross-registry release determinism, remains the acceptance command:
`.venv/bin/python scripts/run_local_gate.py --full`. Older measurements in
`CHELIS_SURFACE.md` are historical, not newly certified by this migration.
