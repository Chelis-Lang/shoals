module ShoalsBlockedRollingF64Absent
import Nautilus.TimeSeries (ts_ewma_series)
-- EXPECTED TO FAIL at this pin: the nearest thing to a rolling/exponential
-- series primitive reachable from a Shoals module is
-- `Nautilus.TimeSeries.ts_ewma_series`, and nautilus 0.7.46 declares it
-- `[n](values: &tensor[n, f32], alpha: f32, initial: f32) -> tensor[n, f32]`
-- -- f32, and tensor-shaped. An f64 `List[f64]` indicator path cannot call
-- it, which is why `Shoals.Indicators` carries its own `ind_rolling_*`,
-- `ind_shift` and `ind_diff` layer (shoals#83).
--
-- This probe tracks the DUPLICATION, not the accuracy and not the shape.
-- It is keyed on a symbol that EXISTS so it cannot rot on a guess: a probe
-- naming a not-yet-written `rolling_mean` would keep failing after
-- nautilus#85 landed under any other name, and that false negative is
-- indistinguishable from "still blocked".
--
-- Two upstream repairs bear on this and they are disjoint. An f64 signature
-- on `Nautilus.TimeSeries` is nautilus#70's f32-only tracking item, and it
-- is the one THIS probe detects. nautilus#85 is the separate request for
-- rolling-window and lag primitives on `List[f64]`; it is what actually
-- removes the reason for the borrowed layer, and this probe would still
-- fail if only nautilus#85 landed while the tensor surface stayed f32.
-- `Coral.Window` has the reductions already but is f32-only and not a
-- compiled lane (coral#26), so it is not a third branch here.
--
-- Not a chelis defect: f64 arithmetic and `List[f64]` higher-order
-- primitives both work at this pin. The barrier is a sibling shell's
-- declared width.
def probe[n](values: &tensor[n, f64], alpha: f64) -> tensor[n, f64] = ts_ewma_series(values, alpha, cast(0.0, f64))
