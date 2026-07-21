"""Manufacturability constraints for printable / net-weave patterns."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from models.materials import emissivity_for_palette_index


@dataclass(frozen=True)
class ManufConstraints:
    tile: int = 32
    n_palette: int = 8
    max_spatial_freq: float = 0.35  # fraction of Nyquist for blur kernel
    seam_period: int = 32  # must divide evenly for tiling


DEFAULT_CONSTRAINTS = ManufConstraints()

# Fixed earth-tone / industrial palette (print-friendly)
PALETTE_RGB = np.array(
    [
        [55, 70, 40],
        [80, 95, 55],
        [100, 105, 70],
        [120, 115, 85],
        [70, 75, 65],
        [90, 85, 60],
        [45, 55, 50],
        [130, 125, 100],
    ],
    dtype=np.uint8,
)


def quantize_to_palette(rgb: np.ndarray, n_palette: int = 8) -> np.ndarray:
    pal = PALETTE_RGB[:n_palette].astype(np.float32)
    flat = rgb.reshape(-1, 3).astype(np.float32)
    # nearest palette color
    d = ((flat[:, None, :] - pal[None, :, :]) ** 2).sum(axis=2)
    idx = d.argmin(axis=1)
    out = pal[idx].reshape(rgb.shape).astype(np.uint8)
    return out


def indices_from_rgb(rgb: np.ndarray, n_palette: int = 8) -> np.ndarray:
    pal = PALETTE_RGB[:n_palette].astype(np.float32)
    flat = rgb.reshape(-1, 3).astype(np.float32)
    d = ((flat[:, None, :] - pal[None, :, :]) ** 2).sum(axis=2)
    return d.argmin(axis=1).reshape(rgb.shape[:2])


def emissivity_from_indices(idx: np.ndarray, n_palette: int = 8) -> np.ndarray:
    flat = idx.reshape(-1)
    emis = np.array([emissivity_for_palette_index(int(i), n_palette) for i in flat], dtype=np.float32)
    return emis.reshape(idx.shape)


def low_pass(rgb: np.ndarray, max_spatial_freq: float) -> np.ndarray:
    """Box blur sized by max_spatial_freq to kill unrealizable high-frequency noise."""
    # higher max_spatial_freq → smaller blur
    k = max(1, int(round(1.0 / max(0.05, max_spatial_freq))))
    if k % 2 == 0:
        k += 1
    if k <= 1:
        return rgb
    pad = k // 2
    x: np.ndarray = rgb.astype(np.float32)
    # separable cumulative sum blur
    for axis in (0, 1):
        c = np.cumsum(x, axis=axis)
        if axis == 0:
            c = np.pad(c, ((pad + 1, pad), (0, 0), (0, 0)), mode="edge")
            x = np.asarray((c[k:] - c[:-k]) / k, dtype=np.float32)
        else:
            c = np.pad(c, ((0, 0), (pad + 1, pad), (0, 0)), mode="edge")
            x = np.asarray((c[:, k:] - c[:, :-k]) / k, dtype=np.float32)
    return np.clip(x, 0, 255).astype(np.uint8)


def enforce_tiling(rgb: np.ndarray) -> np.ndarray:
    """Average opposite edges so the tile wraps with less seam energy."""
    out = rgb.copy().astype(np.float32)
    out[0, :] = 0.5 * (out[0, :] + out[-1, :])
    out[-1, :] = out[0, :]
    out[:, 0] = 0.5 * (out[:, 0] + out[:, -1])
    out[:, -1] = out[:, 0]
    return np.clip(out, 0, 255).astype(np.uint8)


def project_manufacturable(
    rgb: np.ndarray,
    constraints: ManufConstraints = DEFAULT_CONSTRAINTS,
) -> tuple[np.ndarray, np.ndarray]:
    """Apply blur → palette quantize → seam fix → emissivity map."""
    soft = low_pass(rgb, constraints.max_spatial_freq)
    soft = enforce_tiling(soft)
    q = quantize_to_palette(soft, constraints.n_palette)
    q = enforce_tiling(q)
    idx = indices_from_rgb(q, constraints.n_palette)
    emis = emissivity_from_indices(idx, constraints.n_palette)
    return q, emis
