module Shoals.TestsNeg.MertonUnenumerableJumpRate
import Std.Test (assert_true)
import Nautilus.Stats (mean_vec)
import Shoals.Stochastic (merton_jump_terminal)
-- Negative: the enumerated sampler draws the jump count from a slot table
-- whose length is set by the exponentially tilted mean
-- lambda * t * exp(jump_mean + 0.5 * jump_vol^2). Here that is roughly
-- 1.5e5 slots, which is not a table worth materializing per call, so the
-- sampler refuses and names the quantity the caller has to bring down.
--
-- This is the negative-parity case for the slot cap in merton_jump_slots. The
-- cap is a cost bound, not a model bound: it is the jump MEAN, not the
-- intensity, that makes this input expensive -- at a zero jump mean the same
-- lambda*t = 1000 would size the table at about 1233 slots, inside the cap.
-- Removing the cap does not make this file pass either: it would then attempt
-- a 150000-slot table and the assertion would still have to be reached.
def test_neg_merton_rejects_unenumerable_jump_rate() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  paths = merton_jump_terminal(key_from_seed(3i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1000.0, f32), cast(5.0, f32), cast(0.0, f32), cast(1.0, f32))
  assert_true(gt(mean_vec(paths), cast(0.0, f32)), "should not reach here: the jump count for this intensity is not enumerable within the slot cap")
}
