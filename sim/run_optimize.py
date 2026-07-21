"""CLI: optimize Mantle tiles for all site classes."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from models.kit_export import export_kit
from models.optimizer import optimize_pattern
from models.scenes import SITE_CLASSES
from models.scorecard import build_scorecard

ROOT = Path(__file__).resolve().parents[1]
GOLDEN = ROOT / "analysis" / "results" / "golden"


def run(
    *,
    steps: int = 40,
    seed: int = 7,
    detector: str = "surrogate",
    out: Path | None = None,
    write_golden: bool = False,
) -> dict:
    out_dir = Path(out) if out else ROOT / "analysis" / "results" / "runs" / "latest"
    out_dir.mkdir(parents=True, exist_ok=True)

    results = [
        optimize_pattern(sc, seed=seed, steps=steps, detector_kind=detector) for sc in SITE_CLASSES
    ]
    scorecard = build_scorecard(results, detector_kind=detector)
    manifest = export_kit(results, out_dir)

    (out_dir / "scorecard.json").write_text(json.dumps(scorecard, indent=2) + "\n", encoding="utf-8")

    if write_golden:
        GOLDEN.mkdir(parents=True, exist_ok=True)
        export_kit(results, GOLDEN)
        (GOLDEN / "scorecard.json").write_text(
            json.dumps(scorecard, indent=2) + "\n", encoding="utf-8"
        )

    return {"out": str(out_dir), "scorecard": scorecard, "manifest": manifest}


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(description="MS-C Mantle pattern optimize")
    p.add_argument("--preset", choices=("laptop", "gpu"), default="laptop")
    p.add_argument("--steps", type=int, default=None)
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--detector", default="surrogate")
    p.add_argument("--out", type=Path, default=None)
    p.add_argument("--write-golden", action="store_true")
    args = p.parse_args(argv)

    steps = args.steps
    if steps is None:
        steps = 40 if args.preset == "laptop" else 200
    detector = args.detector
    if args.preset == "gpu" and args.detector == "surrogate":
        detector = "yolo"

    info = run(
        steps=steps,
        seed=args.seed,
        detector=detector,
        out=args.out,
        write_golden=args.write_golden,
    )
    s = info["scorecard"]["summary"]
    print(
        f"OK optimize → {info['out']} | "
        f"nominal_collapse={s['nominal_mean_collapse_vs_uncovered']:.3f} | "
        f"adv_collapse={s['adversarial_mean_collapse_vs_uncovered']:.3f} | "
        f"evidence={s['evidence_class']}"
    )


if __name__ == "__main__":
    main()
