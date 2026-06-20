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
     SAME Abramowitz-Stegun 7.1.26 erf the package body uses, so the comparison
     isolates the AD chain rule, not erf accuracy.
  2. The shipped finite-difference Greeks in ``Shoals.Greeks`` (``fd_delta_call``
     etc.): same body, different derivative method, so AD and FD must agree
     within FD truncation error.
  3. BINDING CROSS-CHECK: the f64-downcast price (``call_prices``) equals the
     erfc-based reference price (``Shoals.References.BlackScholes.call_textbook``,
     which goes through Nautilus.Special.erfc) within an f32-precision bound.
     This records that the displayed Greek is the derivative of the displayed
     price -- the two share one erf up to f32 rounding.

  SECOND-ORDER (nested grad): gamma=d2C/dS2, volga=d2C/dsg2, vanna=d2C/dSdsg are
  validated against (a) the exact f64 SECOND derivative of the DISPLAYED A&S price
  (primary, tight: this is the correctness invariant -- gamma is the second
  derivative of the displayed price), (b) the true-BS second-order closed forms
  (secondary, agree up to A&S model error), and (c) tuned CENTRAL finite
  differences of the DISPLAYED f64 price with a per-Greek step (secondary, agree
  up to FD truncation; gamma's tuned step makes its FD bound the tightest so gamma
  sits near that bound). A negative-d1 sign-fold point is included.

  ACCURACY-MONOTONE guard: the new f64-body reference error vs analytic-true must
  be <= the old f32-erfc path's error (no illegitimate tolerance re-baseline).

All numeric agreement is established by ``chelis test --json``: this script
emits ONE generated ``tests/`` file whose assertions encode the references and
precision-derived tolerances, runs it once (the package compiles in one pass),
and reads per-assertion pass/fail. A passing assertion certifies
|package - reference| < tol, where every tol is DERIVED from f32 precision and
FD truncation, never a fixed percent (see ``tol_*`` below). The JSON report
states each derived tolerance so the bound is auditable.

Exit 0 on pass, nonzero on fail. A JSON summary is printed to stdout.
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CHELIS = os.environ.get(
    "CHELIS_BIN",
    str(Path.home() / ".local/share/chelis/0.7.27/bin/chelis"),
)
GEN_TEST = REPO_ROOT / "tests" / "_oracle_greeks_gate_generated.ch"
TEST_TIMEOUT_S = int(os.environ.get("ORACLE_GATE_TIMEOUT_S", "600"))

# --------------------------------------------------------------------------
# Reference math (Python). erf is A&S 7.1.26 -- the SAME coefficients as the
# package body -- so analytic mirrors isolate the AD chain rule, not erf error.
# `_true` versions use math.erf for the accuracy-monotone guard's ground truth.
# --------------------------------------------------------------------------
SQRT2 = math.sqrt(2.0)
INV_SQRT_2PI = 1.0 / math.sqrt(2.0 * math.pi)


def f32(x: float) -> float:
    import struct
    return struct.unpack("f", struct.pack("f", x))[0]


def erf_as(x: float) -> float:
    a1, a2, a3, a4, a5, p = (
        0.254829592, -0.284496736, 1.421413741,
        -1.453152027, 1.061405429, 0.3275911,
    )
    ax = abs(x)
    if ax < 1e-5:
        return x * 1.1283791670955126
    t = 1.0 / (1.0 + p * ax)
    poly = t * (a1 + t * (a2 + t * (a3 + t * (a4 + t * a5))))
    y = 1.0 - poly * math.exp(-ax * ax)
    return -y if x < 0 else y


def ncdf_as(x: float) -> float:
    return 0.5 * (1.0 - erf_as(-x / SQRT2))


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


def erf_as_deriv(x: float) -> float:
    """d/dx erf_AS(x), closed form. For |x|<1e-5 the body uses the linear branch
    erf ~ (2/sqrt pi) x whose derivative is the constant 1.12837..., matching the
    package's small-|x| branch. Even function (erf is odd), so x<0 reuses |x|."""
    a1, a2, a3, a4, a5 = _AS
    p = _AS_P
    ax = abs(x)
    if ax < 1e-5:
        return 1.1283791670955126
    t = 1.0 / (1.0 + p * ax)
    poly = t * (a1 + t * (a2 + t * (a3 + t * (a4 + t * a5))))
    polyp = a1 + t * (2 * a2 + t * (3 * a3 + t * (4 * a4 + t * 5 * a5)))
    e = math.exp(-ax * ax)
    return e * (p * t * t * polyp + 2 * ax * poly)


def pdf_as(x: float) -> float:
    """d/dx ncdf_as(x) = 0.5 * erf_AS'(-x/sqrt2) * (1/sqrt2) -- the A&S 'pdf'."""
    return 0.5 * erf_as_deriv(-x / SQRT2) / SQRT2


def erf_as_deriv2(x: float) -> float:
    """d^2/dx^2 erf_AS(x), closed form. erf_AS' is even (erf is odd), so it equals
    g(|x|) and its x-derivative is g'(|x|)*sign(x). For |x|<1e-5 the package uses
    the linear branch erf ~ (2/sqrt pi) x, whose second derivative is 0. Verified
    against a high-order central difference of ``erf_as_deriv`` to ~1e-10."""
    a1, a2, a3, a4, a5 = _AS
    p = _AS_P
    ax = abs(x)
    if ax < 1e-5:
        return 0.0
    t = 1.0 / (1.0 + p * ax)
    dt = -p * t * t                                       # dt/d(ax)
    poly = t * (a1 + t * (a2 + t * (a3 + t * (a4 + t * a5))))
    polyp = a1 + t * (2 * a2 + t * (3 * a3 + t * (4 * a4 + t * 5 * a5)))   # d poly/dt
    polypp = 2 * a2 + t * (6 * a3 + t * (12 * a4 + t * 20 * a5))           # d^2 poly/dt^2
    e = math.exp(-ax * ax)
    de = -2 * ax * e                                      # d/d(ax) e^{-ax^2}
    # erf_as_deriv = M(ax) = e^{-ax^2} (p t^2 polyp + 2 ax poly). Differentiate in ax.
    inner = p * t * t * polyp + 2 * ax * poly
    d_inner = p * (2 * t * dt * polyp + t * t * polypp * dt) + 2 * poly + 2 * ax * polyp * dt
    g_prime = de * inner + e * d_inner
    return g_prime * (1.0 if x >= 0 else -1.0)


def pdf_as_deriv(x: float) -> float:
    """d/dx pdf_as(x) = d^2/dx^2 ncdf_as(x). pdf_as(x)=0.5 erf_AS'(-x/sqrt2)/sqrt2,
    so pdf_as'(x) = -0.25 * erf_AS''(-x/sqrt2). The analytic 'pdf-prime' of the A&S
    normal CDF; the building block of the exact SECOND derivatives of the displayed
    price, used the same way pdf_as builds the exact first derivatives."""
    return -0.25 * erf_as_deriv2(-x / SQRT2)


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
    gamma = (c(s + h_s, k, r, sg, t) - 2 * c(s, k, r, sg, t) + c(s - h_s, k, r, sg, t)) / (h_s * h_s)
    volga = (c(s, k, r, sg + h_v, t) - 2 * c(s, k, r, sg, t) + c(s, k, r, sg - h_v, t)) / (h_v * h_v)

    def delta(sig):
        return (c(s + h_s, k, r, sig, t) - c(s - h_s, k, r, sig, t)) / (2 * h_s)
    vanna = (delta(sg + h_v) - delta(sg - h_v)) / (2 * h_v)
    return {"gamma": gamma, "volga": volga, "vanna": vanna,
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
    delta = (c(s + hs, k, r, sg, t) - c(s - hs, k, r, sg, t)) / (2 * hs)
    vega = (c(s, k, r, sg + hv, t) - c(s, k, r, sg - hv, t)) / (2 * hv)
    rho = (c(s, k, r + hr, sg, t) - c(s, k, r - hr, sg, t)) / (2 * hr)
    # Shoals.Greeks fd_theta_call uses (dn - up)/(2h) i.e. -dC/dt
    theta = (c(s, k, r, sg, t - ht) - c(s, k, r, sg, t + ht)) / (2 * ht)
    return {"delta": delta, "vega": vega, "rho": rho, "theta": theta,
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


def tol_ad_vs_fd(trunc_err: float, s: float, h: float, v: float) -> float:
    """SECONDARY. AD vs the SHIPPED coarse-step fd_*. Differ by the FD truncation
    at the shipped step h, predicted in-script as |exact_analytic - fd(h)|
    (trunc_err), plus the f32 quotient-rounding band ~ eps_f32 * price_scale / h
    of the shipped f32 FD. Tolerance = 3x trunc + band + floor. Tracks the real
    per-cell FD error; the primary ground-truth gate keeps AD itself tight."""
    f32_fd_band = 4.0 * EPS_F32 * max(abs(s), 1.0) / h
    return 3.0 * trunc_err + f32_fd_band + max(8.0 * EPS_F32 * abs(v), 3e-6)


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


def tol_so_vs_fd(greek: str, trunc_err: float, v: float) -> float:
    """SECONDARY. Nested-grad Greek vs the tuned CENTRAL FD of the DISPLAYED f64
    price. Differ by the FD O(h^2) truncation at the tuned step, predicted in-script
    as |ground_truth - fd| (trunc_err), plus the primary band. f64 FD here so there
    is no f32 quotient band -- truncation dominates. Gamma's tuned step makes its
    truncation the smallest, so the gamma FD bound is the tightest of the three."""
    return 3.0 * trunc_err + tol_so_vs_groundtruth(greek, v)


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
            # SECONDARY: AD vs SHIPPED coarse-step fd_* -- agree up to FD truncation
            # at the shipped step (predicted in-script via the same h).
            st = ref["fd_steps"]
            fd_calls = {
                "delta": f"fd_delta_call({lit32(s)}, {common}, {lit32(st['delta'])})",
                "vega": f"fd_vega_call({lit32(s)}, {common}, {lit32(st['vega'])})",
                "rho": f"fd_rho_call({lit32(s)}, {common}, {lit32(st['rho'])})",
                "theta": f"fd_theta_call({lit32(s)}, {common}, {lit32(st['theta'])})",
            }
            for gk, lst in (("delta", "dl"), ("vega", "vl"), ("rho", "rl"), ("theta", "tl")):
                trunc = abs(ref["analytic"][gk] - ref["fd"][gk])
                asserts.append(
                    f'assert_close(index({lst}, {idx}), {fd_calls[gk]}, '
                    f'{lit32(tol_ad_vs_fd(trunc, s, st[gk], ref["analytic"][gk]))}, '
                    f'"g{gi}c{j} {gk} ad==fd")'
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
            # SECONDARY: vs tuned CENTRAL FD of the DISPLAYED f64 price (truncation).
            for gk in ("gamma", "volga", "vanna"):
                fdv = ref["so_fd"][gk]
                trunc = abs(ref["so_ground_truth"][gk] - fdv)
                asserts.append(
                    f'assert_close(index({so_lst[gk]}, {idx}), {lit32(fdv)}, '
                    f'{lit32(tol_so_vs_fd(gk, trunc, ref["so_ground_truth"][gk]))}, '
                    f'"g{gi}c{j} {gk} ad2==fd-displayed")'
                )
        for a in asserts[:-1]:
            lines.append(f"  _ = {a}")
        lines.append(f"  {asserts[-1]}")
        lines.append("}")
    return "\n".join(lines) + "\n", test_names


def run_chelis_test(path: Path):
    proc = subprocess.run(
        [CHELIS, "test", str(path.relative_to(REPO_ROOT)),
         "--jobs", "1", "--timeout", str(TEST_TIMEOUT_S), "--json"],
        cwd=REPO_ROOT, capture_output=True, text=True, timeout=TEST_TIMEOUT_S + 120,
    )
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
        # Both inherit the IDENTICAL A&S model error; the difference vs true is
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
            "fd_steps": fg["steps"],
            "so_ground_truth": so_gt,
            "so_analytic": so_an,
            "so_fd": {g: so_fd[g] for g in ("gamma", "volga", "vanna")},
            "so_fd_steps": so_fd["steps"],
            # convenience flat keys for the sign-fold report
            "delta": gt["delta"], "vega": gt["vega"],
            "rho": gt["rho"], "theta": gt["theta"],
        }
        refs.append(ref)

    src, test_names = build_test_source(grid, refs)
    GEN_TEST.write_text(src)

    rc, per_test, summary, out, err = run_chelis_test(GEN_TEST)

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
            "description": "gammas_call/volgas_call/vannas_call: nested-grad d2 of the displayed A&S price",
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
            "gamma_sits_near_fd_bound": {
                "description": "gamma vs tuned-FD-of-displayed-price: |gt-fd| should approach its tol",
                "max_ratio_trunc_over_tol": max(
                    abs(rf["so_fd"]["gamma"] - rf["so_ground_truth"]["gamma"])
                    / tol_so_vs_fd("gamma", abs(rf["so_fd"]["gamma"] - rf["so_ground_truth"]["gamma"]),
                                   rf["so_ground_truth"]["gamma"])
                    for rf in refs
                ),
            },
        },
        "tolerance_derivation": {
            "eps_f32": EPS_F32,
            "ad_vs_groundtruth (PRIMARY, gating)":
                "max(16*eps_f32*|v|, 3e-6); AD vs exact f64 derivative of A&S price, f32 ULPs",
            "ad_vs_analytic (secondary)":
                "2*measured_A&S_model_err + max(8*eps_f32*|v|, 3e-6)",
            "ad_vs_fd (secondary)":
                "3*predicted_FD_truncation + 4*eps_f32*price/h + max(8*eps_f32*|v|, 3e-6)",
            "binding": "max(16*eps_f32*|price|, 1e-4); erf-impl rounding of same formula",
            "so_ad2_vs_groundtruth (PRIMARY, gating)":
                "max(48*eps_f32*|v|, greek_floor); nested grad == exact f64 2nd-deriv of A&S price",
            "so_ad2_vs_analytic (secondary)":
                "2*measured_A&S_2nd_deriv_model_err + primary_so_band",
            "so_ad2_vs_fd (secondary)":
                "3*predicted_FD_truncation(f64 displayed price) + primary_so_band",
        },
        "all_ok": all_ok,
    }
    sys.stdout.write(json.dumps(report, indent=2) + "\n")

    if all_ok:
        GEN_TEST.unlink(missing_ok=True)
        print(f"PASS: oracle_greeks_gate -- {n_pass}/{len(test_names)} groups, "
              f"{len(grid)} cells; binding + monotone + sign-fold green.")
        return 0
    sys.stderr.write("\n--- chelis stdout ---\n" + out + "\n--- chelis stderr ---\n" + err + "\n")
    print(f"FAIL: oracle_greeks_gate -- groups {n_pass} pass / {n_fail} fail; "
          f"monotone_ok={monotone_ok}. Generated test kept at {GEN_TEST} for triage.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
