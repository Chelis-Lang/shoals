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


class BuildReleaseAssetsTests(unittest.TestCase):
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
"""
            )
            self.assertEqual(
                BUILDER.release_coordinates(package),
                [
                    "chelis-lang/nautilus@v0.7.37",
                    "chelis-lang/coral@v0.7.34",
                ],
            )

    def test_builder_reinstalls_before_build_and_rejects_noncanonical_lock(self) -> None:
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
                if command[-3:] == ["reef", "build", str(package)]:
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
        self.assertEqual(commands[2], ["/bin/chelis", "reef", "build", str(package)])

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
