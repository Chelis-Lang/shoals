#!/usr/bin/env python3
"""Unit tests for the canonical Shoals release builder (chelis#1002)."""

from __future__ import annotations

import importlib.util
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "build_release_assets", ROOT / "scripts/build_release_assets.py"
)
BUILDER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(BUILDER)
DETERMINISM_SPEC = importlib.util.spec_from_file_location(
    "check_release_artifact_determinism",
    ROOT / "scripts/check_release_artifact_determinism.py",
)
DETERMINISM = importlib.util.module_from_spec(DETERMINISM_SPEC)
assert DETERMINISM_SPEC.loader is not None
DETERMINISM_SPEC.loader.exec_module(DETERMINISM)


class BuildReleaseAssetsTests(unittest.TestCase):
    def test_determinism_candidate_excludes_local_registry_state(self) -> None:
        with tempfile.TemporaryDirectory() as raw_tmp:
            root = Path(raw_tmp)
            source = root / "source"
            source.mkdir()
            (source / "reef.toml").write_text("[package]\nname = \"shoals\"\n")
            (source / "reef.lock").write_text("poisoned lock")
            (source / ".venv").mkdir()
            (source / ".venv" / "marker").write_text("poisoned environment")
            (source / "src").mkdir()
            (source / "src" / "pricing.ch").write_text("module Shoals.Pricing\n")
            with mock.patch.object(DETERMINISM, "ROOT", source):
                candidate = DETERMINISM.copy_candidate(root / "candidate")
            self.assertTrue((candidate / "reef.toml").is_file())
            self.assertTrue((candidate / "src" / "pricing.ch").is_file())
            self.assertFalse((candidate / "reef.lock").exists())
            self.assertFalse((candidate / ".venv").exists())

    def test_canonical_dependency_coordinates_are_lowercase(self) -> None:
        with tempfile.TemporaryDirectory() as raw_tmp:
            package = Path(raw_tmp)
            (package / "reef.toml").write_text(
                """\
[package]
name = "shoals"
version = "0.24.4"
compiler = "=0.17.5"
[dependencies]
chelis-std = { version = "0.4.0" }
nautilus = { version = "0.7.37" }
coral = { version = "0.7.34" }
shoreleave = { version = "0.1.0" }
"""
            )
            self.assertEqual(
                BUILDER.release_coordinates(package),
                [
                    "chelis-lang/nautilus@v0.7.37",
                    "chelis-lang/coral@v0.7.34",
                    "chelis-lang/shoreleave@v0.1.0",
                ],
            )

    def test_builder_uses_fresh_registry_and_replaces_mixed_case_lock(self) -> None:
        with tempfile.TemporaryDirectory() as raw_tmp:
            package = Path(raw_tmp)
            (package / "reef.toml").write_text(
                """\
[package]
name = "shoals"
version = "0.24.4"
compiler = "=0.17.5"
[dependencies]
nautilus = { version = "0.7.37" }
coral = { version = "0.7.34" }
"""
            )
            lock = package / "reef.lock"
            lock.write_text(
                """\
[package]
name = "shoals"
version = "0.24.4"
[[dependencies]]
name = "nautilus"
version = "0.7.37"
archive_sha256 = "official archive"
shell_sha256 = "official shell"
[dependencies.source]
kind = "local_registry"
remote_origin = "github://Chelis-Lang/nautilus@v0.7.37"
"""
            )
            registry_paths: list[str] = []

            def fake_run(command, **kwargs):
                registry_paths.append(kwargs["env"]["CHELIS_REEF_HOME"])
                if "build" in command:
                    self.assertFalse(lock.exists())
                    lock.write_text(
                        """\
[package]
name = "shoals"
version = "0.24.4"
[[dependencies]]
name = "nautilus"
version = "0.7.37"
archive_sha256 = "official archive"
shell_sha256 = "official shell"
[dependencies.source]
kind = "local_registry"
remote_origin = "github://chelis-lang/nautilus@v0.7.37"
[[dependencies]]
name = "coral"
version = "0.7.34"
[dependencies.source]
kind = "local_registry"
remote_origin = "github://chelis-lang/coral@v0.7.34"
"""
                    )
                return mock.Mock(returncode=0, stdout="", stderr="")

            with mock.patch.dict(BUILDER.os.environ, {"CHELIS_REEF_HOME": "/poison"}):
                with mock.patch.object(BUILDER.subprocess, "run", side_effect=fake_run):
                    BUILDER.build("/bin/chelis", package)
            self.assertEqual(len(registry_paths), 3)
            self.assertEqual(len(set(registry_paths)), 1)
            self.assertNotEqual(registry_paths[0], "/poison")
            self.assertFalse(Path(registry_paths[0]).exists())
            self.assertIn("github://chelis-lang/nautilus", lock.read_text())

    def test_builder_rejects_noncanonical_generated_lock(self) -> None:
        with tempfile.TemporaryDirectory() as raw_tmp:
            package = Path(raw_tmp)
            (package / "reef.toml").write_text(
                """\
[package]
name = "shoals"
version = "0.24.4"
compiler = "=0.17.5"
[dependencies]
nautilus = { version = "0.7.37" }
coral = { version = "0.7.34" }
"""
            )
            (package / "dist").mkdir()
            stale_shell = package / "dist/shoals-0.24.4.chb"
            stale_archive = package / "dist/shoals-0.24.4.tar.zst"
            stale_shell.write_bytes(b"stale shell")
            stale_archive.write_bytes(b"stale archive")
            commands: list[list[str]] = []

            def fake_run(command, **kwargs):
                commands.append(command)
                if command[1:3] == ["reef", "build"]:
                    self.assertFalse(stale_shell.exists())
                    self.assertFalse(stale_archive.exists())
                    (package / "reef.lock").write_text(
                        """\
[package]
name = "shoals"
version = "0.24.4"
[[dependencies]]
name = "nautilus"
version = "0.7.37"
[dependencies.source]
kind = "local_registry"
remote_origin = "github://Chelis-Lang/nautilus@v0.7.37"
[[dependencies]]
name = "coral"
version = "0.7.34"
[dependencies.source]
kind = "local_registry"
remote_origin = "github://chelis-lang/coral@v0.7.34"
"""
                    )
                return mock.Mock(returncode=0, stdout="", stderr="")

            with mock.patch.object(BUILDER.subprocess, "run", side_effect=fake_run):
                with self.assertRaisesRegex(RuntimeError, "non-canonical"):
                    BUILDER.build("/bin/chelis", package)

        self.assertEqual(
            commands[:2],
            [
                ["/bin/chelis", "reef", "install", "--from-github",
                 "chelis-lang/nautilus@v0.7.37"],
                ["/bin/chelis", "reef", "install", "--from-github",
                 "chelis-lang/coral@v0.7.34"],
            ],
        )
        self.assertEqual(
            commands[2],
            ["/bin/chelis", "reef", "build", "--no-auto-fetch", str(package)],
        )

    def test_lock_validator_preserves_official_hashes(self) -> None:
        lock = tomllib.loads(
            """\
[package]
name = "shoals"
version = "0.24.4"
[[dependencies]]
name = "nautilus"
version = "0.7.37"
archive_sha256 = "archive"
shell_sha256 = "shell"
[dependencies.source]
kind = "local_registry"
remote_origin = "github://chelis-lang/nautilus@v0.7.37"
"""
        )
        BUILDER.validate_canonical_lock(
            lock,
            {"nautilus": ("0.7.37", "archive", "shell")},
        )
        with self.assertRaisesRegex(RuntimeError, "archive hash"):
            BUILDER.validate_canonical_lock(
                lock,
                {"nautilus": ("0.7.37", "wrong", "shell")},
            )


if __name__ == "__main__":
    unittest.main()
