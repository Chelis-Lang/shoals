module Shoals.TestsNeg.KouUnenumerableJumpRate
import Std.Test (assert_true)
import Nautilus.Stats (mean_vec)
import Shoals.Stochastic (sto_kou_jump_terminal)
-- Negative: the enumerated sampler draws the jump count from a slot table
-- whose length is set by the exponentially tilted mean
-- lambda_jump * t * (1 + sto_kou_compensator(p, eta_up, eta_dn)). At
-- lambda_jump * t = 400 with eta_up = 1.1 the multiplier is 11, so the table
-- would want about 4876 slots, past the cap, and the sampler refuses naming
-- the quantity the caller has to bring down.
--
-- This is the negative-parity case for the slot cap in sto_kou_jump_slots, and
-- the cap is a COST bound rather than a model bound: it is the jump MULTIPLIER
-- that breaches it here, not the intensity. At eta_up = 10 the same
-- lambda_jump * t = 400 tilts to 444 and sizes the table at about 604 slots,
-- comfortably inside the cap. That is why the diagnostic names the tilted
-- product rather than lambda_jump alone.
--
-- Kou pays this cap harder than Merton does, and the fixture exists partly to
-- record that: Merton aggregates its N jumps in closed form, while Kou's jump
-- sizes have no such form, so every slot is also a per-path draw and a fold
-- step. Raising the cap does not make this file pass; it makes the table
-- expensive in paths as well as in slots.
def test_neg_kou_rejects_unenumerable_jump_rate() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  paths = sto_kou_jump_terminal(key_from_seed(3i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(400.0, f32), cast(1.0, f32), cast(1.1, f32), cast(3.0, f32), cast(1.0, f32))
  assert_true(gt(mean_vec(paths), cast(0.0, f32)), "should not reach here: the jump count for this tilted intensity is not enumerable within the slot cap")
}
