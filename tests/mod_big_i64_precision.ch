module Shoals.Tests.ModBigI64Precision
import Std.Test (assert_close)
-- Promoted from tests_blocked/runtime/mod_big_i64_precision.ch at the chelis
-- 0.18.3 bump. chelis#680: builtin `mod(big_i64, m)` used to route through an
-- f64 path and lose precision once the operand exceeded f64's 53-bit mantissa
-- (~9e15). The Park-Miller-shaped update below returned 178065916 on 0.18.1
-- instead of the exact 178066070; it is exact on 0.18.3, on both the eval and
-- compiled-C lanes. This test pins that exactness so the regression cannot
-- return silently -- it is the reason `Shoals.Rng` may call the builtin `mod`
-- directly in its Sobol/xor bit walks instead of the `i64_mod` shim.
def test_mod_big_i64_precision() -> unit ! { Test } = {
  a = 1103515245i64
  s = 1406938949i64
  c = 12345i64
  m = 2147483647i64
  r = mod(add(mul(a, s), c), m)
  assert_close(cast(r, f32), cast(178066070.0, f32), cast(0.5, f32), "big-i64 mod precision")
}
