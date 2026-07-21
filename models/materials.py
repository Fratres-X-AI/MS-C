"""Literature-bounded material table for VIS + LWIR-surrogate planning.

Not FLIR-validated. Values are planning midpoints with explicit uncertainty.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Material:
    id: str
    name: str
    vis_rgb: tuple[int, int, int]
    emissivity_lwir: float
    notes: str


# Midpoint emissivities drawn from public material ranges (planning only).
MATERIALS: dict[str, Material] = {
    "bare_metal": Material(
        "bare_metal",
        "Weathered steel / aluminum",
        (140, 145, 150),
        0.25,
        "Low-e metal; visually bright",
    ),
    "utility_paint": Material(
        "utility_paint",
        "Industrial gray paint",
        (110, 115, 120),
        0.90,
        "High-e paint over metal",
    ),
    "camo_net": Material(
        "camo_net",
        "Commercial camo net proxy",
        (70, 95, 55),
        0.85,
        "VIS blend; weak IR control",
    ),
    "low_e_film": Material(
        "low_e_film",
        "Low-emissivity film",
        (180, 185, 190),
        0.15,
        "IR contrast cut; often conspicuous VIS",
    ),
    "thermal_blanket": Material(
        "thermal_blanket",
        "Thermal blanket / tarp",
        (40, 40, 45),
        0.20,
        "IR suppress; dark VIS",
    ),
    "mantle_tile": Material(
        "mantle_tile",
        "Mantle printed tile (planning)",
        (90, 100, 70),
        0.55,
        "Dual-band stack placeholder",
    ),
}


def emissivity_for_palette_index(idx: int, n_palette: int = 8) -> float:
    """Map quantized palette index to a planning emissivity in [0.15, 0.92]."""
    if n_palette <= 1:
        return 0.55
    t = idx / (n_palette - 1)
    return float(0.15 + t * (0.92 - 0.15))
