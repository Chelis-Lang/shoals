# Credit default swaps

Module: `Shoals.Cds`.

`HazardCurve[n]` stores `n` elapsed year times and their piecewise hazard
rates as `f32` tensors. The times are measured from the valuation origin;
they are not calendar dates. Use `Shoals.Date.year_fraction` with a chosen
day-count convention when deriving them from dates.

`hazard_curve_from_pillars(times, hazards)` requires strictly increasing
times. It fails at the first duplicate or out-of-order pair, naming its index
and both values. It does not reorder caller-supplied pillars; a caller that
needs sorting must keep each time paired with its hazard. `cds_bootstrap_hazards` applies the
same check to its supplied tenors before solving any pillar.

`HazardCurve` is opaque. Construct it through one of those two functions and
use `hazard_curve_pillars(curve)` to read its `(times, hazards)` tensors.
Consumers cannot create a record literal that bypasses the ordering check.

`cds_survival_from_hazards(curve, t)` integrates the piecewise hazards to `t`
and returns `exp(-integral)`. `cds_premium_leg_value`,
`cds_protection_leg_value`, and `cds_pv` use the same curve. The premium grid
uses the supplied payment frequency; the protection leg uses monthly steps.
These functions use elapsed year times, a constant discount rate, and the
caller-supplied recovery. They do not generate a calendar payment schedule.
