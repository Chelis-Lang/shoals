module Shoals.Tests.KeyedPaths
import Nautilus.Distributions (normal_sample)
import Shoals.Stochastic (gbm_terminal, merton_jump_terminal, merton_compensated_drift)
import Std.Test (assert_true)
def template() -> tensor[3, f32] = to_tensor([0.0f32, 0.0f32, 0.0f32])
def close3(a: tensor[3, f32], b: tensor[3, f32]) -> bool = {
  pairs = zip(to_list(a), to_list(b))
  fold(fn (ok: bool, pair: (f32, f32)) -> {
    gap = sub(pair.0, pair.1)
    magnitude = if lt(gap, 0.0f32) then neg(gap) else gap
    and(ok, lt(magnitude, 0.001f32))
  }, true, pairs)
}
def exact3(a: tensor[3, f32], b: tensor[3, f32]) -> bool = {
  pairs = zip(to_list(a), to_list(b))
  fold(fn (ok: bool, pair: (f32, f32)) -> and(ok, eq(pair.0, pair.1)), true, pairs)
}
def gbm_from_noise(rng_key: key) -> tensor[3, f32] = {
  z = normal_sample(rng_key, template(), 0.0f32, 1.0f32)
  to_tensor(map(fn (zi: f32) -> exp(add(log(100.0f32), add(0.03f32, mul(0.2f32, zi)))), to_list(z)))
}
def test_gbm_replay_and_child_routing() -> unit ! { Test } = {
  (left, right) = split_key(key_from_seed(42i64))
  (left_again, _) = split_key(key_from_seed(42i64))
  (left_reference, right_reference) = split_key(key_from_seed(42i64))
  a = gbm_terminal(left, template(), 100.0f32, 0.05f32, 0.2f32, 1.0f32)
  b = gbm_terminal(left_again, template(), 100.0f32, 0.05f32, 0.2f32, 1.0f32)
  c = gbm_terminal(right, template(), 100.0f32, 0.05f32, 0.2f32, 1.0f32)
  _ = assert_true(exact3(copy(a), b), "same derived key replays all GBM samples")
  _ = assert_true(close3(a, gbm_from_noise(left_reference)), "left child supplies GBM noise")
  assert_true(close3(c, gbm_from_noise(right_reference)), "right child supplies GBM noise")
}
def merton_from_noise(rng_key: key) -> tensor[3, f32] = {
  (diff_key, jump_key) = split_key(rng_key)
  diff = to_list(normal_sample(diff_key, template(), 0.0f32, 1.0f32))
  jump = to_list(normal_sample(jump_key, template(), 0.0f32, 1.0f32))
  drift = merton_compensated_drift(0.05f32, 0.2f32, 0.3f32, -0.1f32, 0.15f32)
  jump_mean = mul(0.3f32, -0.1f32)
  jump_std = sqrt(mul(0.3f32, add(mul(0.15f32, 0.15f32), mul(-0.1f32, -0.1f32))))
  to_tensor(map(fn (pair: (f32, f32)) -> {
    log_terminal = add(log(100.0f32), add(add(drift, mul(0.2f32, pair.0)), add(jump_mean, mul(jump_std, pair.1))))
    exp(log_terminal)
  }, zip(diff, jump)))
}
def test_merton_two_child_draws_match_reference() -> unit ! { Test } = {
  a = merton_jump_terminal(key_from_seed(11i64), template(), template(), 100.0f32, 0.05f32, 0.2f32, 0.3f32, -0.1f32, 0.15f32, 1.0f32)
  b = merton_jump_terminal(key_from_seed(11i64), template(), template(), 100.0f32, 0.05f32, 0.2f32, 0.3f32, -0.1f32, 0.15f32, 1.0f32)
  _ = assert_true(exact3(copy(a), b), "same root replays all Merton samples")
  assert_true(close3(a, merton_from_noise(key_from_seed(11i64))), "diffusion and jump use separate ordered children")
}
