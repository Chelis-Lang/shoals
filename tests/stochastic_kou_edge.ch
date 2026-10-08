module Shoals.Tests.StochasticKouEdge
import Std.Test (assert_close, assert_true)
import Shoals.Stochastic (sto_kou_compensator, sto_kou_jump_sample, sto_kou_sampler_log_jump_moment)
def test_kou_zero_probability_compensator_accepts_finite_placeholders() -> unit ! { Test } = {
  placeholders = [-2.0f32, neg(0.0f32), 0.0f32, 0.5f32, 1.0f32, 2.0f32, 50.0f32]
  all_match = fold(fn (ok: bool, eta_up: f32) -> and(ok, eq(sto_kou_compensator(0.0f32, eta_up, 3.0f32), -0.25f32)), true, placeholders)
  _ = assert_true(all_match, "Pure downward compensator is -0.25 for every finite unused upward rate")
  assert_true(eq(sto_kou_compensator(neg(0.0f32), 0.0f32, 3.0f32), -0.25f32), "Signed zero probability also selects the downward law")
}
def test_kou_zero_probability_jump_sample_is_downward() -> unit ! { Test } = {
  _ = assert_true(eq(sto_kou_jump_sample(0.0f32, 0.0f32, 3.0f32, 0.0f32, 2.0f32), neg(div(2.0f32, 3.0f32))), "Uniform zero takes the downward branch without dividing by the unused zero rate")
  assert_true(eq(sto_kou_jump_sample(0.0f32, 1.0f32, 3.0f32, 0.5f32, 2.0f32), neg(div(2.0f32, 3.0f32))), "Positive uniform also draws the downward exponential")
}
def test_kou_zero_probability_moment_preserves_placeholder_and_zero_behavior() -> unit ! { Test } = {
  reference = sto_kou_sampler_log_jump_moment(2.0f32, 0.0f32, 2.0f32, 3.0f32, 1.0f32)
  _ = assert_close(reference, -0.5f32, 0.00001f32, "Pure downward sampler moment agrees with the compound Poisson value")
  _ = assert_true(eq(sto_kou_sampler_log_jump_moment(2.0f32, 0.0f32, 0.0f32, 3.0f32, 1.0f32), reference), "Zero placeholder preserves the exact enumerated moment")
  _ = assert_true(eq(sto_kou_sampler_log_jump_moment(2.0f32, 0.0f32, 1.0f32, 3.0f32, 1.0f32), reference), "Unit placeholder preserves the exact enumerated moment")
  _ = assert_close(sto_kou_sampler_log_jump_moment(neg(0.0f32), 0.0f32, 0.0f32, 3.0f32, 1.0f32), 0.0f32, 1e-6f32, "Signed zero intensity still gives zero moment")
  assert_close(sto_kou_sampler_log_jump_moment(2.0f32, 0.0f32, 0.0f32, 3.0f32, neg(0.0f32)), 0.0f32, 1e-6f32, "Signed zero horizon still gives zero moment")
}
def test_kou_compensator_retains_positive_probability_and_nonfinite_sentinels() -> unit ! { Test } = {
  rejected = fold(fn (ok: bool, eta_up: f32) -> {
    zeta = sto_kou_compensator(1e-6f32, eta_up, 3.0f32)
    and(ok, not(eq(zeta, zeta)))
  }, true, [0.0f32, 0.5f32, 1.0f32])
  _ = assert_true(rejected, "Every positive up probability retains the divergent-moment sentinel")
  nan = div(0.0f32, 0.0f32)
  inf = div(1.0f32, 0.0f32)
  nonfinite = fold(fn (ok: bool, eta_up: f32) -> {
    zeta = sto_kou_compensator(0.0f32, eta_up, 3.0f32)
    and(ok, not(eq(zeta, zeta)))
  }, true, [nan, inf, neg(inf)])
  assert_true(nonfinite, "Unused upward rates must still be finite")
}
