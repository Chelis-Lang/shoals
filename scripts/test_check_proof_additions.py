"""Reject source, domain, engine and proof-status substitutions."""

import copy
import unittest

import check_proof_additions as gate


class ProofAdditionTests(unittest.TestCase):
    def svi_records(self):
        properties = []
        declarations = [
            {
                "id": "f",
                "kind": "function",
                "package": "shoals",
                "module": "Shoals.VolSurface",
                "name": "vs_total_variance",
                "source": {"file": "src/volsurface.ch"},
            }
        ]
        edges = []
        for name, goal in gate.SVI_GOALS.items():
            passed = name == "svi_total_variance_nonnegative"
            properties.append(
                {
                    "kind": "property",
                    "name": name,
                    "goal": goal,
                    "status": "passed" if passed else "failed",
                    "proof_tier": "smt",
                    "samples": 0,
                    "arith_model": "real",
                    "qualifiers": ["real_arithmetic"],
                    "source": {"file": gate.SVI_FILE},
                    "assumptions": [{"non_vacuity": {"status": "established"}}],
                    "counterexample": None if passed else {"a": "1.0"},
                }
            )
            declarations.append(
                {
                    "id": name,
                    "kind": "property",
                    "package": "shoals",
                    "module": "Shoals.Properties.Svi_nonnegative",
                    "name": name,
                    "source": {"file": gate.SVI_FILE},
                }
            )
            if name != "svi_minimum_guards_satisfiable":
                edges.append({"from": name, "to": "f"})
        properties.append(
            {
                "kind": "summary",
                "total": 3,
                "passed": 1,
                "failed": 2,
                "unsupported": 0,
                "errors": 0,
                "dependency_graph": {
                    "status": "complete",
                    "declarations": declarations,
                    "edges": edges,
                },
            }
        )
        return properties

    def bs_records(self):
        records = []
        for name, goal in gate.BS_GOALS.items():
            passed = name != "bs_call_atm_zero_wrong"
            bound = 20.0 if name == "bs_call_box_upper" else 0.0
            witness = {
                "method": "arb_point_256",
                "inputs": {"s": {"lo": 100.0, "hi": 100.0}},
                "bound": {"lo": 10.0, "hi": 11.0},
            }
            engine = {
                "engine_binary_sha256": "a" * 64,
                "bound_side": "lower" if name == "bs_call_box_lower" else "upper",
                "input_box": {"s": {"lo": 96.0, "hi": 104.0}},
                "source_bound": gate.source_bound(bound),
                "source_dtype": "f64",
                "proof_graph_dtype": "f64",
                "float_execution_covered": False,
                "selected_root": 10,
                "folded_root": 12,
                "source_output_root": 10,
                "source_binding": {
                    "expression_sha256": "b" * 64,
                    "declarations": [
                        {"name": function, "sha256": "c" * 64}
                        for function in gate.BS_FUNCTIONS
                    ],
                },
                "beacon_evidence": {
                    "schema_version": "beacon.scalar_upper_bound.v1",
                    "selected_root_node_id": 12,
                    "verdict": "certified" if passed else "failed",
                    "counterexample": None if passed else witness,
                    "certificate": {
                        "method": "arb_box_cover_v1",
                        "leaves_certified": 1 if passed else 0,
                        "leaves_unresolved": 0 if passed else 1,
                        "leaves": [{}] if passed else [],
                    },
                },
            }
            records.append(
                {
                    "kind": "property",
                    "name": name,
                    "goal": goal,
                    "source": {"file": gate.BS_FILE},
                    "status": "passed" if passed else "failed",
                    "proof_tier": "beacon",
                    "samples": 0,
                    "arith_model": "real",
                    "qualifiers": ["real_arithmetic"],
                    "counterexample": None if passed else witness,
                    "engine_evidence": engine,
                }
            )
        records.append(
            {
                "kind": "summary",
                "total": 3,
                "passed": 2,
                "failed": 1,
                "unsupported": 0,
                "errors": 0,
            }
        )
        return records

    def test_accepts_svi_proof_and_two_refutations(self):
        self.assertEqual(gate.check_svi_records(self.svi_records()), [])

    def test_rejects_svi_goal_source_and_status_drift(self):
        for field, value in [
            ("goal", "(a == a)"),
            ("status", "unsupported"),
            ("proof_tier", "fuzz"),
            ("samples", 1),
            ("qualifiers", []),
        ]:
            records = self.svi_records()
            records[0][field] = value
            with self.subTest(field=field):
                self.assertTrue(gate.check_svi_records(records))
        records = self.svi_records()
        records[-1]["dependency_graph"]["edges"] = []
        self.assertTrue(gate.check_svi_records(records))
        records = self.svi_records()
        records[-1]["dependency_graph"]["declarations"][0]["source"][
            "file"
        ] = "wrong.ch"
        self.assertTrue(gate.check_svi_records(records))
        self.assertTrue(gate.check_svi_records(self.svi_records()[:-1]))

    def test_accepts_two_beacon_bounds_and_checked_false_witness(self):
        self.assertEqual(gate.check_bs_records(self.bs_records(), "a" * 64), [])

    def test_rejects_beacon_source_domain_engine_and_certificate_drift(self):
        for field, value in [
            ("goal", "(s == s)"),
            ("status", "unsupported"),
            ("proof_tier", "fuzz"),
            ("samples", 1),
            ("qualifiers", []),
        ]:
            records = self.bs_records()
            records[0][field] = value
            with self.subTest(field=field):
                self.assertTrue(gate.check_bs_records(records, "a" * 64))
        mutations = [
            ("engine_binary_sha256", "d" * 64),
            ("input_box", {"s": {"lo": 100.0, "hi": 104.0}}),
            ("source_bound", gate.source_bound(1.0)),
            ("folded_root", 10),
            ("float_execution_covered", True),
        ]
        for field, value in mutations:
            records = self.bs_records()
            records[0]["engine_evidence"][field] = value
            with self.subTest(field=field):
                self.assertTrue(gate.check_bs_records(records, "a" * 64))
        records = self.bs_records()
        records[0]["engine_evidence"]["source_binding"]["declarations"].pop()
        self.assertTrue(gate.check_bs_records(records, "a" * 64))
        records = self.bs_records()
        records[2]["counterexample"]["inputs"]["s"] = {"lo": 200.0, "hi": 200.0}
        self.assertTrue(gate.check_bs_records(records, "a" * 64))
        self.assertTrue(
            gate.check_bs_records(
                self.bs_records() + [copy.deepcopy(self.bs_records()[0])], "a" * 64
            )
        )


if __name__ == "__main__":
    unittest.main()
