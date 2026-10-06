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
RISK_PROBE = "shoals37_risk_multi_seed"
RISK_FAMILY = {
    "shoals.inv.var_monotone_in_confidence.v1": (
        "finance.risk_measure.parametric", "parametric_var",
        "properties/canonrisk.ch", "var_monotone_in_confidence", None,
    ),
    "shoals.inv.cvar_dominates_var.v1": (
        "finance.risk_measure.parametric", "parametric_var",
        "properties/canonrisk.ch", "cvar_dominates_var", "parametric_cvar",
    ),
    "shoals.inv.var_nonneg_positive_mean.v1": (
        "finance.risk_measure.parametric", "parametric_var",
        "properties/canonrisk.ch", "var_nonneg_positive_mean", None,
    ),
    "shoals.inv.historical_var_monotone_in_confidence.v1": (
        "finance.risk_measure.historical", "historical_var",
        "properties/canonriskhistorical.ch",
        "historical_var_monotone_in_confidence", None,
    ),
    "shoals.inv.historical_cvar_dominates_var.v1": (
        "finance.risk_measure.historical", "historical_var",
        "properties/canonriskhistorical.ch",
        "historical_cvar_dominates_var", "historical_cvar",
    ),
    "shoals.inv.historical_var_nonneg_positive_losses.v1": (
        "finance.risk_measure.historical", "historical_var",
        "properties/canonriskhistorical.ch",
        "historical_var_nonneg_positive_losses", None,
    ),
}
RISK_GOAL_PATTERNS = {
    "shoals.inv.var_monotone_in_confidence.v1": (
        "{{output_fn}}(losses, alpha2) >= {{output_fn}}(losses, alpha1)"
    ),
    "shoals.inv.cvar_dominates_var.v1": (
        "parametric_cvar(losses, alpha) >= {{output_fn}}(losses, alpha)"
    ),
    "shoals.inv.var_nonneg_positive_mean.v1": (
        "{{output_fn}}(losses, alpha) > 0.0"
    ),
    "shoals.inv.historical_var_monotone_in_confidence.v1": (
        "{{output_fn}}(losses, alpha1) <= {{output_fn}}(losses, alpha2)"
    ),
    "shoals.inv.historical_cvar_dominates_var.v1": (
        "historical_cvar(losses, alpha) >= {{output_fn}}(losses, alpha)"
    ),
    "shoals.inv.historical_var_nonneg_positive_losses.v1": (
        "{{output_fn}}(losses, alpha) > 0.0"
    ),
}
AD_GREEK_PROBE = "shoals42_ad_greeks_multi_seed"
INLINE_GRAD_DEFERRED_ID = "shoals.inv.bs_vega_nonneg_grad.v1"
AD_GREEK_FAMILY = {
    "shoals.inv.bs_ad_delta_fd_consistency.v1":
        ("bs_ad_delta_matches_displayed_price", "deltas_call", "s", 1),
    "shoals.inv.bs_ad_vega_fd_consistency.v1":
        ("bs_ad_vega_matches_displayed_price", "vegas_call", "sigma", 1),
    "shoals.inv.bs_ad_rho_fd_consistency.v1":
        ("bs_ad_rho_matches_displayed_price", "rhos_call", "r", 1),
    "shoals.inv.bs_ad_theta_fd_consistency.v1":
        ("bs_ad_theta_matches_displayed_price", "thetas_call", "t", 1),
    "shoals.inv.bs_ad_gamma_fd_consistency.v1":
        ("bs_ad_gamma_matches_displayed_price", "gammas_call", "s", 2),
    "shoals.inv.bs_ad_volga_fd_consistency.v1":
        ("bs_ad_volga_matches_displayed_price", "volgas_call", "sigma", 2),
    "shoals.inv.bs_ad_vanna_fd_consistency.v1":
        ("bs_ad_vanna_matches_displayed_price", "vannas_call", "s,sigma", 2),
}

_errors: list[str] = []


def err(m: str) -> None:
    _errors.append(m)


def reef_pins() -> tuple[str, str]:
    t = (REPO / "reef.toml").read_text()
    ver = re.search(r'^\s*version\s*=\s*"([0-9.]+)"', t, re.M).group(1)
    pin = re.search(r'compiler\s*=\s*"=([0-9.]+)"', t).group(1)
    return ver, pin


def generated_note_errors(manifest: dict, version: str, pin: str) -> list[str]:
    """Keep the producer note aligned with the pinned chain and proof set."""
    note = manifest.get("generated_note")
    if not isinstance(note, str):
        return ["generated_note must be a string"]
    required = [
        f"Shoals {version}",
        f"Chelis {pin}",
        f"{len(manifest.get('invariants', []))} active invariants",
        "compiler-owned dependency edges",
    ]
    deferred_ids = {
        item.get("id") for item in manifest.get("deferred_invariants", [])
        if isinstance(item, dict)
    }
    if "shoals.inv.put_call_parity_reflection.v1" in deferred_ids:
        required.append("chelis#3116")
    out = [
        f"generated_note missing official evidence clause {phrase!r}"
        for phrase in required if phrase not in note
    ]
    forbidden = (
        "pre-release", "not yet published", "expected 0.17.5 release tier",
        "must be reproduced against the official target artifacts",
        "Retained prior", "Prior official-chain evidence",
    )
    for phrase in forbidden:
        if phrase in note:
            out.append(f"generated_note retains stale candidate clause {phrase!r}")
    return out


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


def additional_dependency_errors(dep: object) -> list[str]:
    """Fail closed on an additive exact compiler-dependency declaration."""
    required = {"package", "module", "kind", "name", "source_file"}
    if not isinstance(dep, dict) or set(dep) != required:
        return ["metadata must contain exactly package/module/kind/name/source_file"]
    out: list[str] = []
    if dep["package"] != "shoals" or dep["kind"] != "function":
        out.append("only an exact shoals function dependency is supported")
    source = module_src_file(dep["module"])
    expected_source = str(source.relative_to(REPO))
    if dep["source_file"] != expected_source:
        out.append(f"source_file={dep['source_file']!r}, expected {expected_source!r}")
    if not source.is_file() or declared_module(source) != dep["module"]:
        out.append(f"module {dep['module']!r} does not resolve to its declared source")
    else:
        text = source.read_text()
        match = re.search(r"export\s*\(([^)]*)\)", text)
        exports = {x.strip() for x in match.group(1).split(",")} if match else set()
        if dep["name"] not in exports:
            out.append(f"function {dep['name']!r} is not exported by {dep['module']}")
    return out


def risk_family_errors(manifest: dict, pin: str) -> list[str]:
    """Lock Shoals#37's two-kind/six-invariant release contract exactly."""
    out: list[str] = []
    selected = {
        inv.get("id"): inv for inv in manifest.get("invariants", [])
        if inv.get("dischargeability_probe") == RISK_PROBE
    }
    expected_ids = set(RISK_FAMILY)
    actual_ids = set(selected)
    if actual_ids != expected_ids:
        out.append(
            f"{RISK_PROBE}: invariant set drifted; expected "
            f"{sorted(expected_ids)}, got {sorted(actual_ids)}"
        )

    models = {model.get("id"): model for model in manifest.get("models", [])}
    expected_models = {
        "parametric_var": ("finance.risk_measure.parametric", "parametric_var"),
        "historical_var": ("finance.risk_measure.historical", "historical_var"),
    }
    for model_id, (kind, output_fn) in expected_models.items():
        model = models.get(model_id)
        if not model:
            out.append(f"{RISK_PROBE}: missing model {model_id}")
            continue
        if model.get("kind") != kind or model.get("output_fn") != output_fn:
            out.append(
                f"{RISK_PROBE}: model {model_id} must bind kind={kind!r} "
                f"and output_fn={output_fn!r}"
            )

    for inv_id, expected in RISK_FAMILY.items():
        kind, model_id, source, property_name, extra_fn = expected
        inv = selected.get(inv_id)
        if not inv:
            continue
        if inv.get("kind_applies_to") != [kind]:
            out.append(f"{inv_id}: kind_applies_to must be exactly [{kind!r}]")
        if inv.get("target_model") != model_id:
            out.append(f"{inv_id}: target_model must be {model_id!r}")
        prop = inv.get("property") or {}
        if prop.get("file") != source or prop.get("name") != property_name:
            out.append(
                f"{inv_id}: property must be exactly {source}:{property_name}"
            )
        controls = inv.get("controls") or {}
        satisfying = controls.get("satisfying") or {}
        violating = controls.get("violating") or {}
        if satisfying != {"name": property_name, "expected": "passed"}:
            out.append(f"{inv_id}: satisfying control drifted")
        expected_violating = {
            "name": f"{property_name}_corrupted",
            "expected": "failed",
            "witness_required": True,
        }
        if violating != expected_violating:
            out.append(f"{inv_id}: violating control drifted")
        binding = inv.get("binding") or {}
        if (
            binding.get("mechanism") != "direct-call"
            or binding.get("references_output_fn") != "direct"
            or binding.get("contracts") != []
            or binding.get("goal_pattern") != RISK_GOAL_PATTERNS[inv_id]
        ):
            out.append(f"{inv_id}: direct-call binding contract drifted")
        if inv.get("expected_tier_per_pin", {}).get(pin) != "fuzz_validated":
            out.append(f"{inv_id}: expected {pin} tier must be fuzz_validated")
        if not inv.get("tier_upgrade_trigger"):
            out.append(f"{inv_id}: missing tier_upgrade_trigger")
        domain_note = inv.get("fuzz_domain_note", "")
        for phrase in ("25 accepted", "seed", "0, 1, and 2"):
            if phrase not in domain_note:
                out.append(f"{inv_id}: fuzz_domain_note missing {phrase!r}")

        dependencies = binding.get("additional_compiler_dependencies", [])
        expected_dependencies = []
        if extra_fn:
            expected_dependencies = [{
                "package": "shoals",
                "module": "Shoals.Risk",
                "kind": "function",
                "name": extra_fn,
                "source_file": "src/risk.ch",
            }]
        if dependencies != expected_dependencies:
            out.append(
                f"{inv_id}: additional compiler dependencies must be exactly "
                f"{expected_dependencies!r}"
            )
    return out


def ad_greek_family_errors(manifest: dict, pin: str) -> list[str]:
    """Lock shoals#42 to real AD outputs, one shared displayed-price body,
    corrupt controls, and four explicitly distinct evidence levels."""
    out: list[str] = []
    selected = {
        inv.get("id"): inv for inv in manifest.get("invariants", [])
        if inv.get("dischargeability_probe") == AD_GREEK_PROBE
    }
    if set(selected) != set(AD_GREEK_FAMILY):
        out.append(
            f"{AD_GREEK_PROBE}: invariant set drifted; expected "
            f"{sorted(AD_GREEK_FAMILY)}, got {sorted(selected)}"
        )

    deferred_ids = {
        inv.get("id") for inv in manifest.get("deferred_invariants", [])
        if isinstance(inv, dict)
    }
    if INLINE_GRAD_DEFERRED_ID not in deferred_ids:
        out.append(
            f"{AD_GREEK_PROBE}: additive schema-v1 deferred invariant "
            f"{INLINE_GRAD_DEFERRED_ID!r} is missing; exported-AD consistency "
            "does not replace the unsupported inline-grad sign claim"
        )

    models = {model.get("id"): model for model in manifest.get("models", [])}
    model = models.get("bs_call") or {}
    wanted_sensitivities = [
        {"wrt": wrt, "fn": fn, "order": order}
        for _, fn, wrt, order in AD_GREEK_FAMILY.values()
    ]
    if model.get("sensitivities") != wanted_sensitivities:
        out.append("bs_call sensitivities must enumerate the exact shoals#42 "
                   "first/second-order AD surface")

    for inv_id, (property_name, greek_fn, _, order) in AD_GREEK_FAMILY.items():
        inv = selected.get(inv_id)
        if not inv:
            continue
        if inv.get("target_model") != "bs_call":
            out.append(f"{inv_id}: target_model must be 'bs_call'")
        prop = inv.get("property") or {}
        if prop != {
            "file": "properties/canonadgreeks.ch",
            "name": property_name,
            "module": "Shoals.Properties.CanonAdGreeks",
        }:
            out.append(f"{inv_id}: property binding drifted")
        controls = inv.get("controls") or {}
        if controls.get("satisfying") != {
            "name": property_name, "expected": "passed"
        }:
            out.append(f"{inv_id}: satisfying control drifted")
        if controls.get("violating") != {
            "name": f"{property_name}_corrupted",
            "expected": "failed",
            "witness_required": True,
        }:
            out.append(f"{inv_id}: corrupt derivative control drifted")
        binding = inv.get("binding") or {}
        if (binding.get("mechanism") != "direct-call"
                or binding.get("references_output_fn") != "direct"
                or binding.get("contracts") != []):
            out.append(f"{inv_id}: displayed-price direct binding drifted")
        expected_ad = {
            "sensitivity_fn": {
                "package": "shoals", "module": "Shoals.Pricing",
                "kind": "function", "name": greek_fn,
                "source_file": "src/pricing.ch",
            },
            "displayed_price_fn": {
                "package": "shoals", "module": "Shoals.Pricing",
                "kind": "function", "name": "bs_call_scalar",
                "source_file": "src/pricing.ch",
            },
            "shared_price_body": {
                "package": "shoals", "module": "Shoals.Pricing",
                "kind": "function", "name": "bs_call_f64",
                "source_file": "src/pricing.ch",
            },
            "derivative_order": order,
        }
        if binding.get("ad_binding") != expected_ad:
            out.append(f"{inv_id}: AD/shared-price compiler binding drifted")
        for label, dep in (("sensitivity_fn", expected_ad["sensitivity_fn"]),
                           ("displayed_price_fn", expected_ad["displayed_price_fn"]),
                           ("shared_price_body", expected_ad["shared_price_body"])):
            for detail in additional_dependency_errors(dep):
                out.append(f"{inv_id}: {label}: {detail}")
        if inv.get("expected_tier_per_pin", {}).get(pin) != "fuzz_validated":
            out.append(f"{inv_id}: expected {pin} tier must be fuzz_validated")
        evidence = inv.get("evidence_levels") or {}
        if evidence.get("runtime_oracle") != {
            "status": "validated", "runner": "scripts/oracle_greeks_gate.py"
        }:
            out.append(f"{inv_id}: runtime oracle evidence drifted")
        if evidence.get("fuzz_validation") != {
            "status": "validated", "tier": "fuzz_validated",
            "seeds": [0, 1, 2]
        }:
            out.append(f"{inv_id}: fuzz evidence drifted")
        for level in ("certified_box", "global_proof"):
            record = evidence.get(level) or {}
            if record.get("status") != "deferred" or "shoals#42" not in record.get("trigger", ""):
                out.append(f"{inv_id}: {level} must be an issue-linked explicit deferral")
    return out


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


def check_precondition(header: str, pc: dict, ctx: str) -> None:
    """Structural membership: the declared precondition must be one of the
    property's parsed where-guards. Canonical Surf v0.19 (chelis#1031) strips
    the redundant parens the old substring needle relied on, so the check
    compares parsed guard tuples instead of spellings."""
    guards, _ = parse_where_guards(header)
    if canon_pc(pc) not in guards:
        lhs, op, rhs = pc["lhs"], OP[pc["op"]], pc["rhs"]
        rhs_s = fmt_const(rhs["const"]) if "const" in rhs else rhs["input"]
        err(f"{ctx}: precondition ({lhs} {op} {rhs_s}) not found in property where-clause")


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
    # Canonical Surf v0.19 (chelis#1031) spells the guard list comma-separated
    # with no redundant parens (`where s > 1.0, s < 9.0:`); pre-v0.19 sources
    # wrapped each guard (`where (s > 1.0), (s < 9.0):`). Split on top-level
    # commas and strip one optional layer of surrounding parens so both parse.
    body = w.group(1)
    parts: list[str] = []
    depth, cur = 0, ""
    for ch in body:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    parts.append(cur)
    for inner in parts:
        inner = inner.strip()
        if not inner:
            continue
        if inner.startswith("(") and inner.endswith(")"):
            inner = inner[1:-1]
        g = re.match(r"\s*([A-Za-z_]\w*)\s*(>=|<=|==|>|<)\s*([A-Za-z0-9_.eE+-]+)\s*$", inner)
        if not g:
            unparsed.append(inner.strip())
            continue
        lhs, sym, rhs = g.groups()
        tok = SYM2TOK[sym]
        try:
            guards.append((lhs, tok, ("const", float(rhs))))
        except ValueError:
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
    hdr_v019 = "@property x forall(a: f32, b: f32) where a > 0.0, b < 1.0:"
    hdr_v019_exp = "@property w forall(a: f32) where a > 1e-6:"
    checks = [
        ("complete accepted", completeness_errors(hdr, complete, "st") == []),
        ("v0.19 paren-free complete accepted",
            completeness_errors(hdr_v019, complete, "st") == []),
        ("v0.19 paren-free under-declared caught",
            len(completeness_errors(hdr_v019, under, "st")) == 1),
        ("v0.19 exponent-literal guard parsed", completeness_errors(
            hdr_v019_exp, [{"lhs": "a", "op": "gt", "rhs": {"const": 1e-6}}], "st") == []),
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
        for pc in inst.get("preconditions", []):
            check_precondition(where_block, pc, ctx)
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
    for detail in generated_note_errors(manifest, ver, pin):
        err(detail)

    models = {m["id"]: m for m in manifest["models"]}
    model_ids = [m.get("id") for m in manifest["models"]]
    if len(model_ids) != len(set(model_ids)):
        err("models contains duplicate IDs")
    invariant_ids = [inv.get("id") for inv in manifest["invariants"]]
    if len(invariant_ids) != len(set(invariant_ids)):
        err("invariants contains duplicate IDs")
    for detail in risk_family_errors(manifest, pin):
        err(detail)
    for detail in ad_greek_family_errors(manifest, pin):
        err(detail)
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
        for dep in binding.get("additional_compiler_dependencies", []):
            for detail in additional_dependency_errors(dep):
                err(f"{inv['id']}: additional_compiler_dependency: {detail}")
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
