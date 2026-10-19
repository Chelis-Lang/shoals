"""Exact schema30 and canonical Cast payload controls for the wire seam."""
import copy
import unittest
from unittest import mock
import validate_bs_wire_root as wire


class WireBoundaryTests(unittest.TestCase):
    def setUp(self):
        tensor = {"dims": [{"kind": "named", "name": "n", "size": None}], "precision": "f64"}
        self.payload = {"ok": True, "result": {"dag": {"schema_version": 30,
            "nodes": [{"id": 0, "op": {"kind": "load", "name": "spot"}, "inputs": [], "output_type": tensor},
                      {"id": 1, "op": {"kind": "cast", "new_precision": "f64"}, "inputs": [0], "output_type": tensor}],
            "roots": [1]}, "named_roots": {wire.ENTRY: 1}}}
        self.options = dict(expected_loads={"spot"}, expected_root_op="cast", expected_entry_root=1, expected_node_count=2)

    def test_exact_schema30_and_canonical_cast_accept(self):
        self.assertEqual(wire.WIRE_DAG_SCHEMA_VERSION, 30)
        self.assertEqual(wire.validate_response(self.payload, **self.options), (1, 2))

    def test_missing_older_future_and_wrong_typed_versions_reject(self):
        # Isolate version-shape validation from the pre-migration expected stamp.
        with mock.patch.object(wire, "WIRE_DAG_SCHEMA_VERSION", 30):
            for value in [None, 28, 29, 31, "30", 30.0, True]:
                payload = copy.deepcopy(self.payload)
                payload["result"]["dag"]["schema_version"] = value
                with self.subTest(value=value), self.assertRaises(wire.ValidationError):
                    wire.validate_response(payload, **self.options)
            payload = copy.deepcopy(self.payload)
            del payload["result"]["dag"]["schema_version"]
            with self.assertRaises(wire.ValidationError):
                wire.validate_response(payload, **self.options)

    def test_cast_requires_canonical_matching_target_precision(self):
        with mock.patch.object(wire, "WIRE_DAG_SCHEMA_VERSION", 30):
            for op in [{"kind": "cast", "precision": "f64"}, {"kind": "cast"},
                       {"kind": "cast", "new_precision": "f32"}]:
                payload = copy.deepcopy(self.payload)
                payload["result"]["dag"]["nodes"][1]["op"] = op
                with self.subTest(op=op), self.assertRaises(wire.ValidationError):
                    wire.validate_response(payload, **self.options)

    def test_existing_structural_corruption_controls_still_reject(self):
        wire.validate_corruption_controls()


if __name__ == "__main__":
    unittest.main()
