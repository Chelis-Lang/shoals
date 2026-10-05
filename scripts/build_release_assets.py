#!/usr/bin/env python3
"""Build Shoals release artifacts from canonical dependency provenance.

Chelis preserves caller-provided GitHub owner casing in Reef registry metadata
and packages that string into ``reef.lock`` (chelis#1002). Until the compiler
canonicalizes it, build in a fresh registry populated through canonical
lowercase coordinates and reject any non-canonical generated lockfile.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEPENDENCY_ORDER = ("nautilus", "coral")
CANONICAL_ORG = "chelis-lang"


def manifest(package_root: Path) -> dict:
    with (package_root / "reef.toml").open("rb") as source:
        return tomllib.load(source)


def dependency_versions(package_root: Path) -> dict[str, str]:
    dependencies = manifest(package_root).get("dependencies", {})
    versions: dict[str, str] = {}
    for name in DEPENDENCY_ORDER:
        spec = dependencies.get(name)
        version = spec.get("version") if isinstance(spec, dict) else None
        if not isinstance(version, str):
            raise RuntimeError(f"reef.toml has no exact {name} dependency version")
        versions[name] = version
    return versions


def package_identity(package_root: Path) -> tuple[str, str]:
    info = manifest(package_root).get("package", {})
    name = info.get("name")
    version = info.get("version")
    if not isinstance(name, str) or not isinstance(version, str):
        raise RuntimeError("reef.toml has no exact package name/version")
    return name, version


def release_coordinates(package_root: Path) -> list[str]:
    return [
        f"{CANONICAL_ORG}/{name}@v{version}"
        for name, version in dependency_versions(package_root).items()
    ]


def resolve_binary(package_root: Path) -> str:
    binary = os.environ.get("CHELIS_BIN") or shutil.which("chelis")
    if not binary:
        raise RuntimeError("set CHELIS_BIN or put the pinned chelis on PATH")
    compiler = manifest(package_root)["package"]["compiler"].removeprefix("=")
    completed = subprocess.run(
        [binary, "--version"], capture_output=True, text=True, check=False
    )
    got = completed.stdout.strip()
    if completed.returncode != 0 or got != f"chelis {compiler}":
        raise RuntimeError(f"resolved binary reports {got!r}, expected chelis {compiler}")
    return binary


def checked_run(command: list[str], *, cwd: Path, env: dict[str, str]) -> None:
    completed = subprocess.run(
        command, cwd=cwd, env=env, capture_output=True, text=True, check=False
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"command failed ({completed.returncode}): {' '.join(command)}\n"
            f"{completed.stdout}{completed.stderr}"
        )


def expected_dependency_identity(
    package_root: Path,
) -> dict[str, tuple[str, str | None, str | None]]:
    """Return versions and any pre-build official hashes to preserve.

    A prior lock is supporting evidence only: a build may start without one.
    When it exists, regeneration must not change either official dependency
    artifact hash while rewriting the provenance spelling.
    """
    versions = dependency_versions(package_root)
    lock_path = package_root / "reef.lock"
    previous: dict[str, dict] = {}
    if lock_path.is_file():
        with lock_path.open("rb") as source:
            lock = tomllib.load(source)
        previous = {
            dep.get("name"): dep
            for dep in lock.get("dependencies", [])
            if isinstance(dep, dict) and dep.get("name") in versions
        }
    return {
        name: (
            version,
            previous.get(name, {}).get("archive_sha256"),
            previous.get(name, {}).get("shell_sha256"),
        )
        for name, version in versions.items()
    }


def validate_canonical_lock(
    lock: dict,
    expected: dict[str, tuple[str, str | None, str | None]],
) -> None:
    entries = {
        dep.get("name"): dep
        for dep in lock.get("dependencies", [])
        if isinstance(dep, dict)
    }
    for name, (version, archive_hash, shell_hash) in expected.items():
        dep = entries.get(name)
        if dep is None:
            raise RuntimeError(f"generated reef.lock omitted dependency {name}")
        if dep.get("version") != version:
            raise RuntimeError(
                f"generated reef.lock changed {name} version: {dep.get('version')!r}"
            )
        wanted_origin = f"github://{CANONICAL_ORG}/{name}@v{version}"
        got_origin = dep.get("source", {}).get("remote_origin")
        if got_origin != wanted_origin:
            raise RuntimeError(
                f"generated reef.lock has non-canonical {name} origin "
                f"{got_origin!r}; expected {wanted_origin!r} (chelis#1002)"
            )
        if archive_hash is not None and dep.get("archive_sha256") != archive_hash:
            raise RuntimeError(f"canonicalization changed {name} archive hash")
        if shell_hash is not None and dep.get("shell_sha256") != shell_hash:
            raise RuntimeError(f"canonicalization changed {name} shell hash")


def build(binary: str, package_root: Path) -> None:
    expected = expected_dependency_identity(package_root)
    lock_path = package_root / "reef.lock"
    prior_lock = lock_path.read_bytes() if lock_path.is_file() else None
    # A lowercase reinstall does not rewrite the remote_origin of an already
    # installed mixed-case entry. A fresh registry closes that state leak.
    with tempfile.TemporaryDirectory(prefix="shoals-release-reef-") as raw:
        env = os.environ.copy()
        env["CHELIS_REEF_HOME"] = raw
        for coordinate in release_coordinates(package_root):
            checked_run(
                [binary, "reef", "install", "--from-github", coordinate],
                cwd=package_root,
                env=env,
            )
        try:
            # Reef can retain a prior lock's origin and previously built dist
            # payload even after registry contents change. Re-resolve both from
            # this fresh registry, restoring the prior lock on failure.
            lock_path.unlink(missing_ok=True)
            name, version = package_identity(package_root)
            for suffix in ("chb", "tar.zst"):
                candidate = package_root / "dist" / f"{name}-{version}.{suffix}"
                if candidate.is_file():
                    candidate.unlink()
            checked_run(
                [binary, "reef", "build", "--no-auto-fetch", str(package_root)],
                cwd=package_root,
                env=env,
            )
            with lock_path.open("rb") as source:
                validate_canonical_lock(tomllib.load(source), expected)
        except BaseException:
            if prior_lock is None:
                lock_path.unlink(missing_ok=True)
            else:
                lock_path.write_bytes(prior_lock)
            raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-root", type=Path, default=ROOT)
    args = parser.parse_args()
    package_root = args.package_root.resolve()
    try:
        binary = resolve_binary(package_root)
        build(binary, package_root)
    except (OSError, KeyError, RuntimeError, tomllib.TOMLDecodeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print("OK: canonical release assets built (cross-registry narrowing: chelis#1002)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
