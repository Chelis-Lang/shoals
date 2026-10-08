module Shoals.TestsNeg.KouDivergentJumpMultiplier
import Std.Test (assert_true)
import Nautilus.Stats (mean_vec)
import Shoals.Stochastic (sto_kou_jump_terminal)
-- Negative: p > 0 and eta_up <= 1 make the up-jump exponential moment integral diverge,
-- so E[exp(Y)] does not exist, there is no jump multiplier w, and there is
-- nothing for the drift to compensate. sto_kou_compensator has always returned
-- a NaN sentinel here -- tests-manual/stochastic_kou_heavy.ch pins that, and
-- it stays -- but before shoals#132 sto_kou_jump_terminal multiplied that NaN
-- into its drift and returned NaN for EVERY path. A NaN price is the failure
-- mode this repository files bugs about, so the sampler now refuses.
--
-- This is the negative-parity case for the count_params_finite guard in
-- sto_kou_jump_slots, and it reaches that guard by a different route from its
-- Merton counterpart: Merton's non-finite log_w comes from a non-finite INPUT,
-- Kou's from a divergent moment of finite inputs. The assertion is one that
-- NaN also fails, so deleting the guard does not make this file pass by
-- accident -- it would then fail on the assertion rather than on the refusal,
-- and `--expect neg` checks the diagnostic text, not merely that something
-- failed.
def test_neg_kou_rejects_divergent_jump_multiplier() -> unit ! { Test } = {
  template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  jumps_template = to_tensor(map(fn (i: i64) -> cast(0.0, f32), range(cast(0, i64), cast(8, i64))))
  paths = sto_kou_jump_terminal(key_from_seed(3i64), template, jumps_template, cast(100.0, f32), cast(0.05, f32), cast(0.2, f32), cast(1.0, f32), cast(0.5, f32), cast(0.5, f32), cast(3.0, f32), cast(1.0, f32))
  assert_true(gt(mean_vec(paths), cast(0.0, f32)), "should not reach here: unguarded this returned NaN for every path from a divergent jump multiplier")
}
