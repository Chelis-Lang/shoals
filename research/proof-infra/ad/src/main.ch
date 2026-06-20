module ProofInfraAd.Main
-- Track B sub-package entry. The substance is in bs.ch (grad-able f64
-- Black-Scholes body), greeks.ch (AD Greeks via grad/grad-of-grad over the
-- named body), and step1blocker.ch (host-lane blocker reproduction). The
-- numeric validation is driven by ../runs and the Python harnesses
-- (harness.py / surface.py / calibrate.py) over `chelis eval`. See RESULTS.md.
def identity_f64(x: f64) -> f64 = x
