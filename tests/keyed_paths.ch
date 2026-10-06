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
-- shoals#98 replaced the aggregate-Gaussian jump approximation with a genuine
-- compound-Poisson draw, so the old reference here -- which rebuilt
-- `jump_mean = lambda*t*jump_mean` and
-- `jump_std = sqrt(lambda*t*(jump_vol^2 + jump_mean^2))` by hand -- no longer
-- describes the sampler. It could not be ported either: it encoded the
-- distribution the fix removes, and reproducing the new one needs the
-- enumerated Poisson table, which does not belong in a key-routing test.
--
-- What IS still reproducible in closed form, and is the stronger claim of the
-- two, is the ZERO-INTENSITY reduction. At `lambda = 0` the jump count is
-- always zero and the compensator is exactly zero, so the sampler collapses to
-- GBM with drift `(mu - 0.5*sigma^2)*t` -- which is precisely what
-- `gbm_from_noise` above already encodes at these parameters. So this test now
-- pins that reduction AND that the diffusion noise is drawn from the LEFT
-- child, using the same reference the GBM test uses. The jump-side behaviour is
-- covered by `tests/stochastic_extended.ch`, which owns the model.
def test_merton_replay_and_diffusion_child_routing() -> unit ! { Test } = {
  a = merton_jump_terminal(key_from_seed(11i64), template(), template(), 100.0f32, 0.05f32, 0.2f32, 0.3f32, -0.1f32, 0.15f32, 1.0f32)
  b = merton_jump_terminal(key_from_seed(11i64), template(), template(), 100.0f32, 0.05f32, 0.2f32, 0.3f32, -0.1f32, 0.15f32, 1.0f32)
  _ = assert_true(exact3(copy(a), b), "same root replays all Merton samples")
  c = merton_jump_terminal(key_from_seed(17i64), template(), template(), 100.0f32, 0.05f32, 0.2f32, 0.3f32, -0.1f32, 0.15f32, 1.0f32)
  _ = assert_true(not(close3(a, c)), "a different root draws different Merton samples")
  idle = merton_jump_terminal(key_from_seed(11i64), template(), template(), 100.0f32, 0.05f32, 0.2f32, 0.0f32, -0.1f32, 0.15f32, 1.0f32)
  (left_reference, _) = split_key(key_from_seed(11i64))
  assert_true(close3(idle, gbm_from_noise(left_reference)), "at lambda=0 the sampler is GBM on the left child")
}
