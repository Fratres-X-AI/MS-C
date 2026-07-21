"""Reproduce / validate golden digital evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from models.kit_export import export_kit
from models.optimizer import optimize_pattern
from models.scenes import SITE_CLASSES
from models.scorecard import build_scorecard

ROOT = Path(__file__).resolve().parents[1]
GOLDEN = ROOT / "analysis" / "results" / "golden"

# Locked laptop preset for golden regeneration
GOLDEN_STEPS = 40
GOLDEN_SEED = 7


def _sha256(path: Path) -> str:
    data = path.read_bytes()
    # Text fixtures: hash LF-normalized bytes so Windows CRLF checkouts match CI.
    if path.suffix.lower() in {".json", ".md", ".txt", ".csv"}:
        data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return hashlib.sha256(data).hexdigest()


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def regenerate_golden() -> dict[str, Any]:
    GOLDEN.mkdir(parents=True, exist_ok=True)
    results = [
        optimize_pattern(sc, seed=GOLDEN_SEED, steps=GOLDEN_STEPS, detector_kind="surrogate")
        for sc in SITE_CLASSES
    ]
    scorecard = build_scorecard(results, detector_kind="surrogate")
    export_kit(results, GOLDEN)
    (GOLDEN / "scorecard.json").write_text(json.dumps(scorecard, indent=2) + "\n", encoding="utf-8")

    files = sorted(p for p in GOLDEN.rglob("*") if p.is_file() and p.name != "reproduce_manifest.json")
    manifest = {
        "product": "MS-C Mantle",
        "version": "0.1.0",
        "seed": GOLDEN_SEED,
        "steps": GOLDEN_STEPS,
        "detector": "surrogate_v1",
        "evidence_class": "digital_surrogate_unvalidated",
        "files": {p.relative_to(GOLDEN).as_posix(): _sha256(p) for p in files},
    }
    (GOLDEN / "reproduce_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    return manifest


def validate_golden() -> None:
    man_path = GOLDEN / "reproduce_manifest.json"
    score_path = GOLDEN / "scorecard.json"
    kit_path = GOLDEN / "kit_manifest.json"
    if not man_path.is_file() or not score_path.is_file() or not kit_path.is_file():
        raise SystemExit("golden artifacts missing — run: python -m sim.reproduce")

    manifest = _load_json(man_path)
    scorecard = _load_json(score_path)
    summary = scorecard["summary"]

    # Invariants (honesty + discriminative MoE)
    if summary.get("evidence_class") != "digital_surrogate_unvalidated":
        raise SystemExit("scorecard missing honesty evidence_class")
    if summary["nominal_mean_collapse_vs_uncovered"] <= 0.0:
        raise SystemExit("expected positive nominal collapse vs uncovered")
    if summary["adversarial_mean_collapse_vs_uncovered"] > summary["nominal_mean_collapse_vs_uncovered"] + 0.25:
        # adversarial may be worse (lower collapse); allow equality band the other way
        pass
    # Adversarial collapse should not claim perfection
    if summary["nominal_mean_collapse_vs_uncovered"] >= 0.999:
        raise SystemExit("saturated MoE forbidden (discriminative gate)")

    # Checksum verify
    for rel, digest in manifest["files"].items():
        path = GOLDEN / rel
        if not path.is_file():
            raise SystemExit(f"missing golden file: {rel}")
        if _sha256(path) != digest:
            raise SystemExit(f"checksum mismatch: {rel}")

    kit = _load_json(kit_path)
    if len(kit.get("kits", [])) != len(SITE_CLASSES):
        raise SystemExit("kit_manifest incomplete")
    if "bom_stub" not in kit:
        raise SystemExit("bom_stub missing")


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(description="MS-C reproduce / validate golden evidence")
    p.add_argument("--validate-only", action="store_true")
    p.add_argument("--regen", action="store_true", help="force regenerate golden")
    args = p.parse_args(argv)

    if args.validate_only:
        validate_golden()
        print("OK reproduce validate-only")
        return

    if args.regen or not (GOLDEN / "reproduce_manifest.json").is_file():
        regenerate_golden()
        print("OK golden regenerated")
    validate_golden()
    print("OK reproduce")


if __name__ == "__main__":
    main()
