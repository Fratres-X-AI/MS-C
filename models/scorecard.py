"""MoE scorecard: uncovered / commercial / noise / mantle × nominal / adversarial."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

import numpy as np

from models.detectors import get_detector
from models.optimizer import OptimizeResult, collapse_ratio, evaluate_pattern
from models.renderer import (
    apply_pattern_to_scene,
    commercial_camo_pattern,
    random_noise_pattern,
)
from models.scenes import SITE_CLASSES, generate_scene


@dataclass
class StackScores:
    uncovered: float
    commercial: float
    random_noise: float
    mantle: float
    collapse_vs_uncovered: float
    collapse_vs_commercial: float


def _stack_scores(
    site_class: str,
    seed: int,
    view: str,
    lighting: str,
    mantle_rgb: np.ndarray,
    mantle_emis: np.ndarray,
    detector_kind: str,
    size: int,
) -> StackScores:
    det = get_detector(detector_kind)
    scene = generate_scene(site_class, seed=seed, size=size, view=view, lighting=lighting)
    unc = det.mean_confidence(scene)

    c_rgb, c_e = commercial_camo_pattern(tile=mantle_rgb.shape[0], seed=seed + 11)
    n_rgb, n_e = random_noise_pattern(tile=mantle_rgb.shape[0], seed=seed + 22)

    com = evaluate_pattern(scene, c_rgb, c_e, det)
    noi = evaluate_pattern(scene, n_rgb, n_e, det)
    man = evaluate_pattern(scene, mantle_rgb, mantle_emis, det)

    return StackScores(
        uncovered=float(unc),
        commercial=float(com),
        random_noise=float(noi),
        mantle=float(man),
        collapse_vs_uncovered=collapse_ratio(unc, man),
        collapse_vs_commercial=collapse_ratio(com, man),
    )


def build_scorecard(
    results: list[OptimizeResult],
    *,
    detector_kind: str = "surrogate",
    size: int = 256,
) -> dict[str, Any]:
    """Aggregate nominal vs adversarial stacks. Discriminative, not saturated."""
    by_site: dict[str, Any] = {}
    for res in results:
        nominal = _stack_scores(
            res.site_class,
            res.seed,
            "nadir",
            "nominal",
            res.pattern_rgb,
            res.pattern_emis,
            detector_kind,
            size,
        )
        adversarial = _stack_scores(
            res.site_class,
            res.seed + 1,
            "oblique",
            "harsh",
            res.pattern_rgb,
            res.pattern_emis,
            detector_kind,
            size,
        )
        by_site[res.site_class] = {
            "nominal": asdict(nominal),
            "adversarial": asdict(adversarial),
            "optimize": {
                "steps": res.steps,
                "baseline_score": res.baseline_score,
                "best_score": res.best_score,
                "seed": res.seed,
            },
        }

    # Summary means across sites
    def mean_key(stack: str, key: str) -> float:
        vals = [by_site[s][stack][key] for s in by_site]
        return float(sum(vals) / len(vals)) if vals else 0.0

    summary = {
        "detector": detector_kind,
        "evidence_class": "digital_surrogate_unvalidated",
        "sites": list(by_site.keys()) or list(SITE_CLASSES),
        "nominal_mean_collapse_vs_uncovered": mean_key("nominal", "collapse_vs_uncovered"),
        "adversarial_mean_collapse_vs_uncovered": mean_key("adversarial", "collapse_vs_uncovered"),
        "nominal_mean_mantle_confidence": mean_key("nominal", "mantle"),
        "adversarial_mean_mantle_confidence": mean_key("adversarial", "mantle"),
        "note": (
            "Planning MoE only (A-013). Not a UAS defeat rate. "
            "Adversarial stack uses held-out oblique+harsh lighting."
        ),
    }
    return {"summary": summary, "by_site": by_site}


def covered_preview_rgb(
    site_class: str,
    pattern_rgb: np.ndarray,
    pattern_emis: np.ndarray,
    *,
    seed: int = 0,
    size: int = 256,
) -> np.ndarray:
    scene = generate_scene(site_class, seed=seed, size=size)
    covered = apply_pattern_to_scene(scene, pattern_rgb, pattern_emis)
    return covered.rgb
