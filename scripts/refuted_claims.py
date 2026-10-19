"""Invariant-surface v2 refuted selectors and authenticated predicate replay."""
from __future__ import annotations

import hashlib
import json
import math
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

FIELDS = {"model", "property", "source_sha256", "goal_sha256", "issue"}
PROPERTY_FIELDS = {"file", "module", "name"}
ROOT = "cnote_refuted_result"


def sha256(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def instances(inv: dict):
    yield inv.get("target_model") or inv.get("anchor_model"), inv
    for inst in inv.get("also_instantiated_for", []):
        yield inst.get("target_model"), inst


def find(inv: dict, pin: str, model: str, prop: dict) -> dict | None:
    claims = inv.get("refuted_claims_per_pin", {}).get(pin, [])
    matches = [c for c in claims if isinstance(c, dict) and c.get("model") == model and c.get("property") == prop]
    if len(matches) > 1:
        raise ValueError("duplicate refuted selector")
    return matches[0] if matches else None


def source_path(repo: Path, prop: dict) -> Path:
    relative = Path(prop["file"])
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("property path must stay inside the authenticated package")
    path = repo / relative
    if not path.is_file() or any(repo.joinpath(*relative.parts[:i]).is_symlink() for i in range(1, len(relative.parts) + 1)) or not path.resolve().is_relative_to(repo.resolve()):
        raise ValueError("property source missing or symlinked")
    return path


def manifest_errors(manifest: dict, repo: Path) -> list[str]:
    errors = []
    models = {m["id"] for m in manifest.get("models", [])}
    version = manifest.get("schema_version")
    for inv in manifest.get("invariants", []):
        table = inv.get("refuted_claims_per_pin", {})
        label = inv.get("id", "invariant")
        if not isinstance(table, dict):
            errors.append(f"{label}: refuted_claims_per_pin must be a map")
            continue
        if table and version != "2.0":
            errors.append(f"{label}: refuted claims require schema 2.0")
        for pin, claims in table.items():
            if pin not in inv.get("expected_tier_per_pin", {}) or not isinstance(claims, list) or not claims:
                errors.append(f"{label}: refuted pin requires an expected method and nonempty selectors")
                continue
            seen = set()
            for claim in claims:
                try:
                    if not isinstance(claim, dict) or set(claim) != FIELDS:
                        raise ValueError("refuted claim must contain exactly the v2 fields")
                    prop = claim["property"]
                    if not isinstance(prop, dict) or set(prop) != PROPERTY_FIELDS:
                        raise ValueError("invalid property identity")
                    key = (claim["model"], prop["file"], prop["module"], prop["name"])
                    if key in seen:
                        raise ValueError("duplicate refuted selector")
                    seen.add(key)
                    if claim["model"] not in models or not any(model == claim["model"] and inst.get("property") == prop for model, inst in instances(inv)):
                        raise ValueError("selector does not name a declared model/property instantiation")
                    for field in ("source_sha256", "goal_sha256"):
                        if not isinstance(claim[field], str) or re.fullmatch(r"[0-9a-f]{64}", claim[field]) is None:
                            raise ValueError(f"invalid {field}")
                    primary_model = inv.get("target_model") or inv.get("anchor_model")
                    if claim["model"] == primary_model and prop == inv.get("property") and inv["expected_tier_per_pin"][pin] != "disproved":
                        raise ValueError("selected refuted primary must declare disproved")
                    source = source_path(repo, prop).read_bytes().decode("utf-8")
                    if sha256(source) != claim["source_sha256"]:
                        raise ValueError("original property source digest mismatch")
                    if re.search(r"^module " + re.escape(prop["module"]) + r"$", source, re.M) is None:
                        raise ValueError("original property module mismatch")
                    property_parts(source, prop["name"])
                    if not isinstance(claim["issue"], str) or not claim["issue"].strip():
                        raise ValueError("refuted claim requires an issue")
                except (ValueError, KeyError, TypeError) as exc:
                    errors.append(f"{label}: {exc}")
        pin = manifest.get("chelis_pin")
        if inv.get("expected_tier_per_pin", {}).get(pin) == "disproved" and not inv.get("defective_model"):
            model = inv.get("target_model") or inv.get("anchor_model")
            try:
                if find(inv, pin, model, inv.get("property")) is None:
                    errors.append(f"{label}: a refuted primary requires an exact current-pin disposition")
            except (ValueError, TypeError):
                pass  # malformed/duplicate records were rejected above
    return errors


def property_parts(source: str, name: str) -> tuple[list[tuple[str, str]], str]:
    match = re.search(r"^@property " + re.escape(name) + r"\s+forall\(([^)]*)\)[^\n]*:\n((?:[ \t]+[^\n]*(?:\n|$))+)", source, re.M)
    if match is None:
        raise ValueError("unsupported or missing original property layout")
    params = []
    for item in match[1].split(","):
        typed = re.fullmatch(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(f32|f64)\s*", item)
        if typed is None:
            raise ValueError("predicate replay requires supported explicit scalar parameter types")
        if typed[2] != "f32":
            raise ValueError("predicate replay adapter requires scalar f32 inputs")
        params.append((typed[1], typed[2]))
    body = match[2].strip()
    if not params or "with contract" in body:
        raise ValueError("contract abstraction cannot replace executable predicate replay")
    return params, body


def numeric(value: object) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("counterexample input must be an exact numeric JSON value")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError("nonfinite counterexample input")
    return number


def replay_source(source: str, name: str, witness: dict) -> str:
    params, body = property_parts(source, name)
    if not isinstance(witness, dict) or set(witness) != {p for p, _ in params}:
        raise ValueError("counterexample must contain exactly the quantified inputs")
    if "cnote_refuted_" in source:
        raise ValueError("original source collides with reserved replay identity")
    args = ", ".join(f"cast({numeric(witness[p])!r}{'f64' if ty == 'f64' else ''}, {ty})" for p, ty in params)
    signature = ", ".join(f"{p}: {ty}" for p, ty in params)
    return source + f"\ndef cnote_refuted_replay({signature}) -> bool = {body}\n{ROOT} = cnote_refuted_replay({args})\n"


def record_errors(record: dict, claim: dict, repo: Path) -> list[str]:
    errors = []
    prop = claim["property"]
    if record.get("kind") != "property" or record.get("name") != prop["name"]:
        errors.append("refuted record identity mismatch")
    if record.get("source") != {"file": prop["file"], "kind": "surf"}:
        errors.append("refuted record source mismatch")
    if record.get("status") != "failed" or record.get("proof_tier") not in {"fuzz", "smt", "beacon"}:
        errors.append("refuted record lacks a classified failed method")
    goal = record.get("goal")
    if not isinstance(goal, str) or sha256(goal) != claim["goal_sha256"]:
        errors.append("refuted original goal digest mismatch")
    try:
        source = source_path(repo, prop).read_bytes().decode("utf-8")
        if sha256(source) != claim["source_sha256"]:
            raise ValueError("refuted original source digest mismatch")
        replay_source(source, prop["name"], record.get("counterexample"))
    except (ValueError, TypeError, KeyError) as exc:
        errors.append(str(exc))
    return errors


def replay_failed(output: dict) -> bool:
    if not isinstance(output, dict) or not isinstance(output.get("roots"), list):
        return False
    matches = [r for r in output["roots"] if isinstance(r, dict) and r.get("name") == ROOT]
    return (len(output["roots"]) == 1 and len(matches) == 1
            and isinstance(matches[0].get("value"), dict)
            and set(matches[0]["value"]) == {"type", "value"}
            and matches[0]["value"].get("type") == "bool"
            and matches[0]["value"].get("value") is False)


def replay(binary: str, repo: Path, pin: str, record: dict, claim: dict) -> bool:
    if record_errors(record, claim, repo):
        return False
    version = subprocess.run([binary, "--version"], capture_output=True, text=True, timeout=30)
    if version.returncode != 0 or version.stdout.strip() != f"chelis {pin}":
        return False
    with tempfile.TemporaryDirectory(prefix="shoals-refuted-") as directory:
        package = Path(directory)
        for path in ["reef.toml", "reef.lock", "src", "properties", "references", "demos"]:
            source = repo / path
            if source.is_dir():
                shutil.copytree(source, package / path)
            elif source.is_file():
                shutil.copy2(source, package / path)
        prop = claim["property"]
        target = package / prop["file"]
        target.write_text(replay_source(source_path(repo, prop).read_bytes().decode("utf-8"), prop["name"], record["counterexample"]))
        fmt = subprocess.run([binary, "fmt", "--inplace", str(target)], cwd=package, capture_output=True, text=True, timeout=30)
        if fmt.returncode != 0:
            return False
        lint = subprocess.run([binary, "lint", "--check", str(target)], cwd=package, capture_output=True, text=True, timeout=30)
        if lint.returncode != 0:
            return False
        result = subprocess.run([binary, "eval", "--json", "--file", str(target)], cwd=package, capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            return False
        try:
            return replay_failed(json.loads(result.stdout))
        except ValueError:
            return False
