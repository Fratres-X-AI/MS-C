"""Export printable tile sheets + kit_manifest.json + BOM stub."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

from models.materials import MATERIALS
from models.optimizer import OptimizeResult

BOM_STUB = [
    {
        "item": "Printed camo tile sheet (vinyl / mesh)",
        "material_id": "mantle_tile",
        "qty_per_m2": 1.0,
        "status": "planning_only",
    },
    {
        "item": "Low-e film accent strips",
        "material_id": "low_e_film",
        "qty_per_m2": 0.15,
        "status": "planning_only",
    },
    {
        "item": "Thermal blanket underlay (optional)",
        "material_id": "thermal_blanket",
        "qty_per_m2": 0.5,
        "status": "planning_only",
    },
    {
        "item": "Attachment hardware (zip ties / magnets / grommets)",
        "material_id": None,
        "qty_per_m2": 4.0,
        "status": "planning_only",
    },
]


def _sheet(pattern: np.ndarray, repeats: int = 8) -> np.ndarray:
    return np.tile(pattern, (repeats, repeats, 1) if pattern.ndim == 3 else (repeats, repeats))


def export_kit(
    results: list[OptimizeResult],
    out_dir: Path,
    *,
    coverage_m2_per_site: float = 25.0,
) -> dict[str, Any]:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    tiles_dir = out_dir / "tiles"
    tiles_dir.mkdir(exist_ok=True)

    kits = []
    for res in results:
        stem = f"{res.site_class}_seed{res.seed}"
        tile_path = tiles_dir / f"{stem}_tile.png"
        sheet_path = tiles_dir / f"{stem}_sheet.png"
        emis_path = tiles_dir / f"{stem}_emis.png"

        Image.fromarray(res.pattern_rgb, mode="RGB").save(tile_path)
        Image.fromarray(_sheet(res.pattern_rgb, 8), mode="RGB").save(sheet_path)
        emis_u8 = (np.clip(res.pattern_emis, 0, 1) * 255).astype(np.uint8)
        Image.fromarray(_sheet(emis_u8, 8), mode="L").save(emis_path)

        mean_e = float(res.pattern_emis.mean())
        kits.append(
            {
                "site_class": res.site_class,
                "seed": res.seed,
                "tile_png": str(tile_path.relative_to(out_dir)).replace("\\", "/"),
                "sheet_png": str(sheet_path.relative_to(out_dir)).replace("\\", "/"),
                "emis_png": str(emis_path.relative_to(out_dir)).replace("\\", "/"),
                "tile_px": int(res.pattern_rgb.shape[0]),
                "coverage_m2_planning": coverage_m2_per_site,
                "mean_emissivity_planning": mean_e,
                "digital_best_confidence": res.best_score,
                "digital_baseline_confidence": res.baseline_score,
                "install_notes": (
                    "Planning only. Orient sheets with seam marks aligned. "
                    "Re-audit after weather events. Not a field authorization."
                ),
            }
        )

    manifest: dict[str, Any] = {
        "product": "MS-C Mantle",
        "version": "0.1.0",
        "evidence_class": "digital_surrogate_unvalidated",
        "kits": kits,
        "bom_stub": BOM_STUB,
        "materials_ref": {k: {"name": v.name, "emissivity_lwir": v.emissivity_lwir} for k, v in MATERIALS.items()},
        "disclaimer": (
            "BOM and coverage are planning stubs. No physical print or IR validation."
        ),
    }
    man_path = out_dir / "kit_manifest.json"
    man_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest
