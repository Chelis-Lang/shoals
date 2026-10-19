module ShoalsBlockedRollingF64Absent
import Nautilus.TimeSeries (ts_ewma_series)
-- This capability probe is scoped to the TimeSeries EWMA entry's f32
-- signature (nautilus#70). It says nothing about Nautilus.Rolling, whose
-- independent f64 list/tensor surface supplies the Shoals rolling wrappers.
-- A passing probe calls for a normal cross-width test, not a change to the
-- rolling wrappers' Option masks, complete-window rule, or lag validation.
def probe[n](values: &tensor[n, f64], alpha: f64) -> tensor[n, f64] = ts_ewma_series(values, alpha, cast(0.0, f64))
