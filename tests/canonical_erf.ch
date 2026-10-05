module Shoals.Tests.CanonicalErf
import Std.Test (assert_close)
def test_canonical_erf_and_erfc() -> unit ! { Test } = {
  x = cast(0.5, f64)
  _ = assert_close(erf(x), cast(0.5204998778130465, f64), cast(1e-15, f64), "canonical erf at 0.5")
  _ = assert_close(erfc(x), cast(0.4795001221869535, f64), cast(1e-15, f64), "canonical erfc at 0.5")
  ()
}
