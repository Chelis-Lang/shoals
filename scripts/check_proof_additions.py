"""Check exported real-arithmetic proofs against the selected compiler and engine.

Run `.venv/bin/python scripts/check_proof_additions.py` with CHELIS_BEACON_BIN
set to a verified published Beacon binary. Success requires one SVI SMT theorem,
two SMT refutations, two direct Black-Scholes Beacon bounds and an Arb witness.
--smt-only and --beacon-only select one lane. None certifies float execution.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tomllib

from prove_gate import compiler_graph_directly_references

ROOT = Path(__file__).resolve().parents[1]
SVI_FILE = "properties/svi_nonnegative.ch"
BS_FILE = "properties/beacon_bs_call.ch"
BS_FUNCTIONS = {
    "Shoals.Pricing." + name for name in ("bs_call_f64", "d1_64", "d2_64", "n_cdf64")
}
SVI_GOALS = {
    "svi_total_variance_nonnegative": "forall(a: f32, b: f32, rho: f32, m: f32, sigma: f32, k: f32) "
    "where b >= 0.0, rho > -1.0, rho < 1.0, sigma > 0.0, (a + ((b * "
    "sigma) * sqrt((1.0 - (rho * rho))))) >= 0.0: "
    "(Shoals.VolSurface.vs_total_variance(Shoals.VolSurface.SVI { "
    "a, b, rho, m, sigma }, k) >= 0.0)",
    "svi_without_minimum_guard_wrong": "forall(a: f32, b: f32, rho: f32, m: f32, sigma: f32, k: f32) "
    "where b >= 0.0, rho > -1.0, rho < 1.0, sigma > 0.0: "
    "(Shoals.VolSurface.vs_total_variance(Shoals.VolSurface.SVI { "
    "a, b, rho, m, sigma }, k) >= 0.0)",
    "svi_minimum_guards_satisfiable": "forall(a: f32, b: f32, rho: f32, m: f32, sigma: f32, k: f32) "
    "where b >= 0.0, rho > -1.0, rho < 1.0, sigma > 0.0, (a + ((b * "
    "sigma) * sqrt((1.0 - (rho * rho))))) >= 0.0: false",
}
BS_GOALS = {
    "bs_call_box_lower": "forall(s: f64) where s >= 96.0f64, s <= 104.0f64: "
    "(Shoals.Pricing.bs_call_f64(s, 100.0f64, 0.05f64, 0.2f64, 1.0f64) >= "
    "0.0f64)",
    "bs_call_box_upper": "forall(s: f64) where s >= 96.0f64, s <= 104.0f64: "
    "(Shoals.Pricing.bs_call_f64(s, 100.0f64, 0.05f64, 0.2f64, 1.0f64) <= "
    "20.0f64)",
    "bs_call_atm_zero_wrong": "forall(s: f64) where s >= 96.0f64, s <= 104.0f64: "
    "(Shoals.Pricing.bs_call_f64(s, 100.0f64, 0.05f64, 0.2f64, 1.0f64) <= "
    "0.0f64)",
}


def source_bound(value: float) -> dict[str, str]:
    return {"dtype": "f64", "bits": struct.pack(">d", value).hex()}


def split_records(
    records: list[dict], goals: dict[str, str], passed: int, failed: int
) -> tuple[list[dict], dict, list[str]]:
    properties = [r for r in records if r.get("kind") == "property"]
    summaries = [r for r in records if r.get("kind") == "summary"]
    names = [r.get("name") for r in properties]
    errors = []
    if (
        len(records) != len(goals) + 1
        or len(summaries) != 1
        or len(names) != len(set(names))
        or set(names) != set(goals)
    ):
        errors.append("expected exact property set and one summary")
    summary = summaries[0] if len(summaries) == 1 else {}
    for key, expected in (
        ("total", len(goals)),
        ("passed", passed),
        ("failed", failed),
        ("unsupported", 0),
        ("errors", 0),
    ):
        if summary.get(key) != expected:
            errors.append(f"summary {key} differs from required count")
    return properties, summary, errors


def check_svi_records(records: list[dict]) -> list[str]:
    properties, summary, errors = split_records(records, SVI_GOALS, 1, 2)
    for record in properties:
        name = record.get("name")
        if name not in SVI_GOALS:
            continue
        passed = name == "svi_total_variance_nonnegative"
        if (
            record.get("goal") != SVI_GOALS[name]
            or record.get("source", {}).get("file") != SVI_FILE
            or record.get("status") != ("passed" if passed else "failed")
            or record.get("proof_tier") != "smt"
            or record.get("samples") != 0
            or record.get("arith_model") != "real"
            or record.get("qualifiers") != ["real_arithmetic"]
        ):
            errors.append(f"{name}: incorrect source, goal or real SMT verdict")
        if passed:
            assumptions = record.get("assumptions", [])
            if not assumptions or not all(
                a.get("non_vacuity", {}).get("status") == "established"
                for a in assumptions
            ):
                errors.append(f"{name}: guard non-vacuity missing")
        elif not record.get("counterexample"):
            errors.append(f"{name}: missing SMT counterexample")
        if name != "svi_minimum_guards_satisfiable":
            ok, reason = compiler_graph_directly_references(
                summary.get("dependency_graph"),
                property_name=name,
                property_module="Shoals.Properties.Svi_nonnegative",
                property_file=SVI_FILE,
                target_name="vs_total_variance",
                target_module="Shoals.VolSurface",
                target_package="shoals",
                target_file="src/volsurface.ch",
                package="shoals",
            )
            if not ok:
                errors.append(f"{name}: {reason}")
    return errors


def is_hash(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch("[0-9a-f]{64}", value) is not None


def checked_witness(value: object) -> bool:
    if not isinstance(value, dict) or value.get("method") != "arb_point_256":
        return False
    point = value.get("inputs", {}).get("s", {})
    bound = value.get("bound", {})
    numbers = [point.get("lo"), point.get("hi"), bound.get("lo"), bound.get("hi")]
    return (
        all(type(n) in (int, float) and math.isfinite(n) for n in numbers)
        and 96.0 <= numbers[0] == numbers[1] <= 104.0
        and 0.0 < numbers[2] <= numbers[3]
        and set(value.get("inputs", {})) == {"s"}
    )


def checked_arb_cover(certificate: object) -> bool:
    if (
        not isinstance(certificate, dict)
        or certificate.get("method") != "arb_box_cover_v1"
    ):
        return False
    leaves = certificate.get("leaves")
    if (
        not isinstance(leaves, list)
        or not leaves
        or type(certificate.get("leaves_certified")) is not int
        or certificate["leaves_certified"] != len(leaves)
        or type(certificate.get("leaves_unresolved")) is not int
        or certificate["leaves_unresolved"] != 0
    ):
        return False
    intervals = []
    for leaf in leaves:
        if not isinstance(leaf, dict):
            return False
        inputs = leaf.get("inputs")
        if not isinstance(inputs, dict) or set(inputs) != {"s"}:
            return False
        domain = inputs["s"]
        bound = leaf.get("bound")
        if not isinstance(domain, dict) or not isinstance(bound, dict):
            return False
        values = [domain.get("lo"), domain.get("hi"), bound.get("lo"), bound.get("hi")]
        if not all(
            type(value) in (int, float) and math.isfinite(value) for value in values
        ):
            return False
        lo, hi, bound_lo, bound_hi = values
        if not (96.0 <= lo <= hi <= 104.0 and bound_lo <= bound_hi < 0.0):
            return False
        intervals.append((lo, hi))
    covered_to = 96.0
    for lo, hi in sorted(intervals):
        if lo > covered_to:
            return False
        covered_to = max(covered_to, hi)
    return covered_to == 104.0


def check_bs_records(records: list[dict], engine_sha256: str) -> list[str]:
    properties, summary, errors = split_records(records, BS_GOALS, 2, 1)
    for record in properties:
        name = record.get("name")
        if name not in BS_GOALS:
            continue
        ok, reason = compiler_graph_directly_references(
            summary.get("dependency_graph"),
            property_name=name,
            property_module="Shoals.Properties.Beacon_bs_call",
            property_file=BS_FILE,
            target_name="bs_call_f64",
            target_module="Shoals.Pricing",
            target_package="shoals",
            target_file="src/pricing.ch",
            package="shoals",
        )
        if not ok:
            errors.append(f"{name}: {reason}")
        passed = name != "bs_call_atm_zero_wrong"
        evidence = record.get("engine_evidence") or {}
        engine = evidence.get("beacon_evidence") or {}
        source = evidence.get("source_binding") or {}
        declarations = source.get("declarations") or []
        expected_bound = 20.0 if name == "bs_call_box_upper" else 0.0
        if (
            record.get("goal") != BS_GOALS[name]
            or record.get("source", {}).get("file") != BS_FILE
            or record.get("status") != ("passed" if passed else "failed")
            or record.get("proof_tier") != "beacon"
            or record.get("samples") != 0
            or record.get("arith_model") != "real"
            or record.get("qualifiers") != ["real_arithmetic"]
        ):
            errors.append(f"{name}: incorrect source, goal or qualified Beacon verdict")
        if (
            evidence.get("engine_binary_sha256") != engine_sha256
            or not is_hash(engine_sha256)
            or evidence.get("input_box") != {"s": {"lo": 96.0, "hi": 104.0}}
            or evidence.get("source_bound") != source_bound(expected_bound)
            or evidence.get("bound_side")
            != ("lower" if name == "bs_call_box_lower" else "upper")
            or evidence.get("source_dtype") != "f64"
            or evidence.get("proof_graph_dtype") != "f64"
            or evidence.get("float_execution_covered") is not False
            or len(declarations) != len(BS_FUNCTIONS)
            or {d.get("name") for d in declarations} != BS_FUNCTIONS
            or not all(is_hash(d.get("sha256")) for d in declarations)
            or not is_hash(source.get("expression_sha256"))
        ):
            errors.append(
                f"{name}: engine, source binding, dtype, domain or bound mismatch"
            )
        roots = [
            evidence.get(k)
            for k in ("selected_root", "folded_root", "source_output_root")
        ]
        if (
            not all(type(r) is int and r >= 0 for r in roots)
            or roots[0] == roots[1]
            or engine.get("selected_root_node_id") != roots[1]
            or engine.get("schema_version") != "beacon.scalar_upper_bound.v1"
            or type(engine.get("strict_upper")) not in (int, float)
            or not math.isfinite(engine["strict_upper"])
            or engine["strict_upper"] != 0.0
        ):
            errors.append(f"{name}: actual source/folded graph dispatch missing")
        certificate = engine.get("certificate") or {}
        if passed:
            if engine.get("verdict") != "certified" or not checked_arb_cover(
                certificate
            ):
                errors.append(f"{name}: complete certified Arb cover missing")
        elif (
            engine.get("verdict") != "failed"
            or not checked_witness(record.get("counterexample"))
            or engine.get("counterexample") != record.get("counterexample")
        ):
            errors.append(f"{name}: checked in-domain Arb point witness missing")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    lane = parser.add_mutually_exclusive_group()
    lane.add_argument("--smt-only", action="store_true")
    lane.add_argument("--beacon-only", action="store_true")
    args = parser.parse_args()
    pin = tomllib.loads((ROOT / "reef.toml").read_text())["package"]["compiler"].lstrip(
        "="
    )
    compiler = os.environ.get("CHELIS_BIN") or shutil.which("chelis")
    if not compiler:
        parser.error("install the pinned published Chelis toolchain")
    version = subprocess.run(
        [compiler, "--version"], capture_output=True, text=True, check=True
    )
    if version.stdout.strip() != f"chelis {pin}":
        parser.error("compiler does not match reef.toml")
    tasks = []
    if not args.beacon_only:
        tasks.append((SVI_FILE, "smt-only", check_svi_records))
    if not args.smt_only:
        engine = os.environ.get("CHELIS_BEACON_BIN")
        if not engine or not Path(engine).is_file():
            parser.error(
                "set CHELIS_BEACON_BIN to the verified published Beacon binary"
            )
        digest = hashlib.sha256(Path(engine).read_bytes()).hexdigest()
        tasks.append(
            (BS_FILE, "beacon-only", lambda records: check_bs_records(records, digest))
        )
    errors = []
    for path, tier, validate in tasks:
        run = subprocess.run(
            [compiler, "prove", path, "--tier", tier, "--json"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=120,
        )
        if run.returncode != 1:
            errors.append(
                f"{path}: expected intended-refutation exit1, got {run.returncode}: {run.stderr}"
            )
        try:
            records = [
                json.loads(line) for line in run.stdout.splitlines() if line.strip()
            ]
            errors.extend(validate(records))
        except (ValueError, TypeError, KeyError) as exc:
            errors.append(f"{path}: malformed proof output: {exc}")
    for error in errors:
        print(error, file=sys.stderr)
    if not errors:
        print("PASS: exported real-arithmetic proof additions and false controls")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
