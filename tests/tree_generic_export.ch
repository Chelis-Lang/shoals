module Shoals.Tests.TreeGenericExport
import Std.Test (assert_eq)
import Shoals.Trees (tr_binom_european_call_generic)
def test_generic_tree_zero_steps_payoff() -> unit ! { Test } = {
  price = tr_binom_european_call_generic(150.0f32, 100.0f32, 0.0f32, 0.0f32, 0.25f32, 0.5f32, 0i64)
  assert_eq(price, 50.0f32, "zero steps is terminal payoff")
}
def test_generic_tree_two_steps_discounted_constant_payoff() -> unit ! { Test } = {
  price = tr_binom_european_call_generic(150.0f32, 100.0f32, 0.0f32, 0.0f32, 0.25f32, 0.5f32, 2i64)
  assert_eq(price, 12.5f32, "two steps discount the constant payoff twice")
}
