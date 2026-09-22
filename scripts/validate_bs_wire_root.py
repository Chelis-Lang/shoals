#!/usr/bin/env python3
"""Validate Shoals' real Black-Scholes entry at the Chelis WireDag boundary."""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENTRY = "bs_call_wire_f64"
EXPECTED_ENTRY_ROOT = 787
EXPECTED_NODE_COUNT = 1522
# Schema-13 migration (Chelis 0.18.10). The 0.18.9 pin captured schema 11 with
# entry root 770 and 1488 nodes (raw hash 955c1df6...). Under the published
# 0.18.10 binary the same src/pricing.ch lowers to schema 13, entry root 773
# and 1494 nodes: exactly +3 Copy and +3 Drop plumbing nodes over 0.18.9, and
# nothing else moved. The full-DAG op-kind histogram is add 59, cast 13,
# cmp_lt 13, copy 317, div 8, drop 720, exp 5, extent_witness 166, load 48,
# log 2, mul 91, neg 17, sqrt 3, sub 32 -- every arithmetic op count (add,
# cast, cmp_lt, div, exp, extent_witness, load, log, mul, neg, sqrt, sub) is
# byte-identical to the 0.18.9 capture; only copy (+3) and drop (+3) grew. The
# entry-reachable subgraph is unchanged: the 15 named loads match
# EXPECTED_LOADS exactly, the copy-elided semantic root is still `sub`, and the
# root output type is still tensor[n, f64]. The public entry keeps its Copy
# wrapper around the final Sub. This comparison does not certify shape
# semantics. The two independent cold lowerings are byte-deterministic. Former
# raw hashes: schema-6
# 0c85b5c010446f5704f4daa468b97916994668ff41b303968528ffe8b448fabe; schema-11
# 955c1df66a5731182646ae23d66d15308d4c63991810f41baf3ab425f48cabd2. Provenance:
# re-observed against the published Chelis 0.18.10 darwin binary at release
# prep and re-validated at the release gate; the gate fails closed on any
# mismatch of hash, root, node count, or schema.
# Schema-15 migration (published Chelis 0.18.11): +14 Copy and +14 Drop
# nodes; cmp_lt becomes compare with comparison=lt. All other op counts and
# the 15 reachable loads are unchanged. Copy-elided dataflow, op parameters,
# and precisions match 0.18.10 after that comparison rename. Internal symbolic
# dimension names changed, so this does not certify shape equivalence. Two
# independent cold lowerings reproduce the exact response below.
EXPECTED_RAW_SHA256 = "3be34d901db81b1a0b250d6cb6e8b8b934f11c13323206fb1894b50e9fcfab02"
FORBIDDEN_HOST_NAMES = ("vmap", "shape", "to_list", "map", "tensor_to_scalar")
EXPECTED_LOADS = {
    "a1",
    "a2",
    "a3",
    "a4",
    "a5",
    "half",
    "inv_sqrt_2",
    "k",
    "p",
    "r",
    "s",
    "sigma",
    "small",
    "t",
    "two_over_sqrt_pi",
}
# Exact version, checked against each published compiler during a pin bump.
WIRE_DAG_SCHEMA_VERSION = 15
WIRE_OPS = {
    "add",
    "cast",
    "compare",
    "const",
    "copy",
    "div",
    "drop",
    "exp",
    "load",
    "log",
    "mul",
    "neg",
    "sqrt",
    "sub",
}


class ValidationError(ValueError):
    """The lowering response is not the promised WireDag boundary."""


def pinned_compiler() -> str:
    manifest = (ROOT / "reef.toml").read_text(encoding="utf-8")
    match = re.search(r'^compiler\s*=\s*"=([^"]+)"', manifest, re.MULTILINE)
    if match is None:
        raise ValidationError("reef.toml omitted its exact compiler pin")
    return match.group(1)


def require_pinned_chelis(chelis: str) -> None:
    expected = pinned_compiler()
    completed = subprocess.run(
        [chelis, "--version"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        timeout=10,
    )
    observed = completed.stdout.strip()
    if completed.returncode != 0 or observed != f"chelis {expected}":
        raise ValidationError(
            f"compiler mismatch: reef.toml pins chelis {expected}, observed {observed!r}"
        )


def validate_response(
    response: object,
    expected_loads: set[str] = EXPECTED_LOADS,
    # `sub` since the chelis 0.18.6 pin: the Black-Scholes payoff's final
    # `S*N(d1) - K*exp(-rT)*N(d2)` lowered as `add(x, neg(y))` through 0.18.5
    # and is now the direct [05-OP-40] `sub` identity (chelis#1306).
    expected_root_op: str = "sub",
    expected_entry_root: int = EXPECTED_ENTRY_ROOT,
    expected_node_count: int = EXPECTED_NODE_COUNT,
) -> tuple[int, int]:
    if not isinstance(response, dict) or response.get("ok") is not True:
        raise ValidationError(
            f"Chelis rejected {ENTRY}: {json.dumps(response, sort_keys=True)}"
        )
    result = response.get("result")
    if not isinstance(result, dict):
        raise ValidationError("Chelis lower response omitted its result")
    dag = result.get("dag")
    named_roots = result.get("named_roots")
    if not isinstance(dag, dict) or not isinstance(named_roots, dict):
        raise ValidationError("Chelis lower response omitted dag/named_roots")
    if dag.get("schema_version") != WIRE_DAG_SCHEMA_VERSION:
        raise ValidationError(
            f"unexpected WireDag schema {dag.get('schema_version')!r}; "
            f"expected {WIRE_DAG_SCHEMA_VERSION}"
        )

    nodes = dag.get("nodes")
    roots = dag.get("roots")
    root = named_roots.get(ENTRY)
    if not isinstance(nodes, list) or not nodes:
        raise ValidationError("WireDag is empty")
    if len(nodes) != expected_node_count:
        raise ValidationError(
            f"WireDag node count drifted: expected {expected_node_count}, got {len(nodes)}"
        )
    if not isinstance(roots, list) or any(
        not isinstance(item, int) or isinstance(item, bool) for item in roots
    ):
        raise ValidationError("WireDag roots must be integer node IDs")
    if len(roots) != len(set(roots)):
        raise ValidationError("WireDag roots contain duplicates")
    if not isinstance(root, int) or isinstance(root, bool) or root not in roots:
        raise ValidationError(f"{ENTRY} is not an addressable WireDag root")
    if root != expected_entry_root:
        raise ValidationError(
            f"{ENTRY} root drifted: expected {expected_entry_root}, got {root}"
        )

    by_id: dict[int, dict[str, object]] = {}
    for node in nodes:
        if not isinstance(node, dict):
            raise ValidationError("WireDag contains a non-object node")
        node_id = node.get("id")
        if not isinstance(node_id, int) or isinstance(node_id, bool):
            raise ValidationError("WireDag node omitted an integer ID")
        if node_id in by_id:
            raise ValidationError(f"WireDag contains duplicate node ID {node_id}")
        by_id[node_id] = node
    missing_roots = sorted(set(roots) - set(by_id))
    if missing_roots:
        raise ValidationError(f"WireDag roots reference missing nodes {missing_roots}")
    for name, named_root in named_roots.items():
        if (
            not isinstance(name, str)
            or not isinstance(named_root, int)
            or isinstance(named_root, bool)
        ):
            raise ValidationError(
                "WireDag named roots must map names to integer node IDs"
            )
        if named_root not in roots or named_root not in by_id:
            raise ValidationError(f"WireDag named root {name!r} is dangling")

    for node_id, node in by_id.items():
        inputs = node.get("inputs")
        if not isinstance(inputs, list) or any(
            not isinstance(item, int) or isinstance(item, bool) for item in inputs
        ):
            raise ValidationError(f"WireDag node {node_id} has invalid inputs")
        missing_inputs = sorted(set(inputs) - set(by_id))
        if missing_inputs:
            raise ValidationError(
                f"WireDag node {node_id} references missing inputs {missing_inputs}"
            )
        non_topological = [item for item in inputs if item >= node_id]
        if non_topological:
            raise ValidationError(
                f"WireDag node {node_id} has non-topological inputs {non_topological}"
            )

    reachable: set[int] = set()
    reachable_loads: set[str] = set()
    pending = [root]
    while pending:
        node_id = pending.pop()
        if node_id in reachable:
            continue
        reachable.add(node_id)
        node = by_id[node_id]
        op = node.get("op")
        kind = op.get("kind") if isinstance(op, dict) else None
        if kind not in WIRE_OPS:
            raise ValidationError(
                f"{ENTRY} reaches unsupported/host-only op {kind!r} at node {node_id}"
            )
        if kind == "compare" and op.get("comparison") != "lt":
            raise ValidationError(
                f"{ENTRY} comparison drifted at node {node_id}: {op!r}"
            )
        if kind == "load":
            name = op.get("name")
            if not isinstance(name, str):
                raise ValidationError(f"WireDag load {node_id} omitted its name")
            reachable_loads.add(name)
        pending.extend(node["inputs"])

    if reachable_loads != expected_loads:
        missing = sorted(expected_loads - reachable_loads)
        unexpected = sorted(reachable_loads - expected_loads)
        raise ValidationError(
            f"{ENTRY} reachable loads drifted: missing={missing}, unexpected={unexpected}"
        )

    output_type = by_id[root].get("output_type")
    expected_dim = {"kind": "named", "name": "n", "size": None}
    if not isinstance(output_type, dict) or output_type.get("precision") != "f64":
        raise ValidationError(f"{ENTRY} root is not f64")
    if output_type.get("dims") != [expected_dim]:
        raise ValidationError(f"{ENTRY} root is not tensor[n, f64]")
    semantic_root = root
    while by_id[semantic_root].get("op", {}).get("kind") == "copy":
        inputs = by_id[semantic_root]["inputs"]
        if len(inputs) != 1:
            raise ValidationError(f"{ENTRY} root Copy must have one input")
        semantic_root = inputs[0]
    root_op = by_id[semantic_root].get("op")
    root_kind = root_op.get("kind") if isinstance(root_op, dict) else None
    if root_kind != expected_root_op:
        raise ValidationError(
            f"{ENTRY} root op drifted: expected {expected_root_op!r}, got {root_kind!r}"
        )
    return root, len(nodes)


def validate_corruption_controls() -> None:
    valid = {
        "ok": True,
        "result": {
            "dag": {
                "schema_version": WIRE_DAG_SCHEMA_VERSION,
                "nodes": [
                    {
                        "id": 7,
                        "op": {"kind": "load", "name": "spot"},
                        "inputs": [],
                        "output_type": {
                            "dims": [{"kind": "named", "name": "n", "size": None}],
                            "precision": "f64",
                        },
                    }
                ],
                "roots": [7],
            },
            "named_roots": {ENTRY: 7},
        },
    }
    corruptions = []
    for label in (
        "schema",
        "dangling-root",
        "duplicate-node",
        "host-op",
        "dangling-input",
        "non-topological-input",
        "unexpected-load",
        "redirected-root",
    ):
        candidate = json.loads(json.dumps(valid))
        if label == "schema":
            candidate["result"]["dag"]["schema_version"] = 999
        elif label == "dangling-root":
            candidate["result"]["dag"]["roots"] = [42]
            candidate["result"]["named_roots"][ENTRY] = 42
        elif label == "duplicate-node":
            candidate["result"]["dag"]["nodes"].append(
                json.loads(json.dumps(candidate["result"]["dag"]["nodes"][0]))
            )
        elif label == "host-op":
            candidate["result"]["dag"]["nodes"][0]["op"] = {"kind": "host_only"}
        elif label == "dangling-input":
            candidate["result"]["dag"]["nodes"][0]["inputs"] = [42]
        elif label == "non-topological-input":
            candidate["result"]["dag"]["nodes"][0]["inputs"] = [7]
        elif label == "unexpected-load":
            candidate["result"]["dag"]["nodes"][0]["op"]["name"] = "invented"
        else:
            redirected = json.loads(json.dumps(candidate["result"]["dag"]["nodes"][0]))
            redirected["id"] = 8
            redirected["op"] = {"kind": "add"}
            redirected["inputs"] = [7, 7]
            candidate["result"]["dag"]["nodes"].append(redirected)
            candidate["result"]["dag"]["roots"].append(8)
            candidate["result"]["named_roots"][ENTRY] = 8
        corruptions.append((label, candidate))
    for label, candidate in corruptions:
        try:
            validate_response(
                candidate,
                expected_loads={"spot"},
                expected_root_op="load",
                expected_entry_root=7,
                expected_node_count=1,
            )
        except ValidationError:
            continue
        raise ValidationError(f"validator accepted its {label} corruption control")

    comparison = json.loads(json.dumps(valid))
    dag = comparison["result"]["dag"]
    tensor_type = dag["nodes"][0]["output_type"]
    dag["nodes"].extend([
        {"id": 8, "op": {"kind": "compare", "comparison": "lt"},
         "inputs": [7, 7], "output_type": {**tensor_type, "precision": "bool"}},
        {"id": 9, "op": {"kind": "cast", "precision": "f64"},
         "inputs": [8], "output_type": tensor_type},
    ])
    dag["roots"] = [9]
    comparison["result"]["named_roots"][ENTRY] = 9
    options = dict(expected_loads={"spot"}, expected_root_op="cast",
                   expected_entry_root=9, expected_node_count=3)
    validate_response(comparison, **options)
    for op in ({"kind": "compare", "comparison": "ge"},
               {"kind": "compare"}, {"kind": "cmp_lt"}):
        candidate = json.loads(json.dumps(comparison))
        candidate["result"]["dag"]["nodes"][1]["op"] = op
        try:
            validate_response(candidate, **options)
        except ValidationError:
            continue
        raise ValidationError(f"validator accepted comparison corruption {op!r}")


def fail(message: str, server_log: str = "") -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    if server_log:
        print(server_log, file=sys.stderr)
    return 1


def lower_once(chelis: str, source: str) -> bytes:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    process = subprocess.Popen(
        [chelis, "tide", "serve", "--host", "127.0.0.1", "--port", str(port)],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/lower",
        data=json.dumps(
            {"source_kind": "surf", "source": source, "entry": ENTRY}
        ).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        deadline = time.monotonic() + 15.0
        while time.monotonic() < deadline:
            if process.poll() is not None:
                log = process.stdout.read() if process.stdout else ""
                raise ValidationError(
                    f"chelis tide exited before accepting requests\n{log}"
                )
            try:
                with urllib.request.urlopen(request, timeout=5.0) as handle:
                    return handle.read()
            except (urllib.error.URLError, ConnectionError):
                time.sleep(0.05)
        raise ValidationError("timed out waiting for the Chelis lower endpoint")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5.0)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5.0)


def main() -> int:
    chelis = os.environ.get("CHELIS_BIN") or shutil.which("chelis")
    if not chelis:
        return fail("chelis binary not found (set CHELIS_BIN or PATH)")
    try:
        require_pinned_chelis(chelis)
        validate_corruption_controls()
    except (OSError, subprocess.SubprocessError, ValidationError) as error:
        return fail(str(error))

    source = (ROOT / "src/pricing.ch").read_text(encoding="utf-8")
    marker = "-- Pure tensor-DAG Black-Scholes helpers for the Beacon seam"
    start = source.find(marker)
    end = source.find("def bs_call_f64_vector", start)
    if start < 0 or end < 0:
        return fail("could not isolate the WireDag entry closure")
    closure = source[start:end]
    found = [
        name
        for name in FORBIDDEN_HOST_NAMES
        if re.search(rf"\b{re.escape(name)}\s*\(", closure)
    ]
    if found:
        return fail(f"host-only construct(s) entered the WireDag closure: {found}")

    try:
        raw_responses = [lower_once(chelis, source), lower_once(chelis, source)]
    except (OSError, subprocess.SubprocessError, ValidationError) as error:
        return fail(str(error))
    if raw_responses[0] != raw_responses[1]:
        return fail("independent cold lowerings were not byte-deterministic")
    try:
        response = json.loads(raw_responses[0])
        root, node_count = validate_response(response)
    except (json.JSONDecodeError, ValidationError) as error:
        return fail(str(error))
    digest = hashlib.sha256(raw_responses[0]).hexdigest()
    if digest != EXPECTED_RAW_SHA256:
        return fail(
            f"WireDag raw artifact drifted: expected {EXPECTED_RAW_SHA256}, got {digest}"
        )

    print(
        f"Shoals WireDag OK: entry={ENTRY} root={root} "
        f"nodes={node_count} schema={WIRE_DAG_SCHEMA_VERSION} sha256={digest}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
