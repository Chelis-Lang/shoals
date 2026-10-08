module Shoals.ManualGates.LsmAccuracy
import Shoals.Lsm (lsm_american_put)
import Shoals.Trees (tr_crr_american_put)
-- shoals#152: native replicated accuracy oracle, run by check_lsm_accuracy.py.
-- Same paths fit and value the policy: this has upward look-ahead bias.
-- Replicate SE measures sampling variation, not basis/grid/look-ahead bias.
def path_template() -> tensor[4000, f32] = to_tensor(map(fn (i: i64) -> 0f32, range(0i64, 4000i64)))
def replicate_prices(s0: f32, sigma: f32) -> List[f32] = map(fn (seed: i64) -> lsm_american_put(key_from_seed(seed), path_template(), s0, 100f32, 0.05f32, sigma, 1f32, 50i64), [0i64, 1i64, 2i64, 21i64, 31i64, 37i64, 41i64, 59i64])
atm_prices = replicate_prices(100f32, 0.2f32)
itm_prices = replicate_prices(95f32, 0.3f32)
atm_tree_coarse = tr_crr_american_put(100f32, 100f32, 0.05f32, 0f32, 0.2f32, 1f32, 512i64)
atm_tree_fine = tr_crr_american_put(100f32, 100f32, 0.05f32, 0f32, 0.2f32, 1f32, 1024i64)
itm_tree_coarse = tr_crr_american_put(95f32, 100f32, 0.05f32, 0f32, 0.3f32, 1f32, 512i64)
itm_tree_fine = tr_crr_american_put(95f32, 100f32, 0.05f32, 0f32, 0.3f32, 1f32, 1024i64)
