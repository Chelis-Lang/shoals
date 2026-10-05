#!/usr/bin/env python3
"""Adversarial cross-registry release determinism oracle (chelis#1002).

One fresh Reef home is deliberately seeded through mixed-case manual GitHub
coordinates. A second starts clean. Both then use Shoals' canonical release
builder. The generated lock, CHB, and archive must converge byte-for-byte.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_SUFFIXES = ("chb", "tar.zst")


def checked_run(command: list[str], *, cwd: Path, env: dict[str, str]) -> None:
    completed = subprocess.run(
        command, cwd=cwd, env=env, capture_output=True, text=True, check=False
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"command failed ({completed.returncode}): {' '.join(command)}\n"
            f"{completed.stdout}{completed.stderr}"
        )


def copy_candidate(destination: Path) -> Path:
    package = destination / "shoals"
    ignored = shutil.ignore_patterns(
        ".git", ".venv", "reef.lock", ".reef-write.lock", "dist",
        "__pycache__", ".gate-tmp", "target",
    )
    shutil.copytree(ROOT, package, ignore=ignored)
    return package


def versions(package: Path) -> tuple[str, str, dict[str, str]]:
    with (package / "reef.toml").open("rb") as source:
        reef = tomllib.load(source)
    info = reef["package"]
    deps = reef["dependencies"]
    return (
        info["compiler"].removeprefix("="),
        info["version"],
        {
            name: spec["version"]
            for name, spec in deps.items()
            if name != "chelis-std"
        },
    )


def payloads(package: Path, version: str) -> dict[str, bytes]:
    paths = {"reef.lock": package / "reef.lock"}
    paths.update({
        suffix: package / "dist" / f"shoals-{version}.{suffix}"
        for suffix in ARTIFACT_SUFFIXES
    })
    missing = [str(path) for path in paths.values() if not path.is_file()]
    if missing:
        raise RuntimeError(f"release builder omitted payloads: {missing}")
    return {name: path.read_bytes() for name, path in paths.items()}


def main() -> int:
    binary = os.environ.get("CHELIS_BIN") or shutil.which("chelis")
    if not binary:
        print("FAIL: set CHELIS_BIN or put the pinned chelis on PATH", file=sys.stderr)
        return 1
    try:
        with tempfile.TemporaryDirectory(prefix="shoals-1002-determinism-") as raw:
            temp = Path(raw)
            poisoned = copy_candidate(temp / "mixed-case-manual")
            clean = copy_candidate(temp / "clean-canonical")
            compiler, version, dependencies = versions(poisoned)
            got = subprocess.run(
                [binary, "--version"], capture_output=True, text=True, check=False
            ).stdout.strip()
            if got != f"chelis {compiler}":
                raise RuntimeError(f"resolved binary reports {got!r}, expected chelis {compiler}")

            results: dict[str, dict[str, bytes]] = {}
            for lane, package in (("mixed-case-manual", poisoned),
                                  ("clean-canonical", clean)):
                env = os.environ.copy()
                env["CHELIS_BIN"] = binary
                env["CHELIS_REEF_HOME"] = str(temp / f"reef-{lane}")
                if lane == "mixed-case-manual":
                    for name, dep_version in dependencies.items():
                        checked_run(
                            [binary, "reef", "install", "--from-github",
                             f"Chelis-Lang/{name}@v{dep_version}"],
                            cwd=package,
                            env=env,
                        )
                checked_run(
                    [sys.executable, "scripts/build_release_assets.py"],
                    cwd=package,
                    env=env,
                )
                results[lane] = payloads(package, version)

            mismatches = [
                name for name in results["mixed-case-manual"]
                if results["mixed-case-manual"][name]
                != results["clean-canonical"][name]
            ]
            if mismatches:
                detail = ", ".join(
                    f"{name}: mixed={hashlib.sha256(results['mixed-case-manual'][name]).hexdigest()} "
                    f"clean={hashlib.sha256(results['clean-canonical'][name]).hexdigest()}"
                    for name in mismatches
                )
                raise RuntimeError(
                    f"cross-registry release payloads diverged ({detail}); chelis#1002"
                )
            digests = {
                name: hashlib.sha256(value).hexdigest()
                for name, value in results["clean-canonical"].items()
            }
    except (OSError, KeyError, RuntimeError, tomllib.TOMLDecodeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    print("OK: mixed-case-manual and clean-canonical registries converge")
    for name, digest in digests.items():
        print(f"  {name}: {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
