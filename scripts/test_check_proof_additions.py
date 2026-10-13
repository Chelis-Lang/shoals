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
                    "strict_upper": 0.0,
                    "verdict": "certified" if passed else "failed",
                    "counterexample": None if passed else witness,
                    "certificate": {
                        "method": "arb_box_cover_v1",
                        "leaves_certified": 2 if passed else 0,
                        "leaves_unresolved": 0 if passed else 1,
                        "leaves": (
                            [
                                {
                                    "inputs": {"s": {"lo": lo, "hi": hi}},
                                    "bound": {"lo": -2.0, "hi": -1.0},
                                }
                                for lo, hi in ((96.0, 100.0), (100.0, 104.0))
                            ]
                            if passed
                            else []
                        ),
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
                "dependency_graph": {
                    "status": "complete",
                    "declarations": [
                        {
                            "id": "bs_call_f64",
                            "kind": "function",
                            "package": "shoals",
                            "module": "Shoals.Pricing",
                            "name": "bs_call_f64",
                            "source": {"file": "src/pricing.ch"},
                        },
                        *[
                            {
                                "id": name,
                                "kind": "property",
                                "package": "shoals",
                                "module": "Shoals.Properties.Beacon_bs_call",
                                "name": name,
                                "source": {"file": gate.BS_FILE},
                            }
                            for name in gate.BS_GOALS
                        ],
                    ],
                    "edges": [
                        {"from": name, "to": "bs_call_f64"} for name in gate.BS_GOALS
                    ],
                },
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

    def test_rejects_missing_partial_or_substituted_bs_dependency_graph(self):
        mutations = [
            ("empty", lambda graph: graph.clear()),
            ("partial", lambda graph: graph.update(status="partial")),
            ("missing_edge", lambda graph: graph["edges"].pop()),
            (
                "substituted_target_module",
                lambda graph: graph["declarations"][0].update(module="Other.Pricing"),
            ),
            (
                "substituted_target_file",
                lambda graph: graph["declarations"][0]["source"].update(
                    file="src/other_pricing.ch"
                ),
            ),
            (
                "substituted_property_module",
                lambda graph: graph["declarations"][1].update(
                    module="Shoals.Properties.Other"
                ),
            ),
        ]
        records = self.bs_records()
        del records[-1]["dependency_graph"]
        self.assertTrue(gate.check_bs_records(records, "a" * 64))
        for label, mutate in mutations:
            records = self.bs_records()
            mutate(records[-1]["dependency_graph"])
            with self.subTest(graph_change=label):
                self.assertTrue(gate.check_bs_records(records, "a" * 64))
        for name in gate.BS_GOALS:
            records = self.bs_records()
            records[-1]["dependency_graph"]["edges"] = [
                edge
                for edge in records[-1]["dependency_graph"]["edges"]
                if edge["from"] != name
            ]
            with self.subTest(missing_edge=name):
                self.assertTrue(gate.check_bs_records(records, "a" * 64))

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

    def test_rejects_incomplete_or_noncertifying_beacon_cover(self):
        def change_certificate(records, change):
            engine = records[0]["engine_evidence"]["beacon_evidence"]
            change(engine)
            self.assertTrue(gate.check_bs_records(records, "a" * 64))

        change_certificate(self.bs_records(), lambda e: e.update(strict_upper=1000.0))
        records = self.bs_records()
        records[2]["engine_evidence"]["beacon_evidence"]["strict_upper"] = 1000.0
        self.assertTrue(gate.check_bs_records(records, "a" * 64))

        def drop_leaf(engine):
            cert = engine["certificate"]
            cert["leaves"].pop()
            cert["leaves_certified"] = 1

        change_certificate(self.bs_records(), drop_leaf)
        for replacement in (
            {"lo": 1.0, "hi": 2.0},
            {"lo": -2.0, "hi": 0.0},
            {"lo": -2.0, "hi": float("nan")},
        ):
            change_certificate(
                self.bs_records(),
                lambda e: e["certificate"]["leaves"][0].update(bound=replacement),
            )
        for replacement in (
            {"lo": 96.0, "hi": 99.0},
            {"lo": 95.0, "hi": 100.0},
            {"lo": 96.0, "hi": float("inf")},
        ):
            change_certificate(
                self.bs_records(),
                lambda e: e["certificate"]["leaves"][0]["inputs"].update(s=replacement),
            )


if __name__ == "__main__":
    unittest.main()
