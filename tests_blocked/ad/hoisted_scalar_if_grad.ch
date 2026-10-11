module ShoalsBlockedHoistedScalarIfGrad
import Std.Test (assert_close)
-- chelis#3582: the original chelis#2640 inline-arm witness is fixed at 0.19.2,
-- but sharing a precomputed singular value between the condition and untaken
-- arm still leaks a NaN cotangent. The two controls distinguish that residue
-- from a general sqrt or live-arm derivative failure.
def hoisted(x: f64) -> f64 = {
  d = sqrt(x)
  if lt(d, cast(1.0, f64)) then cast(2.0, f64) else d
}
def inline_arm(x: f64) -> f64 = if lt(sqrt(x), cast(1.0, f64)) then cast(2.0, f64) else sqrt(x)
def test_inline_arm_zero_control() -> unit ! { Test } = assert_close(grad(inline_arm, wrt=x)(cast(0.0, f64)), cast(0.0, f64), cast(0.0, f64), "inline arm routes exact zero cotangent")
def test_live_arm_control() -> unit ! { Test } = {
  _ = assert_close(grad(hoisted, wrt=x)(cast(4.0, f64)), cast(0.25, f64), cast(1e-12, f64), "hoisted live arm derivative")
  assert_close(grad(inline_arm, wrt=x)(cast(4.0, f64)), cast(0.25, f64), cast(1e-12, f64), "inline live arm derivative")
}
def test_hoisted_untaken_arm_zero_cotangent() -> unit ! { Test } = assert_close(grad(hoisted, wrt=x)(cast(0.0, f64)), cast(0.0, f64), cast(0.0, f64), "hoisted untaken arm must route exact zero cotangent")
