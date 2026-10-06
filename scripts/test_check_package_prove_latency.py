#!/usr/bin/env python3
"""Negative-parity unit tests for the chelis#924 release oracle."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import check_package_prove_latency as oracle


def payload(*, status: str = "passed", tier: str = "smt", summary: bool = True) -> bytes:
    rows = [
        {
            "kind": "property",
            "name": oracle.PROPERTY,
            "status": status,
            "proof_tier": tier,
        }
    ]
    if summary:
        rows.append({"kind": "summary", "passed": 1, "failed": 0})
    return b"".join(json.dumps(row, sort_keys=True).encode() + b"\n" for row in rows)


class PackageProveLatencyOracleTests(unittest.TestCase):
    def test_accepts_exact_output_at_limits(self) -> None:
        output = payload()
        digest = oracle.validate_pair(
            oracle.COLD_LIMIT_SECONDS,
            oracle.WARM_LIMIT_SECONDS,
            output,
            output,
        )
        self.assertEqual(len(digest), 64)

    def test_rejects_false_green_or_incomplete_output(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "unexpected property verdict"):
            oracle.validate_pair(1.0, 1.0, payload(status="failed"), payload(status="failed"))
        with self.assertRaisesRegex(RuntimeError, "no final summary"):
            oracle.validate_pair(1.0, 1.0, payload(summary=False), payload(summary=False))

    def test_rejects_output_drift_and_budget_overruns(self) -> None:
        output = payload()
        with self.assertRaisesRegex(RuntimeError, "not byte-identical"):
            oracle.validate_pair(1.0, 1.0, output, output + b"\n")
        with self.assertRaisesRegex(RuntimeError, "cold prove took"):
            oracle.validate_pair(oracle.COLD_LIMIT_SECONDS + 0.001, 1.0, output, output)
        with self.assertRaisesRegex(RuntimeError, "warm prove took"):
            oracle.validate_pair(1.0, oracle.WARM_LIMIT_SECONDS + 0.001, output, output)

    def test_candidate_and_dependencies_share_explicit_isolated_registry(self) -> None:
        with tempfile.TemporaryDirectory() as raw_tmp:
            root = Path(raw_tmp)
            dist = root / "dist"
            dist.mkdir()
            (dist / "shoals-1.2.3.chb").write_bytes(b"shell")
            (dist / "shoals-1.2.3.tar.zst").write_bytes(b"archive")
            reef = root / "reef.toml"
            reef.write_text(
                """
[package]
name = "shoals"
version = "1.2.3"
compiler = "=0.17.4"
[dependencies]
nautilus = { version = "=0.7.36" }
coral = { version = "=0.7.33" }
"""
            )
            isolated = root / "isolated-reef"
            env = {**os.environ, "CHELIS_REEF_HOME": str(isolated)}
            completed = subprocess.CompletedProcess([], 0, "", "")
            with (
                mock.patch.object(oracle, "ROOT", root),
                mock.patch.object(
                    oracle.subprocess, "run", return_value=completed
                ) as run,
            ):
                oracle.install_candidate("/bin/chelis", "1.2.3", env=env)

        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(
            commands[:2],
            [
                [
                    "/bin/chelis",
                    "reef",
                    "install",
                    "--from-github",
                    "chelis-lang/nautilus@v0.7.36",
                ],
                [
                    "/bin/chelis",
                    "reef",
                    "install",
                    "--from-github",
                    "chelis-lang/coral@v0.7.33",
                ],
            ],
        )
        self.assertIn("--from-monorepo", commands[2])
        for call in run.call_args_list:
            self.assertEqual(call.kwargs["env"]["CHELIS_REEF_HOME"], str(isolated))


if __name__ == "__main__":
    unittest.main()
