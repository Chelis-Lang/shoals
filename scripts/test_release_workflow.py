#!/usr/bin/env python3
"""Static contracts for Shoals toolchain and release workflows."""

from __future__ import annotations

import ast
import importlib.util
import re
import unittest
from pathlib import Path


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
            ROOT / ".github/workflows/nightly.yml",
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

    def test_release_seals_every_payload_and_rebuilds_before_publish(self) -> None:
        release = (ROOT / ".github/workflows/release.yml").read_text()
        artifact_oracle = release.index(
            "python3 scripts/check_release_artifact_determinism.py"
        )
        canonical_build = release.index("python3 scripts/build_release_assets.py")
        prove = release.index("python3 scripts/prove_gate.py")
        copy_manifest = release.index("cp docs/cnote-import-surface.json")
        seal = release.index("sha256sum \\\n", copy_manifest)
        rebuild = release.index("python3 scripts/build_release_assets.py", seal)
        validate = release.index("sha256sum -c", rebuild)
        publish = release.index("uses: softprops/action-gh-release@v2")
        self.assertIn('PROVE_GATE_FUZZ: "1"', release[:copy_manifest])
        self.assertLess(artifact_oracle, canonical_build)
        self.assertLess(canonical_build, prove)
        self.assertLess(prove, copy_manifest)
        self.assertLess(copy_manifest, seal)
        self.assertLess(seal, rebuild)
        self.assertLess(rebuild, validate)
        self.assertLess(validate, publish)

        seal_step = release[
            release.index("- name: Seal and validate the complete release payload") :
            release.index("- name: Verify release assets")
        ]
        self.assertIn("GH_TOKEN:", seal_step)
        self.assertIn("GITHUB_TOKEN:", seal_step)
        for suffix in ("chb", "tar.zst", "invariants.json", "sha256"):
            self.assertIn(
                f"dist/${{{{ env.PACKAGE_NAME }}}}-${{{{ env.PACKAGE_VERSION }}}}.{suffix}",
                release[publish:],
            )
        self.assertIn("overwrite_files: true", release[publish:])

    def test_adversarial_risk_self_tests_are_authoritative(self) -> None:
        ci = (ROOT / ".github/workflows/ci.yml").read_text()
        release = (ROOT / ".github/workflows/release.yml").read_text()
        local = (ROOT / "scripts/run_local_gate.py").read_text()
        command = "python3 scripts/test_risk_invariant_gate.py"
        self.assertIn(command, ci)
        self.assertIn(command, release)
        self.assertIn(
            '["python3", "scripts/test_risk_invariant_gate.py"]', local
        )
        self.assertIn("python3 scripts/test_build_release_assets.py", ci)

    def test_bounded_pricing_properties_gate_nightly_full_and_release(self) -> None:
        local = (ROOT / "scripts/run_local_gate.py").read_text()
        ci = (ROOT / ".github/workflows/ci.yml").read_text()
        nightly = (ROOT / ".github/workflows/nightly.yml").read_text()
        release = (ROOT / ".github/workflows/release.yml").read_text()
        command = "python3 scripts/check_pricing_fix_properties.py"
        self.assertNotIn(command, ci)
        self.assertIn("python3 scripts/test_check_pricing_fix_properties.py", ci)
        self.assertIn(command, nightly[nightly.index("  prove:"):nightly.index("  heavy:")])
        self.assertLess(release.index(command), release.index("uses: softprops/action-gh-release@v2"))
        per_pr, full = local.split("    nightly_stages:", 1)
        self.assertNotIn('["python3", "scripts/check_pricing_fix_properties.py"]', per_pr)
        self.assertIn('["python3", "scripts/check_pricing_fix_properties.py"]', full)
        self.assertIn('["python3", "scripts/test_check_pricing_fix_properties.py"]', per_pr)

    def test_lsm_accuracy_runs_in_full_nightly_and_before_publish(self) -> None:
        local = (ROOT / "scripts/run_local_gate.py").read_text()
        ci = (ROOT / ".github/workflows/ci.yml").read_text()
        nightly = (ROOT / ".github/workflows/nightly.yml").read_text()
        release = (ROOT / ".github/workflows/release.yml").read_text()
        command = "python3 scripts/check_lsm_accuracy.py"
        units = "python3 scripts/test_check_lsm_accuracy.py"
        per_pr, full = local.split("    nightly_stages:", 1)
        self.assertNotIn(command, ci)
        self.assertIn(units, ci)
        self.assertIn('["python3", "scripts/test_check_lsm_accuracy.py"]', per_pr)
        self.assertNotIn('["python3", "scripts/check_lsm_accuracy.py"]', per_pr)
        self.assertIn('["python3", "scripts/check_lsm_accuracy.py"]', full)
        heavy = nightly[nightly.index("  heavy:"):nightly.index("  report:")]
        step = heavy[heavy.index("      - name: Check native LSM accuracy"):]
        self.assertIn("if: matrix.file == 'lsm_heavy'", step)
        self.assertIn(command, step)
        self.assertIn(units, release)
        self.assertLess(release.index(command), release.index("uses: softprops/action-gh-release@v2"))

    def test_full_local_gate_runs_cross_registry_artifact_oracle(self) -> None:
        local = (ROOT / "scripts/run_local_gate.py").read_text()
        self.assertIn(
            '["python3", "scripts/check_release_artifact_determinism.py"]',
            local,
        )

    def test_nightly_executes_the_latency_oracle(self) -> None:
        nightly = (ROOT / ".github/workflows/nightly.yml").read_text()
        prove_job = nightly[nightly.index("  prove:") : nightly.index("  heavy:")]
        self.assertIn('PROVE_GATE_FUZZ: "1"', prove_job)
        self.assertIn("python3 scripts/prove_gate.py", prove_job)
        self.assertIn("python3 scripts/check_package_prove_latency.py", prove_job)
        oracle_step = prove_job[
            prove_job.index(
                "Verify package prove latency and deterministic output"
            ) :
        ]
        self.assertIn("GH_TOKEN:", oracle_step)
        self.assertIn("GITHUB_TOKEN:", oracle_step)

        release = (ROOT / ".github/workflows/release.yml").read_text()
        release_oracle = release[
            release.index(
                "Verify package prove latency and deterministic output"
            ) :
        ]
        self.assertIn("GH_TOKEN:", release_oracle)
        self.assertIn("GITHUB_TOKEN:", release_oracle)

    def test_local_full_gate_matches_hosted_manual_matrix(self) -> None:
        nightly = (ROOT / ".github/workflows/nightly.yml").read_text()
        matrix_start = nightly.index("        file:", nightly.index("  heavy:"))
        matrix_end = nightly.index("    steps:", matrix_start)
        hosted = re.findall(
            r"^\s+- ([a-z0-9_]+)\s*$",
            nightly[matrix_start:matrix_end],
            flags=re.MULTILINE,
        )

        local_tree = ast.parse((ROOT / "scripts/run_local_gate.py").read_text())
        assignment = next(
            node for node in local_tree.body
            if isinstance(node, ast.Assign)
            and any(
                isinstance(target, ast.Name)
                and target.id == "NIGHTLY_MANUAL_FILES"
                for target in node.targets
            )
        )
        local = ast.literal_eval(assignment.value)
        self.assertEqual(local, hosted)
        self.assertNotIn("modelfit_bfgs_heavy", local)
        hosted_command = nightly[
            nightly.index(
                'run: chelis test "tests-manual/${{ matrix.file }}.ch"',
                matrix_end,
            ) :
        ]
        self.assertIn("--timeout 1500 --suite-timeout 1650 --jobs 1", hosted_command)

        local_source = (ROOT / "scripts/run_local_gate.py").read_text()
        self.assertIn(
            '"--timeout", "1500", "--suite-timeout", "1650",',
            local_source,
        )
        self.assertIn(
            '["python3", "scripts/test_release_workflow.py"]',
            local_source,
        )


if __name__ == "__main__":
    unittest.main()
