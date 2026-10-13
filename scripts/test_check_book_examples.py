#!/usr/bin/env python3
"""Short regressions for offline repository-signature checks."""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_book_examples as book


class SourceSignatureTests(unittest.TestCase):
    def check(self, text):
        with tempfile.TemporaryDirectory() as directory:
            page = Path(directory) / "example.md"
            page.write_text(text)
            with mock.patch.object(book, "module_exports", return_value=(
                {"price": "Shoals.Pricing", "datetime": "Shoreleave.DateTime"},
                {"price": "def price(spot: f64): f64 !{}"})), \
                    mock.patch.object(book.subprocess, "run", side_effect=AssertionError("runtime forbidden")), \
                    mock.patch.object(book, "resolve_chelis", side_effect=AssertionError("toolchain forbidden")), \
                    mock.patch.object(book.Checker, "write", side_effect=AssertionError("scratch forbidden")), \
                    contextlib.redirect_stdout(io.StringIO()) as output:
                result = book.source_signatures([page])
                return result, output.getvalue()

    def test_repository_signature_passes_without_runtime(self):
        code, output = self.check("```chelis\ndef price(spot: f64): f64 !{}\n```\n"
                                  "```chelis\nx = price(100.0f64)\n```\n")
        self.assertEqual(code, 0, output)
        self.assertIn("1 repository signatures", output)
        self.assertIn("runtime examples were not evaluated", output)

    def test_mismatched_and_unknown_signatures_fail(self):
        for declaration in ("def price(spot: f32): f64 !{}", "def prcie(spot: f64): f64 !{}"):
            with self.subTest(declaration=declaration):
                code, output = self.check("```chelis\ndef price(spot: f64): f64 !{}\n"
                                          f"{declaration}\n```\n")
                self.assertEqual(code, 1, output)

    def test_known_dependency_signature_is_explicitly_deferred(self):
        code, output = self.check("```chelis\ndef price(spot: f64): f64 !{}\n"
                                  "def datetime(): f64 !{}\n```\n")
        self.assertEqual(code, 0, output)
        self.assertIn("1 dependency signatures deferred", output)

    def test_empty_source_check_fails(self):
        code, output = self.check("No code here.\n")
        self.assertEqual(code, 1, output)


class InstallGuideTests(unittest.TestCase):
    def check(self, commands: list[str], dependency_pin: str = "0.24.22", extras: str = "") -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "reef.toml"
            manifest.write_text(
                'schema = "3"\n[package]\nname = "shoals"\nversion = "0.24.22"\n'
                '[dependencies]\nchelis-std = { version = "=0.4.0" }\n'
                'nautilus = { version = "=0.7.55" }\n'
                'chelis-clarabel = { version = "=0.1.0" }\n'
            )
            page = root / "getting-started.md"
            page.write_text(
                "These downloads need no GitHub token:\n```sh\n"
                + "\n".join(f"chelis reef install --from-github {item}" for item in commands)
                + "\n```\n"
                + extras
                + f'shoals = {{ version = "={dependency_pin}" }}\n'
            )
            return book.install_guide_failures(page, manifest)

    def test_install_guide_matches_every_published_dependency(self):
        self.assertEqual(self.check([
            "Chelis-Lang/nautilus@v0.7.55",
            "Chelis-Lang/chelis-clarabel@v0.1.0",
            "Chelis-Lang/shoals@v0.24.22",
        ]), [])

    def test_missing_or_wrong_install_coordinate_fails(self):
        complete = [
            "Chelis-Lang/nautilus@v0.7.55",
            "Chelis-Lang/chelis-clarabel@v0.1.0",
            "Chelis-Lang/shoals@v0.24.22",
        ]
        self.assertIn("chelis-clarabel", " ".join(self.check([complete[0], complete[2]])))
        self.assertIn("nautilus", " ".join(self.check([
            "Chelis-Lang/nautilus@v0.7.54", *complete[1:]
        ])))
        self.assertIn("shoals", " ".join(self.check(complete + [complete[-1]])))

    def test_manifest_and_documented_dependency_pin_must_agree(self):
        failures = self.check([
            "Chelis-Lang/nautilus@v0.7.55",
            "Chelis-Lang/chelis-clarabel@v0.1.0",
            "Chelis-Lang/shoals@v0.24.22",
        ], dependency_pin="0.24.21")
        self.assertIn("shoals", " ".join(failures))

    def test_hidden_or_unfenced_install_does_not_satisfy_guide(self):
        visible = [
            "Chelis-Lang/nautilus@v0.7.55",
            "Chelis-Lang/shoals@v0.24.22",
        ]
        hidden = "chelis reef install --from-github Chelis-Lang/chelis-clarabel@v0.1.0\n"
        self.assertIn("chelis-clarabel", " ".join(self.check(
            visible, extras=f"<!--\n{hidden}-->\n"
        )))
        self.assertIn("chelis-clarabel", " ".join(self.check(
            visible, extras=hidden
        )))


if __name__ == "__main__":
    unittest.main()
