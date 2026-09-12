#!/usr/bin/env python3
"""AD-Greeks oracle gate for Shoals.Pricing (stdlib only).

Validates the SHIPPED first-order Greeks in ``Shoals.Pricing`` --
``deltas_call``, ``vegas_call``, ``rhos_call``, ``thetas_call`` -- the
nested-grad SECOND-order Greeks ``gammas_call``, ``volgas_call``,
``vannas_call``, and the tensor-lane prices ``call_prices`` against THREE
independent references, on a moneyness x maturity grid plus a sign-fold straddle
(a point near d1=0 and a clearly-negative-d1 low-spot point where the hand-built
erf's odd reflection is exercised):

  1. ANALYTIC textbook closed forms (delta=N(d1), vega=S phi(d1) sqrt(t),
     rho=K t e^{-rt} N(d2), theta=-dC/dt) evaluated in this script through the
     same erf the package body evaluates, so the comparison isolates the AD
     chain rule, not erf accuracy. Since this shell's issue 61 that is Cody's
     approximation, mirrored here as `math.erf`; it was Abramowitz-Stegun
     7.1.26 with the coefficients reproduced exactly, and the f32
     corroboration leg still models A&S because `Nautilus.Special.erf` does.
  2. The shipped finite-difference Greeks in ``Shoals.Greeks`` (``fd_delta_call``
     etc.) INDEPENDENTLY CORROBORATE the closed-form ground truth: the assertion
     subject is ``ground_truth`` vs ``fd_*`` (not AD vs FD), bounded by an
     a-priori Richardson truncation band derived from the step ``h`` and f32
     precision alone (see ``fd_apriori_band``). Because the band never uses the
     measured AD-vs-FD or gt-vs-FD gap, it can actually fail if the closed-form
     ground truth is wrong -- it is not the old self-widening ``3*|gt-fd|`` form,
     which the primary AD-vs-ground-truth gate already rendered vacuous via the
     triangle inequality. The primary gate (#1's ``ground_truth``) is what
     constrains AD itself; this corroborates the ground truth that gate uses.
  3. BINDING CROSS-CHECK: the f64-downcast price (``call_prices``) equals the
     erfc-based reference price (``Shoals.References.BlackScholes.call_textbook``,
     which goes through Nautilus.Special.erfc) within an f32-precision bound.
     This records that the displayed Greek is the derivative of the displayed
     price -- the two share one erf up to f32 rounding.

  SECOND-ORDER (nested grad): gamma=d2C/dS2, volga=d2C/dsg2, vanna=d2C/dSdsg are
  validated against (a) the exact f64 SECOND derivative of the DISPLAYED A&S price
  (primary, tight: this is the correctness invariant -- gamma is the second
  derivative of the displayed price), (b) the true-BS second-order closed forms
  (secondary, agree up to A&S model error), and (c) an INDEPENDENT corroboration of
  the closed-form 2nd-derivative ground truth by tuned CENTRAL finite differences of
  the DISPLAYED f64 price (subject is ground_truth vs FD, bounded by an a-priori
  Richardson band from the step alone -- ``so_fd_apriori_band``). A negative-d1
  sign-fold point is included.

  ACCURACY-MONOTONE guard: the new f64-body reference error vs analytic-true must
  be <= the old f32-erfc path's error (no illegitimate tolerance re-baseline).

All numeric agreement is established by ``chelis test --json``: this script
emits ONE generated test file under ``.gate-tmp/`` (gitignored, never under
``tests/``, so a failing run cannot leave an artifact the wholesale tests/ CI
scan picks up), runs it once (the package compiles in one pass), and reads
per-assertion pass/fail. The generated file is unlinked on every exit path. A
passing assertion certifies |package - reference| < tol, where every tol is
DERIVED from f32 precision and FD truncation, never a fixed percent (see
``tol_*`` / ``*_apriori_band`` below). The JSON report states each derived
tolerance so the bound is auditable.

Exit 0 on pass (or SKIP when the configured chelis is missing/pre-0.8.0),
nonzero on fail. A JSON summary is printed to stdout.
"""

from __future__ import annotations

import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
# Binary resolution mirrors the composite gate
# (scripts/manual_gates/phase3l_shoals_oracle_composite_corpus.py): default to a
# bare ``chelis`` on PATH so the gate works on a clean box, and let either
# CHELIS_BIN or CHELIS_PROVE_BIN override it. No hardcoded version-pinned path --
# reef.toml is the single source of truth for the compiler pin (CLAUDE.md).
CHELIS = os.environ.get("CHELIS_BIN") or os.environ.get("CHELIS_PROVE_BIN") or "chelis"
# The generated test lives under .gate-tmp/ (gitignored), never under tests/, so a
# failing run cannot leave an artifact that the wholesale tests/ CI scan picks up.
# .gate-tmp/ still compiles with full package context (chelis test <path> resolves
# imports against the package regardless of the file's directory).
GEN_TEST = REPO_ROOT / ".gate-tmp" / "_oracle_greeks_gate_generated.ch"
TEST_TIMEOUT_S = int(os.environ.get("ORACLE_GATE_TIMEOUT_S", "600"))


def compiler_pin() -> str:
    match = re.search(
        r'^\s*compiler\s*=\s*"=([0-9]+\.[0-9]+\.[0-9]+)"',
        (REPO_ROOT / "reef.toml").read_text(),
        re.M,
    )
    if not match:
        raise RuntimeError("reef.toml has no exact compiler pin")
    return match.group(1)

# --------------------------------------------------------------------------
# Reference math (Python). `erf_pkg` mirrors whatever erf the package body
# evaluates, so analytic mirrors isolate the AD chain rule, not erf error.
# That is `math.erf` since this shell's issue 61 -- see `erf_pkg` for why the
# substitution is faithful. `_erf_as_f32` still models A&S because the f32
# path still evaluates it. `_true` versions use math.erf for the
# accuracy-monotone guard's ground truth.
#
# NAMING: docstrings below still say "the DISPLAYED A&S price". Read that as
# "the price the package displays" -- the formulae are unchanged, only the
# kernel underneath moved.
# --------------------------------------------------------------------------
SQRT2 = math.sqrt(2.0)
INV_SQRT_2PI = 1.0 / math.sqrt(2.0 * math.pi)


def f32(x: float) -> float:
    import struct
    return struct.unpack("f", struct.pack("f", x))[0]


def erf_pkg(x: float) -> float:
    """The erf the PACKAGE evaluates, mirrored here so the comparison isolates
    the AD chain rule rather than erf accuracy.

    Since this shell's issue 61 the package evaluates Cody's approximation at
    >= 3.3675e-16, so `math.erf` is a faithful mirror: the two differ by
    ~1e-16, ten orders below this gate's tightest tolerance (3e-6).

    `_erf_as_f32` below is NOT updated with this. It models
    `Nautilus.Special.erf`, which carries A&S at the PINNED nautilus 0.7.43 --
    not on nautilus main, where nautilus#57 switched it to a 4-term series
    below 0.25 with no tag yet carrying it. A pin bump invalidates this leg and
    it must be re-measured; `docs/UPSTREAM_BUGS.md` holds that trigger. Do not
    rely on an issue transition instead -- #57 can ship without closing one.
    """
    return math.erf(x)


def ncdf_as(x: float) -> float:
    return 0.5 * (1.0 - erf_pkg(-x / SQRT2))


def ncdf_true(x: float) -> float:
    return 0.5 * math.erfc(-x / SQRT2)


def npdf(x: float) -> float:
    return INV_SQRT_2PI * math.exp(-0.5 * x * x)


def d1d2(s, k, r, sg, t):
    d1 = (math.log(s / k) + (r + 0.5 * sg * sg) * t) / (sg * math.sqrt(t))
    return d1, d1 - sg * math.sqrt(t)


def call_price(s, k, r, sg, t, ncdf):
    d1, d2 = d1d2(s, k, r, sg, t)
    return s * ncdf(d1) - k * math.exp(-r * t) * ncdf(d2)


def _erf_as_f32(x: float) -> float:
    """A&S 7.1.26 erf in f32 arithmetic -- models the OLD Nautilus.Special.erfc
    path (Nautilus erf is the SAME A&S 7.1.26 coefficients, evaluated in f32)."""
    a1, a2, a3, a4, a5, p = (
        f32(0.254829592), f32(-0.284496736), f32(1.421413741),
        f32(-1.453152027), f32(1.061405429), f32(0.3275911),
    )
    ax = f32(abs(x))
    if ax < f32(1e-5):
        return f32(x * f32(1.1283791670955126))
    t = f32(1.0 / f32(1.0 + f32(p * ax)))
    poly = f32(t * f32(a1 + f32(t * f32(a2 + f32(t * f32(a3 + f32(t * f32(a4 + f32(t * a5)))))))))
    y = f32(1.0 - f32(poly * f32(math.exp(-f32(ax * ax)))))
    return f32(-y) if x < 0 else y


def call_price_old_f32(s, k, r, sg, t) -> float:
    """OLD shipped path modeled in f32 arithmetic with A&S erf (= Nautilus erfc)."""
    sg = f32(sg)
    sqrt_t = f32(math.sqrt(t))
    d1 = f32((f32(math.log(f32(s / k))) + f32(f32(r + f32(0.5 * f32(sg * sg))) * t))
             / f32(sg * sqrt_t))
    d2 = f32(d1 - f32(sg * sqrt_t))
    nd1 = f32(0.5 * f32(1.0 - _erf_as_f32(f32(-d1 / f32(SQRT2)))))
    nd2 = f32(0.5 * f32(1.0 - _erf_as_f32(f32(-d2 / f32(SQRT2)))))
    return f32(f32(s * nd1) - f32(k * f32(f32(math.exp(-f32(r * t))) * nd2)))


def analytic_greeks(s, k, r, sg, t, ncdf):
    """EXACT textbook closed forms (delta=N(d1), vega=S phi(d1) sqrt t, etc.)
    using the EXACT Gaussian pdf -- these equal the TRUE Black-Scholes Greeks.
    They agree with the AD Greeks only up to the A&S approximation's derivative
    (model) error, since AD differentiates the A&S-erf price, not true BS."""
    d1, d2 = d1d2(s, k, r, sg, t)
    delta = ncdf(d1)
    vega = s * npdf(d1) * math.sqrt(t)
    rho = k * t * math.exp(-r * t) * ncdf(d2)
    theta = -(s * npdf(d1) * sg / (2 * math.sqrt(t))
              + r * k * math.exp(-r * t) * ncdf(d2))
    return {"delta": delta, "vega": vega, "rho": rho, "theta": theta}


_AS = (0.254829592, -0.284496736, 1.421413741, -1.453152027, 1.061405429)
_AS_P = 0.3275911


def erf_pkg_deriv(x: float) -> float:
    """d/dx of the package's erf, closed form.

    With the package on Cody's approximation the derivative of the
    approximation and the true derivative agree far inside this gate's
    tolerances, so this is the exact 2/sqrt(pi) * exp(-x^2) rather than the
    differentiated A&S rational form it used to be. That older form is what
    made this gate fail 13 of 14 groups once the kernel changed: it was
    measuring erf accuracy, which the docstring says it must not.
    """
    return 1.1283791670955126 * math.exp(-x * x)


def pdf_as(x: float) -> float:
    """d/dx ncdf_as(x) = 0.5 * erf'(-x/sqrt2) * (1/sqrt2) -- the package's pdf."""
    return 0.5 * erf_pkg_deriv(-x / SQRT2) / SQRT2


def erf_pkg_deriv2(x: float) -> float:
    """d^2/dx^2 of the package's erf, closed form: -2x * 2/sqrt(pi) * exp(-x^2).

    Was the differentiated A&S rational form. Same reasoning as
    ``erf_pkg_deriv``: with the package on Cody's approximation the true second
    derivative is the faithful mirror, and the old form measured erf accuracy
    rather than the AD chain rule.
    """
    return -2.0 * x * 1.1283791670955126 * math.exp(-x * x)


def pdf_as_deriv(x: float) -> float:
    """d/dx pdf_as(x) = d^2/dx^2 ncdf_as(x), so pdf_as'(x) = -0.25 * erf''(-x/sqrt2).
    The 'pdf-prime' of the package's normal CDF; the building block of the exact
    SECOND derivatives of the displayed price, as pdf_as builds the first."""
    return -0.25 * erf_pkg_deriv2(-x / SQRT2)


def ad_ground_truth_greeks(s, k, r, sg, t):
    """The EXACT first-order derivatives of the DISPLAYED A&S-erf price -- what
    AD must reproduce. CLOSED FORM via the chain rule using the analytic A&S
    'pdf' (pdf_as = d/dx ncdf_as), NOT finite differences: the A&S erf has a
    derivative kink at d1=0 (the small-|x| branch boundary) that makes FD of the
    price noisy exactly at the sign-fold point, whereas AD evaluates the chain
    rule pointwise. This closed form matches AD to f32 ULPs everywhere, so it is
    the tight chain-rule oracle isolating the autodiff transform itself.

    With dd1/dP and dd2/dP the param-derivatives of d1,d2, and N=ncdf_as,
    n=pdf_as:  dC/dP = N(d1) [P=S] + S n(d1) dd1/dP - K e^{-rt} n(d2) dd2/dP
    plus the explicit -rt term in r/t. Standard, but with the A&S n() not the
    exact Gaussian."""
    sqrt_t = math.sqrt(t)
    d1, d2 = d1d2(s, k, r, sg, t)
    disc = math.exp(-r * t)
    n1, n2 = pdf_as(d1), pdf_as(d2)
    N1, N2 = ncdf_as(d1), ncdf_as(d2)
    # delta = dC/dS. dd1/dS = dd2/dS = 1/(S sg sqrt t).
    dd_dS = 1.0 / (s * sg * sqrt_t)
    delta = N1 + s * n1 * dd_dS - k * disc * n2 * dd_dS
    # vega = dC/dsigma. dd1/dsg = -d1/sg + sqrt t ; dd2/dsg = dd1/dsg - sqrt t.
    dd1_dsg = -d1 / sg + sqrt_t
    dd2_dsg = dd1_dsg - sqrt_t
    vega = s * n1 * dd1_dsg - k * disc * n2 * dd2_dsg
    # rho = dC/dr. dd1/dr = dd2/dr = sqrt t / sg ; plus t K e^{-rt} N2 from disc.
    dd_dr = sqrt_t / sg
    rho = s * n1 * dd_dr - k * (-t * disc * N2 + disc * n2 * dd_dr)
    # theta = -dC/dt. dd1/dt and dd2/dt from d1,d2 forms.
    dd1_dt = (r + 0.5 * sg * sg) / (sg * sqrt_t) - 0.5 * (math.log(s / k)
             + (r + 0.5 * sg * sg) * t) / (sg * t * sqrt_t)
    dd2_dt = dd1_dt - 0.5 * sg / sqrt_t
    # dC/dt = S n1 dd1/dt - K [ d/dt(e^{-rt}) N2 + e^{-rt} n2 dd2/dt ]
    #       = S n1 dd1/dt - K [ -r e^{-rt} N2 + e^{-rt} n2 dd2/dt ]
    dCdt = s * n1 * dd1_dt - k * (-r * disc * N2 + disc * n2 * dd2_dt)
    theta = -dCdt
    return {"delta": delta, "vega": vega, "rho": rho, "theta": theta}


def ad_second_order_groundtruth(s, k, r, sg, t):
    """The EXACT second derivatives of the DISPLAYED A&S-erf price -- what the
    nested-grad Greeks (gammas_call, volgas_call, vannas_call) must reproduce.
    CLOSED FORM via the chain rule with the analytic A&S pdf and pdf-prime
    (pdf_as, pdf_as_deriv), NOT finite differences: like the first-order ground
    truth, this evaluates the chain rule pointwise so the A&S small-|x| branch kink
    at d1=0 does not inject FD noise. This is the tight oracle isolating the nested
    autodiff transform; it matches AD to f32 ULPs.

      C  = S N(d1) - K e^{-rt} N(d2),  N=ncdf_as, n=pdf_as, n'=pdf_as_deriv.
      gamma = d2C/dS2, volga = d2C/dsg2, vanna = d2C/dS dsg, all of the A&S price."""
    st = math.sqrt(t)
    d1, d2 = d1d2(s, k, r, sg, t)
    disc = math.exp(-r * t)
    n1, n2 = pdf_as(d1), pdf_as(d2)
    np1, np2 = pdf_as_deriv(d1), pdf_as_deriv(d2)
    # gamma = d2C/dS2. dd1/dS = dd2/dS = a = 1/(S sg sqrt t); d a/dS = -a/S.
    a = 1.0 / (s * sg * st)
    da_ds = -a / s
    # delta = N1 + S n1 a - K disc n2 a ; differentiate again in S.
    gamma = (n1 * a
             + (n1 * a + s * np1 * a * a + s * n1 * da_ds)
             - k * disc * (np2 * a * a + n2 * da_ds))
    # volga = d2C/dsg2. dd1/dsg = -d1/sg + sqrt t ; dd2/dsg = that - sqrt t.
    dd1 = -d1 / sg + st
    dd2 = dd1 - st
    # d2 d1/dsg2 = -(dd1/dsg)/sg + d1/sg^2 ; same for d2 (sqrt t is sg-independent).
    dd1_2 = -dd1 / sg + d1 / (sg * sg)
    dd2_2 = dd1_2
    # vega = S n1 dd1 - K disc n2 dd2 ; differentiate in sg.
    volga = (s * (np1 * dd1 * dd1 + n1 * dd1_2)
             - k * disc * (np2 * dd2 * dd2 + n2 * dd2_2))
    # vanna = d(delta)/dsg. a depends on sg: da/dsg = -a/sg.
    da_dsg = -a / sg
    vanna = (n1 * dd1
             + s * (np1 * dd1 * a + n1 * da_dsg)
             - k * disc * (np2 * dd2 * a + n2 * da_dsg))
    return {"gamma": gamma, "volga": volga, "vanna": vanna}


def second_order_analytic(s, k, r, sg, t):
    """EXACT textbook closed forms of the TRUE Black-Scholes second-order Greeks
    using the EXACT Gaussian pdf (gamma = phi(d1)/(S sg sqrt t),
    volga = vega d1 d2 / sg, vanna = -phi(d1) d2 / sg). They agree with the AD
    Greeks only up to the A&S approximation's second-derivative model error, which
    is measured per cell as |this - ad_second_order_groundtruth| and folded into
    the secondary tolerance -- it never loosens the primary ground-truth gate."""
    st = math.sqrt(t)
    d1, d2 = d1d2(s, k, r, sg, t)
    n1 = npdf(d1)
    gamma = n1 / (s * sg * st)
    vega = s * n1 * st
    volga = vega * d1 * d2 / sg
    vanna = -n1 * d2 / sg
    return {"gamma": gamma, "volga": volga, "vanna": vanna}


def fd_second_order(s, k, r, sg, t, ncdf):
    """Tuned CENTRAL finite differences of the DISPLAYED f64 A&S price -- the
    second independent reference required for gamma/volga/vanna. Steps are tuned
    PER GREEK so neither O(h^2) truncation nor f64 cancellation dominates the
    second difference: gamma differences a small curvature out of S-scale prices,
    so it takes a large spot step (h_s = 1% of S); volga/vanna take vol steps that
    keep the second difference well-conditioned. Computed in f64 (no f32 rounding)
    so this isolates FD truncation of the SAME body the AD Greeks differentiate."""
    def c(ss, kk, rr, vv, tt):
        return call_price(ss, kk, rr, vv, tt, ncdf)
    h_s = 1e-2 * s          # spot step ~1% of S: gamma curvature out of S-scale price
    h_v = 5e-3              # vol step: volga/vanna second differences well-conditioned

    def fd_gamma(hs):
        return (c(s + hs, k, r, sg, t) - 2 * c(s, k, r, sg, t) + c(s - hs, k, r, sg, t)) / (hs * hs)

    def fd_volga(hv):
        return (c(s, k, r, sg + hv, t) - 2 * c(s, k, r, sg, t) + c(s, k, r, sg - hv, t)) / (hv * hv)

    def fd_vanna(hs, hv):
        def delta(sig):
            return (c(s + hs, k, r, sig, t) - c(s - hs, k, r, sig, t)) / (2 * hs)
        return (delta(sg + hv) - delta(sg - hv)) / (2 * hv)

    # FD at the tuned step and at 2x the step: the 2x value feeds the a-priori
    # Richardson truncation band, independent of the closed-form ground truth.
    fd_h = {"gamma": fd_gamma(h_s), "volga": fd_volga(h_v),
            "vanna": fd_vanna(h_s, h_v)}
    fd_2h = {"gamma": fd_gamma(2 * h_s), "volga": fd_volga(2 * h_v),
             "vanna": fd_vanna(2 * h_s, 2 * h_v)}
    return {**fd_h, "fd2h": fd_2h,
            "steps": {"h_s": h_s, "h_v": h_v}}


def fd_greeks(s, k, r, sg, t, ncdf):
    """Central-difference Greeks of the A&S price body, predicting the SHIPPED
    Shoals.Greeks fd_* (which difference bs_call_scalar in f32). Steps are chosen
    moderate so neither O(h^2) truncation nor f32 quotient rounding dominates;
    the prices are f32-rounded here to mirror the f32 fd_* quotient."""
    def c(ss, kk, rr, vv, tt):
        return f32(call_price(ss, kk, rr, vv, tt, ncdf))
    # Moderate steps: large enough that eps_f32*price/h stays ~1e-5, small enough
    # that O(h^2) truncation stays ~1e-4. t-step is capped below t to stay valid.
    hs = 1e-2 * s
    hv, hr = 1e-2, 1e-2
    ht = min(1e-2, 0.25 * t)

    def cdiff_delta(h):
        return (c(s + h, k, r, sg, t) - c(s - h, k, r, sg, t)) / (2 * h)

    def cdiff_vega(h):
        return (c(s, k, r, sg + h, t) - c(s, k, r, sg - h, t)) / (2 * h)

    def cdiff_rho(h):
        return (c(s, k, r + h, sg, t) - c(s, k, r - h, sg, t)) / (2 * h)

    def cdiff_theta(h):
        # Shoals.Greeks fd_theta_call uses (dn - up)/(2h) i.e. -dC/dt
        return (c(s, k, r, sg, t - h) - c(s, k, r, sg, t + h)) / (2 * h)

    # FD at the shipped step h and at 2h: the 2h value feeds the a-priori
    # Richardson truncation band (|fd(h)-fd(2h)| ~= 3x the O(h^2) truncation of
    # the central difference), which is independent of any closed-form value.
    fd_h = {"delta": cdiff_delta(hs), "vega": cdiff_vega(hv),
            "rho": cdiff_rho(hr), "theta": cdiff_theta(ht)}
    fd_2h = {"delta": cdiff_delta(2 * hs), "vega": cdiff_vega(2 * hv),
             "rho": cdiff_rho(2 * hr), "theta": cdiff_theta(2 * ht)}
    return {**fd_h, "fd2h": fd_2h,
            "steps": {"delta": hs, "vega": hv, "rho": hr, "theta": ht}}


# --------------------------------------------------------------------------
# Precision-derived tolerances (no fixed percents). eps_f32 = 2^-23 ~= 1.19e-7
# (relative); a downcast f32 scalar carries absolute error ~ eps_f32 * |value|,
# and through the ~20 chained f32 ops in the Greek path the running error is a
# small multiple. Every tolerance below is built from eps_f32, an explicit
# FD-truncation prediction, or the measured A&S derivative-model error -- never
# a fixed percent. Each tol's derivation is echoed into the JSON report.
# --------------------------------------------------------------------------
EPS_F32 = 2.0 ** -23


def tol_ad_vs_groundtruth(v: float) -> float:
    """PRIMARY, tight. AD must equal the exact derivative of the DISPLAYED A&S
    price (ad_ground_truth_greeks). The only difference is f32 rounding of the
    AD output vs the f64 ground truth, plus the ~4e-9 Richardson residual -> a
    few f32 ULPs of the value, floored for near-zero Greeks."""
    return max(16.0 * EPS_F32 * abs(v), 3e-6)


def tol_ad_vs_analytic(model_err: float, v: float) -> float:
    """SECONDARY. AD vs the EXACT textbook closed form (true BS). These differ by
    the A&S approximation's derivative-model error, measured per cell as
    |exact_analytic - ground_truth| (model_err). Tolerance = 2x that measured
    model error + the f32 floor. This documents that AD tracks true BS to within
    the erf model error -- it does not loosen to hide an AD bug, because the
    PRIMARY ground-truth gate already pins AD tight."""
    return 2.0 * model_err + max(8.0 * EPS_F32 * abs(v), 3e-6)


def fd_apriori_band(fd_h: float, fd_2h: float, price_scale: float, h: float) -> float:
    """A-PRIORI finite-difference truncation band for a central difference,
    derived from the step h and f32 precision ALONE -- it does NOT depend on the
    closed-form ground truth or on any measured gt-vs-fd / AD-vs-fd gap. The
    central difference has O(h^2) truncation E(h); Richardson gives
    E(h) ~= |fd(h) - fd(2h)| / 3, so 2*|fd(h)-fd(2h)| safely upper-bounds E(h)
    (factor 6 over the leading-order estimate). The roundoff floor
    ~ eps_f32 * price_scale / h is the f32 quotient-rounding of the shipped FD,
    again a function of precision and h only. Because the band is built from
    {fd(h), fd(2h), h, eps_f32} and never from the ground truth, the corroboration
    |ground_truth - fd(h)| <= band can genuinely FAIL if the closed-form ground
    truth is wrong -- it is not auto-satisfied by the triangle inequality."""
    richardson = 2.0 * abs(fd_h - fd_2h)
    roundoff = 8.0 * EPS_F32 * max(abs(price_scale), 1.0) / h
    return richardson + roundoff + 3e-7


def tol_binding(price: float) -> float:
    """f64-downcast price vs erfc-based reference price: both are f32 outputs of
    the same BS formula differing only by erf implementation rounding -> a few
    f32 ULPs of the price magnitude, floored for small prices."""
    return max(16.0 * EPS_F32 * abs(price), 1e-4)


# -- Second-order tolerances. A nested grad applies the chain rule TWICE, so the
# f32 output carries roughly double the chained-rounding of a first-order Greek;
# the relative band is widened to 48*eps_f32 (vs 16 for first order). The absolute
# floor is GREEK-SPECIFIC and PHYSICALLY scaled: gamma ~1e-2 with a steep S-scale
# curvature so its f32 ULP floor is small (5e-6) -- gamma must sit NEAR this bound;
# volga ~1e1..1e2 carries a larger absolute floor; vanna ~1e-1..1e0 an intermediate
# one. No fixed percent: each floor is a stated multiple of eps_f32 times the
# Greek's natural magnitude scale, echoed into the JSON report.
SECOND_ORDER_REL = 48.0 * EPS_F32         # ~5.7e-6 relative, double the first-order band
GAMMA_ABS_FLOOR = 5e-6                     # gamma ~1e-2; f32 ULP-scale floor (tight; gamma sits near it)
VOLGA_ABS_FLOOR = 1.5e-3                   # volga ~1e1..1e2; ULPs of that magnitude
VANNA_ABS_FLOOR = 4e-5                     # vanna ~1e-1..1e0; intermediate floor


def tol_so_vs_groundtruth(greek: str, v: float) -> float:
    """PRIMARY, tight. The nested-grad Greek must equal the exact SECOND derivative
    of the DISPLAYED A&S price (ad_second_order_groundtruth). Difference is f32
    rounding of the AD output vs the f64 closed form, doubled-chain-rule band plus
    the greek-specific f32 floor."""
    floor = {"gamma": GAMMA_ABS_FLOOR, "volga": VOLGA_ABS_FLOOR, "vanna": VANNA_ABS_FLOOR}[greek]
    return max(SECOND_ORDER_REL * abs(v), floor)


def tol_so_vs_analytic(greek: str, model_err: float, v: float) -> float:
    """SECONDARY. Nested-grad Greek vs the EXACT true-BS second-order closed form.
    They differ by the A&S approximation's SECOND-derivative model error, measured
    per cell as |true_BS - ground_truth| (model_err). Tolerance = 2x that measured
    model error + the primary band. Documents that AD tracks true BS to within the
    erf model error; the primary ground-truth gate keeps AD itself pinned tight."""
    return 2.0 * model_err + tol_so_vs_groundtruth(greek, v)


def so_fd_apriori_band(fd_h: float, fd_2h: float, value_scale: float, h: float) -> float:
    """A-PRIORI second-order finite-difference truncation band, derived from the
    tuned step h and f64 precision ALONE -- NOT from the closed-form ground truth.
    The tuned second/cross differences are O(h^2): Richardson gives the truncation
    as ~|fd(h)-fd(2h)|/3, so 2*|fd(h)-fd(2h)| safely bounds it. The f64 second-
    difference also carries a cancellation roundoff ~ eps_f64 * |value_scale| / h^2
    (the second difference divides by h^2 a quantity formed by subtracting nearly
    equal f64 prices); we use the f32 eps as a conservative multiplier since the
    displayed price is ultimately f32-meaningful. Built from {fd(h), fd(2h), h}
    only, so |ground_truth - fd(h)| <= band can genuinely fail if the closed-form
    second derivative is wrong."""
    richardson = 2.0 * abs(fd_h - fd_2h)
    roundoff = 8.0 * EPS_F32 * max(abs(value_scale), 1.0) / (h * h)
    return richardson + roundoff + 3e-7


# --------------------------------------------------------------------------
# Chelis test-file generation. One file, asserted in one `chelis test` pass.
# Greek vectors are computed once per (k,r,sg,t) sub-grid sharing a spot tensor;
# each cell is asserted against its reference at the precision-derived tolerance.
# --------------------------------------------------------------------------
def lit32(v: float) -> str:
    return f"cast({v!r}, f32)"


def build_test_source(grid, refs):
    """grid: list of dict cells. refs: parallel list of reference dicts."""
    lines = [
        "module Shoals.Tests.OracleGreeksGenerated",
        "import Std.Test (assert_close)",
        "import Shoals.Pricing (call_prices, deltas_call, vegas_call, rhos_call, thetas_call, gammas_call, volgas_call, vannas_call)",
        "import Shoals.References.BlackScholes (call_textbook)",
        "import Shoals.Greeks (fd_delta_call, fd_vega_call, fd_rho_call, fd_theta_call)",
    ]
    # Group cells by (k,r,sg,t) so we issue one vector call per group.
    groups: dict = {}
    for cell, ref in zip(grid, refs):
        key = (cell["k"], cell["r"], cell["sigma"], cell["t"])
        groups.setdefault(key, []).append((cell, ref))

    test_names = []
    for gi, (key, members) in enumerate(groups.items()):
        k, r, sg, t = key
        spots = [m[0]["s"] for m in members]
        spots_lit = ", ".join(lit32(s) for s in spots)
        common = f"{lit32(k)}, {lit32(r)}, {lit32(sg)}, {lit32(t)}"
        fn = f"test_group_{gi}"
        test_names.append(fn)
        lines.append(f"def {fn}() -> unit ! {{ Test }} = {{")
        lines.append(f"  spots = to_tensor([{spots_lit}])")
        lines.append(f"  cp = to_list(call_prices(copy(spots), {common}))")
        lines.append(f"  dl = to_list(deltas_call(copy(spots), {common}))")
        lines.append(f"  vl = to_list(vegas_call(copy(spots), {common}))")
        lines.append(f"  rl = to_list(rhos_call(copy(spots), {common}))")
        lines.append(f"  tl = to_list(thetas_call(copy(spots), {common}))")
        lines.append(f"  gm = to_list(gammas_call(copy(spots), {common}))")
        lines.append(f"  vg = to_list(volgas_call(copy(spots), {common}))")
        lines.append(f"  vn = to_list(vannas_call(spots, {common}))")
        asserts = []
        for j, (cell, ref) in enumerate(members):
            s = cell["s"]
            idx = f"cast({j}, int64)"
            # BINDING cross-check: displayed price (f64-downcast) == erfc reference.
            asserts.append(
                f'assert_close(index(cp, {idx}), call_textbook({lit32(s)}, {common}), '
                f'{lit32(tol_binding(ref["price_ref"]))}, "g{gi}c{j} price==erfc-ref")'
            )
            # PRIMARY (tight): AD Greek == exact derivative of the DISPLAYED A&S
            # price (Richardson ground truth). Isolates the autodiff transform.
            for gk, lst in (("delta", "dl"), ("vega", "vl"), ("rho", "rl"), ("theta", "tl")):
                gt = ref["ground_truth"][gk]
                asserts.append(
                    f'assert_close(index({lst}, {idx}), {lit32(gt)}, '
                    f'{lit32(tol_ad_vs_groundtruth(gt))}, "g{gi}c{j} {gk} ad==groundtruth")'
                )
            # SECONDARY: AD vs EXACT textbook analytic (true BS) -- agree up to the
            # measured A&S derivative-model error.
            for gk, lst in (("delta", "dl"), ("vega", "vl"), ("rho", "rl"), ("theta", "tl")):
                an = ref["analytic"][gk]
                merr = abs(an - ref["ground_truth"][gk])
                asserts.append(
                    f'assert_close(index({lst}, {idx}), {lit32(an)}, '
                    f'{lit32(tol_ad_vs_analytic(merr, an))}, "g{gi}c{j} {gk} ad==analytic")'
                )
            # SECONDARY: the closed-form GROUND TRUTH is independently corroborated
            # by the SHIPPED coarse-step fd_* of the displayed price. The subject of
            # the assertion is the closed-form ground-truth LITERAL vs the in-package
            # fd_* call, with an A-PRIORI band derived from the step h and f32
            # precision alone (Richardson + roundoff floor, fd_apriori_band). The
            # band does NOT depend on the AD value or any measured gt-vs-fd gap, so
            # this can genuinely fail if the closed-form derivative is wrong -- it is
            # not the old self-widening 3*|gt-fd| form, which the primary AD==gt gate
            # already made vacuous by the triangle inequality. (The primary gate above
            # is what constrains AD; this corroborates the ground truth used there.)
            st = ref["fd_steps"]
            fd_calls = {
                "delta": f"fd_delta_call({lit32(s)}, {common}, {lit32(st['delta'])})",
                "vega": f"fd_vega_call({lit32(s)}, {common}, {lit32(st['vega'])})",
                "rho": f"fd_rho_call({lit32(s)}, {common}, {lit32(st['rho'])})",
                "theta": f"fd_theta_call({lit32(s)}, {common}, {lit32(st['theta'])})",
            }
            for gk in ("delta", "vega", "rho", "theta"):
                gt = ref["ground_truth"][gk]
                band = fd_apriori_band(ref["fd"][gk], ref["fd2h"][gk], s, st[gk])
                asserts.append(
                    f'assert_close({lit32(gt)}, {fd_calls[gk]}, '
                    f'{lit32(band)}, "g{gi}c{j} {gk} groundtruth~=fd (a-priori band)")'
                )
            # ---- SECOND-ORDER GREEKS (nested grad): gamma, volga, vanna ----
            so_lst = {"gamma": "gm", "volga": "vg", "vanna": "vn"}
            # PRIMARY (tight): nested-grad Greek == exact SECOND derivative of the
            # DISPLAYED A&S price (closed-form ground truth). Isolates nested AD.
            for gk in ("gamma", "volga", "vanna"):
                sgt = ref["so_ground_truth"][gk]
                asserts.append(
                    f'assert_close(index({so_lst[gk]}, {idx}), {lit32(sgt)}, '
                    f'{lit32(tol_so_vs_groundtruth(gk, sgt))}, "g{gi}c{j} {gk} ad2==groundtruth")'
                )
            # SECONDARY: vs EXACT true-BS second-order closed form (model error).
            for gk in ("gamma", "volga", "vanna"):
                an = ref["so_analytic"][gk]
                merr = abs(an - ref["so_ground_truth"][gk])
                asserts.append(
                    f'assert_close(index({so_lst[gk]}, {idx}), {lit32(an)}, '
                    f'{lit32(tol_so_vs_analytic(gk, merr, an))}, "g{gi}c{j} {gk} ad2==analytic")'
                )
            # SECONDARY: the closed-form SECOND-DERIVATIVE ground truth is
            # independently corroborated by a tuned CENTRAL FD of the DISPLAYED f64
            # price. The subject is the closed-form ground-truth LITERAL vs the
            # in-script FD literal, with an A-PRIORI band from the tuned step alone
            # (Richardson + roundoff, so_fd_apriori_band) -- NOT the old
            # 3*|gt-fd| self-widening form. so_ground_truth comes from the analytic
            # chain-rule 2nd derivative; so_fd differences the price directly, so a
            # bug in the closed-form 2nd derivative makes the two diverge past the
            # band. The primary ad2==groundtruth gate above is what pins the AD value.
            so_steps = ref["so_fd_steps"]
            so_h = {"gamma": so_steps["h_s"], "volga": so_steps["h_v"], "vanna": so_steps["h_v"]}
            for gk in ("gamma", "volga", "vanna"):
                sgt = ref["so_ground_truth"][gk]
                band = so_fd_apriori_band(ref["so_fd"][gk], ref["so_fd2h"][gk], sgt, so_h[gk])
                asserts.append(
                    f'assert_close({lit32(sgt)}, {lit32(ref["so_fd"][gk])}, '
                    f'{lit32(band)}, "g{gi}c{j} {gk} groundtruth~=fd-displayed (a-priori band)")'
                )
        for a in asserts[:-1]:
            lines.append(f"  _ = {a}")
        lines.append(f"  {asserts[-1]}")
        lines.append("}")
    return "\n".join(lines) + "\n", test_names


class ChelisUnavailable(Exception):
    """The configured chelis binary is missing or cannot run this gate (e.g. a
    pre-0.8.0 compiler that fails to satisfy the package pin). Raised so main()
    can SKIP (exit 0) rather than FAIL on an environment that cannot run it."""


def chelis_available() -> tuple[bool, str]:
    """Return (ok, detail). Mirrors the composite gate's availability guard: if
    the binary is missing OR its version cannot satisfy the package compiler pin
    (pre-0.8.0 / errors out), the gate SKIPs rather than reporting a false FAIL.
    reef.toml is the source of truth for the pin, so we don't hardcode a number
    here -- we only require the binary to exist and report a version."""
    try:
        proc = subprocess.run(
            [CHELIS, "--version"], cwd=REPO_ROOT,
            capture_output=True, text=True, timeout=60,
        )
    except FileNotFoundError:
        return False, f"binary not found on PATH or at {CHELIS!r}"
    except (OSError, subprocess.SubprocessError) as exc:
        return False, f"could not invoke {CHELIS!r}: {exc}"
    if proc.returncode != 0:
        return False, f"{CHELIS!r} --version exited {proc.returncode}: {proc.stderr.strip()}"
    observed = proc.stdout.strip() or proc.stderr.strip()
    expected = f"chelis {compiler_pin()}"
    if observed != expected:
        return False, f"compiler mismatch: observed {observed!r}, expected {expected!r}"
    return True, observed


def run_chelis_test(path: Path):
    try:
        proc = subprocess.run(
            [CHELIS, "test", str(path.relative_to(REPO_ROOT)),
             "--jobs", "1", "--timeout", str(TEST_TIMEOUT_S), "--json"],
            cwd=REPO_ROOT, capture_output=True, text=True, timeout=TEST_TIMEOUT_S + 120,
        )
    except FileNotFoundError as exc:
        raise ChelisUnavailable(
            f"binary not found on PATH or at {CHELIS!r}"
        ) from exc
    per_test, summary = {}, {}
    for line in proc.stdout.splitlines():
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "test" in rec:
            per_test[rec["test"]] = (rec.get("status", "?"), rec.get("message", ""))
        elif "summary" in rec:
            summary = rec["summary"]
    return proc.returncode, per_test, summary, proc.stdout, proc.stderr


def main() -> int:
    # Availability guard (mirrors the composite gate): a missing or pre-0.8.0
    # binary SKIPs (exit 0), it does not FAIL. This keeps a clean box / non-pinned
    # environment from reporting a false negative.
    ok, detail = chelis_available()
    if not ok:
        print(
            f"SKIP: oracle_greeks_gate -- configured chelis ({CHELIS!r}) unavailable: "
            f"{detail}. Set CHELIS_BIN (or CHELIS_PROVE_BIN) to the exact "
            f"reef.toml compiler pin ({compiler_pin()}) to run this gate."
        )
        return 0

    K = 100.0
    # moneyness x maturity x vol x rate grid + sign-fold straddle.
    spots_main = [80.0, 90.0, 100.0, 110.0, 120.0]
    rs = [0.01, 0.05]
    sgs = [0.15, 0.30]
    ts = [0.25, 1.0, 2.0]

    # Sign-fold straddle (K=100, r=0.05, sg=0.2, t=1):
    #   d1=0 exactly at S = K*exp(-(r+sg^2/2)t) = 100*exp(-0.07) ~= 93.2394
    #   clearly-negative d1 at low spot S=60 (d1 ~= -2.2)
    signfold = [
        {"s": 100.0 * math.exp(-0.07), "k": K, "r": 0.05, "sigma": 0.2, "t": 1.0, "tag": "d1~0"},
        {"s": 60.0, "k": K, "r": 0.05, "sigma": 0.2, "t": 1.0, "tag": "neg-d1"},
        {"s": 50.0, "k": K, "r": 0.05, "sigma": 0.2, "t": 0.5, "tag": "deep-neg-d1"},
    ]

    grid = []
    for r in rs:
        for sg in sgs:
            for t in ts:
                for s in spots_main:
                    grid.append({"s": s, "k": K, "r": r, "sigma": sg, "t": t, "tag": "grid"})
    grid.extend(signfold)

    # Build references + accuracy-monotone guard.
    refs = []
    acc_new_max = 0.0  # max |A&S-body price - true price|
    acc_old_max = 0.0  # max |f32-erfc path price - true price| (modeled)
    for cell in grid:
        s, k, r, sg, t = cell["s"], cell["k"], cell["r"], cell["sigma"], cell["t"]
        ag = analytic_greeks(s, k, r, sg, t, ncdf_as)
        fg = fd_greeks(s, k, r, sg, t, ncdf_as)
        price_as = call_price(s, k, r, sg, t, ncdf_as)
        price_true = call_price(s, k, r, sg, t, ncdf_true)
        # NEW path: A&S erf computed in f64 then downcast to f32 (bs_call_scalar).
        # OLD path: A&S erf computed in f32 arithmetic (Nautilus.Special.erfc).
        # These no longer inherit one model error: since this shell's issue 61
        # the new path evaluates Cody's and the old f32 path evaluates A&S, so
        # this compares two approximations rather than isolating arithmetic
        # precision. The guard still means "new is at least as accurate as
        # old" -- measured 9.16e-7 against 3.64e-5 -- but not "same model,
        # different width". The difference vs true is
        # the arithmetic precision. The monotone guard asserts new <= old.
        price_new_f32 = f32(price_as)
        price_old_f32 = call_price_old_f32(s, k, r, sg, t)
        acc_new_max = max(acc_new_max, abs(price_new_f32 - price_true))
        acc_old_max = max(acc_old_max, abs(price_old_f32 - price_true))
        gt = ad_ground_truth_greeks(s, k, r, sg, t)
        # Second-order references: exact 2nd derivative of the DISPLAYED A&S price
        # (primary), true-BS 2nd-order closed form (secondary), tuned f64 FD of the
        # displayed price (secondary).
        so_gt = ad_second_order_groundtruth(s, k, r, sg, t)
        so_an = second_order_analytic(s, k, r, sg, t)
        so_fd = fd_second_order(s, k, r, sg, t, ncdf_as)
        ref = {
            "analytic": ag,
            "ground_truth": gt,
            "price_ref": price_as,
            "fd": {g: fg[g] for g in ("delta", "vega", "rho", "theta")},
            "fd2h": {g: fg["fd2h"][g] for g in ("delta", "vega", "rho", "theta")},
            "fd_steps": fg["steps"],
            "so_ground_truth": so_gt,
            "so_analytic": so_an,
            "so_fd": {g: so_fd[g] for g in ("gamma", "volga", "vanna")},
            "so_fd2h": {g: so_fd["fd2h"][g] for g in ("gamma", "volga", "vanna")},
            "so_fd_steps": so_fd["steps"],
            # convenience flat keys for the sign-fold report
            "delta": gt["delta"], "vega": gt["vega"],
            "rho": gt["rho"], "theta": gt["theta"],
        }
        refs.append(ref)

    src, test_names = build_test_source(grid, refs)
    GEN_TEST.parent.mkdir(parents=True, exist_ok=True)
    GEN_TEST.write_text(src)

    # The generated file is unlinked on EVERY exit path (try/finally), so a failing
    # run never leaves an artifact behind. It lives under .gate-tmp/ (gitignored),
    # so even mid-run it cannot be picked up by the wholesale tests/ CI scan.
    try:
        try:
            rc, per_test, summary, out, err = run_chelis_test(GEN_TEST)
        except ChelisUnavailable as exc:
            print(
                f"SKIP: oracle_greeks_gate -- configured chelis ({CHELIS!r}) "
                f"unavailable: {exc}. Set CHELIS_BIN (or CHELIS_PROVE_BIN) to "
                f"the exact reef.toml compiler pin ({compiler_pin()})."
            )
            return 0
        return _finish(grid, refs, test_names, src, rc, per_test, summary, out, err,
                       acc_new_max, acc_old_max)
    finally:
        GEN_TEST.unlink(missing_ok=True)


def _finish(grid, refs, test_names, src, rc, per_test, summary, out, err,
            acc_new_max, acc_old_max) -> int:
    n_pass = summary.get("passed", 0)
    n_fail = summary.get("failed", 0)
    failures = {k: v for k, v in per_test.items() if v[0] != "pass"}

    # The monotone guard: the new f64-A&S body must be at least as accurate.
    monotone_ok = acc_new_max <= acc_old_max + 1e-12

    all_ok = (rc == 0) and (n_fail == 0) and (n_pass == len(test_names)) and monotone_ok

    report = {
        "gate": "oracle_greeks_gate",
        "chelis": CHELIS,
        "grid_cells": len(grid),
        "groups_run": len(test_names),
        "chelis_exit": rc,
        "passed_groups": n_pass,
        "failed_groups": n_fail,
        "failures": failures,
        "binding_crosscheck": {
            "description": "call_prices (f64-downcast) == call_textbook (erfc) within f32 bound",
            "max_tol_used": max(tol_binding(r["price_ref"]) for r in refs),
        },
        "accuracy_monotone": {
            "new_f64_body_max_abs_err_vs_true": acc_new_max,
            "old_f32_erfc_path_max_abs_err_vs_true_modeled": acc_old_max,
            "new_le_old": monotone_ok,
        },
        "sign_fold": [
            {"tag": c["tag"], "s": c["s"],
             "d1": d1d2(c["s"], c["k"], c["r"], c["sigma"], c["t"])[0],
             "groundtruth_delta": rf["ground_truth"]["delta"],
             "groundtruth_vega": rf["ground_truth"]["vega"],
             "groundtruth_rho": rf["ground_truth"]["rho"],
             "groundtruth_theta": rf["ground_truth"]["theta"],
             "groundtruth_gamma": rf["so_ground_truth"]["gamma"],
             "groundtruth_volga": rf["so_ground_truth"]["volga"],
             "groundtruth_vanna": rf["so_ground_truth"]["vanna"]}
            for c, rf in zip(grid, refs) if c["tag"] != "grid"
        ],
        "second_order": {
            "description": "gammas_call/volgas_call/vannas_call: nested-grad d2 of the displayed price",
            "max_so_model_err_vs_trueBS": {
                gk: max(abs(rf["so_analytic"][gk] - rf["so_ground_truth"][gk]) for rf in refs)
                for gk in ("gamma", "volga", "vanna")
            },
            "max_so_fd_trunc_vs_groundtruth": {
                gk: max(abs(rf["so_fd"][gk] - rf["so_ground_truth"][gk]) for rf in refs)
                for gk in ("gamma", "volga", "vanna")
            },
            "abs_floors": {"gamma": GAMMA_ABS_FLOOR, "volga": VOLGA_ABS_FLOOR, "vanna": VANNA_ABS_FLOOR},
            "fd_steps_per_greek": "h_s=1% of S (gamma,vanna spot leg); h_v=5e-3 (volga,vanna vol leg)",
            "fd_corroboration_apriori": {
                "description": "ground_truth ~= FD-of-displayed-price within an a-priori "
                               "Richardson band (so_fd_apriori_band) derived from the step "
                               "alone; NOT the old self-widening 3*|gt-fd|. Ratio = "
                               "|gt-fd(h)| / band; <1 means it holds, and >0 means it is not "
                               "auto-satisfied (the band can fail if the closed form is wrong).",
                "max_residual_over_band": {
                    gk: max(
                        abs(rf["so_ground_truth"][gk] - rf["so_fd"][gk])
                        / so_fd_apriori_band(
                            rf["so_fd"][gk], rf["so_fd2h"][gk], rf["so_ground_truth"][gk],
                            rf["so_fd_steps"]["h_s"] if gk == "gamma" else rf["so_fd_steps"]["h_v"])
                        for rf in refs
                    )
                    for gk in ("gamma", "volga", "vanna")
                },
            },
        },
        "tolerance_derivation": {
            "eps_f32": EPS_F32,
            "ad_vs_groundtruth (PRIMARY, gating)":
                "max(16*eps_f32*|v|, 3e-6); AD vs exact f64 derivative of the displayed price, f32 ULPs",
            "ad_vs_analytic (secondary)":
                "2*measured_displayed_model_err + max(8*eps_f32*|v|, 3e-6)",
            "groundtruth_vs_fd (secondary, INDEPENDENT corroboration)":
                "2*|fd(h)-fd(2h)| (Richardson, a-priori) + 8*eps_f32*price/h + 3e-7; "
                "subject is closed-form ground_truth vs in-package fd_*; band is "
                "derived from h+precision alone (NOT from any gt-vs-fd gap), so it "
                "can fail if the closed form is wrong",
            "binding": "max(16*eps_f32*|price|, 1e-4); f32 quantization plus the "
                       "Cody-vs-A&S approximation gap, which sits far below it",
            "so_ad2_vs_groundtruth (PRIMARY, gating)":
                "max(48*eps_f32*|v|, greek_floor); nested grad == exact f64 2nd-deriv of the displayed price",
            "so_ad2_vs_analytic (secondary)":
                "2*measured_displayed_2nd_deriv_model_err + primary_so_band",
            "so_groundtruth_vs_fd (secondary, INDEPENDENT corroboration)":
                "2*|fd(h)-fd(2h)| (Richardson, a-priori) + 8*eps_f32*|v|/h^2 + 3e-7; "
                "subject is closed-form 2nd-deriv ground_truth vs FD of displayed "
                "price; band derived from h alone (NOT from any gt-vs-fd gap)",
        },
        "all_ok": all_ok,
    }
    sys.stdout.write(json.dumps(report, indent=2) + "\n")

    if all_ok:
        print(f"PASS: oracle_greeks_gate -- {n_pass}/{len(test_names)} groups, "
              f"{len(grid)} cells; binding + monotone + sign-fold green.")
        return 0
    # The generated file is unlinked in the caller's finally even on FAIL (it is
    # gitignored under .gate-tmp/ and must not be left behind); echo the source and
    # chelis output here so a failing run is still fully triageable from the log.
    sys.stderr.write("\n--- chelis stdout ---\n" + out + "\n--- chelis stderr ---\n" + err
                     + "\n--- generated test source (for triage) ---\n" + src + "\n")
    print(f"FAIL: oracle_greeks_gate -- groups {n_pass} pass / {n_fail} fail; "
          f"monotone_ok={monotone_ok}. Generated test source echoed above for triage.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
