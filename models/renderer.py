"""Dual-band surrogate renderer: VIS overlay + LWIR brightness from emissivity.

Surrogate physics only — not a FLIR simulator.
"""

from __future__ import annotations

import numpy as np
from PIL import Image

from models.scenes import BBox, Scene


def apply_pattern_to_scene(
    scene: Scene,
    pattern_rgb: np.ndarray,
    pattern_emis: np.ndarray,
    *,
    alpha: float = 0.85,
    boxes: list[BBox] | None = None,
) -> Scene:
    """Composite tileable pattern over asset boxes (or full frame if boxes is None)."""
    rgb = scene.rgb.copy()
    emis = scene.emissivity.copy()
    ph, pw = pattern_rgb.shape[:2]
    targets = boxes if boxes is not None else scene.boxes

    for box in targets:
        x0, y0, x1, y1 = box.as_tuple()
        h, w = y1 - y0, x1 - x0
        if h <= 0 or w <= 0:
            continue
        # tile pattern
        reps_y = int(np.ceil(h / ph)) + 1
        reps_x = int(np.ceil(w / pw)) + 1
        tiled = np.tile(pattern_rgb, (reps_y, reps_x, 1))[:h, :w]
        tiled_e = np.tile(pattern_emis, (reps_y, reps_x))[:h, :w]
        region = rgb[y0:y1, x0:x1].astype(np.float32)
        blend = (1.0 - alpha) * region + alpha * tiled.astype(np.float32)
        rgb[y0:y1, x0:x1] = np.clip(blend, 0, 255).astype(np.uint8)
        emis[y0:y1, x0:x1] = (1.0 - alpha) * emis[y0:y1, x0:x1] + alpha * tiled_e

    return Scene(
        site_class=scene.site_class,
        rgb=rgb,
        emissivity=emis,
        boxes=list(scene.boxes),
        seed=scene.seed,
        view=scene.view,
        lighting=scene.lighting,
    )


def lwir_proxy(emissivity: np.ndarray, *, ambient: float = 0.35) -> np.ndarray:
    """Map emissivity to an 8-bit LWIR-looking single channel (planning proxy)."""
    # Higher emissivity → brighter in this simplified proxy (not radiometrically correct).
    sig = ambient + (1.0 - ambient) * np.clip(emissivity, 0, 1)
    return (sig * 255).astype(np.uint8)


def dual_band_preview(scene: Scene) -> tuple[Image.Image, Image.Image]:
    vis = Image.fromarray(scene.rgb, mode="RGB")
    ir = Image.fromarray(lwir_proxy(scene.emissivity), mode="L")
    return vis, ir


def commercial_camo_pattern(tile: int = 32, seed: int = 1) -> tuple[np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed)
    rgb = np.zeros((tile, tile, 3), dtype=np.uint8)
    palette = [(60, 80, 45), (90, 100, 55), (40, 55, 35), (110, 105, 70)]
    for y in range(tile):
        for x in range(tile):
            rgb[y, x] = palette[int(rng.integers(0, len(palette)))]
    emis = np.full((tile, tile), 0.85, dtype=np.float32)
    return rgb, emis


def random_noise_pattern(tile: int = 32, seed: int = 2) -> tuple[np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed)
    rgb = rng.integers(0, 256, size=(tile, tile, 3), dtype=np.uint8)
    emis = rng.uniform(0.2, 0.9, size=(tile, tile)).astype(np.float32)
    return rgb, emis
