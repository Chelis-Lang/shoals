#!/usr/bin/env python3
"""Validate Shoals' real Black-Scholes entry at the Chelis WireDag boundary."""

from __future__ import annotations

import json
import os
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
FORBIDDEN_HOST_TOKENS = ("vmap(", "shape(", "to_list(", "map(", "tensor_to_scalar(")


def fail(message: str, server_log: str = "") -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    if server_log:
        print(server_log, file=sys.stderr)
    return 1


def main() -> int:
    chelis = os.environ.get("CHELIS_BIN") or shutil.which("chelis")
    if not chelis:
        return fail("chelis binary not found (set CHELIS_BIN or PATH)")

    source = (ROOT / "src/pricing.ch").read_text(encoding="utf-8")
    marker = "-- Pure tensor-DAG Black-Scholes helpers for the Beacon seam"
    start = source.find(marker)
    end = source.find("def bs_call_f64_vector", start)
    if start < 0 or end < 0:
        return fail("could not isolate the WireDag entry closure")
    closure = source[start:end]
    found = [token for token in FORBIDDEN_HOST_TOKENS if token in closure]
    if found:
        return fail(f"host-only token(s) entered the WireDag closure: {found}")

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
    response: dict[str, object] | None = None
    try:
        deadline = time.monotonic() + 15.0
        while time.monotonic() < deadline:
            if process.poll() is not None:
                log = process.stdout.read() if process.stdout else ""
                return fail("chelis tide exited before accepting requests", log)
            try:
                with urllib.request.urlopen(request, timeout=5.0) as handle:
                    response = json.load(handle)
                break
            except (urllib.error.URLError, ConnectionError):
                time.sleep(0.05)
        if response is None:
            return fail("timed out waiting for the Chelis lower endpoint")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5.0)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5.0)

    if response.get("ok") is not True:
        return fail(f"Chelis rejected {ENTRY}: {json.dumps(response, sort_keys=True)}")
    result = response.get("result")
    if not isinstance(result, dict):
        return fail("Chelis lower response omitted its result")
    dag = result.get("dag")
    named_roots = result.get("named_roots")
    if not isinstance(dag, dict) or not isinstance(named_roots, dict):
        return fail("Chelis lower response omitted dag/named_roots")
    nodes = dag.get("nodes")
    roots = dag.get("roots")
    root = named_roots.get(ENTRY)
    if not isinstance(nodes, list) or not nodes:
        return fail("WireDag is empty")
    if not isinstance(roots, list) or root not in roots:
        return fail(f"{ENTRY} is not an addressable WireDag root")

    print(
        f"Shoals WireDag OK: entry={ENTRY} root={root} "
        f"nodes={len(nodes)} schema={dag.get('schema_version')}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
