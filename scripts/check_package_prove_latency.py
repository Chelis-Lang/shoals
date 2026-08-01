#!/usr/bin/env python3
"""Release oracle for chelis#924 package-graph preparation latency.

The script installs the released Nautilus and Coral dependencies plus the
already-built Shoals candidate into a disposable Reef registry, builds a
disposable consumer package, then proves the same trivial property with an
isolated cold prepared-graph cache and an unchanged warm cache. Process wall
time includes finalization: a verdict printed by a process that remains alive
does not pass.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COLD_LIMIT_SECONDS = 20.0
WARM_LIMIT_SECONDS = 5.0
PROPERTY = "issue_924_trivial_zero"


def manifest_values() -> tuple[str, str]:
    compiler = package = None
    for raw in (ROOT / "reef.toml").read_text().splitlines():
        line = raw.strip()
        if line.startswith("version =") and package is None:
            package = line.split('"', 2)[1]
        elif line.startswith("compiler ="):
            compiler = line.split('"', 2)[1].removeprefix("=")
    if not compiler or not package:
        raise RuntimeError("could not resolve compiler/package versions from reef.toml")
    return compiler, package


def resolve_binary(expected: str) -> str:
    binary = os.environ.get("CHELIS_BIN") or shutil.which("chelis")
    if not binary:
        raise RuntimeError("set CHELIS_BIN or put chelis on PATH")
    got = subprocess.run(
        [binary, "--version"], capture_output=True, text=True, check=True
    ).stdout.strip()
    if got != f"chelis {expected}":
        raise RuntimeError(f"resolved binary reports {got!r}, expected chelis {expected}")
    return binary


def dependency_releases() -> list[str]:
    with (ROOT / "reef.toml").open("rb") as source:
        manifest = tomllib.load(source)
    dependencies = manifest.get("dependencies", {})
    releases: list[str] = []
    for name in ("nautilus", "coral"):
        spec = dependencies.get(name)
        version = spec.get("version") if isinstance(spec, dict) else None
        if not isinstance(version, str):
            raise RuntimeError(f"reef.toml has no exact {name} dependency version")
        # Keep registry provenance canonical until chelis#1002 is fixed.
        releases.append(f"chelis-lang/{name}@v{version}")
    return releases


def checked_run(
    command: list[str], *, env: dict[str, str], label: str, cwd: Path = ROOT
) -> None:
    proc = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"{label} failed\n{proc.stdout}{proc.stderr}")


def install_candidate(
    binary: str, version: str, *, env: dict[str, str]
) -> None:
    expected = [
        ROOT / "dist" / f"shoals-{version}.chb",
        ROOT / "dist" / f"shoals-{version}.tar.zst",
    ]
    missing = [str(path) for path in expected if not path.is_file()]
    if missing:
        raise RuntimeError(
            f"build Shoals before running the latency oracle; missing {missing}"
        )
    for release in dependency_releases():
        checked_run(
            [binary, "reef", "install", "--from-github", release],
            env=env,
            label=f"official dependency install {release}",
        )
    with tempfile.TemporaryDirectory(prefix="shoals-924-monorepo-") as tmp:
        packages = Path(tmp) / "packages"
        packages.mkdir()
        (packages / "shoals").symlink_to(ROOT, target_is_directory=True)
        checked_run(
            [
                binary,
                "reef",
                "install",
                "--from-monorepo",
                tmp,
                f"shoals={version}",
            ],
            env=env,
            label="current Shoals candidate install",
        )


def run_timed(cmd: list[str], *, cwd: Path, env: dict[str, str]) -> tuple[float, bytes]:
    started = time.monotonic()
    proc = subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=COLD_LIMIT_SECONDS + 10.0,
    )
    elapsed = time.monotonic() - started
    if proc.returncode != 0:
        raise RuntimeError(
            f"prove exited {proc.returncode} after {elapsed:.3f}s\n"
            f"stdout:\n{proc.stdout.decode(errors='replace')}\n"
            f"stderr:\n{proc.stderr.decode(errors='replace')}"
        )
    return elapsed, proc.stdout


def validate_ndjson(payload: bytes) -> None:
    records = [json.loads(line) for line in payload.splitlines() if line.strip()]
    prop = next(
        (
            row
            for row in records
            if row.get("kind") == "property" and row.get("name") == PROPERTY
        ),
        None,
    )
    if prop is None:
        raise RuntimeError(f"no {PROPERTY!r} property record in prove output")
    if prop.get("status") != "passed" or prop.get("proof_tier") != "smt":
        raise RuntimeError(f"unexpected property verdict: {prop}")
    if not any(row.get("kind") == "summary" for row in records):
        raise RuntimeError("prove output has no final summary record")


def validate_pair(cold: float, warm: float, cold_out: bytes, warm_out: bytes) -> str:
    validate_ndjson(cold_out)
    validate_ndjson(warm_out)
    if cold_out != warm_out:
        raise RuntimeError("cold and warm prove NDJSON are not byte-identical")
    if cold > COLD_LIMIT_SECONDS:
        raise RuntimeError(
            f"cold prove took {cold:.3f}s (limit {COLD_LIMIT_SECONDS:.1f}s)"
        )
    if warm > WARM_LIMIT_SECONDS:
        raise RuntimeError(
            f"warm prove took {warm:.3f}s (limit {WARM_LIMIT_SECONDS:.1f}s)"
        )
    return hashlib.sha256(cold_out).hexdigest()


def main() -> int:
    compiler, shoals = manifest_values()
    binary = resolve_binary(compiler)
    with tempfile.TemporaryDirectory(prefix="shoals-924-consumer-") as tmp:
        package = Path(tmp)
        env = os.environ.copy()
        env["CHELIS_REEF_HOME"] = str(package / "isolated-reef")
        env["XDG_CACHE_HOME"] = str(package / "isolated-cache")
        install_candidate(binary, shoals, env=env)
        (package / "src").mkdir()
        (package / "reef.toml").write_text(
            f"""\
[package]
name = "shoals-latency-oracle"
version = "0.1.0"
compiler = "={compiler}"
module_prefix = "ShoalsLatencyOracle"

[dependencies]
shoals = {{ version = "{shoals}" }}
"""
        )
        (package / "src" / "main.ch").write_text(
            f"""\
module ShoalsLatencyOracle.Main

import Shoals.Pricing (bs_call_scalar)

def price_at_one() -> f32 =
  bs_call_scalar(cast(1.0, f32), cast(1.0, f32), cast(0.02, f32),
                 cast(0.2, f32), cast(1.0, f32))

@property {PROPERTY} forall(x: f32):
  ((x * 0.0) == 0.0)
"""
        )

        build = subprocess.run(
            [binary, "reef", "build", "."],
            cwd=package,
            env=env,
            capture_output=True,
            text=True,
        )
        if build.returncode != 0:
            raise RuntimeError(
                f"consumer build failed\n{build.stdout}{build.stderr}"
            )

        cmd = [
            binary,
            "prove",
            "src/main.ch",
            "--json",
            "--tier",
            "smt-only",
            "--package",
            ".",
        ]
        cold, cold_out = run_timed(cmd, cwd=package, env=env)
        warm, warm_out = run_timed(cmd, cwd=package, env=env)
        digest = validate_pair(cold, warm, cold_out, warm_out)
        print(
            f"PASS chelis#924: cold={cold:.3f}s <= {COLD_LIMIT_SECONDS:.1f}s; "
            f"warm={warm:.3f}s <= {WARM_LIMIT_SECONDS:.1f}s; "
            f"byte-identical NDJSON sha256={digest}"
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print(f"FAIL chelis#924: {exc}", file=sys.stderr)
        raise SystemExit(1)
