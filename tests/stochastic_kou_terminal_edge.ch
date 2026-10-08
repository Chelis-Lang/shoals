module Shoals.Tests.StochasticKouTerminalEdge
import Std.Test (assert_true)
import Shoals.Stochastic (sto_kou_jump_terminal)
def make_template() -> tensor[8, f32] = to_tensor([0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32, 0.0f32])
def values_exact(xs: List[f32], ys: List[f32]) -> bool = and(eq(len(xs), len(ys)), fold(fn (ok: bool, pair: (f32, f32)) -> and(ok, eq(pair.0, pair.1)), true, zip(xs, ys)))
def test_kou_zero_probability_terminal_is_finite_and_exact_across_placeholders() -> unit ! { Test } = {
  reference = to_list(sto_kou_jump_terminal(key_from_seed(9i64), make_template(), make_template(), 100.0f32, 0.05f32, 0.2f32, 2.0f32, 0.0f32, 2.0f32, 3.0f32, 1.0f32))
  zero_up = to_list(sto_kou_jump_terminal(key_from_seed(9i64), make_template(), make_template(), 100.0f32, 0.05f32, 0.2f32, 2.0f32, 0.0f32, 0.0f32, 3.0f32, 1.0f32))
  half_up = to_list(sto_kou_jump_terminal(key_from_seed(9i64), make_template(), make_template(), 100.0f32, 0.05f32, 0.2f32, 2.0f32, 0.0f32, 0.5f32, 3.0f32, 1.0f32))
  unit_up = to_list(sto_kou_jump_terminal(key_from_seed(9i64), make_template(), make_template(), 100.0f32, 0.05f32, 0.2f32, 2.0f32, 0.0f32, 1.0f32, 3.0f32, 1.0f32))
  finite_positive = fold(fn (ok: bool, x: f32) -> and(ok, and(eq(sub(x, x), 0.0f32), gt(x, 0.0f32))), true, reference)
  _ = assert_true(and(eq(len(reference), 8i64), finite_positive), "Eight pure downward terminal prices are finite and positive")
  _ = assert_true(values_exact(zero_up, reference), "Zero upward rate preserves every seed-9 terminal value exactly")
  _ = assert_true(values_exact(half_up, reference), "Subunit upward rate preserves every seed-9 terminal value exactly")
  assert_true(values_exact(unit_up, reference), "Unit upward rate preserves every seed-9 terminal value exactly")
}
