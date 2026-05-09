# Changelog

All notable changes to this project are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Replaced the stale blanket host-runtime AD limitation with scoped
  documentation: Shoals keeps executable Greek coverage on finite
  differences, while `Shoals.Pricing`'s grad-derived Greeks remain a
  deferred runtime path until the full pricing body is IR-lowerable by
  host-runtime `grad`.
- Scoped the default Shoals CI/local gate to formatter checks plus
  `chelis reef build`. The full `chelis test tests/ --timeout 120`
  runtime suite remains documented as an explicit manual/local gate.

## [0.3.1] — 2026-05-06

Compiler-pin alignment release. Tracks chelis 0.6.0 → 0.6.1
(bootstrap-list patch), nautilus 0.6.0 → 0.6.1, and coral 0.6.0 →
0.6.1 (companion alignments). No source changes from 0.3.0 — only
version + pin bumps.

## [0.3.0] — 2026-05-06

Naming-convention release. Aligns shoals with the recorded style
guide in `chelis/spec/01-nomenclature.md`. Track-forward for
chelis 0.6.0 / chelis-std 0.2.0 / nautilus 0.6.0 / coral 0.6.0.

### Changed — `Nautilus.SDE` → `Nautilus.Sde` reference update

Two references in `spec/phase3l.md` updated from `Nautilus.SDE` to
`Nautilus.Sde` per nautilus's §6.2 Title-case-not-ALL-CAPS rename.
No other shoals source files referenced the renamed surfaces.

### Style guide — §7.1.1 model/algorithm sub-namespace prefixes recognized

The `bs_*` (Black-Scholes pricing), `mc_*` (Monte-Carlo pricing),
`gbm_*` (geometric Brownian motion), and `fd_*` (finite-difference
numerical method) prefixes used in `Shoals.Pricing`, `Shoals.Stochastic`,
and `Shoals.Properties.Greeks` are now formally recognized as §7.1.1
model/algorithm sub-namespaces in `chelis/spec/01-nomenclature.md`.
The chelis-lint `MODEL_NAMESPACE_PREFIXES` allowlist accepts them.
The closer-read step from the original cleanup brief settled on
"Outcome A" — keep the prefixes as load-bearing model-discrimination,
not as helper-marker violations.

(That phrasing — "load-bearing" — is the kind shoals's Black-Scholes
trader would find compelling. The author of these conventions
prefers more concrete framing: dropping the prefixes would conflate
distinct mathematical objects in a single function-name namespace.
Either phrasing leads to the same call.)

### Changed — pin bumps for the upstream rename chain

`reef.toml`:
- `compiler = "=0.5.0"` → `"=0.6.0"`
- `chelis-std = { version = "0.1.0" }` → `{ version = "0.2.0" }`
- `nautilus = { version = "0.5.0" }` → `{ version = "0.6.0" }`
- `coral = { version = "0.5.0" }` → `{ version = "0.6.0" }`

All four pins must move together — partial bumps fail the gate
because shoals's callers reach into the renamed surfaces in coral
and the renamed-module imports in nautilus.

### Style guide

Adheres to `chelis/spec/01-nomenclature.md`. Local `STYLE.md` is a
one-line pointer at the central guide.
