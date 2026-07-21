"""Detectors: CPU surrogate (CI) + optional Ultralytics YOLO (GPU path)."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from models.renderer import lwir_proxy
from models.scenes import BBox, Scene


@dataclass(frozen=True)
class DetectionScore:
    """Per-box confidence in [0, 1]. Surrogate or YOLO — always labeled in scorecard."""

    label: str
    confidence: float
    box: tuple[int, int, int, int]


def _sobel_energy(gray: np.ndarray) -> float:
    g = gray.astype(np.float32)
    if g.size < 9:
        return 0.0
    gx = np.zeros_like(g)
    gy = np.zeros_like(g)
    gx[:, 1:-1] = g[:, 2:] - g[:, :-2]
    gy[1:-1, :] = g[2:, :] - g[:-2, :]
    return float(np.mean(np.sqrt(gx * gx + gy * gy)))


def _box_confidence(scene: Scene, box: BBox) -> float:
    """Heuristic detectability: VIS contrast + edge energy + IR contrast vs surround."""
    x0, y0, x1, y1 = box.as_tuple()
    patch = scene.rgb[y0:y1, x0:x1]
    if patch.size == 0:
        return 0.0
    gray = patch.mean(axis=2)
    # surround ring
    pad = 8
    H, W = scene.rgb.shape[:2]
    sx0, sy0 = max(0, x0 - pad), max(0, y0 - pad)
    sx1, sy1 = min(W, x1 + pad), min(H, y1 + pad)
    surround = scene.rgb[sy0:sy1, sx0:sx1].mean(axis=2)
    # mask out interior approx by comparing means
    contrast = abs(float(gray.mean()) - float(surround.mean())) / 255.0
    edges = min(1.0, _sobel_energy(gray) / 40.0)

    ir = lwir_proxy(scene.emissivity)
    ir_p = ir[y0:y1, x0:x1].astype(np.float32)
    ir_s = ir[sy0:sy1, sx0:sx1].astype(np.float32)
    ir_c = abs(float(ir_p.mean()) - float(ir_s.mean())) / 255.0

    # Weighted fusion — planning surrogate only (A-001)
    score = 0.45 * contrast + 0.35 * edges + 0.20 * ir_c
    return float(np.clip(score * 1.6, 0.0, 1.0))


class SurrogateDetector:
    """Laptop-safe detector proxy. Not a trained neural detector."""

    name = "surrogate_v1"

    def score_scene(self, scene: Scene) -> list[DetectionScore]:
        out: list[DetectionScore] = []
        for box in scene.boxes:
            conf = _box_confidence(scene, box)
            out.append(DetectionScore(box.label, conf, box.as_tuple()))
        return out

    def mean_confidence(self, scene: Scene) -> float:
        scores = self.score_scene(scene)
        if not scores:
            return 0.0
        return float(sum(s.confidence for s in scores) / len(scores))


class YoloDetector:
    """Optional Ultralytics wrapper. Prefer fine-tuned site weights for Mantle."""

    name = "yolo"

    def __init__(self, weights: str = "yolov8n.pt") -> None:
        try:
            from ultralytics import YOLO  # type: ignore
        except ImportError as exc:  # pragma: no cover
            raise RuntimeError(
                "ultralytics not installed; pip install -e '.[yolo]' or use surrogate"
            ) from exc
        self.weights = weights
        self.model = YOLO(weights)

    def score_scene(self, scene: Scene) -> list[DetectionScore]:
        # Map YOLO detections onto GT boxes by IoU — planning transfer path only.
        results = self.model.predict(scene.rgb, verbose=False)
        dets = []
        if results and results[0].boxes is not None:
            xyxy = results[0].boxes.xyxy.cpu().numpy()
            confs = results[0].boxes.conf.cpu().numpy()
            for box, conf in zip(xyxy, confs):
                dets.append((box, float(conf)))

        out: list[DetectionScore] = []
        for gt in scene.boxes:
            best = 0.0
            for box, conf in dets:
                if _iou(gt.as_tuple(), tuple(map(int, box))) > 0.2:
                    best = max(best, conf)
            out.append(DetectionScore(gt.label, best, gt.as_tuple()))
        return out

    def mean_confidence(self, scene: Scene) -> float:
        scores = self.score_scene(scene)
        if not scores:
            return 0.0
        return float(sum(s.confidence for s in scores) / len(scores))


def _iou(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> float:
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    iw, ih = max(0, ix1 - ix0), max(0, iy1 - iy0)
    inter = iw * ih
    if inter <= 0:
        return 0.0
    area_a = max(0, ax1 - ax0) * max(0, ay1 - ay0)
    area_b = max(0, bx1 - bx0) * max(0, by1 - by0)
    union = area_a + area_b - inter
    return inter / union if union > 0 else 0.0


def get_detector(
    kind: str = "surrogate",
    *,
    weights: str | None = None,
) -> SurrogateDetector | YoloDetector:
    if kind in ("surrogate", "surrogate_v1"):
        return SurrogateDetector()
    if kind == "yolo":
        return YoloDetector(weights or "yolov8n.pt")
    raise ValueError(f"unknown detector={kind!r}")
