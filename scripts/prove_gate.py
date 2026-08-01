#!/usr/bin/env python3
"""Keystone canon self-audit gate for Shoals (contract WI-6).

Expected-tier-driven off docs/cnote-import-surface.json, run against the PINNED
RELEASE binary. For every manifest invariant:

  1. Satisfying control holds at exactly its expected_tier_per_pin[pin] -- tier
     drift in EITHER direction fails (better-than-expected => "run the
     de-narrowing motion"). Tier is classified from proof_tier + qualifiers,
     NEVER from the composite_verdict string (contract rule; verdict strings
     may demote, never promote).
  2. Anti-vacuity, THREE layers:
     (a) compiler attribution (mandatory since Chelis 0.17.2): the summary
         dependency graph is complete and reports an edge from the exact
         package/module/file/name property declaration to the exact
         package/module/name output function (direct lane), or to
         Std.Contracts.normal_cdf (structural lane). No dependency is
         reconstructed from source text.
     (b) syntactic (fast necessary condition): the prover-emitted GOAL string
         names the output fn (direct) or the abstracted contract symbol.
         This alone is FORGEABLE (a canceling call f(x)-f(x)<c or
         reflexive f(x)==f(x) names the fn but is model-independent).
     (c) metamorphic (the real bar): re-prove the goal with the referenced body
         (direct lane) or abstracted contract (structural lane) SUBSTITUTED by
         several alternatives, and require the outcome to flip under AT LEAST
         ONE -- only a goal whose truth depends on the model survives. A
         self-test runs the same core on committed metamorphic/ forge fixtures
         (canceling + reflexive rejected, a legit green survives).
  3. Violating control breaks with a real IN-DOMAIN witness: status matches the
     declared expectation (failed / unsupported), a counterexample is present
     (when failed), and the counterexample satisfies the manifest's structured
     preconditions (evaluated in python).
  4. Non-vacuity witnesses (`*_guards_satisfiable`) REFUTE at SMT (cvc5
     exhibits a guard-satisfying model).
  5. Defective-model invariants: the goal is DISPROVED with an in-domain
     witness that re-executes at f32 (in_region_defect).

An honesty self-test runs FIRST: the tier classifier must reject verdict
strings wearing a clean mask (a fuzz pass carrying a proven-looking
composite_verdict classifies as fuzz_validated, never proven).

Stdlib-only. Resolves the binary env-first (CHELIS_SMT_BIN / CHELIS_BIN) then
the pin-derived ~/.local/share/chelis/<pin>/ then PATH. Fuzz sample count is
FUZZ_SAMPLES controls the primary seed budget. Direct Black-Scholes Greek-sign
invariants additionally run two deterministic seeds at a capped five-sample
budget. The parametric and historical risk-coherence families run the full
configured budget over all three seeds, so their activation cannot rest on a
one-off or starved sample.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MANIFEST = REPO / "docs" / "cnote-import-surface.json"
SMT_TIMEOUT_MS = "20000"
DEFAULT_FUZZ_SAMPLES = 25
FUZZ_SEED = "0"
EXTRA_GREEK_FUZZ_SEEDS = ("1", "2")
EXTRA_GREEK_FUZZ_SAMPLE_CAP = 5
GREEK_FUZZ_INVARIANT_IDS = {
    "shoals.inv.call_monotone_in_s.bs.v1",
    "shoals.inv.bs_vega_sign.v1",
    "shoals.inv.bs_rho_sign.v1",
    "shoals.inv.bs_gamma_sign.v1",
}
AD_GREEK_FUZZ_PROBE = "shoals42_ad_greeks_multi_seed"
AD_GREEK_FUZZ_INVARIANT_IDS = {
    "shoals.inv.bs_ad_delta_fd_consistency.v1",
    "shoals.inv.bs_ad_vega_fd_consistency.v1",
    "shoals.inv.bs_ad_rho_fd_consistency.v1",
    "shoals.inv.bs_ad_theta_fd_consistency.v1",
    "shoals.inv.bs_ad_gamma_fd_consistency.v1",
    "shoals.inv.bs_ad_volga_fd_consistency.v1",
    "shoals.inv.bs_ad_vanna_fd_consistency.v1",
}
EXTRA_RISK_FUZZ_SEEDS = ("1", "2")
RISK_FUZZ_INVARIANT_IDS = {
    "shoals.inv.var_monotone_in_confidence.v1",
    "shoals.inv.cvar_dominates_var.v1",
    "shoals.inv.var_nonneg_positive_mean.v1",
    "shoals.inv.historical_var_monotone_in_confidence.v1",
    "shoals.inv.historical_cvar_dominates_var.v1",
    "shoals.inv.historical_var_nonneg_positive_losses.v1",
}

# Contract sec 1 tier vocabulary.
TIERS = {"proven", "proven_modulo_contract", "sound_approximate",
         "fuzz_validated", "disproved", "unknown", "error"}
# Tiers that must carry a tier_upgrade_trigger (below the proven ceiling).
BELOW_PROVEN = {"proven_modulo_contract", "sound_approximate", "fuzz_validated"}
# Name lint: honest vocabulary only (no convergence/limit claims) over canon files.
BANNED_NAME_SUBSTR = ("converge", "stationary", "fixed_point", "ergodic",
                      "limit", "iterat")


def fail(msg: str) -> None:
    print(f"  FAIL: {msg}")


def resolve_bin() -> str:
    for env in ("CHELIS_SMT_BIN", "CHELIS_BIN"):
        v = os.environ.get(env)
        if v and Path(v).expanduser().is_file():
            return str(Path(v).expanduser())
    pin = re.search(r'compiler\s*=\s*"=([0-9.]+)"',
                    (REPO / "reef.toml").read_text()).group(1)
    for rel in ("bin/chelis", "chelis"):
        p = Path.home() / ".local/share/chelis" / pin / rel
        if p.is_file():
            return str(p)
    import shutil
    found = shutil.which("chelis")
    if found:
        return found
    sys.exit("error: no chelis binary (set CHELIS_SMT_BIN or install the pin)")


def classify_tier(rec: dict) -> str:
    """Achieved contract tier from proof_tier + qualifiers + status ONLY.
    composite_verdict is deliberately ignored (it may demote, never promote)."""
    status = rec.get("status")
    tier = rec.get("proof_tier")
    quals = set(rec.get("qualifiers") or [])
    if status == "passed":
        if tier == "smt":
            # A fuzz-discharged contract riding an SMT structural proof is
            # proven_modulo_contract (composites: qualifiers [real_arithmetic, fuzz]).
            return "proven_modulo_contract" if "fuzz" in quals else "proven"
        if tier == "fuzz":
            return "fuzz_validated"
        return "unknown"
    if status == "failed":
        return "disproved"
    if status in ("unsupported", "error"):
        return "unknown" if status == "unsupported" else "error"
    return "unknown"


def honesty_self_test() -> bool:
    """The classifier must key on proof_tier+qualifiers, never composite_verdict."""
    cases = [
        ({"status": "passed", "proof_tier": "smt", "qualifiers": ["real_arithmetic"],
          "composite_verdict": "proven_modulo_real_arithmetic"}, "proven"),
        ({"status": "passed", "proof_tier": "smt", "qualifiers": ["real_arithmetic", "fuzz"],
          "composite_verdict": "proven_modulo_fuzz_validated_contract"}, "proven_modulo_contract"),
        ({"status": "passed", "proof_tier": "fuzz", "qualifiers": ["fuzz", "fuzz_base"],
          "composite_verdict": "fuzz_validated"}, "fuzz_validated"),
        # The adversarial case: a fuzz pass wearing a proven-looking verdict
        # string must classify as fuzz_validated, NOT proven.
        ({"status": "passed", "proof_tier": "fuzz", "qualifiers": ["fuzz"],
          "composite_verdict": "proven_modulo_real_arithmetic"}, "fuzz_validated"),
        ({"status": "failed", "proof_tier": "smt", "qualifiers": ["real_arithmetic"],
          "composite_verdict": "disproved_modulo_real_arithmetic"}, "disproved"),
        ({"status": "unsupported", "proof_tier": None, "qualifiers": [],
          "composite_verdict": "unsupported"}, "unknown"),
    ]
    ok = True
    for rec, want in cases:
        got = classify_tier(rec)
        if got != want:
            fail(f"honesty self-test: classify({rec['composite_verdict']}"
                 f"/{rec['proof_tier']}) = {got}, expected {want}")
            ok = False
    print(f"  honesty self-test: {'PASS' if ok else 'FAIL'} "
          f"({len(cases)} cases, composite_verdict ignored)")
    return ok


def run_prove(binary: str, file: str, fuzz: bool, samples: int,
              seed: str = FUZZ_SEED) -> dict:
    """Run prove on one canon file, preserving compiler attribution evidence.

    Property records are keyed by name only after duplicate detection. The
    compiler graph is accepted only from the single summary record; callers
    fail closed when it is absent, duplicated, malformed, or incomplete.
    """
    cmd = [binary, "prove", file, "--json"]
    if fuzz:
        # fuzz-only, NOT auto: chelis#637 still prevents a proven discharge, so
        # fuzz-only avoids spending time on the known-unreachable SMT lane.
        # Chelis 0.17.4 made direct-pricer sampling tractable; keep the nightly
        # sample budget (FUZZ_SAMPLES) explicit and measured.
        cmd += ["--tier", "fuzz-only", "--samples", str(samples), "--seed", seed]
    else:
        cmd += ["--tier", "smt-only", "--smt-timeout", SMT_TIMEOUT_MS]
    out = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    recs: dict[str, dict] = {}
    duplicate_records: list[str] = []
    summaries: list[dict] = []
    for line in out.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("kind") == "property" and "name" in obj and "status" in obj:
            name = obj["name"]
            if name in recs:
                duplicate_records.append(name)
            else:
                recs[name] = obj
        elif obj.get("kind") == "summary":
            summaries.append(obj)
    if len(summaries) == 1:
        for name, summary in (summaries[0].get("summary") or {}).items():
            recs.setdefault(name, {**summary, "name": name})
    return {
        "records": recs,
        "duplicate_records": duplicate_records,
        "summary_count": len(summaries),
        "dependency_graph": summaries[0].get("dependency_graph")
        if len(summaries) == 1 else None,
        "returncode": out.returncode,
    }


def parse_version(pin: str) -> tuple[int, int, int] | None:
    try:
        parts = tuple(int(x) for x in pin.split("."))
    except (TypeError, ValueError):
        return None
    return parts if len(parts) == 3 else None


def version_at_least(pin: str, floor: tuple[int, int, int]) -> bool:
    parsed = parse_version(pin)
    return parsed is not None and parsed >= floor


def compiler_graph_directly_references(
        graph: object, *, property_name: str, property_module: str,
        property_file: str, target_name: str, target_module: str,
        target_package: str, package: str,
        target_file: str | None = None) -> tuple[bool, str]:
    """Validate one exact compiler-reported declaration edge.

    Identity is namespace-aware. A same-name declaration in another module,
    package, or source file cannot satisfy the check, and duplicate exact
    declarations/IDs fail closed instead of making attribution ambiguous.
    """
    if not isinstance(graph, dict) or graph.get("status") != "complete":
        return False, "dependency_graph missing or status is not complete"
    declarations = graph.get("declarations")
    edges = graph.get("edges")
    if not isinstance(declarations, list) or not isinstance(edges, list):
        return False, "dependency_graph declarations/edges are malformed"
    if not all(isinstance(d, dict) and isinstance(d.get("id"), str)
               for d in declarations):
        return False, "dependency_graph contains malformed declarations"
    ids = [d["id"] for d in declarations]
    if len(ids) != len(set(ids)):
        return False, "dependency_graph contains duplicate declaration IDs"

    def source_matches(d: dict) -> bool:
        src = d.get("source")
        return (
            d.get("kind") == "property"
            and d.get("package") == package
            and d.get("module") == property_module
            and d.get("name") == property_name
            and isinstance(src, dict)
            and src.get("file") == property_file
        )

    def target_matches(d: dict) -> bool:
        identity_matches = (
            d.get("kind") == "function"
            and d.get("package") == target_package
            and d.get("module") == target_module
            and d.get("name") == target_name
        )
        if not identity_matches or target_file is None:
            return identity_matches
        src = d.get("source")
        return isinstance(src, dict) and src.get("file") == target_file

    sources = [d for d in declarations if source_matches(d)]
    targets = [d for d in declarations if target_matches(d)]
    if len(sources) != 1:
        return False, f"exact property declaration count is {len(sources)}, expected 1"
    if len(targets) != 1:
        return False, f"exact dependency declaration count is {len(targets)}, expected 1"
    valid_ids = set(ids)
    normalized_edges: set[tuple[str, str]] = set()
    for edge in edges:
        if not isinstance(edge, dict):
            return False, "dependency_graph contains a malformed edge"
        from_id, to_id = edge.get("from"), edge.get("to")
        if not isinstance(from_id, str) or not isinstance(to_id, str):
            return False, "dependency_graph contains an edge without string endpoints"
        if from_id not in valid_ids or to_id not in valid_ids:
            return False, "dependency_graph edge refers to an unknown declaration ID"
        normalized_edges.add((from_id, to_id))
    wanted = (sources[0]["id"], targets[0]["id"])
    if wanted not in normalized_edges:
        return False, "exact compiler-reported dependency edge is absent"
    return True, "exact compiler-reported dependency edge present"


def additional_dependency_references(
        graph: object, dependency: dict, *, property_name: str,
        property_module: str, property_file: str,
        package: str) -> tuple[bool, str]:
    """Validate one manifest-declared extra function dependency from the graph."""
    required = {"package", "module", "kind", "name", "source_file"}
    if (not isinstance(dependency, dict)
            or set(dependency) != required
            or dependency.get("kind") != "function"):
        return False, "additional compiler dependency metadata is malformed"
    return compiler_graph_directly_references(
        graph,
        property_name=property_name,
        property_module=property_module,
        property_file=property_file,
        target_name=dependency["name"],
        target_module=dependency["module"],
        target_package=dependency["package"],
        target_file=dependency["source_file"],
        package=package,
    )


def compiler_graph_function_edge(graph: object, source: dict,
                                 target: dict) -> tuple[bool, str]:
    """Validate one exact function-to-function edge from compiler records."""
    if not isinstance(graph, dict) or graph.get("status") != "complete":
        return False, "dependency_graph missing or status is not complete"
    declarations, edges = graph.get("declarations"), graph.get("edges")
    if not isinstance(declarations, list) or not isinstance(edges, list):
        return False, "dependency_graph declarations/edges are malformed"

    def matches(decl: object, spec: dict) -> bool:
        if not isinstance(decl, dict):
            return False
        src = decl.get("source")
        return (
            decl.get("kind") == "function"
            and decl.get("package") == spec.get("package")
            and decl.get("module") == spec.get("module")
            and decl.get("name") == spec.get("name")
            and isinstance(src, dict)
            and src.get("file") == spec.get("source_file")
            and isinstance(decl.get("id"), str)
        )

    sources = [decl for decl in declarations if matches(decl, source)]
    targets = [decl for decl in declarations if matches(decl, target)]
    if len(sources) != 1 or len(targets) != 1:
        return False, (f"exact function declaration counts are "
                       f"source={len(sources)}, target={len(targets)}")
    wanted = (sources[0]["id"], targets[0]["id"])
    normalized = {
        (edge.get("from"), edge.get("to")) for edge in edges
        if isinstance(edge, dict)
    }
    if wanted not in normalized:
        return False, "exact compiler-reported function edge is absent"
    return True, "exact compiler-reported function edge present"


def ad_binding_references(graph: object, inv: dict, *, property_name: str,
                          package: str) -> tuple[bool, list[str]]:
    """Validate the shoals#42 chain solely from compiler-owned records:
    property -> AD output; property -> displayed price (checked separately);
    AD output -> shared f64 price body; displayed price -> same body."""
    ad = inv.get("binding", {}).get("ad_binding")
    if not isinstance(ad, dict):
        return True, []
    messages: list[str] = []
    greek = ad.get("sensitivity_fn")
    displayed = ad.get("displayed_price_fn")
    shared = ad.get("shared_price_body")
    if not all(isinstance(x, dict) for x in (greek, displayed, shared)):
        return False, ["AD binding metadata is malformed"]
    direct, why = compiler_graph_directly_references(
        graph,
        property_name=property_name,
        property_module=inv["property"]["module"],
        property_file=inv["property"]["file"],
        target_name=greek["name"], target_module=greek["module"],
        target_package=greek["package"], target_file=greek["source_file"],
        package=package,
    )
    messages.append(f"property -> {greek['name']}: {why}")
    greek_body, why = compiler_graph_function_edge(graph, greek, shared)
    messages.append(f"{greek['name']} -> {shared['name']}: {why}")
    displayed_body, why = compiler_graph_function_edge(graph, displayed, shared)
    messages.append(f"{displayed['name']} -> {shared['name']}: {why}")
    return direct and greek_body and displayed_body, messages


def dependency_binding_references(
        rec: dict, graph: object, inv: dict, *, pin: str, output_fn: str,
        output_module: str, package: str,
        property_name: str | None = None) -> tuple[bool, str]:
    """Require compiler attribution on modern pins; legacy pins use the goal."""
    parsed_pin = parse_version(pin)
    if parsed_pin is None:
        return False, f"malformed Chelis pin {pin!r}"
    if parsed_pin < (0, 17, 2):
        return (goal_names_ref(rec.get("goal", ""), {**inv, "_output_fn": output_fn}),
                "legacy pre-0.17.2 goal fallback")
    binding = inv["binding"]
    if binding["references_output_fn"] == "structural":
        target = binding.get("compiler_dependency")
        if not isinstance(target, dict):
            return False, "structural binding lacks compiler_dependency metadata"
        target_name = target.get("name")
        target_module = target.get("module")
        target_package = target.get("package")
        target_file = target.get("source_file")
    else:
        target_name = output_fn
        target_module = output_module
        target_package = package
        target_file = None
    return compiler_graph_directly_references(
        graph,
        property_name=property_name or inv["property"]["name"],
        property_module=inv["property"]["module"],
        property_file=inv["property"]["file"],
        target_name=target_name,
        target_module=target_module,
        target_package=target_package,
        package=package,
        target_file=target_file,
    )


def dependency_graph_self_test() -> bool:
    """Lock fail-closed namespace-aware attribution against graph forgeries."""
    prop = {
        "id": "p", "kind": "property", "package": "shoals",
        "module": "Shoals.Properties.CanonTrees", "name": "crr_call_nonneg",
        "source": {"file": "properties/canontrees.ch"},
    }
    fn = {
        "id": "f", "kind": "function", "package": "shoals",
        "module": "Shoals.Trees", "name": "tr_crr_call_2step",
        "source": {"file": "src/trees.ch"},
    }
    kwargs = {
        "property_name": prop["name"], "property_module": prop["module"],
        "property_file": prop["source"]["file"], "target_name": fn["name"],
        "target_module": fn["module"], "target_package": fn["package"],
        "package": "shoals",
    }

    def bound(g: object) -> bool:
        return compiler_graph_directly_references(g, **kwargs)[0]

    good = {"status": "complete", "declarations": [prop, fn],
            "edges": [{"from": "p", "to": "f"}]}
    wrong_fn = {
        **good,
        "declarations": [prop, fn, {**fn, "id": "attacker-f",
                                   "module": "Attacker.Decoy"}],
        "edges": [{"from": "p", "to": "attacker-f"}],
    }
    wrong_prop = {
        **good,
        "declarations": [prop, fn, {**prop, "id": "attacker-p",
                                   "module": "Attacker.Decoy",
                                   "source": {"file": "attacker.ch"}}],
        "edges": [{"from": "attacker-p", "to": "f"}],
    }
    cases = [
        ("exact edge accepted", bound(good)),
        ("unavailable graph rejected", not bound(None)),
        ("incomplete graph rejected", not bound({**good, "status": "partial"})),
        ("malformed graph rejected",
         not bound({"status": "complete", "declarations": {}, "edges": []})),
        ("wrong edge rejected", not bound({**good, "edges": []})),
        ("same-name function decoy rejected", not bound(wrong_fn)),
        ("same-name property decoy rejected", not bound(wrong_prop)),
        ("duplicate declaration ID rejected",
         not bound({**good, "declarations": [prop, {**fn, "id": "p"}]})),
    ]
    legacy_inv = {
        "property": {"name": prop["name"], "module": prop["module"],
                     "file": prop["source"]["file"]},
        "binding": {"references_output_fn": "direct"},
    }
    legacy_rec = {"goal": "tr_crr_call_2step(s, k, u, d, q, disc) >= 0.0"}
    legacy = dependency_binding_references(
        legacy_rec, None, legacy_inv, pin="0.17.1", output_fn=fn["name"],
        output_module=fn["module"], package="shoals")[0]
    modern_missing = dependency_binding_references(
        legacy_rec, None, legacy_inv, pin="0.17.4", output_fn=fn["name"],
        output_module=fn["module"], package="shoals")[0]
    malformed_pin = dependency_binding_references(
        legacy_rec, good, legacy_inv, pin="0.17.x", output_fn=fn["name"],
        output_module=fn["module"], package="shoals")[0]
    cases += [
        ("pre-0.17.2 goal fallback accepted", legacy),
        ("modern missing graph rejected", not modern_missing),
        ("malformed pin rejected", not malformed_pin),
    ]
    greek = {
        "id": "g", "kind": "function", "package": "shoals",
        "module": "Shoals.Pricing", "name": "deltas_call",
        "source": {"file": "src/pricing.ch"},
    }
    body = {
        "id": "b", "kind": "function", "package": "shoals",
        "module": "Shoals.Pricing", "name": "bs_call_f64",
        "source": {"file": "src/pricing.ch"},
    }
    greek_spec = {k: greek[k] for k in ("package", "module", "kind", "name")}
    greek_spec["source_file"] = greek["source"]["file"]
    body_spec = {k: body[k] for k in ("package", "module", "kind", "name")}
    body_spec["source_file"] = body["source"]["file"]
    function_graph = {
        "status": "complete", "declarations": [greek, body],
        "edges": [{"from": "g", "to": "b"}],
    }
    cases += [
        ("exact function-body edge accepted",
         compiler_graph_function_edge(function_graph, greek_spec, body_spec)[0]),
        ("missing function-body edge rejected",
         not compiler_graph_function_edge(
             {**function_graph, "edges": []}, greek_spec, body_spec)[0]),
        ("wrong function source rejected",
         not compiler_graph_function_edge(
             function_graph, {**greek_spec, "source_file": "attacker.ch"},
             body_spec)[0]),
    ]
    failed = [name for name, passed in cases if not passed]
    if failed:
        for name in failed:
            fail(f"dependency graph self-test: {name}")
        return False
    print(f"  dependency graph self-test: PASS ({len(cases)} adversarial cases)")
    return True


def smt_value(v: str) -> float | None:
    """Parse an SMT/fuzz counterexample scalar: '1.0', '(/ 1 2)', '(- 3)'."""
    v = v.strip()
    m = re.fullmatch(r"\(/ (-?[\d.]+) (-?[\d.]+)\)", v)
    if m:
        return float(m.group(1)) / float(m.group(2))
    m = re.fullmatch(r"\(- ([\d.]+)\)", v)
    if m:
        return -float(m.group(1))
    try:
        return float(v)
    except ValueError:
        return None


def precondition_holds(pc: dict, env: dict) -> bool | None:
    lhs = env.get(pc["lhs"])
    rhs_spec = pc["rhs"]
    if "const" in rhs_spec:
        rhs = float(rhs_spec["const"])
    else:
        rhs = env.get(rhs_spec["input"])
    if lhs is None or rhs is None:
        return None
    op = pc["op"]
    return {"gt": lhs > rhs, "gte": lhs >= rhs, "lt": lhs < rhs,
            "lte": lhs <= rhs}[op]


def witness_in_domain(cx: dict, preconditions: list) -> tuple[bool, str]:
    env = {}
    for k, v in (cx or {}).items():
        f = smt_value(v) if isinstance(v, str) else v
        if f is not None:
            env[k] = f
    for pc in preconditions:
        r = precondition_holds(pc, env)
        if r is None:
            return False, f"cannot evaluate precondition {pc['lhs']} (missing witness value)"
        if not r:
            return False, f"witness violates precondition {pc['lhs']} {pc['op']} {pc['rhs']}"
    return True, "in-domain"


def failed_witness_in_domain(rec: dict, preconditions: list,
                             witness_required: bool) -> tuple[bool, str]:
    """Validate any emitted counterexample, independent of proof tier."""
    cx = rec.get("counterexample")
    if not cx:
        if witness_required:
            return False, "required counterexample is absent"
        return True, "no witness required or emitted"
    return witness_in_domain(cx, preconditions)


def witness_domain_self_test() -> bool:
    """An out-of-domain fuzz witness must never satisfy the corrupt oracle."""
    preconditions = [
        {"lhs": "alpha", "op": "gt", "rhs": {"const": 0.5}},
        {"lhs": "alpha", "op": "lt", "rhs": {"const": 1.0}},
    ]
    cases = [
        (
            "valid fuzz witness accepted",
            failed_witness_in_domain(
                {"proof_tier": "fuzz", "counterexample": {"alpha": "0.75"}},
                preconditions,
                True,
            )[0],
        ),
        (
            "out-of-domain fuzz witness rejected",
            not failed_witness_in_domain(
                {"proof_tier": "fuzz", "counterexample": {"alpha": "0.25"}},
                preconditions,
                True,
            )[0],
        ),
        (
            "missing required fuzz witness rejected",
            not failed_witness_in_domain(
                {"proof_tier": "fuzz"}, preconditions, True
            )[0],
        ),
    ]
    failed = [name for name, passed in cases if not passed]
    for name in failed:
        fail(f"witness-domain self-test: {name}")
    ok = not failed
    print(f"  witness-domain self-test: {'PASS' if ok else 'FAIL'} "
          f"({len(cases)} cases; fuzz has no domain-check bypass)")
    return ok


def goal_names_ref(goal: str, invariant: dict) -> bool:
    """Supplemental call-site check; never the modern ownership oracle.

    Match the output fn at a CALL SITE (`fn(`), not as a bare substring, so a fn
    name that is a prefix of another (tr_crr_call_2step vs
    tr_crr_call_2step_nodisc) does not false-match its sibling."""
    goal = goal or ""
    if invariant["binding"]["references_output_fn"] == "structural":
        return re.search(r"normal_cdf\s*\(", goal) is not None
    fn = invariant.get("_output_fn", "")
    return bool(fn) and re.search(rf"{re.escape(fn)}\s*\(", goal) is not None


def check_control(recs, name, want_status, label) -> tuple[bool, dict | None]:
    rec = recs.get(name)
    if rec is None:
        fail(f"{label}: property `{name}` not found in prover output")
        return False, None
    st = rec.get("status")
    if want_status == "failed":
        ok = st == "failed"
    elif want_status == "unsupported":
        ok = st in ("unsupported", "error")
    else:
        ok = st == want_status
    if not ok:
        fail(f"{label}: `{name}` status={st}, expected {want_status}")
    return ok, rec


def fuzz_non_vacuity(rec: dict) -> tuple[bool, str]:
    """Require a satisfying fuzz record to consume its full constrained budget."""
    samples = rec.get("samples")
    accepted = rec.get("accepted_samples")
    attempted = rec.get("attempted_samples")
    if not isinstance(samples, int) or samples <= 0:
        return False, "missing positive requested sample count"
    if accepted != samples or attempted != samples:
        return False, (f"sample budget not fully accepted: requested={samples}, "
                       f"accepted={accepted}, attempted={attempted}")
    if rec.get("sampling_method") != "constraint_directed":
        return False, f"sampling_method={rec.get('sampling_method')!r}, expected constraint_directed"
    assumptions = rec.get("assumptions") or []
    established = any(
        isinstance(a, dict)
        and isinstance(a.get("non_vacuity"), dict)
        and a["non_vacuity"].get("status") == "established"
        for a in assumptions
    )
    if not established:
        return False, "compiler did not report established precondition non-vacuity"
    return True, "full constraint-directed budget with established non-vacuity"


def check_instantiation(recs, graph, inv, inst, pin, model, package) -> bool:
    ok = True
    exp_tier = inv["expected_tier_per_pin"].get(pin)
    controls = inst["controls"]
    output_fn = model["output_fn"]
    effective = {**inv, "property": inst.get("property", inv["property"])}
    inv_with_fn = {**effective, "_output_fn": output_fn}

    def check_dependency(rec: dict, control_name: str, label: str) -> bool:
        bound, why = dependency_binding_references(
            rec, graph, effective, pin=pin, output_fn=output_fn,
            output_module=model["module"], package=package,
            property_name=control_name)
        if not bound:
            fail(f"{label} `{control_name}` compiler attribution: {why}")
            return False
        if version_at_least(pin, (0, 17, 2)):
            print(f"    compiler attribution `{control_name}`: {why}")
        extras_ok = True
        for dep in effective["binding"].get("additional_compiler_dependencies", []):
            extra_bound, extra_why = additional_dependency_references(
                graph, dep,
                property_name=control_name,
                property_module=effective["property"]["module"],
                property_file=effective["property"]["file"],
                package=package,
            )
            if not extra_bound:
                fail(f"{label} `{control_name}` additional compiler attribution "
                     f"{dep.get('module')}.{dep.get('name')}: {extra_why}")
                extras_ok = False
            else:
                print(f"    compiler attribution `{control_name}` -> "
                      f"{dep['module']}.{dep['name']}: {extra_why}")
        ad_ok, ad_messages = ad_binding_references(
            graph, effective, property_name=control_name, package=package)
        for message in ad_messages:
            print(f"    AD attribution `{control_name}`: {message}")
        if not ad_ok:
            fail(f"{label} `{control_name}` AD/shared-price attribution failed")
            extras_ok = False
        return extras_ok

    # Defective-model invariants have only a violating control (the break).
    if inv.get("defective_model"):
        vg = controls["violating"]
        okc, rec = check_control(recs, vg["name"], "failed", "defect")
        ok = okc and ok
        if rec:
            ok = check_dependency(rec, vg["name"], "defect") and ok
            got = classify_tier(rec)
            if got != exp_tier:
                fail(f"defect `{vg['name']}` tier {got} != expected {exp_tier}")
                ok = False
            cx = rec.get("counterexample")
            if not cx:
                fail(f"defect `{vg['name']}` has no counterexample")
                ok = False
            else:
                ind, why = witness_in_domain(cx, inst.get("preconditions", []))
                if not ind:
                    fail(f"defect witness not in-domain: {why}")
                    ok = False
                else:
                    print(f"    defect `{vg['name']}`: disproved, in-domain arbitrage witness {cx}")
        return ok

    # Satisfying control: exact expected tier + anti-vacuity goal ref.
    sg = controls["satisfying"]
    okc, rec = check_control(recs, sg["name"], "passed", "satisfying")
    ok = okc and ok
    if rec:
        ok = check_dependency(rec, sg["name"], "satisfying") and ok
        got = classify_tier(rec)
        if got != exp_tier:
            fail(f"TIER DRIFT: `{sg['name']}` achieved {got}, expected {exp_tier} "
                 f"(either direction fails -- run the de-narrowing motion)")
            ok = False
        if got == "fuzz_validated":
            non_vacuous, why = fuzz_non_vacuity(rec)
            if not non_vacuous:
                fail(f"fuzz non-vacuity `{sg['name']}`: {why}")
                ok = False
            else:
                print(f"    fuzz non-vacuity `{sg['name']}`: {why}")
        if not goal_names_ref(rec.get("goal", ""), inv_with_fn):
            fail(f"anti-vacuity: goal for `{sg['name']}` does not name the "
                 f"output fn / contract symbol (goal={rec.get('goal','')[:80]})")
            ok = False

    # Violating control: flips, with an in-domain witness.
    vg = controls["violating"]
    okc, vrec = check_control(recs, vg["name"], vg["expected"], "violating")
    ok = okc and ok
    if vrec:
        ok = check_dependency(vrec, vg["name"], "violating") and ok
    if vrec and vg["expected"] == "failed":
        ind, why = failed_witness_in_domain(
            vrec,
            inst.get("preconditions", []),
            bool(vg.get("witness_required")),
        )
        if not ind:
            fail(f"violating `{vg['name']}` witness not in-domain: {why}")
            ok = False
    return ok


def check_non_vacuity(recs, inv) -> bool:
    nv = inv.get("non_vacuity_witness")
    if not nv:
        return True
    rec = recs.get(nv)
    if rec is None:
        fail(f"non-vacuity `{nv}` not found")
        return False
    if rec.get("status") != "failed":
        fail(f"non-vacuity `{nv}`: status={rec.get('status')}, must REFUTE "
             "(cvc5 exhibits a guard-satisfying model)")
        return False
    return True


# --- Metamorphic anti-vacuity ------------------------------------------------
# A syntactic "the goal names the output fn" check is forgeable: a canceling
# call f(x)-f(x)<c or a reflexive f(x)==f(x) textually names the fn but its
# truth is INDEPENDENT of the model body. The real bar is metamorphic: re-prove
# the goal with the referenced body (direct lane) or abstracted contract
# (structural lane) SUBSTITUTED by several alternatives and require the outcome
# to CHANGE under AT LEAST ONE. A single substitution is unsound (F=const-0
# makes monotonicity F(s2)>=F(s1) trivially true -> false-positive); the
# >=1-of-several rule fixes it. Substitutions use PLAIN forms -- `cast(...)`
# does not lower to SMT, so a cast-wrapped body wrongly reads `unsupported`.
FORGE_DIR = REPO / "metamorphic"
STRUCT_CONTRACT_SUBS = ["2.0", "0.3"]  # constants VIOLATING the normal_cdf contract


def outcome(tier: str) -> str:
    """Coarse metamorphic outcome. proven_modulo_contract collapses to `proved`
    so a structural substitution (which drops the modulo-contract qualifier)
    only counts as a flip when it changes proved<->disproved, not merely the
    qualifier."""
    if tier in ("proven", "proven_modulo_contract"):
        return "proved"
    if tier == "disproved":
        return "disproved"
    return "other"


def prove_standalone(binary: str, source: str) -> str:
    """Prove a self-contained scratch .ch OUTSIDE the repo (package
    auto-detection changes prove semantics); return the single property's
    classified tier, or 'error' if it did not type-check / emit a record."""
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        f = Path(td) / "forge.ch"
        f.write_text(source)
        out = subprocess.run(
            [binary, "prove", str(f), "--json", "--tier", "smt-only",
             "--smt-timeout", SMT_TIMEOUT_MS],
            cwd=td, capture_output=True, text=True)
        for line in out.stdout.splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get("kind") == "property":
                return classify_tier(obj)
        return "error"


def extract_property_block(pfile: Path, name: str) -> str | None:
    """The `@property NAME ...:` header line plus its indented continuation
    (goal, `with contract`). Stops at the first non-indented line."""
    lines = pfile.read_text().splitlines()
    out: list[str] = []
    started = False
    for ln in lines:
        if not started:
            if re.match(rf"@property\s+{re.escape(name)}\b", ln):
                started = True
                out.append(ln)
            continue
        if ln[:1] in (" ", "\t"):
            out.append(ln)
        else:
            break
    return "\n".join(out) if started else None


def _first_param(sig: str) -> str:
    m = re.search(r"\(\s*(\w+)\s*:", sig)
    return m.group(1) if m else ""


def _ret_type(sig: str) -> str:
    m = re.search(r"->\s*(\w+)", sig)
    return m.group(1) if m else "f32"


def _params(sig: str) -> list[tuple[str, str]]:
    """[(name, type), ...] from a signature's parameter list (return excluded)."""
    return re.findall(r"(\w+)\s*:\s*(\w+)", sig.split("->")[0])


def direct_alt_bodies(sig: str) -> list[tuple[str, str]]:
    """(label, body) alternatives substituted for the output fn body. The
    affine trio -- identity-of-first-param, negated-first-param, a distinct
    constant -- discriminates single-call and first-param-relational goals
    (nonneg, monotone-in-spot, the intrinsic lower bound), but it CANNOT flip
    three shapes the model-free canon adds, so the goal would read spuriously
    vacuous:
      * an upper bound `F <= s` -- every affine body (s, neg(s), 0) is <= s
        under the guards, so none flips;
      * a relation that varies a NON-first parameter (bull spread / strike
        monotonicity) -- an affine body depends only on the first param, so both
        strike-calls collapse to the same value and the goal is reflexive;
      * a convexity/butterfly second difference -- the butterfly of ANY affine
        body is identically zero, so convexity can never flip under the trio.
    The sum-based triple below closes all three: a body that depends on EVERY
    parameter linearly flips upper-bound and non-first-param relations, and its
    concave square `neg(sum^2)` flips convexity. This is a strict STRENGTHENING
    of the metamorphic check (more discriminating substitutions -> harder to
    forge); a truly model-independent goal still flips under none of them. Added
    only for the all-f32 case, which every finance model satisfies: `cast(...)`
    does not lower to SMT, so a mixed-type sum would read `unsupported` and give
    a spurious non-flip. The forge_legit_convex self-test fixture locks the
    `neg_sq_sum` capability (a real convexity green survives)."""
    params = _params(sig)
    p0 = params[0][0] if params else _first_param(sig)
    ret = _ret_type(sig)
    const = "0.0" if ret == "f32" else f"cast(0.0, {ret})"
    alts = [("identity", p0), ("negated", f"neg({p0})"), ("constant", const)]
    if ret == "f32" and params and all(t == "f32" for _, t in params):
        names = [n for n, _ in params]
        s = names[0]
        for n in names[1:]:
            s = f"add({s}, {n})"
        alts += [("sum", s), ("neg_sum", f"neg({s})"),
                 ("neg_sq_sum", f"neg(mul({s}, {s}))")]
    return alts


def _strip_contract(prop_block: str) -> str:
    return "\n".join(ln for ln in prop_block.splitlines() if "with contract" not in ln)


def metamorphic_flips(binary: str, prop_block: str, orig_out: str,
                      structural: bool, fn: str = "", sig: str = "") -> tuple[bool, list]:
    """Re-prove the goal under several substitutions; return (flipped, results).
    flipped == some alternative's outcome differs from the original."""
    results = []
    if structural:
        body = _strip_contract(prop_block)
        for c in STRUCT_CONTRACT_SUBS:
            src = f"module Forge\ndef normal_cdf(x: f32) -> f32 = {c}\n{body}\n"
            t = prove_standalone(binary, src)
            results.append((f"normal_cdf={c}", t, outcome(t)))
    else:
        for label, alt in direct_alt_bodies(sig):
            src = f"module Forge\ndef {fn}{sig} = {alt}\n{prop_block}\n"
            t = prove_standalone(binary, src)
            results.append((f"{label}({alt})", t, outcome(t)))
    flipped = any(o != orig_out for _, _, o in results)
    return flipped, results


def check_metamorphic(inv: dict, models: dict, binary: str) -> bool:
    """Anti-vacuity by metamorphic substitution (supersedes the syntactic
    goal-names-fn check for real F-dependence)."""
    binding = inv["binding"]
    if inv.get("defective_model"):
        ctrl_name = inv["controls"]["violating"]["name"]
        orig_out = "disproved"
    else:
        ctrl_name = inv["controls"]["satisfying"]["name"]
        orig_out = "proved"
    prop_block = extract_property_block(REPO / inv["property"]["file"], ctrl_name)
    if prop_block is None:
        fail(f"metamorphic: property `{ctrl_name}` not found for {inv['id']}")
        return False
    structural = binding["references_output_fn"] == "structural"
    if structural:
        flipped, results = metamorphic_flips(binary, prop_block, orig_out, True)
        lane = "contract"
    else:
        # Model-free invariants set target_model: null; the body substituted is
        # the anchor model's output fn.
        model = models[inv.get("target_model") or inv.get("anchor_model")]
        flipped, results = metamorphic_flips(
            binary, prop_block, orig_out, False,
            fn=model["output_fn"], sig=model["sig"])
        lane = "body"
    if not flipped:
        fail(f"metamorphic VACUITY: {inv['id']} [{lane}] goal outcome "
             f"'{orig_out}' is INVARIANT under every substitution "
             f"{[(label, result) for label, _, result in results]} -- its truth is independent of "
             "the model (a canceling/reflexive forge would pass a syntactic check)")
        return False
    flips = [label for label, _, result in results if result != orig_out]
    print(f"    metamorphic [{lane}] `{ctrl_name}`: orig={orig_out}; "
          f"outcome flips under {flips}")
    return True


def parse_fixture(path: Path) -> tuple[str, str, str]:
    """(fn, sig, property-block) from a self-contained forge fixture .ch."""
    text = path.read_text()
    dm = re.search(r"def\s+(\w+)\s*(\(.*?\)\s*->\s*\w+)\s*=", text)
    pm = re.search(r"@property\s+(\w+)", text)
    fn, sig = dm.group(1), dm.group(2).strip()
    return fn, sig, extract_property_block(path, pm.group(1))


def metamorphic_self_test(binary: str) -> bool:
    """The metamorphic check must REJECT vacuous greens (canceling, reflexive:
    no substitution flips) and SURVIVE a legit green (a substitution flips).
    Runs the same core on the committed forge fixtures under metamorphic/."""
    expect = {  # fixture stem -> should the outcome flip under substitution?
        "forge_canceling": False,     # f(x)-f(x)<c: invariant -> REJECT
        "forge_reflexive": False,     # f(x)==f(x): invariant -> REJECT
        "forge_legit_monotone": True,  # f(x2)>=f(x1): flips under neg -> SURVIVE
        "forge_legit_convex": True,   # butterfly>=0: flips under neg_sq_sum -> SURVIVE
        "forge_vacuous_convex": False,  # butterfly at one point (0>=0): body-independent -> REJECT
    }
    ok = True
    for stem, should_flip in expect.items():
        path = FORGE_DIR / f"{stem}.ch"
        if not path.is_file():
            fail(f"metamorphic self-test: fixture {path.relative_to(REPO)} missing")
            ok = False
            continue
        fn, sig, block = parse_fixture(path)
        flipped, results = metamorphic_flips(binary, block, "proved", False, fn=fn, sig=sig)
        if flipped != should_flip:
            fail(f"metamorphic self-test: {stem} flipped={flipped}, expected "
                 f"{should_flip} (results "
                 f"{[(label, result) for label, _, result in results]})")
            ok = False
    print(f"  metamorphic self-test: {'PASS' if ok else 'FAIL'} "
          "(canceling+reflexive rejected, legit green survives)")
    return ok


def name_lint(files: list[Path]) -> bool:
    ok = True
    for f in files:
        for m in re.finditer(r"@property\s+(\w+)", f.read_text()):
            nm = m.group(1).lower()
            for bad in BANNED_NAME_SUBSTR:
                if bad in nm:
                    fail(f"name lint: `{m.group(1)}` in {f.name} contains "
                         f"banned term '{bad}' (honest vocabulary only)")
                    ok = False
    return ok


def check_extra_greek_fuzz_seeds(binary: str, manifest: dict, models: dict,
                                 package: str, pin: str,
                                 primary_samples: int) -> bool:
    """Require the issue-38 real-pricer family to survive multiple seeds.

    The primary release sweep already checks seed 0 at FUZZ_SAMPLES. Seeds 1
    and 2 use a bounded five-sample budget: enough to change every generated
    point while keeping the nightly/release oracle proportional. Each run still
    proves the whole source file against the real imported pricer body, and the
    normal instantiation checker re-applies tier, compiler-attribution, corrupt
    twin, and witness requirements.
    """
    greek_invs = [
        inv for inv in manifest["invariants"]
        if inv.get("dischargeability_probe") == "p15_bs_greeks_multi_seed"
    ]
    greek_ids = {inv.get("id") for inv in greek_invs}
    if greek_ids != GREEK_FUZZ_INVARIANT_IDS:
        fail("multi-seed Greek gate: p15 invariant set drifted; expected "
             f"{sorted(GREEK_FUZZ_INVARIANT_IDS)}, got {sorted(greek_ids)}")
        return False
    files = {inv["property"]["file"] for inv in greek_invs}
    if files != {"properties/canonpricing.ch"}:
        fail(f"multi-seed Greek gate: expected canonpricing.ch only, got {sorted(files)}")
        return False

    samples = min(primary_samples, EXTRA_GREEK_FUZZ_SAMPLE_CAP)
    ok = True
    for seed in EXTRA_GREEK_FUZZ_SEEDS:
        print(f"\n== multi-seed Greek probe: seed={seed} samples={samples} ==")
        result = run_prove(binary, "properties/canonpricing.ch", True,
                           samples, seed=seed)
        if result["returncode"] not in (0, 1):
            fail(f"multi-seed Greek probe seed {seed}: compiler exited "
                 f"{result['returncode']}")
            ok = False
        if result["summary_count"] != 1:
            fail(f"multi-seed Greek probe seed {seed}: emitted "
                 f"{result['summary_count']} summary records, expected 1")
            ok = False
        if result["duplicate_records"]:
            fail(f"multi-seed Greek probe seed {seed}: duplicate records "
                 f"{sorted(set(result['duplicate_records']))}")
            ok = False
        for inv in greek_invs:
            anchor = inv.get("target_model") or inv.get("anchor_model")
            print(f"  [{inv['id']}] seed {seed}")
            i_ok = check_instantiation(
                result["records"], result["dependency_graph"], inv,
                {"controls": inv["controls"],
                 "preconditions": inv.get("preconditions", []),
                 "property": inv["property"]},
                pin, models[anchor], package)
            ok = i_ok and ok
    return ok


def check_extra_ad_greek_fuzz_seeds(binary: str, manifest: dict, models: dict,
                                    package: str, pin: str,
                                    primary_samples: int) -> bool:
    """Require shoals#42's actual AD-output family over seeds 1 and 2."""
    invs = [inv for inv in manifest["invariants"]
            if inv.get("dischargeability_probe") == AD_GREEK_FUZZ_PROBE]
    ids = {inv.get("id") for inv in invs}
    if ids != AD_GREEK_FUZZ_INVARIANT_IDS:
        fail("multi-seed AD Greek gate: invariant set drifted; expected "
             f"{sorted(AD_GREEK_FUZZ_INVARIANT_IDS)}, got {sorted(ids)}")
        return False
    if {inv["property"]["file"] for inv in invs} != {"properties/canonadgreeks.ch"}:
        fail("multi-seed AD Greek gate: expected canonadgreeks.ch only")
        return False
    samples = min(primary_samples, EXTRA_GREEK_FUZZ_SAMPLE_CAP)
    ok = True
    for seed in EXTRA_GREEK_FUZZ_SEEDS:
        print(f"\n== multi-seed actual-AD Greek probe: seed={seed} samples={samples} ==")
        result = run_prove(binary, "properties/canonadgreeks.ch", True,
                           samples, seed=seed)
        if result["returncode"] not in (0, 1):
            fail(f"multi-seed actual-AD probe seed {seed}: compiler exited "
                 f"{result['returncode']}")
            ok = False
        if result["summary_count"] != 1:
            fail(f"multi-seed actual-AD probe seed {seed}: emitted "
                 f"{result['summary_count']} summary records, expected 1")
            ok = False
        if result["duplicate_records"]:
            fail(f"multi-seed actual-AD probe seed {seed}: duplicate records "
                 f"{sorted(set(result['duplicate_records']))}")
            ok = False
        for inv in invs:
            print(f"  [{inv['id']}] seed {seed}")
            i_ok = check_instantiation(
                result["records"], result["dependency_graph"], inv,
                {"controls": inv["controls"],
                 "preconditions": inv.get("preconditions", []),
                 "property": inv["property"]},
                pin, models[inv["target_model"]], package)
            ok = i_ok and ok
    return ok


def check_extra_risk_fuzz_seeds(binary: str, manifest: dict, models: dict,
                                package: str, pin: str,
                                primary_samples: int) -> bool:
    """Require both #37 families to pass their real bodies over three seeds."""
    risk_invs = [
        inv for inv in manifest["invariants"]
        if inv.get("dischargeability_probe") == "shoals37_risk_multi_seed"
    ]
    risk_ids = {inv.get("id") for inv in risk_invs}
    if risk_ids != RISK_FUZZ_INVARIANT_IDS:
        fail("multi-seed risk gate: invariant set drifted; expected "
             f"{sorted(RISK_FUZZ_INVARIANT_IDS)}, got {sorted(risk_ids)}")
        return False
    files = {inv["property"]["file"] for inv in risk_invs}
    expected_files = {"properties/canonrisk.ch", "properties/canonriskhistorical.ch"}
    if files != expected_files:
        fail(f"multi-seed risk gate: expected {sorted(expected_files)}, got {sorted(files)}")
        return False

    ok = True
    by_file: dict[str, list] = {}
    for inv in risk_invs:
        by_file.setdefault(inv["property"]["file"], []).append(inv)
    for seed in EXTRA_RISK_FUZZ_SEEDS:
        for fname, invs in sorted(by_file.items()):
            print(f"\n== multi-seed risk probe: {fname} seed={seed} "
                  f"samples={primary_samples} ==")
            result = run_prove(binary, fname, True, primary_samples, seed=seed)
            if result["returncode"] not in (0, 1):
                fail(f"multi-seed risk probe {fname} seed {seed}: compiler exited "
                     f"{result['returncode']}")
                ok = False
            if result["summary_count"] != 1:
                fail(f"multi-seed risk probe {fname} seed {seed}: emitted "
                     f"{result['summary_count']} summary records, expected 1")
                ok = False
            if result["duplicate_records"]:
                fail(f"multi-seed risk probe {fname} seed {seed}: duplicate records "
                     f"{sorted(set(result['duplicate_records']))}")
                ok = False
            for inv in invs:
                anchor = inv.get("target_model") or inv.get("anchor_model")
                print(f"  [{inv['id']}] seed {seed}")
                i_ok = check_instantiation(
                    result["records"], result["dependency_graph"], inv,
                    {"controls": inv["controls"],
                     "preconditions": inv.get("preconditions", []),
                     "property": inv["property"]},
                    pin, models[anchor], package)
                ok = i_ok and ok
    return ok


def main() -> None:
    manifest = json.loads(MANIFEST.read_text())
    pin = manifest["chelis_pin"]
    models = {m["id"]: m for m in manifest["models"]}
    binary = resolve_bin()
    samples = int(os.environ.get("FUZZ_SAMPLES", DEFAULT_FUZZ_SAMPLES))
    # The direct Black-Scholes and Black-76 call-price positivity surfaces are
    # active at fuzz_validated from 0.17.4. Keep them off the default lean path;
    # nightly/full release validation enables PROVE_GATE_FUZZ=1. No other
    # transcendental-pricer family is promoted without its own observed probe.
    include_fuzz = os.environ.get("PROVE_GATE_FUZZ") == "1"
    print(f"prove_gate: binary={binary} pin={pin} fuzz_samples={samples} "
          f"fuzz_lane={'on' if include_fuzz else 'off (nightly)'}")

    def gated(inv: dict) -> bool:
        return include_fuzz or inv["expected_tier_per_pin"].get(pin) != "fuzz_validated"

    ok = honesty_self_test()
    ok = witness_domain_self_test() and ok
    ok = dependency_graph_self_test() and ok
    ok = metamorphic_self_test(binary) and ok

    canon_files = [REPO / "properties" / "canonpricing.ch",
                   REPO / "properties" / "canontrees.ch",
                   REPO / "properties" / "canonfixedincome.ch",
                   REPO / "properties" / "canonrisk.ch",
                   REPO / "properties" / "canonriskhistorical.ch"]
    ok = name_lint([f for f in canon_files if f.exists()]) and ok

    # Group invariants by property file; a file is a fuzz lane if any of its
    # invariants expects fuzz_validated.
    gated_invs = [inv for inv in manifest["invariants"] if gated(inv)]
    by_file: dict[str, list] = {}
    for inv in gated_invs:
        by_file.setdefault(inv["property"]["file"], []).append(inv)
        for inst in inv.get("also_instantiated_for", []):
            by_file.setdefault(inst["property"]["file"], []).append(inv)

    fuzz_files = {inv["property"]["file"] for inv in gated_invs
                  if inv["expected_tier_per_pin"].get(pin) == "fuzz_validated"}
    for inv in gated_invs:
        for inst in inv.get("also_instantiated_for", []):
            if inv["expected_tier_per_pin"].get(pin) == "fuzz_validated":
                fuzz_files.add(inst["property"]["file"])

    recs_by_file = {}
    for fname in sorted(by_file):
        is_fuzz = fname in fuzz_files
        print(f"\n== proving {fname} ({'fuzz' if is_fuzz else 'smt-only'}) ==")
        result = run_prove(binary, fname, is_fuzz, samples)
        recs_by_file[fname] = result
        # `chelis prove` exits 1 when any property is disproved. Every canon
        # file deliberately includes corrupted twins, so 1 is expected and the
        # record-level checks below decide whether those failures are the right
        # ones. Exit >=2 remains an invocation/compiler failure.
        if result["returncode"] not in (0, 1):
            fail(f"{fname}: compiler exited {result['returncode']}")
            ok = False
        if result["summary_count"] != 1:
            fail(f"{fname}: compiler emitted {result['summary_count']} summary "
                 "records, expected exactly 1")
            ok = False
        if result["duplicate_records"]:
            fail(f"{fname}: duplicate proof records for "
                 f"{sorted(set(result['duplicate_records']))}")
            ok = False

    skipped = [inv["id"] for inv in manifest["invariants"] if not gated(inv)]
    if skipped:
        print(f"\n== fuzz lane deferred to nightly (PROVE_GATE_FUZZ=1): "
              f"{', '.join(skipped)} ==")

    print("\n== verifying invariants ==")
    for inv in gated_invs:
        exp = inv["expected_tier_per_pin"].get(pin)
        if exp is None:
            fail(f"{inv['id']}: no expected_tier_per_pin entry for pin {pin} "
                 "(stale for this pin)")
            ok = False
            continue
        if exp in BELOW_PROVEN and not inv.get("tier_upgrade_trigger"):
            fail(f"{inv['id']}: expected tier {exp} is below-proven but carries "
                 "no tier_upgrade_trigger")
            ok = False
        # Model-free (kind-scoped) invariants set target_model: null and name the
        # proving-ground model in anchor_model; model-pinned ones use target_model.
        anchor = inv.get("target_model") or inv.get("anchor_model")
        proof_result = recs_by_file[inv["property"]["file"]]
        recs = proof_result["records"]
        print(f"  [{inv['id']}] expected {exp}")
        i_ok = check_instantiation(
            recs, proof_result["dependency_graph"], inv,
            {"controls": inv["controls"],
             "preconditions": inv.get("preconditions", []),
             "property": inv["property"]},
            pin, models[anchor], manifest["pkg"])
        i_ok = check_non_vacuity(recs, inv) and i_ok
        # Metamorphic anti-vacuity (SMT lanes): substitute the model body /
        # abstracted contract and require the outcome to flip. The syntactic
        # goal_names_ref check above is a fast necessary condition; this is the
        # real one. (Fuzz-tier invariants -- none active -- are out of scope.)
        if exp != "fuzz_validated":
            i_ok = check_metamorphic(inv, models, binary) and i_ok
        for inst in inv.get("also_instantiated_for", []):
            inst_result = recs_by_file[inst["property"]["file"]]
            irecs = inst_result["records"]
            print(f"    also-instantiated: {inst['target_model']}")
            i_ok = check_instantiation(
                irecs, inst_result["dependency_graph"], inv, inst, pin,
                models[inst["target_model"]], manifest["pkg"]) and i_ok
        ok = i_ok and ok

    if include_fuzz:
        ok = check_extra_greek_fuzz_seeds(
            binary, manifest, models, manifest["pkg"], pin, samples) and ok
        ok = check_extra_ad_greek_fuzz_seeds(
            binary, manifest, models, manifest["pkg"], pin, samples) and ok
        ok = check_extra_risk_fuzz_seeds(
            binary, manifest, models, manifest["pkg"], pin, samples) and ok

    print()
    if ok:
        print("PASS: shoals prove_gate green")
        sys.exit(0)
    print("FAIL: shoals prove_gate")
    sys.exit(1)


if __name__ == "__main__":
    main()
