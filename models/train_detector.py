"""Fine-tune a tiny YOLO detector on synthetic Mantle site fixtures."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

from models.scenes import SITE_CLASSES, generate_scene

# Ultralytics class names for our synthetic assets
CLASS_NAMES = [
    "transformer",
    "buswork",
    "tank",
    "pump",
    "pipe",
    "valve_skid",
]
CLASS_TO_ID = {n: i for i, n in enumerate(CLASS_NAMES)}


def _yolo_label_line(box, img_w: int, img_h: int) -> str | None:
    cid = CLASS_TO_ID.get(box.label)
    if cid is None:
        return None
    x0, y0, x1, y1 = box.as_tuple()
    cx = ((x0 + x1) / 2) / img_w
    cy = ((y0 + y1) / 2) / img_h
    bw = (x1 - x0) / img_w
    bh = (y1 - y0) / img_h
    return f"{cid} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}"


def build_synth_dataset(
    root: Path,
    *,
    n_train: int = 240,
    n_val: int = 48,
    size: int = 320,
    seed: int = 0,
) -> Path:
    """Write YOLO-format dataset under root/synth_sites."""
    ds = root / "synth_sites"
    if ds.exists():
        shutil.rmtree(ds)
    for split in ("train", "val"):
        (ds / "images" / split).mkdir(parents=True)
        (ds / "labels" / split).mkdir(parents=True)

    rng = np.random.default_rng(seed)
    views = ("nadir", "oblique")
    lights = ("nominal", "harsh", "dim")

    def write_split(split: str, n: int, seed_off: int) -> None:
        idx = 0
        for i in range(n):
            sc = SITE_CLASSES[i % len(SITE_CLASSES)]
            view = views[int(rng.integers(0, len(views)))]
            lighting = lights[int(rng.integers(0, len(lights)))]
            scene = generate_scene(
                sc,
                seed=seed_off + i,
                size=size,
                view=view,
                lighting=lighting,
            )
            stem = f"{split}_{idx:05d}"
            Image.fromarray(scene.rgb).save(ds / "images" / split / f"{stem}.jpg", quality=92)
            lines = []
            h, w = scene.rgb.shape[:2]
            for box in scene.boxes:
                line = _yolo_label_line(box, w, h)
                if line:
                    lines.append(line)
            (ds / "labels" / split / f"{stem}.txt").write_text(
                "\n".join(lines) + ("\n" if lines else ""), encoding="utf-8"
            )
            idx += 1

    write_split("train", n_train, seed)
    write_split("val", n_val, seed + 10_000)

    data_yaml = {
        "path": str(ds.resolve()).replace("\\", "/"),
        "train": "images/train",
        "val": "images/val",
        "names": {i: n for i, n in enumerate(CLASS_NAMES)},
    }
    yaml_path = ds / "data.yaml"
    # minimal YAML without pyyaml dependency
    lines = [
        f"path: {data_yaml['path']}",
        f"train: {data_yaml['train']}",
        f"val: {data_yaml['val']}",
        "names:",
    ]
    for i, n in enumerate(CLASS_NAMES):
        lines.append(f"  {i}: {n}")
    yaml_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    meta = {"n_train": n_train, "n_val": n_val, "size": size, "classes": CLASS_NAMES}
    (ds / "meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    return yaml_path


def train_site_detector(
    out_dir: Path,
    *,
    epochs: int = 40,
    imgsz: int = 320,
    batch: int = 16,
    workers: int = 4,
    device: str = "0",
    n_train: int = 240,
    n_val: int = 48,
) -> Path:
    """Fine-tune yolov8n; returns path to best.pt."""
    try:
        from ultralytics import YOLO
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("pip install -e '.[yolo]' required") from exc

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    yaml_path = build_synth_dataset(out_dir, n_train=n_train, n_val=n_val, size=imgsz)
    # Keep Ultralytics project path simple — nested abs paths break weight lookup.
    ultra_project = out_dir / "ultra"
    ultra_project.mkdir(parents=True, exist_ok=True)
    model = YOLO("yolov8n.pt")
    model.train(
        data=str(yaml_path),
        epochs=epochs,
        imgsz=imgsz,
        batch=batch,
        workers=workers,
        device=device,
        project=str(ultra_project.resolve()),
        name="site_det",
        exist_ok=True,
        verbose=True,
        patience=15,
    )
    search_roots = [
        ultra_project,
        out_dir,
        Path.cwd() / "runs",
        Path("/workspace/MS-C/runs"),
    ]
    cands: list[Path] = []
    for root in search_roots:
        if root.is_dir():
            cands.extend(root.rglob("best.pt"))
    if not cands:
        raise FileNotFoundError("best.pt not found after train")
    # Prefer newest
    best = max(cands, key=lambda p: p.stat().st_mtime)
    dest = out_dir / "site_yolov8n_best.pt"
    shutil.copy2(best, dest)
    return dest
