#!/usr/bin/env python3
"""Composite derivatives property corpus gate (S8).

Runs ``chelis prove`` over ``properties/composites.ch`` and asserts each
property reaches the expected COMPOSITE verdict under the chelis 0.10.1 contract
mechanism:

  * ``put_call_parity_reflection``  -> passed,
        composite_verdict ``proven_modulo_fuzz_validated_contract`` (or
        all-SMT ``proven_modulo_real_arithmetic``; ``proven`` is the retired
        back-compat alias), with the std.normal_cdf.reflection contract
        discharged (fuzz, 8192 samples) AND a cvc5 non-vacuity SAT check.
  * ``call_upper_bounded_by_spot``  -> passed, composite proven (range contract).
  * ``delta_in_unit_interval``      -> passed, composite proven (range contract).
  * ``put_call_parity_corrupted``   -> failed (the corrupted coupling no longer
        follows from the sound contract; cvc5 returns a counterexample -- the
        verdict FLIPS, proving the green depended on the real contract).
  * ``delta_unknown_contract``      -> unsupported (an unknown contract id cannot
        bind any assumptions).

This gate needs the SMT-enabled ``chelis`` build (``--features smt``, cvc5 linked
via cvc5-rs). Like the research that established this corpus, SMT is an OPTIONAL
build -- the stock PATH ``chelis`` is not SMT-enabled. Point the gate at an SMT
binary with ``CHELIS_PROVE_BIN`` (e.g. the chelis-prove-pipeline release build).
If the configured binary lowers nothing (every property comes back unsupported
with "does not lower to Tier B"), the gate SKIPS with a clear message rather than
failing, so a non-SMT environment does not report a false negative.

Run:
    CHELIS_PROVE_BIN=/path/to/smt/chelis \
        python scripts/manual_gates/phase3l_shoals_oracle_composite_corpus.py

Exit 0 on PASS (or SKIP when no SMT binary is available), 1 on FAIL.

This script lives in Python per the repo policy that prohibits shell scripts
(`AGENTS.md`).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

GATE_NAME = "phase3l_shoals_oracle_composite_corpus"
REPO_ROOT = Path(__file__).resolve().parents[2]
CORPUS = "properties/composites.ch"

# A composite green is one of these (base SMT proof + a fuzz-validated contract,
# or an all-SMT proof when no transcendental contract is needed). Under chelis
# 0.9.0 every all-SMT green now reads ``proven_modulo_real_arithmetic``; the
# bare ``proven`` token it replaces is kept here as a back-compat alias. The
# shoals composites corpus emits ``proven_modulo_fuzz_validated_contract`` for
# all three greens (each carries a normal_cdf contract), so the real-arithmetic
# token is forward-compat for a future contract-free composite. The 0.9.0
# ``sound_approximate`` verdict is intentionally NOT accepted: no legitimately
# green property in this corpus emits it (observed at the 0.9.0 cascade).
GREEN_VERDICTS = {
    "proven_modulo_fuzz_validated_contract",
    "proven_modulo_real_arithmetic",
    "proven",
}

# property name -> expected outcome.
#   ("green", required_contract_ids)  -> passed with a composite green and those
#                                        std contracts discharged.
#   ("failed", None)                  -> the verdict must flip to failed.
#   ("unsupported", None)             -> must be unsupported (unknown contract).
EXPECTED = {
    "put_call_parity_reflection": ("green", {"std.normal_cdf.reflection"}),
    "call_upper_bounded_by_spot": ("green", {"std.normal_cdf.range"}),
    "delta_in_unit_interval": ("green", {"std.normal_cdf.range"}),
    "put_call_parity_corrupted": ("failed", None),
    "delta_unknown_contract": ("unsupported", None),
}


def prove_binary() -> str:
    return os.environ.get("CHELIS_PROVE_BIN", "chelis")


def run_prove() -> tuple[int, list[dict]]:
    proc = subprocess.run(
        [
            prove_binary(),
            "prove",
            CORPUS,
            "--tier",
            "smt-only",
            "--json",
            "--smt-timeout",
            "20000",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=900,
    )
    records = []
    for line in proc.stdout.splitlines():
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return proc.returncode, records


def std_contracts_discharged(record: dict) -> set[str]:
    """Std contract ids with a validated discharge AND an established
    non-vacuity check on this record."""
    ok: set[str] = set()
    for a in record.get("assumptions", []):
        if a.get("source_type") != "std_contract":
            continue
        discharged = a.get("discharge", {}).get("evidence", {}).get("status") == "validated"
        non_vacuous = a.get("non_vacuity", {}).get("status") == "established"
        if discharged and non_vacuous:
            ok.add(a.get("name", ""))
    return ok


def base_proof_non_vacuous(record: dict) -> bool:
    """The base SMT obligation carries an established non-vacuity (the SMT
    analog of samples>0: cvc5 found a model of the assumption set)."""
    for a in record.get("assumptions", []):
        if a.get("source_type") == "std_contract":
            continue
        if a.get("non_vacuity", {}).get("status") == "established":
            return True
    return False


def main() -> int:
    code, records = run_prove()
    by_name = {r.get("name"): r for r in records if r.get("kind") == "property"}
    seen = {n: by_name.get(n) for n in EXPECTED}

    # SMT/binary availability -> SKIP (never a false FAIL on an environment that
    # cannot run the corpus). Two forms:
    #  (a) the binary emitted NO property record for any expected property -- it
    #      is too old to parse the contract syntax (e.g. pre-0.8.0) or lacks the
    #      contract mechanism entirely; or
    #  (b) every expected property came back unsupported with "does not lower"
    #      -- the binary parses the corpus but has no Tier B (no SMT feature).
    no_records = all(r is None for r in seen.values())
    not_lowered = [
        n
        for n, r in seen.items()
        if r is not None
        and r.get("status") == "unsupported"
        and "does not lower" in (r.get("reason") or "")
    ]
    if no_records or len(not_lowered) == len(EXPECTED):
        why = (
            "did not emit any composite property record (binary likely predates the "
            "0.8.0 contract mechanism)"
            if no_records
            else "did not lower any composite to Tier B (no SMT feature)"
        )
        print(
            f"SKIP: {GATE_NAME} — configured chelis ({prove_binary()}) {why}; SMT is an "
            f"optional build. Set CHELIS_PROVE_BIN to an SMT-enabled chelis 0.9.0 to run "
            f"this gate."
        )
        return 0

    report: dict = {"gate": GATE_NAME, "corpus": CORPUS, "properties": []}
    all_ok = True
    for name, (kind, contracts) in EXPECTED.items():
        rec = by_name.get(name)
        entry: dict = {
            "name": name,
            "expected": kind,
            "status": rec.get("status") if rec else None,
            "composite_verdict": rec.get("composite_verdict") if rec else None,
            "reason": rec.get("reason") if rec else None,
        }
        if rec is None:
            ok = False
            entry["why"] = "no property record emitted"
        elif kind == "green":
            verdict = rec.get("composite_verdict")
            discharged = std_contracts_discharged(rec)
            ok = (
                rec.get("status") == "passed"
                and verdict in GREEN_VERDICTS
                and rec.get("proof_tier") == "smt"
                and contracts.issubset(discharged)
                and base_proof_non_vacuous(rec)
            )
            entry["discharged_contracts"] = sorted(discharged)
            entry["base_non_vacuous"] = base_proof_non_vacuous(rec)
        elif kind == "failed":
            # The corrupted coupling must be refuted with a concrete model.
            ok = rec.get("status") == "failed" and rec.get("counterexample") is not None
            entry["has_counterexample"] = rec.get("counterexample") is not None
        elif kind == "unsupported":
            ok = rec.get("status") == "unsupported" and "unknown contract" in (
                rec.get("reason") or ""
            )
        else:
            ok = False
        entry["ok"] = ok
        all_ok = all_ok and ok
        report["properties"].append(entry)

    report["prove_exit_code"] = code
    report["all_ok"] = all_ok
    sys.stdout.write(json.dumps(report, indent=2) + "\n")
    if all_ok:
        green_tokens = sorted(
            {
                e["composite_verdict"]
                for e in report["properties"]
                if e["expected"] == "green" and e["composite_verdict"]
            }
        )
        print(
            f"PASS: {GATE_NAME} — 3 composite greens "
            f"({', '.join(green_tokens)}), 1 corrupted-coupling flip "
            f"(failed), 1 unknown-contract (unsupported)."
        )
        return 0
    print(f"FAIL: {GATE_NAME} — see per-property JSON above.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
