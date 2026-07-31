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
    where-clause text (declared subset of the proof's guards);
  * COMPLETENESS (the reverse direction): every region-constraining guard in
    the property's where-clause is a declared precondition (declared superset of
    the proof's guards). An UNDER-declared manifest -- declared a strict subset
    of the where-clause -- lets the consumer derive a validity region WIDER than
    what was proved (a region-overclaim forge the red-team found in a sibling
    shell). Together the two directions pin declared == where-clause exactly;
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
OP = {"gt": ">", "gte": ">=", "lt": "<", "lte": "<=", "eq": "=="}
# where-clause comparison operator -> contract op token (longest first).
SYM2TOK = {">=": "gte", "<=": "lte", "==": "eq", ">": "gt", "<": "lt"}

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


def declared_module(path: Path) -> str | None:
    if not path.is_file():
        return None
    match = re.search(r"^\s*module\s+([A-Za-z_][A-Za-z0-9_.]*)\s*$",
                      path.read_text(), re.M)
    return match.group(1) if match else None


def exports_of(module: str) -> set[str]:
    f = module_src_file(module)
    if not f.is_file():
        err(f"module {module}: source file {f.relative_to(REPO)} not found")
        return set()
    actual_module = declared_module(f)
    if actual_module != module:
        err(f"module {module}: {f.relative_to(REPO)} declares "
            f"{actual_module!r}, not the manifest module")
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
    matches = re.findall(rf"@property\s+{re.escape(name)}\b[^\n]*", text)
    return matches[0] if len(matches) == 1 else None


def property_count(pfile: Path, name: str) -> int:
    if not pfile.is_file():
        return 0
    return len(re.findall(rf"@property\s+{re.escape(name)}\b",
                          pfile.read_text()))


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


def canon_pc(pc: dict) -> tuple:
    """A declared manifest precondition in canonical comparable form."""
    rhs = pc["rhs"]
    if "const" in rhs:
        r = ("const", float(rhs["const"]))
    else:  # `input` is the param-reference key; `param` accepted as read-alias.
        r = ("input", rhs.get("input", rhs.get("param")))
    return (pc["lhs"], pc["op"], r)


def parse_where_guards(header: str) -> tuple[list[tuple], list[str]]:
    """Guards of a `@property ... where (g), (g), ...:` header, in the same
    canonical form as canon_pc, plus any guards that did not parse. Returns
    ([] , []) for a property with no where-clause."""
    w = re.search(r"\bwhere\b(.*):", header)
    if not w:
        return [], []
    guards: list[tuple] = []
    unparsed: list[str] = []
    for inner in re.findall(r"\(([^()]+)\)", w.group(1)):
        g = re.match(r"\s*([A-Za-z_]\w*)\s*(>=|<=|==|>|<)\s*([A-Za-z0-9_.]+)\s*$", inner)
        if not g:
            unparsed.append(inner.strip())
            continue
        lhs, sym, rhs = g.groups()
        tok = SYM2TOK[sym]
        if re.fullmatch(r"[0-9.]+", rhs):
            guards.append((lhs, tok, ("const", float(rhs))))
        else:
            guards.append((lhs, tok, ("input", rhs)))
    return guards, unparsed


def completeness_errors(header: str, preconditions: list, ctx: str) -> list[str]:
    """Pure (no global mutation): the completeness errors for one property.
    Every region-constraining guard in the where-clause MUST be a declared
    precondition (declared superset of the proof's guards). Reverse of
    check_precondition; an UNDER-declared manifest lets the consumer derive a
    region wider than the proof (region-overclaim forge). Fails closed on an
    unparsed guard -- an unparsed guard might be the under-declared one."""
    out: list[str] = []
    guards, unparsed = parse_where_guards(header)
    declared = {canon_pc(pc) for pc in preconditions}
    for lhs, tok, rhs in guards:
        if (lhs, tok, rhs) not in declared:
            rhs_s = fmt_const(rhs[1]) if rhs[0] == "const" else rhs[1]
            out.append(f"{ctx}: UNDER-DECLARED -- property where-clause guard "
                       f"({lhs} {OP[tok]} {rhs_s}) is not a declared precondition; "
                       "the consumer would derive a validity region WIDER than the proof")
    for u in unparsed:
        out.append(f"{ctx}: could not parse where-clause guard `({u})`; cannot "
                   "confirm it is declared (failing closed -- may be under-declared)")
    return out


def check_completeness(header: str, preconditions: list, ctx: str) -> None:
    for e in completeness_errors(header, preconditions, ctx):
        err(e)


def self_test() -> None:
    """The completeness check must catch an under-declared manifest. Runs first;
    a regression that weakens the check fails the gate itself (mirrors
    prove_gate's honesty self-test)."""
    hdr = "@property x forall(a: f32, b: f32) where (a > 0.0), (b < 1.0):"
    complete = [{"lhs": "a", "op": "gt", "rhs": {"const": 0.0}},
                {"lhs": "b", "op": "lt", "rhs": {"const": 1.0}}]
    under = [{"lhs": "a", "op": "gt", "rhs": {"const": 0.0}}]  # missing (b < 1.0)
    hdr_rel = "@property y forall(a: f32, b: f32) where (b > a):"
    checks = [
        ("complete accepted", completeness_errors(hdr, complete, "st") == []),
        ("under-declared caught", len(completeness_errors(hdr, under, "st")) == 1
            and "UNDER-DECLARED" in completeness_errors(hdr, under, "st")[0]),
        ("param-ref guard accepted", completeness_errors(
            hdr_rel, [{"lhs": "b", "op": "gt", "rhs": {"input": "a"}}], "st") == []),
        ("param-ref under-declared caught",
            len(completeness_errors(hdr_rel, [], "st")) == 1),
        ("no-where property clean", completeness_errors(
            "@property z forall(d1: f32):", [], "st") == []),
    ]
    failed = [name for name, ok in checks if not ok]
    if failed:
        err("completeness self-test FAILED: " + "; ".join(failed))
    else:
        print(f"  completeness self-test: PASS ({len(checks)} cases)")


def check_instantiation(inv: dict, inst: dict, models: dict) -> None:
    ctx = f"{inv['id']}"
    prop = inst["property"]
    pfile = REPO / prop["file"]
    actual_module = declared_module(pfile)
    if actual_module != prop.get("module"):
        err(f"{ctx}: {prop['file']} declares module {actual_module!r}, "
            f"not manifest module {prop.get('module')!r}")
    if property_count(pfile, prop["name"]) != 1:
        err(f"{ctx}: manifest property `{prop['name']}` resolves "
            f"{property_count(pfile, prop['name'])} times in {prop['file']} "
            "(expected exactly 1)")
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
    where_block = None
    for nm in names:
        count = property_count(pfile, nm)
        if count != 1:
            err(f"{ctx}: @property `{nm}` resolves {count} times in "
                f"{prop['file']} (expected exactly 1)")
            continue
        blk = property_block(pfile, nm)
        if nm == inst["controls"].get("satisfying", {}).get("name") or \
                (inv.get("defective_model") and nm == inst["controls"]["violating"]["name"]):
            where_block = blk
    # preconditions vs the satisfying (or defect) control's where-clause, BOTH
    # directions: declared subset of the guards (each declared appears in text)
    # AND declared superset of the guards (completeness -- no under-declaration).
    if where_block is not None:
        where_ns = re.sub(r"\s+", "", where_block)
        for pc in inst.get("preconditions", []):
            check_precondition(where_ns, pc, ctx)
        check_completeness(where_block, inst.get("preconditions", []), ctx)


def main() -> None:
    self_test()
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
    model_ids = [m.get("id") for m in manifest["models"]]
    if len(model_ids) != len(set(model_ids)):
        err("models contains duplicate IDs")
    invariant_ids = [inv.get("id") for inv in manifest["invariants"]]
    if len(invariant_ids) != len(set(invariant_ids)):
        err("invariants contains duplicate IDs")
    for m in manifest["models"]:
        if m["output_fn"] not in exports_of(m["module"]):
            err(f"model {m['id']}: output_fn `{m['output_fn']}` not exported by {m['module']}")

    for inv in manifest["invariants"]:
        # Model-free (kind-scoped) invariants set target_model: null and name the
        # proving-ground model in anchor_model; either must resolve to a model.
        anchor = inv.get("target_model") or inv.get("anchor_model")
        if anchor not in models:
            err(f"{inv['id']}: neither target_model nor anchor_model resolves to a "
                f"model (got {anchor!r})")
        if pin not in inv.get("expected_tier_per_pin", {}):
            err(f"{inv['id']}: no expected_tier_per_pin entry for current pin {pin}")
        else:
            tier = inv["expected_tier_per_pin"][pin]
            if tier in BELOW_PROVEN and not inv.get("tier_upgrade_trigger"):
                err(f"{inv['id']}: below-proven tier {tier} lacks tier_upgrade_trigger")
        binding = inv.get("binding", {})
        if binding.get("references_output_fn") == "structural":
            dep = binding.get("compiler_dependency")
            expected = {
                "package": "chelis-std",
                "module": "Std.Contracts",
                "kind": "function",
                "name": "normal_cdf",
                "source_file": "src/contracts.ch",
            }
            if dep != expected:
                err(f"{inv['id']}: structural compiler_dependency={dep!r}; "
                    f"expected exact {expected!r}")
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
