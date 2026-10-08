# Credit default swaps

Module: `Shoals.Cds`.

This module values a single-name credit default swap from a piecewise-constant
hazard curve, and bootstraps that curve from par spreads. Times are elapsed
years from the valuation date as `f32`, not calendar dates; derive them with
`Shoals.Date.year_fraction` under the day count the contract uses. Spreads,
hazards, rates, and recovery are decimals (`0.01` is 100 basis points), and
every value is per unit of notional.

## Hazard curves

```chelis
def hazard_curve_from_pillars[n](times: tensor[n, f32], hazards: tensor[n, f32]) -> HazardCurve[n]
def hazard_curve_pillars[n](curve: HazardCurve[n]) -> (tensor[n, f32], tensor[n, f32])
def cds_survival_from_hazards[n](curve: HazardCurve[n], t: f32) -> f32
```

`hazards[i]` is the constant default intensity on the interval ending at
`times[i]`: the first applies from time 0 to `times[0]`, and the last
continues past the final pillar. `cds_survival_from_hazards(curve, t)` is
`exp(-integral of the hazard from 0 to t)`.

`hazard_curve_from_pillars` requires strictly increasing times. It fails at
the first duplicate or out-of-order pair, naming its index and both values.
It does not reorder pillars, and it does not check the hazards: a negative
hazard gives a survival probability above one. Pillar times should be
positive; a pillar at or before 0 covers no time. Survival at any `t <= 0`
is 1. With no pillars the curve has
zero hazard and every survival probability is 1. `HazardCurve` is opaque, so
the only ways to build one are this constructor and `cds_bootstrap_hazards`;
read it back with `hazard_curve_pillars`.

```chelis
curve = hazard_curve_from_pillars(
  to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32)]),
  to_tensor([cast(0.01, f32), cast(0.02, f32), cast(0.03, f32)])
)
q4 = cds_survival_from_hazards(curve, cast(4.0, f32))  -- 0.9231163 = exp(-(0.01 + 0.02 * 2 + 0.03))
q7 = cds_survival_from_hazards(curve, cast(7.0, f32))  -- 0.8436648
```

## Valuation

```chelis
def cds_premium_leg_value[n](spread: f32, t_maturity: f32, n_premiums_per_year: i64, hazards: HazardCurve[n], r: f32) -> f32
def cds_protection_leg_value[n](t_maturity: f32, recovery: f32, hazards: HazardCurve[n], r: f32) -> f32
def cds_pv[n](spread: f32, t_maturity: f32, n_premiums_per_year: i64, recovery: f32, hazards: HazardCurve[n], r: f32) -> f32
```

Discounting uses `exp(-r * t)` with one continuously compounded rate `r`.

- The premium leg pays on the grid `k / n_premiums_per_year` for
  `k = 1 .. trunc(t_maturity * n_premiums_per_year)`. Each payment is
  `spread * dt * DF(t_k) * Q(t_k)`, where `dt` is the time since the previous
  payment. There is no accrued premium on default, and a maturity that is not
  a whole number of periods drops the final stub.
- The protection leg uses a monthly grid to `t_maturity` and sums
  `(1 - recovery) * DF(midpoint) * (Q(t_{k-1}) - Q(t_k))`.
- `cds_pv` is protection minus premium: the value to the protection buyer.

The premium leg and `cds_pv` require `n_premiums_per_year >= 1` and fail
with a diagnostic naming the received frequency otherwise. Supply
`t_maturity > 0` and `0 <= recovery <= 1`; these conditions are not
checked. A recovery above 1 makes the protection leg negative.

```chelis
prem = cds_premium_leg_value(cast(0.01, f32), cast(5.0, f32), cast(4, i64), curve, cast(0.03, f32))  -- 0.044187766
prot = cds_protection_leg_value(cast(5.0, f32), cast(0.4, f32), curve, cast(0.03, f32))            -- 0.057317026
pv = cds_pv(cast(0.01, f32), cast(5.0, f32), cast(4, i64), cast(0.4, f32), curve, cast(0.03, f32))  -- 0.01312926
```

## Bootstrapping from par spreads

```chelis
def cds_bootstrap_hazards[n](spreads: tensor[n, f32], tenors: tensor[n, f32], recovery: f32, r: f32, n_premiums_per_year: i64) -> HazardCurve[n]
```

`cds_bootstrap_hazards` takes par spreads (positive decimals per year) at
strictly increasing positive tenors, with `0 <= recovery < 1` and
`n_premiums_per_year >= 1`, and
solves one hazard per tenor, in order, holding the earlier hazards fixed, so
that `cds_pv` at that tenor is zero. It checks tenor ordering before solving
any pillar and fails the same way as `hazard_curve_from_pillars`, naming
`Shoals.Cds.cds_bootstrap_hazards`. A nonempty bootstrap also checks the
payment frequency when it values each pillar. Empty spread and tenor
tensors produce an empty curve without reading the frequency.

Each pillar is solved by Brent's method over hazards in `[1e-6, 2.0]`, to a
tolerance of `1e-6` within 100 iterations. A spread whose hazard falls
outside that bracket does not fail: its hazard comes back NaN, and so does
every later pillar that depends on it. Spreads `[0.006, 5.0]` at tenors
`[1, 3]` return hazards `[0.009949725, NaN]`. Check the result for NaN
before using the curve.

```chelis
boot = cds_bootstrap_hazards(
  to_tensor([cast(0.006, f32), cast(0.01, f32), cast(0.012, f32)]),
  to_tensor([cast(1.0, f32), cast(3.0, f32), cast(5.0, f32)]),
  cast(0.4, f32), cast(0.03, f32), cast(4, i64)
)
-- hazards [0.009949725, 0.0201197, 0.025517497]
```

The module generates no calendar payment schedule, no IMM dates, and no
upfront fee; supply those terms through the times and spread you pass.
