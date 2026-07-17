module Shoals.TestsBlocked.ModBigI64Precision
import Std.Test (assert_close)
-- Blocked probe: builtin `mod(big_i64, m)` routes through an f64 path and
-- loses precision once the operand exceeds f64's 53-bit mantissa (~9e15).
-- Park-Miller-shaped update (a*s + c ~ 1.55e18) — the exact reason
-- `Shoals.Rng` hand-rolls `i64_mod` (sub/mul/floor_div) for the Sobol/xor
-- bit walks instead of calling the builtin. Same drift class as the school
-- shell's pinned probe. EXPECTED TO FAIL at the current pin.
def test_blocked_mod_big_i64_precision() -> unit ! { Test } = {
  a = 1103515245i64
  s = 1406938949i64
  c = 12345i64
  m = 2147483647i64
  r = mod(add(mul(a, s), c), m)
  assert_close(cast(r, f32), cast(178066070.0, f32), cast(0.5, f32), "big-i64 mod precision")
}
