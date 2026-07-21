"""Manufacturable adversarial tile optimizer (CPU finite-difference / random search)."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from models.constraints import PALETTE_RGB, ManufConstraints, project_manufacturable
from models.detectors import SurrogateDetector, get_detector
from models.renderer import apply_pattern_to_scene
from models.scenes import Scene, generate_scene


@dataclass
class OptimizeResult:
    pattern_rgb: np.ndarray
    pattern_emis: np.ndarray
    best_score: float  # mean confidence after cover (lower is better)
    baseline_score: float
    steps: int
    site_class: str
    seed: int


def _pattern_from_logits(logits: np.ndarray, constraints: ManufConstraints) -> tuple[np.ndarray, np.ndarray]:
    # logits: (tile, tile, n_palette) → soft pick then harden via project
    idx = logits.argmax(axis=2)
    rgb = PALETTE_RGB[idx % constraints.n_palette]
    return project_manufacturable(rgb, constraints)


def evaluate_pattern(
    scene: Scene,
    pattern_rgb: np.ndarray,
    pattern_emis: np.ndarray,
    detector: SurrogateDetector,
    *,
    alpha: float = 0.85,
) -> float:
    covered = apply_pattern_to_scene(scene, pattern_rgb, pattern_emis, alpha=alpha)
    return detector.mean_confidence(covered)


def optimize_pattern(
    site_class: str,
    *,
    seed: int = 0,
    steps: int = 40,
    tile: int = 32,
    detector_kind: str = "surrogate",
    detector_weights: str | None = None,
    size: int = 256,
    constraints: ManufConstraints | None = None,
) -> OptimizeResult:
    """Random local search over palette logits; laptop-safe default steps."""
    constraints = constraints or ManufConstraints(tile=tile)
    rng = np.random.default_rng(seed)
    detector = get_detector(detector_kind, weights=detector_weights)
    scene = generate_scene(site_class, seed=seed, size=size, view="nadir", lighting="nominal")
    baseline = detector.mean_confidence(scene)

    logits = rng.normal(0, 1, size=(constraints.tile, constraints.tile, constraints.n_palette))
    best_rgb, best_emis = _pattern_from_logits(logits, constraints)
    best_score = evaluate_pattern(scene, best_rgb, best_emis, detector)

    for _ in range(steps):
        cand = logits + rng.normal(0, 0.55, size=logits.shape)
        # occasional palette block mutate for manufacturable structure
        if rng.random() < 0.3:
            y0 = int(rng.integers(0, constraints.tile))
            x0 = int(rng.integers(0, constraints.tile))
            bh = int(rng.integers(2, max(3, constraints.tile // 4)))
            bw = int(rng.integers(2, max(3, constraints.tile // 4)))
            p = int(rng.integers(0, constraints.n_palette))
            cand[y0 : y0 + bh, x0 : x0 + bw, :] = -2.0
            cand[y0 : y0 + bh, x0 : x0 + bw, p] = 3.0
        rgb, emis = _pattern_from_logits(cand, constraints)
        score = evaluate_pattern(scene, rgb, emis, detector)
        if score < best_score:
            best_score = score
            best_rgb, best_emis = rgb, emis
            logits = cand

    return OptimizeResult(
        pattern_rgb=best_rgb,
        pattern_emis=best_emis,
        best_score=float(best_score),
        baseline_score=float(baseline),
        steps=steps,
        site_class=site_class,
        seed=seed,
    )


def collapse_ratio(baseline: float, covered: float) -> float:
    """Fraction of confidence removed; 0 if baseline ~ 0."""
    if baseline <= 1e-6:
        return 0.0
    return float(np.clip((baseline - covered) / baseline, 0.0, 1.0))
