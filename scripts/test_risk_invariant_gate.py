#!/usr/bin/env python3
"""Regression tests for the #37 compiler-evidence and fuzz non-vacuity gate."""

from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("prove_gate", ROOT / "scripts/prove_gate.py")
PROVE_GATE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(PROVE_GATE)
CONTRACT_SPEC = importlib.util.spec_from_file_location(
    "contract_gate", ROOT / "scripts/contract_gate.py")
CONTRACT_GATE = importlib.util.module_from_spec(CONTRACT_SPEC)
assert CONTRACT_SPEC.loader is not None
CONTRACT_SPEC.loader.exec_module(CONTRACT_GATE)


class RiskInvariantGateTests(unittest.TestCase):
    def test_manifest_locks_exact_two_kind_six_invariant_contract(self) -> None:
        manifest = json.loads(
            (ROOT / "docs/cnote-import-surface.json").read_text()
        )
        self.assertEqual(
            CONTRACT_GATE.risk_family_errors(manifest, manifest["chelis_pin"]),
            [],
        )
        self.assertEqual(
            CONTRACT_GATE.generated_note_errors(
                manifest, manifest["pkg_version"], manifest["chelis_pin"]
            ),
            [],
        )

        missing = copy.deepcopy(manifest)
        missing["invariants"] = [
            inv for inv in missing["invariants"]
            if inv.get("id") != "shoals.inv.var_monotone_in_confidence.v1"
        ]
        self.assertTrue(CONTRACT_GATE.risk_family_errors(missing, "0.17.5"))

        forged = copy.deepcopy(manifest)
        monotone = next(
            inv for inv in forged["invariants"]
            if inv.get("id") == "shoals.inv.var_monotone_in_confidence.v1"
        )
        monotone["binding"]["additional_compiler_dependencies"] = [{
            "package": "shoals", "module": "Shoals.Risk",
            "kind": "function", "name": "parametric_cvar",
            "source_file": "src/risk.ch",
        }]
        errors = CONTRACT_GATE.risk_family_errors(forged, "0.17.5")
        self.assertTrue(
            any("additional compiler dependencies" in e for e in errors)
        )

        for invariant_id in (
            "shoals.inv.cvar_dominates_var.v1",
            "shoals.inv.historical_cvar_dominates_var.v1",
        ):
            missing_second_edge = copy.deepcopy(manifest)
            dominance = next(
                inv for inv in missing_second_edge["invariants"]
                if inv.get("id") == invariant_id
            )
            dominance["binding"]["additional_compiler_dependencies"] = []
            errors = CONTRACT_GATE.risk_family_errors(
                missing_second_edge, "0.17.5"
            )
            self.assertTrue(
                any("additional compiler dependencies" in e for e in errors),
                invariant_id,
            )

    def test_additional_dependency_requires_exact_compiler_edge(self) -> None:
        prop = {
            "id": "p", "kind": "property", "package": "shoals",
            "module": "Shoals.Properties.CanonRisk", "name": "dominance",
            "source": {"file": "properties/canonrisk.ch"},
        }
        cvar = {
            "id": "c", "kind": "function", "package": "shoals",
            "module": "Shoals.Risk", "name": "parametric_cvar",
            "source": {"file": "src/risk.ch"},
        }
        dependency = {
            "package": "shoals", "module": "Shoals.Risk",
            "kind": "function", "name": "parametric_cvar",
            "source_file": "src/risk.ch",
        }
        good = {"status": "complete", "declarations": [prop, cvar],
                "edges": [{"from": "p", "to": "c"}]}
        missing = {**good, "edges": []}
        kwargs = dict(property_name="dominance",
                      property_module="Shoals.Properties.CanonRisk",
                      property_file="properties/canonrisk.ch", package="shoals")
        self.assertTrue(PROVE_GATE.additional_dependency_references(
            good, dependency, **kwargs)[0])
        self.assertFalse(PROVE_GATE.additional_dependency_references(
            missing, dependency, **kwargs)[0])
        self.assertFalse(PROVE_GATE.additional_dependency_references(
            good, None, **kwargs)[0])

    def test_fuzz_non_vacuity_requires_full_constraint_directed_budget(self) -> None:
        good = {
            "status": "passed", "proof_tier": "fuzz", "samples": 25,
            "accepted_samples": 25, "attempted_samples": 25,
            "sampling_method": "constraint_directed",
            "assumptions": [{"non_vacuity": {"status": "established"}}],
        }
        self.assertTrue(PROVE_GATE.fuzz_non_vacuity(good)[0])
        self.assertFalse(PROVE_GATE.fuzz_non_vacuity(
            {**good, "accepted_samples": 1})[0])
        self.assertFalse(PROVE_GATE.fuzz_non_vacuity(
            {**good, "sampling_method": "rejection"})[0])
        self.assertFalse(PROVE_GATE.fuzz_non_vacuity(
            {**good, "assumptions": []})[0])

    def test_manifest_additional_dependency_fails_closed(self) -> None:
        good = {
            "package": "shoals", "module": "Shoals.Risk",
            "kind": "function", "name": "parametric_cvar",
            "source_file": "src/risk.ch",
        }
        self.assertEqual(CONTRACT_GATE.additional_dependency_errors(good), [])
        self.assertTrue(CONTRACT_GATE.additional_dependency_errors(
            {**good, "module": "Attacker.Risk"}))
        self.assertTrue(CONTRACT_GATE.additional_dependency_errors(
            {**good, "name": "not_exported"}))
        self.assertTrue(CONTRACT_GATE.additional_dependency_errors(
            {**good, "extra": "forged"}))
        self.assertTrue(CONTRACT_GATE.additional_dependency_errors(None))


if __name__ == "__main__":
    unittest.main()
