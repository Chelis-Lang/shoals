`Shoals.Cds` rejects duplicate or out-of-order hazard pillar times before
building or bootstrapping a curve, preventing a silently wrong survival
probability. `HazardCurve` is opaque; external record literals and patterns
must use the checked constructors and `hazard_curve_pillars` reader.
