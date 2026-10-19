"""v2 contract admission: identity, witness and actual-replay negatives."""
import copy
import hashlib
import tempfile
import unittest
import contextlib
import io
from unittest import mock

import prove_gate
import check_refuted_claims
from pathlib import Path

import refuted_claims as refuted


class RefutedClaimContractTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.repo = Path(self.directory.name)
        (self.repo / "properties").mkdir()
        self.source = "module Shoals.Properties.P\nimport Shoals.A (f)\n@property p forall(x: f32) where x > 0.0:\n  (f(x) > 0.0)\n"
        (self.repo / "properties/p.ch").write_text(self.source)
        self.prop = {"file": "properties/p.ch", "module": "Shoals.Properties.P", "name": "p"}
        self.goal = "forall(x: f32) where x > 0.0: (Shoals.A.f(x) > 0.0)"
        self.claim = {"model": "m", "property": self.prop,
                      "source_sha256": hashlib.sha256(self.source.encode()).hexdigest(),
                      "goal_sha256": hashlib.sha256(self.goal.encode()).hexdigest(),
                      "issue": "Shoals#182"}
        self.inv = {"id": "inv", "target_model": "m", "property": self.prop,
                    "controls": {"satisfying": {"name": "p", "expected": "passed"},
                                 "violating": {"name": "wrong", "expected": "failed", "witness_required": True}},
                    "preconditions": [{"lhs": "x", "op": "gt", "rhs": {"const": 0.0}}],
                    "expected_tier_per_pin": {"0.19.4": "fuzz_validated", "0.21.0": "disproved"},
                    "refuted_claims_per_pin": {"0.21.0": [self.claim]}}
        self.manifest = {"schema_version": "2.0", "chelis_pin": "0.21.0",
                         "models": [{"id": "m"}], "invariants": [self.inv]}
        self.record = {"kind": "property", "name": "p", "source": {"file": "properties/p.ch", "kind": "surf"},
                       "goal": self.goal, "status": "failed", "proof_tier": "fuzz", "counterexample": {"x": 1.0}}

    def test_valid_v2_identity(self):
        self.assertEqual(refuted.manifest_errors(self.manifest, self.repo), [])
        self.assertEqual(refuted.find(self.inv, "0.21.0", "m", self.prop), self.claim)
        self.assertIsNone(refuted.find(self.inv, "0.19.4", "m", self.prop))

    def test_v1_rejects_refutation_semantics(self):
        self.manifest["schema_version"] = "1.0"
        self.assertTrue(refuted.manifest_errors(self.manifest, self.repo))

    def test_unknown_model_property_hash_and_fields_reject(self):
        for key, value in [("model", "other"), ("property", {**self.prop, "name": "other"}),
                           ("source_sha256", "0" * 64), ("goal_sha256", "invalid"), ("extra", True)]:
            with self.subTest(key=key):
                forged = copy.deepcopy(self.manifest)
                forged["invariants"][0]["refuted_claims_per_pin"]["0.21.0"][0][key] = value
                self.assertTrue(refuted.manifest_errors(forged, self.repo))

    def test_duplicate_and_missing_current_selector_reject(self):
        self.inv["refuted_claims_per_pin"]["0.21.0"].append(copy.deepcopy(self.claim))
        self.assertTrue(refuted.manifest_errors(self.manifest, self.repo))
        self.inv["refuted_claims_per_pin"] = {}
        self.assertTrue(refuted.manifest_errors(self.manifest, self.repo))

    def test_wrong_model_or_pin_never_selects_disproof(self):
        self.assertIsNone(refuted.find(self.inv, "0.21.0", "other", self.prop))
        self.assertIsNone(refuted.find(self.inv, "0.20.0", "m", self.prop))

    def test_shared_primary_and_refuted_instantiation_are_distinct(self):
        primary = copy.deepcopy(self.inv)
        primary["expected_tier_per_pin"]["0.21.0"] = "fuzz_validated"
        primary["also_instantiated_for"] = [{"target_model": "other", "property": {**self.prop, "name": "q"},
                                              "controls": primary["controls"], "preconditions": []}]
        primary["refuted_claims_per_pin"]["0.21.0"][0]["model"] = "other"
        primary["refuted_claims_per_pin"]["0.21.0"][0]["property"] = {**self.prop, "name": "q"}
        self.assertIsNone(refuted.find(primary, "0.21.0", "m", self.prop))
        self.assertIsNotNone(refuted.find(primary, "0.21.0", "other", {**self.prop, "name": "q"}))

    def test_exact_record_source_goal_status_and_witness_are_required(self):
        self.assertEqual(refuted.record_errors(self.record, self.claim, self.repo), [])
        for key, value in [("kind", "summary"), ("name", "other"), ("source", {"file": "other.ch", "kind": "surf"}),
                           ("goal", "true"), ("status", "passed"), ("counterexample", {}),
                           ("counterexample", {"x": float("inf")}), ("counterexample", {"x": "not a number"})]:
            with self.subTest(key=key, value=value):
                forged = {**self.record, key: value}
                self.assertTrue(refuted.record_errors(forged, self.claim, self.repo))

    def test_replay_uses_original_typed_predicate_and_complete_inputs(self):
        text = refuted.replay_source(self.source, "p", {"x": 1.0})
        self.assertTrue(text.startswith(self.source))
        self.assertIn("(f(x) > 0.0)", text)
        self.assertIn("cast(1.0, f32)", text)
        for inputs in [{}, {"x": 1.0, "extra": 2.0}, {"x": float("nan")}]:
            with self.subTest(inputs=inputs), self.assertRaises(ValueError):
                refuted.replay_source(self.source, "p", inputs)

    def test_owning_gate_enforces_graph_corrupt_control_witness_and_actual_replay(self):
        (self.repo / "src").mkdir()
        (self.repo / "src/a.ch").write_text("module Shoals.A\ndef f(x: f32) -> f32 = neg(x)\n")
        self.inv["binding"] = {"references_output_fn": "direct", "contracts": [], "goal_pattern": "(f(x) > 0.0)"}
        model = {"id": "m", "module": "Shoals.A", "output_fn": "f"}
        self.manifest.update(pkg="shoals", models=[model])
        records = {"p": self.record, "wrong": {**self.record, "name": "wrong"}}
        declarations = [{"id": name, "kind": "property", "package": "shoals", "module": self.prop["module"],
                         "name": name, "source": {"file": self.prop["file"]}} for name in records]
        declarations.append({"id": "f", "kind": "function", "package": "shoals", "module": "Shoals.A", "name": "f", "source": {"file": "src/a.ch"}})
        graph = {"status": "complete", "declarations": declarations, "edges": [{"from": name, "to": "f"} for name in records]}
        result = {"records": records, "dependency_graph": graph, "summary_count": 1, "duplicate_records": [], "returncode": 1}
        with mock.patch.object(prove_gate, "REPO", self.repo), mock.patch.object(prove_gate, "resolve_bin", return_value="actual-test-double"), \
             mock.patch.object(refuted, "replay", return_value=True), contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(check_refuted_claims.check_result(result, self.manifest, self.prop["file"], "unused")[0])
            for field, value in [("summary_count", 0), ("summary_count", 2), ("duplicate_records", ["p"]),
                                 ("dependency_graph", None), ("returncode", 124)]:
                self.assertFalse(check_refuted_claims.check_result({**result, field: value}, self.manifest, self.prop["file"], "unused")[0])
            for mutate in ["missing-control", "passed-control", "out-of-domain", "missing-input", "wrong-file", "missing-edge"]:
                forged = copy.deepcopy(result)
                if mutate == "missing-control": forged["records"].pop("wrong")
                if mutate == "passed-control": forged["records"]["wrong"]["status"] = "passed"
                if mutate == "out-of-domain": forged["records"]["p"]["counterexample"] = {"x": -1.0}
                if mutate == "missing-input": forged["records"]["p"]["counterexample"] = {}
                if mutate == "wrong-file": forged["dependency_graph"]["declarations"][-1]["source"]["file"] = "src/forged.ch"
                if mutate == "missing-edge": forged["dependency_graph"]["edges"] = []
                self.assertFalse(check_refuted_claims.check_result(forged, self.manifest, self.prop["file"], "unused")[0], mutate)
            with mock.patch.object(refuted, "replay", return_value=False):
                self.assertFalse(check_refuted_claims.check_result(result, self.manifest, self.prop["file"], "unused")[0])

    def test_primary_cannot_be_positive_with_a_refuted_selector_and_paths_stay_authentic(self):
        self.inv["expected_tier_per_pin"]["0.21.0"] = "fuzz_validated"
        self.assertTrue(refuted.manifest_errors(self.manifest, self.repo))
        for path in ["../outside.ch", "/tmp/outside.ch"]:
            with self.assertRaises(ValueError): refuted.source_path(self.repo, {"file": path})
        (self.repo / "properties/link.ch").symlink_to(self.repo / "properties/p.ch")
        with self.assertRaises(ValueError): refuted.source_path(self.repo, {"file": "properties/link.ch"})

    def test_source_digest_binds_original_bytes_without_newline_normalization(self):
        (self.repo / "properties/p.ch").write_bytes(self.source.replace("\n", "\r\n").encode())
        self.assertTrue(refuted.manifest_errors(self.manifest, self.repo))
        self.assertTrue(refuted.record_errors(self.record, self.claim, self.repo))

    def test_only_exact_single_false_root_admits_replay(self):
        good = {"roots": [{"name": "cnote_refuted_result", "value": {"type": "bool", "value": False}}]}
        self.assertTrue(refuted.replay_failed(good))
        for output in [{"roots": []}, {"roots": good["roots"] * 2},
                       {"roots": [*good["roots"], {"name": "other", "value": {"type": "bool", "value": False}}]},
                       {"roots": [{"name": "cnote_refuted_result", "value": {"type": "bool", "value": 0}}]},
                       {"roots": [{"name": "cnote_refuted_result", "value": {"type": "bool", "value": True}}]},
                       {"roots": [{"name": "other", "value": {"type": "bool", "value": False}}]}]:
            self.assertFalse(refuted.replay_failed(output))
