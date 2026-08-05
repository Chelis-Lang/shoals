module Shoals.TestsNeg.BsCallWireDimMismatch
import Shoals.Pricing (bs_call_wire_f64)
def constant_2(v: f64) -> tensor[2, f64] = to_tensor([v, v])
def constant_3(v: f64) -> tensor[3, f64] = to_tensor([v, v, v])
def test_neg_wire_pricer_rejects_mismatched_market_rows() -> tensor[2, f64] = bs_call_wire_f64(constant_2(cast(100.0, f64)), constant_3(cast(100.0, f64)), constant_2(cast(0.05, f64)), constant_2(cast(0.2, f64)), constant_2(cast(1.0, f64)), constant_2(cast(0.5, f64)), constant_2(cast(0.7071067811865476, f64)), constant_2(cast(0.254829592, f64)), constant_2(cast(-0.284496736, f64)), constant_2(cast(1.421413741, f64)), constant_2(cast(-1.453152027, f64)), constant_2(cast(1.061405429, f64)), constant_2(cast(0.3275911, f64)), constant_2(cast(1.1283791670955126, f64)), constant_2(cast(0.00001, f64)))
