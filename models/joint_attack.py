"""Multi-objective Mantle attack: site-YOLO + multi-view + beat commercial camo.

Maxxed for multi-process + batched YOLO predict.

Collapse objective (MSC_OBJ_MODE=collapse, default): reward YOLO collapse vs
uncovered and punish covered>uncovered inversions. Legacy mode keeps the old
mean_yolo + beat_com objective.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

import numpy as np

from models.constraints import (
    PALETTE_RGB,
    ManufConstraints,
    indices_from_rgb,
    project_manufacturable,
)
from models.detectors import get_detector
from models.optimizer import OptimizeResult
from models.renderer import apply_pattern_to_scene, commercial_camo_pattern
from models.scenes import generate_scene


@dataclass(frozen=True)
class ViewSpec:
    view: str
    lighting: str
    weight: float


HARD_VIEWS = (
    ViewSpec("nadir", "nominal", 1.0),
    ViewSpec("oblique", "harsh", 1.2),
    ViewSpec("oblique", "dim", 1.0),
    ViewSpec("nadir", "harsh", 0.9),
    ViewSpec("oblique", "nominal", 1.0),
    ViewSpec("nadir", "dim", 0.8),
)


def _pattern_from_logits(logits: np.ndarray, constraints: ManufConstraints) -> tuple[np.ndarray, np.ndarray]:
    idx = logits.argmax(axis=2)
    rgb = PALETTE_RGB[idx % constraints.n_palette]
    return project_manufacturable(rgb, constraints)


def _batched_yolo_means(detector, images: list[np.ndarray]) -> list[float]:
    """One GPU forward for many images; map max conf (or 0)."""
    if not images:
        return []
    # Ultralytics accepts list/ndarray batch
    results = detector.model.predict(images, verbose=False, stream=False)
    out: list[float] = []
    for r in results:
        if r.boxes is None or len(r.boxes) == 0:
            out.append(0.0)
        else:
            out.append(float(r.boxes.conf.cpu().numpy().max()))
    return out


def evaluate_joint(
    site_class: str,
    seed: int,
    pattern_rgb: np.ndarray,
    pattern_emis: np.ndarray,
    detector,
    *,
    size: int = 320,
    alpha: float = 0.72,
    views: tuple[ViewSpec, ...] = HARD_VIEWS,
) -> dict:
    scenes = [
        generate_scene(site_class, seed=seed, size=size, view=vs.view, lighting=vs.lighting) for vs in views
    ]
    covered_imgs = [
        apply_pattern_to_scene(sc, pattern_rgb, pattern_emis, alpha=alpha).rgb for sc in scenes
    ]
    unc_imgs = [sc.rgb for sc in scenes]
    unc_scores = _batched_yolo_means(detector, unc_imgs)
    cov_scores = _batched_yolo_means(detector, covered_imgs)
    weights = [vs.weight for vs in views]
    mean_unc = float(np.average(unc_scores, weights=weights))
    mean_yolo = float(np.average(cov_scores, weights=weights))
    yolo_collapse = max(0.0, (mean_unc - mean_yolo) / max(mean_unc, 1e-6))
    inversion_pen = max(0.0, mean_yolo - mean_unc)

    scene0 = scenes[0]
    c_rgb, c_e = commercial_camo_pattern(tile=pattern_rgb.shape[0], seed=seed + 11)
    com_img = apply_pattern_to_scene(scene0, c_rgb, c_e, alpha=alpha).rgb
    man_img = covered_imgs[0]
    com, man = _batched_yolo_means(detector, [com_img, man_img])
    beat_com = max(0.0, man - com + 0.02)
    uniq = int(np.unique(pattern_rgb.reshape(-1, 3), axis=0).shape[0])
    natural_pen = max(0.0, (3 - uniq) * 0.05)

    mode = os.environ.get("MSC_OBJ_MODE", "collapse").strip().lower()
    w_collapse = float(os.environ.get("MSC_OBJ_COLLAPSE_W", "1.0"))
    w_inv = float(os.environ.get("MSC_OBJ_INVERSION_W", "1.5"))
    if mode == "legacy":
        objective = mean_yolo + 0.35 * beat_com + natural_pen
    else:
        # Minimize: low covered conf, high collapse vs uncovered, no inversion.
        objective = (
            mean_yolo
            - w_collapse * yolo_collapse
            + 0.35 * beat_com
            + natural_pen
            + w_inv * inversion_pen
        )
    return {
        "objective": objective,
        "mean_yolo_covered": mean_yolo,
        "mean_yolo_uncovered": mean_unc,
        "yolo_collapse": float(yolo_collapse),
        "inversion_pen": float(inversion_pen),
        "mantle_nadir": float(man),
        "commercial_nadir": float(com),
        "uniq_colors": uniq,
        "beat_com_pen": float(beat_com),
        "obj_mode": mode,
    }


def optimize_joint(
    site_class: str,
    *,
    seed: int = 0,
    steps: int = 120,
    tile: int = 32,
    detector_weights: str,
    size: int = 320,
    alpha: float = 0.72,
) -> OptimizeResult:
    constraints = ManufConstraints(tile=tile)
    rng = np.random.default_rng(seed)
    detector = get_detector("yolo", weights=detector_weights)
    scene = generate_scene(site_class, seed=seed, size=size, view="nadir", lighting="nominal")
    baseline = float(_batched_yolo_means(detector, [scene.rgb])[0])

    logits = rng.normal(0, 1, size=(tile, tile, constraints.n_palette))
    best_rgb, best_emis = _pattern_from_logits(logits, constraints)
    best_metrics = evaluate_joint(
        site_class, seed, best_rgb, best_emis, detector, size=size, alpha=alpha
    )
    best_obj = best_metrics["objective"]

    # Candidate batching: evaluate K mutants per GPU call cycle (fat GPUs: 8)
    k_batch = 8
    for i in range(0, steps, k_batch):
        cands = []
        cand_logits = []
        for j in range(k_batch):
            if i + j >= steps:
                break
            cand = logits + rng.normal(0, 0.5, size=logits.shape)
            if rng.random() < 0.4:
                y0 = int(rng.integers(0, tile))
                x0 = int(rng.integers(0, tile))
                bh = int(rng.integers(2, max(3, tile // 3)))
                bw = int(rng.integers(2, max(3, tile // 3)))
                p = int(rng.integers(0, constraints.n_palette))
                cand[y0 : y0 + bh, x0 : x0 + bw, :] = -2.0
                cand[y0 : y0 + bh, x0 : x0 + bw, p] = 3.0
            if rng.random() < 0.12:
                c_rgb, _ = commercial_camo_pattern(tile=tile, seed=seed + i + j)
                idx = indices_from_rgb(c_rgb, constraints.n_palette)
                soft = np.full((tile, tile, constraints.n_palette), -1.0, dtype=np.float64)
                flat_i = idx.reshape(-1)
                # vectorized soft assign
                soft = soft.reshape(-1, constraints.n_palette)
                soft[np.arange(flat_i.size), flat_i] = 2.0
                soft = soft.reshape(tile, tile, constraints.n_palette)
                cand = 0.7 * cand + 0.3 * soft
            rgb, emis = _pattern_from_logits(cand, constraints)
            cands.append((rgb, emis))
            cand_logits.append(cand)

        # score each candidate (batched views inside evaluate_joint)
        for (rgb, emis), cand in zip(cands, cand_logits):
            metrics = evaluate_joint(site_class, seed, rgb, emis, detector, size=size, alpha=alpha)
            if metrics["objective"] < best_obj:
                best_obj = metrics["objective"]
                best_rgb, best_emis = rgb, emis
                logits = cand

    covered = apply_pattern_to_scene(scene, best_rgb, best_emis, alpha=alpha)
    best_score = float(_batched_yolo_means(detector, [covered.rgb])[0])
    return OptimizeResult(
        pattern_rgb=best_rgb,
        pattern_emis=best_emis,
        best_score=best_score,
        baseline_score=baseline,
        steps=steps,
        site_class=site_class,
        seed=seed,
    )


def _worker_job(args: tuple) -> dict:
    site_class, seed, steps, weights, size, alpha = args
    res = optimize_joint(
        site_class,
        seed=seed,
        steps=steps,
        detector_weights=weights,
        size=size,
        alpha=alpha,
    )
    return {
        "site_class": res.site_class,
        "seed": res.seed,
        "steps": res.steps,
        "baseline_score": res.baseline_score,
        "best_score": res.best_score,
        "rgb": res.pattern_rgb,
        "emis": res.pattern_emis,
    }


def optimize_joint_parallel(
    jobs: list[tuple],
    *,
    n_workers: int,
) -> list[dict]:
    """jobs: list of (site, seed, steps, weights, size, alpha)."""
    from concurrent.futures import ProcessPoolExecutor, as_completed

    results: list[dict] = []
    with ProcessPoolExecutor(max_workers=n_workers) as ex:
        futs = [ex.submit(_worker_job, j) for j in jobs]
        for fut in as_completed(futs):
            results.append(fut.result())
    return results
