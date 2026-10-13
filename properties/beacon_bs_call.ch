module Shoals.Properties.Beacon_bs_call
import Shoals.Pricing (bs_call_f64)
-- Direct imported Black-Scholes source acceptance for the bounded Beacon
-- scalar route. The source call includes Chelis's actual normal CDF graph.
-- These are real-arithmetic range claims; they do not certify f64 rounding.
@property bs_call_box_lower forall(s: f64) where s >= 96.0f64, s <= 104.0f64:
  (bs_call_f64(s, 100.0f64, 0.05f64, 0.2f64, 1.0f64) >= 0.0f64)
@property bs_call_box_upper forall(s: f64) where s >= 96.0f64, s <= 104.0f64:
  (bs_call_f64(s, 100.0f64, 0.05f64, 0.2f64, 1.0f64) <= 20.0f64)
@property bs_call_atm_zero_wrong forall(s: f64) where s >= 96.0f64, s <= 104.0f64:
  (bs_call_f64(s, 100.0f64, 0.05f64, 0.2f64, 1.0f64) <= 0.0f64)
