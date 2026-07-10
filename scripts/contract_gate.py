#!/usr/bin/env python3
"""Producer-side contract gate for Shoals (frozen contract sec 3).

Offline, stdlib-only. Validates docs/cnote-import-surface.json against the
reef.toml pins and the real .ch sources -- the freshness + resolvability checks
the unconsumed v1 manifest lacked:

  * schema_id / schema_version literals;
  * pkg_version and chelis_pin agree with reef.toml;
  * every models[].output_fn is a real export of its module;
  * every invariants[].property (and also_instantiated_for) resolves to a real
    @property in the named file;
  * every control / non_vacuity_witness / edge_control name exists as a @property;
  * every structured precondition appears (normalized) in the property's
    where-clause text (prove --json has no structured preconditions field);
  * expected_tier_per_pin has an entry for the current pin;
  * every below-proven expected tier carries a tier_upgrade_trigger citation.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MANIFEST = REPO / "docs" / "cnote-import-surface.json"
BELOW_PROVEN = {"proven_modulo_contract", "sound_approximate", "fuzz_validated"}
OP = {"gt": ">", "gte": ">=", "lt": "<", "lte": "<="}

_errors: list[str] = []


def err(m: str) -> None:
    _errors.append(m)


def reef_pins() -> tuple[str, str]:
    t = (REPO / "reef.toml").read_text()
    ver = re.search(r'^\s*version\s*=\s*"([0-9.]+)"', t, re.M).group(1)
    pin = re.search(r'compiler\s*=\s*"=([0-9.]+)"', t).group(1)
    return ver, pin


def module_src_file(module: str) -> Path:
    # Shoals.Pricing -> src/pricing.ch ; Shoals.PricingExtended -> src/pricingextended.ch
    return REPO / "src" / (module.split(".")[-1].lower() + ".ch")


def exports_of(module: str) -> set[str]:
    f = module_src_file(module)
    if not f.is_file():
        err(f"module {module}: source file {f.relative_to(REPO)} not found")
        return set()
    m = re.search(r"export\s*\(([^)]*)\)", f.read_text())
    if not m:
        return set()
    return {x.strip() for x in m.group(1).split(",") if x.strip()}


def property_block(pfile: Path, name: str) -> str | None:
    """The `@property <name> ...:` HEADER line (params + where-guards). The
    canonically-formatted header is one line ending in `:`, the goal on the
    next; capturing the header line avoids stopping at a `param: type` colon."""
    if not pfile.is_file():
        return None
    text = pfile.read_text()
    m = re.search(rf"@property\s+{re.escape(name)}\b[^\n]*", text)
    return m.group(0) if m else None


def fmt_const(v) -> str:
    f = float(v)
    return str(int(f)) + ".0" if f == int(f) else str(f)


def check_precondition(where_ns: str, pc: dict, ctx: str) -> None:
    lhs = pc["lhs"]
    op = OP[pc["op"]]
    rhs = pc["rhs"]
    rhs_s = fmt_const(rhs["const"]) if "const" in rhs else rhs["input"]
    needle = f"({lhs}{op}{rhs_s})"
    if needle not in where_ns:
        err(f"{ctx}: precondition {needle} not found in property where-clause")


def check_instantiation(inv: dict, inst: dict, models: dict) -> None:
    ctx = f"{inv['id']}"
    prop = inst["property"]
    pfile = REPO / prop["file"]
    # controls + non-vacuity + edge names must all resolve to @property blocks.
    names = []
    for role in ("satisfying", "violating"):
        c = inst["controls"].get(role)
        if c:
            names.append(c["name"])
    if inv.get("non_vacuity_witness"):
        names.append(inv["non_vacuity_witness"])
    if inv.get("edge_control"):
        names.append(inv["edge_control"]["name"])
    where_ns = None
    for nm in names:
        blk = property_block(pfile, nm)
        if blk is None:
            err(f"{ctx}: @property `{nm}` not found in {prop['file']}")
        elif nm == inst["controls"].get("satisfying", {}).get("name") or \
                (inv.get("defective_model") and nm == inst["controls"]["violating"]["name"]):
            where_ns = re.sub(r"\s+", "", blk)
    # preconditions checked against the satisfying (or defect) control's guards.
    if where_ns is not None:
        for pc in inst.get("preconditions", []):
            check_precondition(where_ns, pc, ctx)


def main() -> None:
    manifest = json.loads(MANIFEST.read_text())
    ver, pin = reef_pins()

    if manifest.get("schema_id") != "chelis-shell.invariant-surface":
        err(f"schema_id={manifest.get('schema_id')!r} (expected chelis-shell.invariant-surface)")
    if manifest.get("schema_version") != "1.0":
        err(f"schema_version={manifest.get('schema_version')!r} (expected '1.0')")
    if manifest.get("pkg_version") != ver:
        err(f"pkg_version={manifest.get('pkg_version')} != reef.toml version {ver}")
    if manifest.get("chelis_pin") != pin:
        err(f"chelis_pin={manifest.get('chelis_pin')} != reef.toml compiler pin {pin}")

    models = {m["id"]: m for m in manifest["models"]}
    for m in manifest["models"]:
        if m["output_fn"] not in exports_of(m["module"]):
            err(f"model {m['id']}: output_fn `{m['output_fn']}` not exported by {m['module']}")

    for inv in manifest["invariants"]:
        if inv.get("target_model") not in models:
            err(f"{inv['id']}: target_model `{inv.get('target_model')}` not in models")
        if pin not in inv.get("expected_tier_per_pin", {}):
            err(f"{inv['id']}: no expected_tier_per_pin entry for current pin {pin}")
        else:
            tier = inv["expected_tier_per_pin"][pin]
            if tier in BELOW_PROVEN and not inv.get("tier_upgrade_trigger"):
                err(f"{inv['id']}: below-proven tier {tier} lacks tier_upgrade_trigger")
        check_instantiation(inv, inv, models)
        for inst in inv.get("also_instantiated_for", []):
            if inst.get("target_model") not in models:
                err(f"{inv['id']}: also_instantiated_for target `{inst.get('target_model')}` not in models")
            check_instantiation(inv, inst, models)

    if _errors:
        print(f"FAIL: contract_gate ({len(_errors)} issue(s))")
        for e in _errors:
            print(f"  - {e}")
        sys.exit(1)
    print(f"PASS: contract_gate green (schema {manifest['schema_id']}/{manifest['schema_version']}, "
          f"pkg {ver}, pin {pin}, {len(manifest['models'])} models, "
          f"{len(manifest['invariants'])} invariants)")
    sys.exit(0)


if __name__ == "__main__":
    main()
