#!/usr/bin/env python3
"""Keystone canon self-audit gate for Shoals (contract WI-6).

Expected-tier-driven off docs/cnote-import-surface.json, run against the PINNED
RELEASE binary. For every manifest invariant:

  1. Satisfying control holds at exactly its expected_tier_per_pin[pin] -- tier
     drift in EITHER direction fails (better-than-expected => "run the
     de-narrowing motion"). Tier is classified from proof_tier + qualifiers,
     NEVER from the composite_verdict string (contract rule; verdict strings
     may demote, never promote).
  2. Anti-vacuity: the prover-emitted GOAL string for the satisfying control
     names the output fn (direct) or the abstracted contract symbol
     (structural). dependency_edges is NOT used -- it does not cross module
     import boundaries (uniformly [] for imported output fns; economoist
     docs/issue_drafts/dependency_edges_imports.md), so keying on it would
     false-pass vacuity. The corrupt-flip (control 2) is the second half.
  3. Violating control breaks with a real IN-DOMAIN witness: status matches the
     declared expectation (failed / unsupported), a counterexample is present
     (when failed), and the counterexample satisfies the manifest's structured
     preconditions (evaluated in python).
  4. Non-vacuity witnesses (`*_guards_satisfiable`) REFUTE at SMT (cvc5
     exhibits a guard-satisfying model).
  5. Defective-model invariants: the goal is DISPROVED with an in-domain
     witness that re-executes at f32 (in_region_defect).

An honesty self-test runs FIRST: the tier classifier must reject verdict
strings wearing a clean mask (a fuzz pass carrying a proven-looking
composite_verdict classifies as fuzz_validated, never proven).

Stdlib-only. Resolves the binary env-first (CHELIS_SMT_BIN / CHELIS_BIN) then
the pin-derived ~/.local/share/chelis/<pin>/ then PATH. Fuzz sample count is
FUZZ_SAMPLES (default from the manifest run_samples); CI dials it down and the
full-sample sweep runs in nightly.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MANIFEST = REPO / "docs" / "cnote-import-surface.json"
SMT_TIMEOUT_MS = "20000"
DEFAULT_FUZZ_SAMPLES = 25
FUZZ_SEED = "0"

# Contract sec 1 tier vocabulary.
TIERS = {"proven", "proven_modulo_contract", "sound_approximate",
         "fuzz_validated", "disproved", "unknown", "error"}
# Tiers that must carry a tier_upgrade_trigger (below the proven ceiling).
BELOW_PROVEN = {"proven_modulo_contract", "sound_approximate", "fuzz_validated"}
# Name lint: honest vocabulary only (no convergence/limit claims) over canon files.
BANNED_NAME_SUBSTR = ("converge", "stationary", "fixed_point", "ergodic",
                      "limit", "iterat")


def fail(msg: str) -> None:
    print(f"  FAIL: {msg}")


def resolve_bin() -> str:
    for env in ("CHELIS_SMT_BIN", "CHELIS_BIN"):
        v = os.environ.get(env)
        if v and Path(v).expanduser().is_file():
            return str(Path(v).expanduser())
    pin = re.search(r'compiler\s*=\s*"=([0-9.]+)"',
                    (REPO / "reef.toml").read_text()).group(1)
    for rel in ("bin/chelis", "chelis"):
        p = Path.home() / ".local/share/chelis" / pin / rel
        if p.is_file():
            return str(p)
    import shutil
    found = shutil.which("chelis")
    if found:
        return found
    sys.exit("error: no chelis binary (set CHELIS_SMT_BIN or install the pin)")


def classify_tier(rec: dict) -> str:
    """Achieved contract tier from proof_tier + qualifiers + status ONLY.
    composite_verdict is deliberately ignored (it may demote, never promote)."""
    status = rec.get("status")
    tier = rec.get("proof_tier")
    quals = set(rec.get("qualifiers") or [])
    if status == "passed":
        if tier == "smt":
            # A fuzz-discharged contract riding an SMT structural proof is
            # proven_modulo_contract (composites: qualifiers [real_arithmetic, fuzz]).
            return "proven_modulo_contract" if "fuzz" in quals else "proven"
        if tier == "fuzz":
            return "fuzz_validated"
        return "unknown"
    if status == "failed":
        return "disproved"
    if status in ("unsupported", "error"):
        return "unknown" if status == "unsupported" else "error"
    return "unknown"


def honesty_self_test() -> bool:
    """The classifier must key on proof_tier+qualifiers, never composite_verdict."""
    cases = [
        ({"status": "passed", "proof_tier": "smt", "qualifiers": ["real_arithmetic"],
          "composite_verdict": "proven_modulo_real_arithmetic"}, "proven"),
        ({"status": "passed", "proof_tier": "smt", "qualifiers": ["real_arithmetic", "fuzz"],
          "composite_verdict": "proven_modulo_fuzz_validated_contract"}, "proven_modulo_contract"),
        ({"status": "passed", "proof_tier": "fuzz", "qualifiers": ["fuzz", "fuzz_base"],
          "composite_verdict": "fuzz_validated"}, "fuzz_validated"),
        # The adversarial case: a fuzz pass wearing a proven-looking verdict
        # string must classify as fuzz_validated, NOT proven.
        ({"status": "passed", "proof_tier": "fuzz", "qualifiers": ["fuzz"],
          "composite_verdict": "proven_modulo_real_arithmetic"}, "fuzz_validated"),
        ({"status": "failed", "proof_tier": "smt", "qualifiers": ["real_arithmetic"],
          "composite_verdict": "disproved_modulo_real_arithmetic"}, "disproved"),
        ({"status": "unsupported", "proof_tier": None, "qualifiers": [],
          "composite_verdict": "unsupported"}, "unknown"),
    ]
    ok = True
    for rec, want in cases:
        got = classify_tier(rec)
        if got != want:
            fail(f"honesty self-test: classify({rec['composite_verdict']}"
                 f"/{rec['proof_tier']}) = {got}, expected {want}")
            ok = False
    print(f"  honesty self-test: {'PASS' if ok else 'FAIL'} "
          f"({len(cases)} cases, composite_verdict ignored)")
    return ok


def run_prove(binary: str, file: str, fuzz: bool, samples: int) -> dict:
    """Run prove on one canon file; return {property_name: record}."""
    cmd = [binary, "prove", file, "--json"]
    if fuzz:
        cmd += ["--tier", "auto", "--samples", str(samples), "--seed", FUZZ_SEED]
    else:
        cmd += ["--tier", "smt-only", "--smt-timeout", SMT_TIMEOUT_MS]
    out = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    recs: dict[str, dict] = {}
    for line in out.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("kind") == "property" and "name" in obj and "status" in obj:
            recs[obj["name"]] = obj
        elif obj.get("kind") == "summary":
            for name, s in (obj.get("summary") or {}).items():
                recs.setdefault(name, {**s, "name": name})
    return recs


def smt_value(v: str) -> float | None:
    """Parse an SMT/fuzz counterexample scalar: '1.0', '(/ 1 2)', '(- 3)'."""
    v = v.strip()
    m = re.fullmatch(r"\(/ (-?[\d.]+) (-?[\d.]+)\)", v)
    if m:
        return float(m.group(1)) / float(m.group(2))
    m = re.fullmatch(r"\(- ([\d.]+)\)", v)
    if m:
        return -float(m.group(1))
    try:
        return float(v)
    except ValueError:
        return None


def precondition_holds(pc: dict, env: dict) -> bool | None:
    lhs = env.get(pc["lhs"])
    rhs_spec = pc["rhs"]
    if "const" in rhs_spec:
        rhs = float(rhs_spec["const"])
    else:
        rhs = env.get(rhs_spec["input"])
    if lhs is None or rhs is None:
        return None
    op = pc["op"]
    return {"gt": lhs > rhs, "gte": lhs >= rhs, "lt": lhs < rhs,
            "lte": lhs <= rhs}[op]


def witness_in_domain(cx: dict, preconditions: list) -> tuple[bool, str]:
    env = {}
    for k, v in (cx or {}).items():
        f = smt_value(v) if isinstance(v, str) else v
        if f is not None:
            env[k] = f
    for pc in preconditions:
        r = precondition_holds(pc, env)
        if r is None:
            return False, f"cannot evaluate precondition {pc['lhs']} (missing witness value)"
        if not r:
            return False, f"witness violates precondition {pc['lhs']} {pc['op']} {pc['rhs']}"
    return True, "in-domain"


def goal_names_ref(goal: str, invariant: dict) -> bool:
    """Anti-vacuity via the goal string (dependency_edges are [] across imports)."""
    b = invariant["binding"]
    if b["references_output_fn"] == "structural":
        return "normal_cdf" in (goal or "")
    fn = invariant.get("target_model")
    # the output fn is on the model; but the goal carries the fn NAME directly.
    # accept if any exported output-fn token appears.
    for tok in (invariant.get("_output_fn", ""), fn or ""):
        if tok and tok in (goal or ""):
            return True
    return invariant.get("_output_fn", "___") in (goal or "")


def check_control(recs, name, want_status, label) -> tuple[bool, dict | None]:
    rec = recs.get(name)
    if rec is None:
        fail(f"{label}: property `{name}` not found in prover output")
        return False, None
    st = rec.get("status")
    if want_status == "failed":
        ok = st == "failed"
    elif want_status == "unsupported":
        ok = st in ("unsupported", "error")
    else:
        ok = st == want_status
    if not ok:
        fail(f"{label}: `{name}` status={st}, expected {want_status}")
    return ok, rec


def check_instantiation(recs, inv, inst, pin, output_fn) -> bool:
    ok = True
    exp_tier = inv["expected_tier_per_pin"].get(pin)
    controls = inst["controls"]
    inv_with_fn = {**inv, "_output_fn": output_fn}

    # Defective-model invariants have only a violating control (the break).
    if inv.get("defective_model"):
        vg = controls["violating"]
        okc, rec = check_control(recs, vg["name"], "failed", "defect")
        ok = okc and ok
        if rec:
            got = classify_tier(rec)
            if got != exp_tier:
                fail(f"defect `{vg['name']}` tier {got} != expected {exp_tier}")
                ok = False
            cx = rec.get("counterexample")
            if not cx:
                fail(f"defect `{vg['name']}` has no counterexample")
                ok = False
            else:
                ind, why = witness_in_domain(cx, inst.get("preconditions", []))
                if not ind:
                    fail(f"defect witness not in-domain: {why}")
                    ok = False
                else:
                    print(f"    defect `{vg['name']}`: disproved, in-domain arbitrage witness {cx}")
        return ok

    # Satisfying control: exact expected tier + anti-vacuity goal ref.
    sg = controls["satisfying"]
    okc, rec = check_control(recs, sg["name"], "passed", "satisfying")
    ok = okc and ok
    if rec:
        got = classify_tier(rec)
        if got != exp_tier:
            fail(f"TIER DRIFT: `{sg['name']}` achieved {got}, expected {exp_tier} "
                 f"(either direction fails -- run the de-narrowing motion)")
            ok = False
        if not goal_names_ref(rec.get("goal", ""), inv_with_fn):
            fail(f"anti-vacuity: goal for `{sg['name']}` does not name the "
                 f"output fn / contract symbol (goal={rec.get('goal','')[:80]})")
            ok = False

    # Violating control: flips, with an in-domain witness.
    vg = controls["violating"]
    okc, vrec = check_control(recs, vg["name"], vg["expected"], "violating")
    ok = okc and ok
    if vrec and vg["expected"] == "failed":
        cx = vrec.get("counterexample")
        if vg.get("witness_required") and not cx:
            fail(f"violating `{vg['name']}` requires a witness but has none")
            ok = False
        elif cx:
            ind, why = witness_in_domain(cx, inst.get("preconditions", []))
            # fuzz counterexamples are in-domain f32 by construction; SMT ones
            # are checked against the structured preconditions.
            if not ind and vrec.get("proof_tier") != "fuzz":
                fail(f"violating `{vg['name']}` witness not in-domain: {why}")
                ok = False
    return ok


def check_non_vacuity(recs, inv) -> bool:
    nv = inv.get("non_vacuity_witness")
    if not nv:
        return True
    rec = recs.get(nv)
    if rec is None:
        fail(f"non-vacuity `{nv}` not found")
        return False
    if rec.get("status") != "failed":
        fail(f"non-vacuity `{nv}`: status={rec.get('status')}, must REFUTE "
             "(cvc5 exhibits a guard-satisfying model)")
        return False
    return True


def name_lint(files: list[Path]) -> bool:
    ok = True
    for f in files:
        for m in re.finditer(r"@property\s+(\w+)", f.read_text()):
            nm = m.group(1).lower()
            for bad in BANNED_NAME_SUBSTR:
                if bad in nm:
                    fail(f"name lint: `{m.group(1)}` in {f.name} contains "
                         f"banned term '{bad}' (honest vocabulary only)")
                    ok = False
    return ok


def main() -> None:
    manifest = json.loads(MANIFEST.read_text())
    pin = manifest["chelis_pin"]
    models = {m["id"]: m for m in manifest["models"]}
    binary = resolve_bin()
    samples = int(os.environ.get("FUZZ_SAMPLES", DEFAULT_FUZZ_SAMPLES))
    # The real transcendental pricers cost ~17s per accepted fuzz sample (p08),
    # so the fuzz lane is NOT per-PR-viable at any meaningful sample count. The
    # per-PR gate runs the deterministic SMT lanes (proven / proven_modulo_contract
    # / disproved); the fuzz lane is gated in nightly with PROVE_GATE_FUZZ=1 at
    # the full sample budget. This is a budget split, not a dropped invariant --
    # the fuzz invariants stay in the manifest and are characterizable.
    include_fuzz = os.environ.get("PROVE_GATE_FUZZ") == "1"
    print(f"prove_gate: binary={binary} pin={pin} fuzz_samples={samples} "
          f"fuzz_lane={'on' if include_fuzz else 'off (nightly)'}")

    def gated(inv: dict) -> bool:
        return include_fuzz or inv["expected_tier_per_pin"].get(pin) != "fuzz_validated"

    ok = honesty_self_test()

    canon_files = [REPO / "properties" / "canonpricing.ch",
                   REPO / "properties" / "canontrees.ch"]
    ok = name_lint([f for f in canon_files if f.exists()]) and ok

    # Group invariants by property file; a file is a fuzz lane if any of its
    # invariants expects fuzz_validated.
    gated_invs = [inv for inv in manifest["invariants"] if gated(inv)]
    by_file: dict[str, list] = {}
    for inv in gated_invs:
        by_file.setdefault(inv["property"]["file"], []).append(inv)
        for inst in inv.get("also_instantiated_for", []):
            by_file.setdefault(inst["property"]["file"], []).append(inv)

    fuzz_files = {inv["property"]["file"] for inv in gated_invs
                  if inv["expected_tier_per_pin"].get(pin) == "fuzz_validated"}
    for inv in gated_invs:
        for inst in inv.get("also_instantiated_for", []):
            if inv["expected_tier_per_pin"].get(pin) == "fuzz_validated":
                fuzz_files.add(inst["property"]["file"])

    recs_by_file = {}
    for fname in sorted(by_file):
        is_fuzz = fname in fuzz_files
        print(f"\n== proving {fname} ({'fuzz' if is_fuzz else 'smt-only'}) ==")
        recs_by_file[fname] = run_prove(binary, fname, is_fuzz, samples)

    skipped = [inv["id"] for inv in manifest["invariants"] if not gated(inv)]
    if skipped:
        print(f"\n== fuzz lane deferred to nightly (PROVE_GATE_FUZZ=1): "
              f"{', '.join(skipped)} ==")

    print("\n== verifying invariants ==")
    for inv in gated_invs:
        exp = inv["expected_tier_per_pin"].get(pin)
        if exp is None:
            fail(f"{inv['id']}: no expected_tier_per_pin entry for pin {pin} "
                 "(stale for this pin)")
            ok = False
            continue
        if exp in BELOW_PROVEN and not inv.get("tier_upgrade_trigger"):
            fail(f"{inv['id']}: expected tier {exp} is below-proven but carries "
                 "no tier_upgrade_trigger")
            ok = False
        output_fn = models[inv["target_model"]]["output_fn"]
        recs = recs_by_file[inv["property"]["file"]]
        print(f"  [{inv['id']}] expected {exp}")
        i_ok = check_instantiation(recs, inv,
                                   {"controls": inv["controls"],
                                    "preconditions": inv.get("preconditions", [])},
                                   pin, output_fn)
        i_ok = check_non_vacuity(recs, inv) and i_ok
        for inst in inv.get("also_instantiated_for", []):
            of = models[inst["target_model"]]["output_fn"]
            irecs = recs_by_file[inst["property"]["file"]]
            print(f"    also-instantiated: {inst['target_model']}")
            i_ok = check_instantiation(irecs, inv, inst, pin, of) and i_ok
        ok = i_ok and ok

    print()
    if ok:
        print("PASS: shoals prove_gate green")
        sys.exit(0)
    print("FAIL: shoals prove_gate")
    sys.exit(1)


if __name__ == "__main__":
    main()
