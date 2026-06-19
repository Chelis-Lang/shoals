#!/usr/bin/env python3
"""Track B AD-Greeks validation harness.

Drives the SMT-enabled chelis binary's `eval` on SELF-CONTAINED inline f64
expressions (no package imports needed) that build a Black-Scholes call from
the exact Nautilus A&S erf approximation, take Greeks via `grad`/`grad(grad)`,
and compare against (a) the analytic textbook closed forms evaluated through
the SAME erf (isolates the AD chain rule) and (b) central finite differences
of the same chelis pricing body (isolates AD vs numerical differentiation).

All numeric outputs are parsed from chelis stdout `data=[...]`. Nothing is
computed in Python except the error reduction and the FD bumping recipe (the
bumped prices themselves are computed by chelis).
"""
import subprocess
import re
import math
import sys
import json
import itertools

CHELIS = "/home/jeff/Documents/scratch/chelis/target/release/chelis"

# ---------------------------------------------------------------------------
# Chelis source fragments (f64). erf = Nautilus.Special.erf A&S 7.1.26 coeffs.
# ---------------------------------------------------------------------------

# abs(x): if-lowers to masked arithmetic, fully differentiable.
ABS = "(fn (x: f64) -> if lt(x, cast(0.0, f64)) then neg(x) else x)"

# erf(x): two if-branches (small-x linearization; sign fold), A&S main branch.
ERF = f"""(fn (x: f64) ->
  (fn (ax: f64) ->
    if lt(ax, cast(0.00001, f64)) then mul(x, cast(1.1283791670955126, f64)) else
      (fn (t: f64) ->
        (fn (y: f64) -> if lt(x, cast(0.0, f64)) then neg(y) else y)
        (sub(cast(1.0, f64),
             mul(mul(t, add(cast(0.254829592, f64), mul(t, add(cast(-0.284496736, f64),
                 mul(t, add(cast(1.421413741, f64), mul(t, add(cast(-1.453152027, f64),
                 mul(t, cast(1.061405429, f64)))))))))),
                 exp(neg(mul(ax, ax)))))))
      (div(cast(1.0, f64), add(cast(1.0, f64), mul(cast(0.3275911, f64), ax)))))
  ({ABS}(x)))"""

# n_cdf(x) = 0.5 * erfc(-x/sqrt2) = 0.5 * (1 - erf(-x/sqrt2))  (EXACT Shoals expr)
NCDF = f"""(fn (z: f64) ->
  mul(cast(0.5, f64), sub(cast(1.0, f64), {ERF}(neg(mul(z, cast(0.7071067811865476, f64)))))))"""

# d1, d2
D1 = """(fn (s: f64, k: f64, r: f64, sg: f64, t: f64) ->
  div(add(log(div(s, k)), mul(add(r, mul(cast(0.5, f64), mul(sg, sg))), t)), mul(sg, sqrt(t))))"""
D2 = f"""(fn (s: f64, k: f64, r: f64, sg: f64, t: f64) ->
  sub({D1}(s, k, r, sg, t), mul(sg, sqrt(t))))"""

# Black-Scholes call price, pure scalar f64.
BS_CALL = f"""(fn (s: f64, k: f64, r: f64, sg: f64, t: f64) ->
  sub(mul(s, {NCDF}({D1}(s, k, r, sg, t))),
      mul(k, mul(exp(neg(mul(r, t))), {NCDF}({D2}(s, k, r, sg, t))))))"""

BS_PUT = f"""(fn (s: f64, k: f64, r: f64, sg: f64, t: f64) ->
  sub(mul(k, mul(exp(neg(mul(r, t))), {NCDF}(neg({D2}(s, k, r, sg, t))))),
      mul(s, {NCDF}(neg({D1}(s, k, r, sg, t))))))"""

# normal pdf  phi(x) = exp(-x^2/2)/sqrt(2pi)
NPDF = """(fn (x: f64) ->
  div(exp(neg(mul(cast(0.5, f64), mul(x, x)))), cast(2.5066282746310002, f64)))"""

# ---------------------------------------------------------------------------
# Textbook analytic Greeks (closed form), built through the SAME n_cdf / pdf.
# ---------------------------------------------------------------------------
ORACLE = {
    "delta": f"(fn (s: f64, k: f64, r: f64, sg: f64, t: f64) -> {NCDF}({D1}(s, k, r, sg, t)))",
    "vega":  f"(fn (s: f64, k: f64, r: f64, sg: f64, t: f64) -> mul(s, mul({NPDF}({D1}(s, k, r, sg, t)), sqrt(t))))",
    "rho":   f"(fn (s: f64, k: f64, r: f64, sg: f64, t: f64) -> mul(k, mul(t, mul(exp(neg(mul(r, t))), {NCDF}({D2}(s, k, r, sg, t))))))",
    # textbook theta = -dC/dt
    "theta": f"""(fn (s: f64, k: f64, r: f64, sg: f64, t: f64) ->
        add(neg(div(mul(mul(s, {NPDF}({D1}(s, k, r, sg, t))), sg), mul(cast(2.0, f64), sqrt(t)))),
            neg(mul(r, mul(k, mul(exp(neg(mul(r, t))), {NCDF}({D2}(s, k, r, sg, t))))))))""",
    "gamma": f"""(fn (s: f64, k: f64, r: f64, sg: f64, t: f64) ->
        div({NPDF}({D1}(s, k, r, sg, t)), mul(s, mul(sg, sqrt(t)))))""",
    # vanna = dDelta/dsigma = -pdf(d1) * d2 / sigma  (standard closed form)
    "vanna": f"""(fn (s: f64, k: f64, r: f64, sg: f64, t: f64) ->
        neg(div(mul({NPDF}({D1}(s, k, r, sg, t)), {D2}(s, k, r, sg, t)), sg)))""",
    # volga = vega * d1 * d2 / sigma
    "volga": f"""(fn (s: f64, k: f64, r: f64, sg: f64, t: f64) ->
        div(mul(mul(s, mul({NPDF}({D1}(s, k, r, sg, t)), sqrt(t))),
                mul({D1}(s, k, r, sg, t), {D2}(s, k, r, sg, t))), sg))""",
}

# ---------------------------------------------------------------------------
# AD Greek expressions: grad / grad(grad) over BS_CALL.
#
# COMPILER CONSTRAINT (discovered, see RESULTS.md "capture bug"): grad cannot
# differentiate a closure that CAPTURES a free f64 variable -- the backward DAG
# fails verification ("mismatched precisions F64 vs F32"). The supported forms
# are (a) `grad(named_fn, wrt=P)(args...)` passing every arg explicitly, or
# (b) a lambda whose non-differentiated args are INLINED AS LITERALS at the
# innermost call site (no capture across the grad boundary). Nested grad
# (gamma/vanna/volga) only lowers in the host evaluator via the inlined-literal
# lambda form, not via `grad(grad(named_fn, wrt=..), wrt=..)`. We therefore
# build per-cell, fully-literal Greek expressions.
# ---------------------------------------------------------------------------

def lit(v: float) -> str:
    return f"cast({v!r}, f64)"


def ad_greek_expr(greek: str, s, k, r, sg, t) -> str:
    """Fully literal-inlined AD Greek expression for one grid cell."""
    S, K, R, SG, T = lit(s), lit(k), lit(r), lit(sg), lit(t)

    def first(var_pos):  # grad of BS_CALL wrt the var at this position, others literal
        # var_pos in {s,sg,r,t}: build a 1-arg lambda with that slot live.
        slots = {"s": S, "k": K, "r": R, "sg": SG, "t": T}
        slots[var_pos] = "x"
        args = f"{slots['s']}, {slots['k']}, {slots['r']}, {slots['sg']}, {slots['t']}"
        seed = {"s": S, "sg": SG, "r": R, "t": T}[var_pos]
        return f"grad((fn (x: f64) -> {BS_CALL}({args})), wrt=x)({seed})"

    def second(outer, inner):
        # d/d(outer) of [ d/d(inner) of BS_CALL ]. inner is live as y, outer as x.
        slots = {"s": S, "k": K, "r": R, "sg": SG, "t": T}
        slots[inner] = "y"
        slots[outer] = "x"   # if outer==inner this overwrites to x; handle below
        if outer == inner:
            slots[inner] = "y"  # inner lambda var
        args = f"{slots['s']}, {slots['k']}, {slots['r']}, {slots['sg']}, {slots['t']}"
        # inner grad wrt y evaluated at x (so x feeds the inner seed via the inner var)
        inner_grad = f"grad((fn (y: f64) -> {BS_CALL}({args})), wrt=y)(x)"
        seed_outer = {"s": S, "sg": SG, "r": R, "t": T}[outer]
        return f"grad((fn (x: f64) -> {inner_grad}), wrt=x)({seed_outer})"

    if greek == "delta":
        return first("s")
    if greek == "vega":
        return first("sg")
    if greek == "rho":
        return first("r")
    if greek == "theta":
        return f"neg({first('t')})"   # textbook theta = -dC/dt
    if greek == "gamma":
        return second("s", "s")
    if greek == "volga":
        return second("sg", "sg")
    if greek == "vanna":
        # d2C/(dS dsigma): inner wrt s (y), outer wrt sigma (x).
        slots = {"s": "y", "k": K, "r": R, "sg": "x", "t": T}
        args = f"{slots['s']}, {slots['k']}, {slots['r']}, {slots['sg']}, {slots['t']}"
        inner_grad = f"grad((fn (y: f64) -> {BS_CALL}({args})), wrt=y)({S})"
        return f"grad((fn (x: f64) -> {inner_grad}), wrt=x)({SG})"
    raise KeyError(greek)


_num_re = re.compile(r"data=\[([^\]]*)\]")


def chelis_eval(expr: str) -> float:
    out = subprocess.run([CHELIS, "eval", expr], capture_output=True, text=True)
    txt = out.stdout.strip()
    m = _num_re.search(txt)
    if not m:
        # scalar prints bare sometimes
        try:
            return float(txt)
        except ValueError:
            raise RuntimeError(f"could not parse chelis output:\nSTDOUT:{out.stdout}\nSTDERR:{out.stderr}\nEXPR:{expr[:200]}")
    return float(m.group(1).split(",")[0])


def call5(fn: str, s, k, r, sg, t) -> str:
    return f"{fn}({lit(s)}, {lit(k)}, {lit(r)}, {lit(sg)}, {lit(t)})"


def main():
    # Grid: ITM/ATM/OTM spots, short/long maturity, vol & rate spread.
    spots = [80.0, 100.0, 120.0]      # OTM-ish, ATM, ITM (K=100)
    K = 100.0
    rs = [0.01, 0.05]
    sgs = [0.15, 0.30]
    ts = [0.25, 2.0]                  # short, long
    grid = list(itertools.product(spots, rs, sgs, ts))

    greeks = ["delta", "vega", "rho", "theta", "gamma", "vanna", "volga"]
    # FD steps tuned per Greek (relative to variable scale). gamma is 2nd order.
    results = {g: [] for g in greeks}

    for (s, r, sg, t) in grid:
        for g in greeks:
            ad_v = chelis_eval(ad_greek_expr(g, s, K, r, sg, t))
            or_v = chelis_eval(call5(ORACLE[g], s, K, r, sg, t))
            abs_e = abs(ad_v - or_v)
            rel_e = abs_e / max(abs(or_v), 1e-300)
            results[g].append({
                "S": s, "K": K, "r": r, "sigma": sg, "t": t,
                "ad": ad_v, "oracle": or_v, "abs_err": abs_e, "rel_err": rel_e,
            })

    # FD cross-check on first-order Greeks + gamma, at the ATM/representative cell.
    fd_report = fd_crosscheck(K)

    summary = {}
    for g in greeks:
        rows = results[g]
        max_abs = max(r["abs_err"] for r in rows)
        max_rel = max(r["rel_err"] for r in rows if abs(r["oracle"]) > 1e-8)
        summary[g] = {"max_abs": max_abs, "max_rel": max_rel, "n_cells": len(rows)}

    print(json.dumps({"summary": summary, "fd": fd_report, "cells": results}, indent=2))


def fd_crosscheck(K):
    """Central finite differences of the chelis BS body vs AD, tuned step per Greek."""
    s, r, sg, t = 100.0, 0.05, 0.2, 1.0
    report = {}

    def price(ss, kk, rr, vv, tt):
        return chelis_eval(call5(BS_CALL, ss, kk, rr, vv, tt))

    # First-order: central diff of the chelis price body vs AD. Sweep the step
    # and report the step that best agrees with AD (the FD-truncation floor).
    def bump_price(var, val):
        a = {"s": s, "r": r, "sg": sg, "t": t}
        a[var] = val
        return price(a["s"], K, a["r"], a["sg"], a["t"])

    base = {"delta": s, "vega": sg, "rho": r, "theta": t}
    var_of = {"delta": "s", "vega": "sg", "rho": "r", "theta": "t"}
    for name in ["delta", "vega", "rho", "theta"]:
        v0 = base[name]
        ad = chelis_eval(ad_greek_expr(name, s, K, r, sg, t))
        sweep = []
        for frac in [1e-2, 1e-3, 1e-4, 1e-5, 1e-6]:
            h = frac * abs(v0) if abs(v0) > 1e-9 else frac
            fp = bump_price(var_of[name], v0 + h)
            fm = bump_price(var_of[name], v0 - h)
            fd = (fp - fm) / (2 * h)
            if name == "theta":
                fd = -fd   # textbook theta = -dC/dt
            sweep.append({"frac": frac, "h": h, "fd": fd, "abs_err": abs(fd - ad)})
        best = min(sweep, key=lambda d: d["abs_err"])
        report[name] = {"ad": ad, "best_fd": best, "sweep": sweep}

    # gamma: d2C/dS2, central 2nd diff, TUNED step (sweep, extended to small h).
    ad_gamma = chelis_eval(ad_greek_expr("gamma", s, K, r, sg, t))
    gamma_sweep = []
    for frac in [1e-1, 5e-2, 1e-2, 5e-3, 1e-3, 5e-4]:
        h = frac * s
        fp = price(s + h, K, r, sg, t)
        f0 = price(s, K, r, sg, t)
        fm = price(s - h, K, r, sg, t)
        fd_g = (fp - 2 * f0 + fm) / (h * h)
        gamma_sweep.append({"h": h, "frac": frac, "fd": fd_g, "abs_err": abs(fd_g - ad_gamma)})
    best = min(gamma_sweep, key=lambda d: d["abs_err"])
    report["gamma"] = {"ad": ad_gamma, "best_fd": best, "sweep": gamma_sweep}

    # volga: d2C/dsigma2, central 2nd diff, tuned step.
    ad_volga = chelis_eval(ad_greek_expr("volga", s, K, r, sg, t))
    volga_sweep = []
    for frac in [1e-1, 5e-2, 1e-2, 5e-3, 1e-3]:
        h = frac * sg
        fp = price(s, K, r, sg + h, t)
        f0 = price(s, K, r, sg, t)
        fm = price(s, K, r, sg - h, t)
        fd_v = (fp - 2 * f0 + fm) / (h * h)
        volga_sweep.append({"h": h, "frac": frac, "fd": fd_v, "abs_err": abs(fd_v - ad_volga)})
    report["volga"] = {"ad": ad_volga, "best_fd": min(volga_sweep, key=lambda d: d["abs_err"]), "sweep": volga_sweep}

    # vanna: d2C/(dS dsigma), central mixed diff, tuned step.
    ad_vanna = chelis_eval(ad_greek_expr("vanna", s, K, r, sg, t))
    vanna_sweep = []
    for frac in [1e-1, 5e-2, 1e-2, 5e-3]:
        hs = frac * s
        hv = frac * sg
        fpp = price(s + hs, K, r, sg + hv, t)
        fpm = price(s + hs, K, r, sg - hv, t)
        fmp = price(s - hs, K, r, sg + hv, t)
        fmm = price(s - hs, K, r, sg - hv, t)
        fd_x = (fpp - fpm - fmp + fmm) / (4 * hs * hv)
        vanna_sweep.append({"hs": hs, "hv": hv, "frac": frac, "fd": fd_x, "abs_err": abs(fd_x - ad_vanna)})
    report["vanna"] = {"ad": ad_vanna, "best_fd": min(vanna_sweep, key=lambda d: d["abs_err"]), "sweep": vanna_sweep}
    return report


if __name__ == "__main__":
    main()
