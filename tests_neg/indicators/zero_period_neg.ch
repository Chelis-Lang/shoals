module Shoals.TestsNeg.IndicatorsZeroPeriod
import Std.Test (assert_eq)
import Shoals.Indicators (sma)
-- A window of 0 has no correct answer, so it traps rather than returning an
-- all-`None` series (which would report "no data" for a caller bug).
--
-- The assertion is deliberately the length an UNGUARDED implementation would
-- return, so this probe is not vacuous: if the guard were removed, the
-- assertion would PASS and `--expect neg` would flag the file. Verified by
-- removing the guard and observing the flip.
def test_neg_sma_rejects_zero_period() -> unit ! { Test } = assert_eq(len(sma([cast(1.0, f64), cast(2.0, f64), cast(3.0, f64)], cast(0, i64))), cast(3, i64), "sma with period 0 must trap before returning a length")
