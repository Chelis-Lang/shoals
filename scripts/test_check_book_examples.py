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


if __name__ == "__main__":
    unittest.main()
