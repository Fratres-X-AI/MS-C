"""Synthetic critical-site scenes with known bboxes (seedable, laptop-safe)."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

SITE_CLASSES = ("substation", "tank_pad", "pipeline")


@dataclass(frozen=True)
class BBox:
    """xyxy pixel box."""

    x0: int
    y0: int
    x1: int
    y1: int
    label: str

    def as_tuple(self) -> tuple[int, int, int, int]:
        return self.x0, self.y0, self.x1, self.y1

    def clip(self, w: int, h: int) -> BBox:
        return BBox(
            max(0, min(self.x0, w - 1)),
            max(0, min(self.y0, h - 1)),
            max(1, min(self.x1, w)),
            max(1, min(self.y1, h)),
            self.label,
        )


@dataclass
class Scene:
    site_class: str
    rgb: np.ndarray  # HxWx3 uint8
    emissivity: np.ndarray  # HxW float32
    boxes: list[BBox]
    seed: int
    view: str = "nadir"
    lighting: str = "nominal"


def _rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def _fill_rect(
    rgb: np.ndarray,
    emis: np.ndarray,
    box: BBox,
    color: tuple[int, int, int],
    e: float,
) -> None:
    x0, y0, x1, y1 = box.as_tuple()
    rgb[y0:y1, x0:x1] = color
    emis[y0:y1, x0:x1] = e


def _background(h: int, w: int, rng: np.random.Generator, lighting: str) -> tuple[np.ndarray, np.ndarray]:
    base = np.array([95, 110, 70], dtype=np.float32)
    if lighting == "harsh":
        base = base * 1.25
    elif lighting == "dim":
        base = base * 0.65
    noise = rng.normal(0, 8, size=(h, w, 3))
    rgb = np.clip(base + noise, 0, 255).astype(np.uint8)
    emis = np.full((h, w), 0.88, dtype=np.float32)
    # dirt patches
    for _ in range(12):
        cx, cy = int(rng.integers(0, w)), int(rng.integers(0, h))
        rw, rh = int(rng.integers(8, 40)), int(rng.integers(8, 40))
        x0, y0 = max(0, cx - rw), max(0, cy - rh)
        x1, y1 = min(w, cx + rw), min(h, cy + rh)
        rgb[y0:y1, x0:x1] = np.clip(
            rgb[y0:y1, x0:x1].astype(np.int16) + rng.integers(-20, 15), 0, 255
        ).astype(np.uint8)
    return rgb, emis


def generate_scene(
    site_class: str,
    *,
    seed: int = 0,
    size: int = 256,
    view: str = "nadir",
    lighting: str = "nominal",
) -> Scene:
    if site_class not in SITE_CLASSES:
        raise ValueError(f"unknown site_class={site_class!r}")
    rng = _rng(seed + hash((site_class, view, lighting)) % 10_000)
    h = w = size
    rgb, emis = _background(h, w, rng, lighting)

    # Oblique: shear-like offset for boxes
    skew = 0 if view == "nadir" else int(0.08 * size)

    boxes: list[BBox] = []
    if site_class == "substation":
        specs = [
            (40 + skew, 50, 110, 140, "transformer", (150, 155, 160), 0.28),
            (130, 45 + skew // 2, 200, 130, "transformer", (145, 150, 155), 0.30),
            (70, 160, 180, 210, "buswork", (170, 175, 180), 0.22),
        ]
    elif site_class == "tank_pad":
        specs = [
            (60 + skew, 40, 150, 150, "tank", (130, 135, 140), 0.35),
            (160, 90 + skew // 2, 220, 170, "pump", (100, 105, 110), 0.85),
        ]
    else:  # pipeline
        specs = [
            (20, 110 + skew // 3, 240, 145, "pipe", (120, 125, 130), 0.40),
            (90 + skew, 150, 160, 210, "valve_skid", (90, 95, 100), 0.80),
        ]

    for x0, y0, x1, y1, label, color, e in specs:
        box = BBox(x0, y0, x1, y1, label).clip(w, h)
        _fill_rect(rgb, emis, box, color, e)
        # high-contrast edge hint (detector-friendly)
        rgb[box.y0 : box.y0 + 2, box.x0 : box.x1] = (30, 30, 30)
        rgb[box.y1 - 2 : box.y1, box.x0 : box.x1] = (30, 30, 30)
        boxes.append(box)

    return Scene(
        site_class=site_class,
        rgb=rgb,
        emissivity=emis,
        boxes=boxes,
        seed=seed,
        view=view,
        lighting=lighting,
    )


def fixture_bundle(seed: int = 7, size: int = 256) -> list[Scene]:
    """Nominal + adversarial (held-out view/light) fixtures for all site classes."""
    scenes: list[Scene] = []
    for sc in SITE_CLASSES:
        scenes.append(generate_scene(sc, seed=seed, size=size, view="nadir", lighting="nominal"))
        scenes.append(
            generate_scene(sc, seed=seed + 1, size=size, view="oblique", lighting="harsh")
        )
    return scenes
