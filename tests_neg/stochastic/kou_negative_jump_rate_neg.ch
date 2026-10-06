module Shoals.TestsNeg.KouNegativeJumpRate
import Std.Test (assert_true)
import Nautilus.Stats (mean_vec)
import Shoals.Stochastic (sto_kou_jump_terminal)
-- Negative: a negative jump intensity names no Poisson law, so there is no
-- jump count to draw. Before shoals#132 the thinned sampler took this input
-- silently: thin_prob = lambda_jump * t / n_max was negative, `u < thin_prob`
-- was false for every uniform draw, and the sampler returned a jump-free GBM
-- path compensated for a NEGATIVE jump contribution -- a plausible-looking
-- price for a model that does not exist.
--
-- This is the negative-parity case for the `gte(rate, zero)` guard in
-- sto_kou_jump_slots. It is ordered AFTER the finiteness guard for the reason
-- the Merton fixtures record: an ordering comparison cannot reject NaN, so
-- finiteness has to be established first or this guard reports the wrong
-- cause.
def test_neg_kou_rejects_negative_jump_rate() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  paths = sto_kou_jump_terminal(key_from_seed(3i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(-1.0, f32), cast(0.5, f32), cast(3.0, f32), cast(3.0, f32), cast(1.0, f32))
  assert_true(gt(mean_vec(paths), cast(0.0, f32)), "should not reach here: unguarded this priced a jump-free path against a negative jump compensation")
}
