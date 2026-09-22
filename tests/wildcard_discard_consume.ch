module Shoals.Tests.WildcardDiscardConsume
import Std.Test (assert_eq)
-- Promoted from tests_blocked/linearity/wildcard_discard_consume.ch at the
-- chelis 0.18.5 bump. chelis#1200: a `_ =` wildcard discard used to desugar
-- with the `destructure: true` marker, opening the Linearity-F2
-- destructure-consume scope over the rest of the enclosing body. Any later
-- reuse of a variable that a record-destructuring callee had consumed was then
-- a hard `UseAfterConsume` instead of receiving the implicit Copy a named
-- binding gets. On the 0.18.4 binary the body below reported
-- `variable `b` (from a destructured binding) was already consumed by call to
-- `discard_tag_of``; on 0.18.5 it checks clean. This test pins the fix so the
-- regression cannot return silently -- it is the reason `tests/curves_basis.ch`
-- may discard its intermediate assertions with `_ =` again instead of holding
-- them in unused `asserted_N` bindings.
type DiscardBox =
  | DiscardBox { data: tensor[2, f32], tag: i64 }
def discard_tag_of(b: DiscardBox) -> i64 =
  match b with {
    | DiscardBox { data, tag } => tag
  }
def test_wildcard_discard_does_not_consume() -> unit ! { Test } = {
  b = DiscardBox { data: to_tensor([cast(1.0, f32), cast(2.0, f32)]), tag: 7i64 }
  _ = discard_tag_of(b)
  assert_eq(discard_tag_of(b), 7i64, "`_ =` discard must not consume `b` for the rest of the body")
}
