module Shoals.Tests.NautilusErfF64
import Nautilus.Special (erf)
import Std.Test (assert_true)
-- Nautilus 0.7.47 makes erf callable at f64. This only tests reachability:
-- nautilus#74 tracks its A&S accuracy, while Shoals.Pricing keeps Cody's.
def test_nautilus_erf_reaches_f64() -> unit ! { Test } = {
  value = erf(0.5f64)
  assert_true(and(gt(value, 0.520499f64), lt(value, 0.520501f64)), "imported erf accepts f64")
}
