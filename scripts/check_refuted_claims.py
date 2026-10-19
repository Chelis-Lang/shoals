#!/usr/bin/env python3
"""Bounded optional v2 method/control/replay probe; never a full campaign.

Run with the pinned release or explicitly disclosed candidate CHELIS_BIN and an
isolated CHELIS_REEF_HOME. --output writes actual classifier/control receipts.
"""
from __future__ import annotations
import argparse
import contextlib
import hashlib
import io
import json
import subprocess
from pathlib import Path
import prove_gate as gate
import refuted_claims


def check_result(result: dict, manifest: dict, file: str, binary: str) -> tuple[bool, list[dict]]:
    if result["returncode"] not in (0, 1) or result["summary_count"] != 1 or result["duplicate_records"]:
        return False, [{"file": file, "error": "invocation, summary or duplicate property records"}]
    models = {model["id"]: model for model in manifest["models"]}
    rows = []
    ok = True
    for inv in manifest["invariants"]:
        for model_id, inst in refuted_claims.instances(inv):
            if inst["property"]["file"] != file:
                continue
            capture = io.StringIO()
            with contextlib.redirect_stdout(capture):
                passed = gate.check_instantiation(result["records"], result["dependency_graph"],
                                                 inv, inst, manifest["chelis_pin"], models[model_id], manifest["pkg"])
            ok = passed and ok
            prop = inst["property"]
            claim = refuted_claims.find(inv, manifest["chelis_pin"], model_id, prop)
            rec = result["records"].get(prop["name"], {})
            rows.append({"invariant": inv["id"], "model": model_id, "property": prop,
                         "refuted": claim is not None, "classified": gate.classify_tier(rec),
                         "original_record": rec, "passed": passed, "oracle": capture.getvalue()})
    return ok, rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    manifest = json.loads(gate.MANIFEST.read_text())
    errors = refuted_claims.manifest_errors(manifest, gate.REPO)
    files = {claim["property"]["file"] for inv in manifest["invariants"]
             for claim in inv.get("refuted_claims_per_pin", {}).get(manifest["chelis_pin"], [])}
    if errors or not files:
        print("FAIL:", errors or ["no active refuted selectors"])
        return 1
    binary = gate.resolve_bin()
    version = subprocess.run([binary, "--version"], capture_output=True, text=True, timeout=30)
    if version.returncode or version.stdout.strip() != f"chelis {manifest['chelis_pin']}":
        print("FAIL: compiler pin mismatch")
        return 1
    receipt = {"compiler_version": version.stdout.strip(), "binary_sha256": hashlib.sha256(Path(binary).read_bytes()).hexdigest(),
               "package_version": manifest["pkg_version"], "sample_budget": 25, "seed": 0, "files": {}, "rows": []}
    ok = True
    for file in sorted(files):
        result = gate.run_prove(binary, file, True, 25, timeout=60)
        passed, rows = check_result(result, manifest, file, binary)
        receipt["files"][file] = result
        receipt["rows"].extend(rows)
        ok = passed and ok
        print(f"{file}: {'PASS' if passed else 'FAIL'}", flush=True)
        for row in rows:
            print(f"  {row.get('model')}:{row.get('property', {}).get('name')} {row.get('classified')} {row.get('passed')}", flush=True)
    receipt["passed"] = ok
    if args.output:
        args.output.write_text(json.dumps(receipt, indent=2) + "\n")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
