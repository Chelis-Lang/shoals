#!/usr/bin/env python3
"""Static contracts for Shoals toolchain and release workflows."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import re
import unittest
from pathlib import Path
from unittest import mock

import run_local_gate


ROOT = Path(__file__).resolve().parents[1]


class ReleaseWorkflowTests(unittest.TestCase):
    def test_heston_manual_gate_generates_explicit_key_source(self) -> None:
        script = ROOT / "scripts/manual_gates/phase3l_shoals_oracle_heston_qe.py"
        spec = importlib.util.spec_from_file_location("heston_qe_gate", script)
        assert spec is not None and spec.loader is not None
        gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(gate)
        source = gate._subst(gate.QE_SETUP)
        self.assertNotIn("with seed", source)
        self.assertIn(
            "heston_qe_paths_terminal(key_from_seed(2026i64), template,",
            source,
        )

    def test_every_dependency_coordinate_uses_canonical_lowercase_owner(self) -> None:
        paths = [
            ROOT / ".github/workflows/ci.yml",
            ROOT / ".github/workflows/release.yml",
            ROOT / "scripts/check_package_prove_latency.py",
            ROOT / "scripts/build_release_assets.py",
        ]
        combined = "\n".join(path.read_text() for path in paths)
        self.assertNotIn("Chelis-Lang/nautilus", combined)
        self.assertNotIn("Chelis-Lang/coral", combined)
        self.assertNotIn("Chelis-Lang/shoreleave", combined)
        self.assertIn("chelis-lang/nautilus", combined)
        self.assertIn("chelis-lang/coral", combined)
        self.assertIn("chelis-lang/shoreleave", combined)
        adversarial = (
            ROOT / "scripts/check_release_artifact_determinism.py"
        ).read_text()
        self.assertIn('f"Chelis-Lang/{name}@v{dep_version}"', adversarial)

    def test_toolchain_download_verifies_the_publisher_sidecar(self) -> None:
        action = (ROOT / ".github/actions/install-chelis/action.yml").read_text()
        self.assertIn("default: linux-x86_64-glibc2.31", action)
        self.assertIn("chelis-toolchain-sha256-v1-", action)
        self.assertIn('--pattern "$asset.sha256"', action)
        self.assertIn('sha256sum -c "$asset.sha256"', action)
        self.assertIn('shasum -a 256 -c "$asset.sha256"', action)
        self.assertLess(
            action.index('--pattern "$asset.sha256"'),
            action.index('tar -xzf "/tmp/chelis-toolchain/$asset"'),
        )
        self.assertIn(
            "inputs.platform }}-${{ inputs.chelis-tag }}-${{ inputs.reef-cache-key",
            action,
        )

    def test_release_seals_actual_payload_before_publish(self) -> None:
        release = live_yaml(ROOT / ".github/workflows/release.yml")
        build = release.index("python3 scripts/build_release_assets.py")
        manifest = release.index("cp docs/cnote-import-surface.json")
        verify = release.index("chelis reef verify-artifact", manifest)
        seal = release.index("sha256sum", verify)
        compare = release.index("cmp docs/cnote-import-surface.json", seal)
        validate = release.index("sha256sum -c", compare)
        publish = release.index("uses: softprops/action-gh-release@v2")
        self.assertLess(build, manifest)
        self.assertLess(manifest, verify)
        self.assertLess(verify, seal)
        self.assertLess(seal, compare)
        self.assertLess(compare, validate)
        self.assertLess(validate, publish)
        self.assertEqual(release.count("python3 scripts/build_release_assets.py"), 1)
        for suffix in ("chb", "tar.zst", "invariants.json", "sha256"):
            self.assertIn(
                f"dist/${{{{ env.PACKAGE_NAME }}}}-${{{{ env.PACKAGE_VERSION }}}}.{suffix}",
                release[publish:],
            )
            self.assertIn(f'${{PACKAGE_NAME}}-${{PACKAGE_VERSION}}.{suffix}',
                          release[:publish])
        self.assertIn('test "$MANIFEST_VER" = "$PACKAGE_VERSION"', release)
        self.assertIn('test "${GITHUB_REF_NAME#v}" = "${PACKAGE_VERSION}"', release)
        self.assertIn("fail_on_unmatched_files: true", release[publish:])
        self.assertIn("overwrite_files: true", release[publish:])

    def test_adversarial_risk_self_tests_are_authoritative(self) -> None:
        ci = live_yaml(ROOT / ".github/workflows/ci.yml")
        release = live_yaml(ROOT / ".github/workflows/release.yml")
        local = (ROOT / "scripts/run_local_gate.py").read_text()
        command = "python3 scripts/test_risk_invariant_gate.py"
        self.assertIn(command, ci)
        self.assertIn(command, release)
        self.assertIn(
            '["python3", "scripts/test_risk_invariant_gate.py"]', local
        )
        self.assertIn("python3 scripts/test_build_release_assets.py", ci)

    def test_no_workflow_runs_long_numerical_checks(self) -> None:
        workflows = sorted((ROOT / ".github/workflows").glob("*.y*ml"))
        workflows += sorted((ROOT / ".github/actions").glob("**/*.y*ml"))
        self.assertTrue(workflows)
        self.assertFalse((ROOT / ".github/workflows/nightly.yml").exists())
        for path in workflows:
            with self.subTest(workflow=path.name):
                self.assertEqual(long_runtime_commands(live_yaml(path)), [])

    def test_runtime_guard_rejects_dispatch_release_and_shell_blocks(self) -> None:
        for command in LONG_RUNTIME_PATTERNS:
            # Witnesses exercise the same detector used for every workflow.
            example = {
                "tests-suite": "chelis test tests/ --jobs 1",
                "manual-suite": 'chelis test "tests-manual/pde_heavy.ch"',
                "full-local": "python3 scripts/run_local_gate.py --full",
                "measurement": "python3 scripts/oracle_erf64_accuracy.py --measurement",
                "accuracy-default": "python3 scripts/oracle_erf64_accuracy.py",
                "book-runtime": "python3 scripts/check_book_examples.py",
                "pricing-full": "python3 scripts/check_pricing_fix_properties.py",
            }.get(command, f"python3 scripts/{command}.py")
            with self.subTest(command=command):
                self.assertTrue(long_runtime_commands(f"on: workflow_dispatch\n  run: |\n    {example}"))
                self.assertEqual(long_runtime_commands(f"# run: {example}"), [])
        self.assertEqual(long_runtime_commands(
            "run: python3 scripts/check_book_examples.py --source-only"), [])
        self.assertEqual(long_runtime_commands(
            "run: python3 scripts/test_check_lsm_accuracy.py"), [])
        self.assertEqual(long_runtime_commands(
            "run: python3 scripts/oracle_erf64_accuracy.py --transcription"), [])
        self.assertTrue(long_runtime_commands(
            "run: python3 scripts/check_book_examples.py # --source-only"))
        self.assertTrue(long_runtime_commands(
            "run: python3 scripts/oracle_erf64_accuracy.py # --transcription"))
        self.assertTrue(long_runtime_commands(
            "run: python3 scripts/oracle_erf64_accuracy.py --transcription --measurement"))
        self.assertEqual(long_runtime_commands(
            "run: python3 scripts/check_pricing_fix_properties.py --smoke"), [])
        self.assertTrue(long_runtime_commands(
            "run: python3 scripts/check_pricing_fix_properties.py # --smoke"))
        self.assertTrue(long_runtime_commands(
            "run: python3 scripts/check_pricing_fix_properties.py --smoke --full"))

    def test_default_gate_is_lean_and_extended_suite_is_optional(self) -> None:
        default = local_commands(False)
        extended = local_commands(True)
        default_text = "\n".join(" ".join(cmd) for cmd in default)
        self.assertEqual(long_runtime_commands(default_text), [])
        for command in (
            "scripts/prove_gate.py", "scripts/check_pricing_fix_properties.py",
            "scripts/check_lsm_accuracy.py", "scripts/manual_gates/spread_adi_oracle.py",
            "scripts/check_package_prove_latency.py",
            "scripts/check_release_artifact_determinism.py",
            "scripts/oracle_greeks_gate.py",
        ):
            self.assertTrue(any(command in cmd for cmd in extended), command)
        self.assertTrue(any("--measurement" in cmd for cmd in extended))
        self.assertTrue(any("tests/" in cmd and "test" in cmd for cmd in extended))
        self.assertTrue(any(any("tests-manual/" in arg for arg in cmd)
                            and "test" in cmd for cmd in extended))
        self.assertIn(["python3", "scripts/check_book_examples.py"], extended)
        self.assertIn(["python3", "scripts/check_book_examples.py", "--source-only"], default)
        self.assertIn(["python3", "scripts/test_check_pricing_fix_properties.py"], default)

    def test_offline_classifiers_remain_live_in_ci_and_release(self) -> None:
        for workflow in ("ci.yml", "release.yml"):
            live = live_yaml(ROOT / ".github/workflows" / workflow)
            for script in ("test_risk_invariant_gate.py", "test_check_pricing_fix_properties.py",
                           "test_check_lsm_accuracy.py", "test_spread_adi_oracle.py"):
                with self.subTest(workflow=workflow, script=script):
                    self.assertIn(f"run: python3 scripts/{script}", live)


def live_yaml(path: Path) -> str:
    return uncommented(path.read_text())


def uncommented(text: str) -> str:
    """Preserve command/quoted text while excluding YAML and shell comments."""
    lines = []
    for line in text.splitlines():
        quote = None
        escaped = False
        for index, char in enumerate(line):
            if escaped:
                escaped = False
            elif char == "\\" and quote != "'":
                escaped = True
            elif char in ("'", '"'):
                if quote == char:
                    quote = None
                elif quote is None:
                    quote = char
            elif char == "#" and quote is None and (index == 0 or line[index - 1].isspace()):
                line = line[:index]
                break
        lines.append(line)
    return "\n".join(lines)


LONG_RUNTIME_PATTERNS = {
    "tests-suite": r'\bchelis\s+test\s+[\"\']?tests(?:/|\s|$)',
    "manual-suite": r'\bchelis\s+test\s+[\"\']?tests-manual(?:/|\s|$)',
    "full-local": r'\brun_local_gate\.py\b[^\n]*--full\b',
    "measurement": r'\boracle_erf64_accuracy\.py\b[^\n]*--measurement\b',
    "accuracy-default": r'\boracle_erf64_accuracy\.py\b(?![^\n]*--transcription\b)',
    "book-runtime": r'\bcheck_book_examples\.py\b(?![^\n]*--source-only\b)',
    "pricing-full": r'\bcheck_pricing_fix_properties\.py\b(?![ \t]+--smoke[ \t]*(?:\n|$))',
    **{name: rf"(?<![\w]){re.escape(name)}\.py\b" for name in (
        "prove_gate", "check_lsm_accuracy",
        "spread_adi_oracle", "oracle_greeks_gate", "check_package_prove_latency",
        "check_release_artifact_determinism",
    )},
}


def long_runtime_commands(text: str) -> list[str]:
    live = re.sub(r"\\\n\s*", " ", uncommented(text))
    return [name for name, pattern in LONG_RUNTIME_PATTERNS.items()
            if re.search(pattern, live)]


def local_commands(full: bool) -> list[list[str]]:
    commands = []
    with mock.patch.object(run_local_gate, "run", side_effect=lambda cmd, **kwargs: commands.append(cmd) or 0), \
            mock.patch("sys.argv", ["run_local_gate.py"] + (["--full"] if full else [])), \
            contextlib.redirect_stdout(io.StringIO()):
        assert run_local_gate.main() == 0
    return commands


if __name__ == "__main__":
    unittest.main()
