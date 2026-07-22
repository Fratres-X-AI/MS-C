#!/usr/bin/env bash
# MAXXED SOTA burn for fat GPUs (RTX PRO 6000 / H100-class).
# cgroup workers ONLY — never trust nproc.
# Waves: train → parallel attack → fat retrain → hardened re-attack → report.
set -euo pipefail
cd /workspace/MS-C

WORKERS=$(bash scripts/_pod_cgroup_workers.sh)
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export PYTHONUNBUFFERED=1
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"

# Attack processes each load a YOLO on GPU. PRO 6000 96GB → pack hard, leave CPU headroom.
GPU_WORKERS=$(( WORKERS * 3 / 4 ))
if [[ "${GPU_WORKERS}" -lt 8 ]]; then GPU_WORKERS=8; fi
if [[ "${GPU_WORKERS}" -gt 36 ]]; then GPU_WORKERS=36; fi
if [[ "${GPU_WORKERS}" -ge "${WORKERS}" ]]; then
  GPU_WORKERS=$((WORKERS - 4))
fi
# Ultralytics dataloader workers — never exceed cgroup
ULTRA_WORKERS=$(( WORKERS / 2 ))
if [[ "${ULTRA_WORKERS}" -lt 4 ]]; then ULTRA_WORKERS=4; fi
if [[ "${ULTRA_WORKERS}" -gt 16 ]]; then ULTRA_WORKERS=16; fi

# Fat quality knobs (override via env)
IMGSZ="${MSC_IMGSZ:-640}"
ATTACK_SIZE="${MSC_ATTACK_SIZE:-512}"
BATCH="${MSC_BATCH:-192}"
MODEL_NAME="${MSC_YOLO_MODEL:-yolov8s.pt}"
MINUTES="${MSC_BURN_MINUTES:-360}"

START_TS=$(date +%s)
DEADLINE=$((START_TS + MINUTES * 60))
LOG=/workspace/logs/msc_sota_max.log
OUT=analysis/results/runs/sota_max
DET_DIR=analysis/results/runs/site_detector
mkdir -p /workspace/logs "${OUT}" "${DET_DIR}"
: > "${LOG}"
ln -sf "${LOG}" /workspace/logs/msc_sota_burn.log

{
  echo "=== MS-C SOTA MAXX PRO START $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "cgroup_workers=${WORKERS} gpu_attack_workers=${GPU_WORKERS} ultra_dl_workers=${ULTRA_WORKERS}"
  echo "nproc_lie=$(nproc) minutes=${MINUTES} imgsz=${IMGSZ} attack_size=${ATTACK_SIZE} batch=${BATCH} model=${MODEL_NAME}"
  nvidia-smi --query-gpu=name,memory.total,utilization.gpu,memory.used --format=csv,noheader || true
} | tee -a "${LOG}"

# PEP 668: workspace venv with system-site-packages (keep image CUDA torch)
VENV=/workspace/MS-C/.venv
if [[ ! -x "${VENV}/bin/python" ]]; then
  python3 -m venv --system-site-packages "${VENV}"
fi
# shellcheck disable=SC1091
source "${VENV}/bin/activate"
python -m pip install -U pip >>"${LOG}" 2>&1
python -m pip install -e ".[dev,yolo]" >>"${LOG}" 2>&1
export PATH="${VENV}/bin:${PATH}"
hash -r
which python | tee -a "${LOG}"
python - <<'PY' | tee -a "${LOG}"
import torch
assert torch.cuda.is_available(), "CUDA required"
print("torch", torch.__version__, torch.cuda.get_device_name(0), "vram_gb", round(torch.cuda.get_device_properties(0).total_memory/1e9,1))
PY

export MSC_DEADLINE="${DEADLINE}"
export MSC_GPU_WORKERS="${GPU_WORKERS}"
export MSC_ULTRA_WORKERS="${ULTRA_WORKERS}"
export MSC_OUT="${OUT}"
export MSC_DET_DIR="${DET_DIR}"
export MSC_IMGSZ="${IMGSZ}"
export MSC_ATTACK_SIZE="${ATTACK_SIZE}"
export MSC_BATCH="${BATCH}"
export MSC_YOLO_MODEL="${MODEL_NAME}"

# -------- WAVE0: fat site detector train (skip if fresh weights exist) --------
WEIGHTS="${DET_DIR}/site_yolo_best.pt"
if [[ ! -f "${WEIGHTS}" ]]; then
  [[ -f "${DET_DIR}/site_yolov8n_best.pt" ]] && WEIGHTS="${DET_DIR}/site_yolov8n_best.pt"
fi
if [[ ! -f "${WEIGHTS}" ]]; then
  echo "[max] WAVE0 fat train model=${MODEL_NAME}" | tee -a "${LOG}"
  python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, os, shutil
from pathlib import Path
from models.train_detector import build_synth_dataset
from ultralytics import YOLO

det = Path(os.environ["MSC_DET_DIR"])
ultra_w = int(os.environ["MSC_ULTRA_WORKERS"])
imgsz = int(os.environ["MSC_IMGSZ"])
batch = int(os.environ["MSC_BATCH"])
model_name = os.environ["MSC_YOLO_MODEL"]
yaml = build_synth_dataset(det / "base_data", n_train=1200, n_val=200, size=imgsz, seed=7)
ds = det / "base_data" / "synth_sites"
model = YOLO(model_name)
model.train(
    data=str(ds / "data.yaml"),
    epochs=60,
    imgsz=imgsz,
    batch=batch,
    workers=ultra_w,
    device="0",
    project=str((det / "ultra_base").resolve()),
    name="site_det",
    exist_ok=True,
    patience=12,
    amp=True,
    cache=True,
    cos_lr=True,
)
cands = list((det / "ultra_base").rglob("best.pt")) + list(Path("/workspace/MS-C/runs").rglob("best.pt"))
best = max(cands, key=lambda p: p.stat().st_mtime)
dest = det / "site_yolo_best.pt"
shutil.copy2(best, dest)
shutil.copy2(best, det / "site_yolov8n_best.pt")  # compat alias
print(f"[w0] WEIGHTS={dest}", flush=True)
(det / "train_meta_w0.json").write_text(json.dumps({
    "best": str(dest), "model": model_name, "imgsz": imgsz, "batch": batch, "epochs": 60
}, indent=2) + "\n")
PY
  WEIGHTS="${DET_DIR}/site_yolo_best.pt"
fi
export MSC_YOLO_WEIGHTS="${WEIGHTS}"
echo "[max] weights0=${WEIGHTS}" | tee -a "${LOG}"

# -------- WAVE1: parallel joint attack --------
echo "[max] WAVE1 parallel attack" | tee -a "${LOG}"
python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, os, time
from pathlib import Path
import numpy as np
from concurrent.futures import ProcessPoolExecutor, as_completed
from models.scenes import SITE_CLASSES, generate_scene
from models.kit_export import export_kit
from models.scorecard import build_scorecard
from models.optimizer import OptimizeResult
from models.detectors import get_detector
from models.renderer import apply_pattern_to_scene
from models.joint_attack import _worker_job

deadline = float(os.environ["MSC_DEADLINE"])
wave_end = time.time() + max(1800, 0.38 * (deadline - time.time()))
weights = os.environ["MSC_YOLO_WEIGHTS"]
n_workers = int(os.environ["MSC_GPU_WORKERS"])
attack_size = int(os.environ["MSC_ATTACK_SIZE"])
out = Path(os.environ["MSC_OUT"])
out.mkdir(parents=True, exist_ok=True)

print(f"[w1-max] gpu_workers={n_workers} size={attack_size} wave_end_in={wave_end-time.time():.0f}s", flush=True)

best_by = {}
all_results = []
round_i = 0
seed = 1000

with ProcessPoolExecutor(max_workers=n_workers) as ex:
    in_flight = {}

    def submit_one(sc, sd, steps):
        fut = ex.submit(_worker_job, (sc, sd, steps, weights, attack_size, 0.72))
        in_flight[fut] = (sc, sd, steps)

    for sc in SITE_CLASSES:
        for _ in range(max(2, n_workers // len(SITE_CLASSES))):
            seed += 1
            submit_one(sc, seed, 220)

    while time.time() < wave_end and time.time() < deadline:
        if not in_flight:
            break
        done = next(as_completed(list(in_flight.keys()), timeout=900))
        sc0, sd0, st0 = in_flight.pop(done)
        try:
            r = done.result()
        except Exception as e:
            print(f"[w1-max] FAIL {sc0} {e}", flush=True)
            seed += 1
            submit_one(sc0, seed, st0)
            continue
        all_results.append(r)
        round_i += 1
        res = OptimizeResult(
            pattern_rgb=r["rgb"], pattern_emis=r["emis"], best_score=r["best_score"],
            baseline_score=r["baseline_score"], steps=r["steps"], site_class=r["site_class"], seed=r["seed"],
        )
        cur = best_by.get(res.site_class)
        if cur is None or res.best_score < cur.best_score:
            best_by[res.site_class] = res
        print(
            f"[w1-max] DONE n={round_i} site={res.site_class} base={res.baseline_score:.3f} "
            f"best={res.best_score:.3f} in_flight={len(in_flight)} left={max(0,deadline-time.time()):.0f}s",
            flush=True,
        )
        if time.time() < wave_end:
            seed += 1
            steps = min(220 + (round_i // n_workers) * 30, 400)
            submit_one(res.site_class, seed, steps)

        if round_i % max(4, n_workers) == 0:
            keep = list(best_by.values())
            card = build_scorecard(keep, detector_kind="surrogate")
            det = get_detector("yolo", weights=weights)
            yolo = {}
            for site, rr in best_by.items():
                scene = generate_scene(site, seed=rr.seed, size=attack_size)
                cov = apply_pattern_to_scene(scene, rr.pattern_rgb, rr.pattern_emis, alpha=0.72)
                yolo[site] = {
                    "uncovered": round(det.mean_confidence(scene), 4),
                    "mantle": round(det.mean_confidence(cov), 4),
                }
            card["burn"] = {
                "wave": "1-max", "n": round_i, "gpu_workers": n_workers,
                "attack_size": attack_size, "yolo_site_scores": yolo,
            }
            (out / "scorecard.json").write_text(json.dumps(card, indent=2) + "\n")
            export_kit(keep, out)
            for site, rr in best_by.items():
                np.savez(out / f"pattern_{site}.npz", rgb=rr.pattern_rgb, emis=rr.pattern_emis, seed=rr.seed)
            status = {
                "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "stage": "wave1_max_parallel",
                "round": round_i,
                "gpu_workers": n_workers,
                "in_flight": len(in_flight),
                "yolo_site_scores": yolo,
                "seconds_left": max(0, deadline - time.time()),
                "summary": card["summary"],
            }
            (out / "live_status.json").write_text(json.dumps(status, indent=2) + "\n")
            print("[w1-max] STATUS", json.dumps(status), flush=True)

print(f"[w1-max] COMPLETE jobs={round_i} best_sites={list(best_by)}", flush=True)
PY

# -------- WAVE2: FAT adversarial retrain --------
echo "[max] WAVE2 fat adversarial retrain" | tee -a "${LOG}"
python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, shutil, os
from pathlib import Path
import numpy as np
from PIL import Image
from models.scenes import SITE_CLASSES, generate_scene
from models.renderer import apply_pattern_to_scene
from models.train_detector import CLASS_TO_ID, build_synth_dataset
from ultralytics import YOLO

out = Path(os.environ["MSC_OUT"])
det_dir = Path(os.environ["MSC_DET_DIR"])
ultra_w = int(os.environ["MSC_ULTRA_WORKERS"])
imgsz = int(os.environ["MSC_IMGSZ"])
batch = int(os.environ["MSC_BATCH"])
model_name = os.environ["MSC_YOLO_MODEL"]
prev = Path(os.environ["MSC_YOLO_WEIGHTS"])

yaml = build_synth_dataset(det_dir / "adv_data", n_train=1600, n_val=240, size=imgsz, seed=42)
ds = det_dir / "adv_data" / "synth_sites"
img_tr = ds / "images" / "train"
lbl_tr = ds / "labels" / "train"
idx = 90000
for site in SITE_CLASSES:
    npz = out / f"pattern_{site}.npz"
    if not npz.is_file():
        continue
    z = np.load(npz)
    rgb, emis = z["rgb"], z["emis"]
    for k in range(160):
        scene = generate_scene(
            site, seed=3000 + k, size=imgsz,
            view=("nadir", "oblique")[k % 2],
            lighting=("nominal", "harsh", "dim")[k % 3],
        )
        cov = apply_pattern_to_scene(scene, rgb, emis, alpha=0.72)
        stem = f"adv_{idx:05d}"
        Image.fromarray(cov.rgb).save(img_tr / f"{stem}.jpg", quality=92)
        h, w = cov.rgb.shape[:2]
        lines = []
        for box in cov.boxes:
            cid = CLASS_TO_ID.get(box.label)
            if cid is None:
                continue
            x0, y0, x1, y1 = box.as_tuple()
            lines.append(
                f"{cid} {(x0+x1)/2/w:.6f} {(y0+y1)/2/h:.6f} {(x1-x0)/w:.6f} {(y1-y0)/h:.6f}"
            )
        (lbl_tr / f"{stem}.txt").write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
        idx += 1
print(f"[w2] train_imgs={len(list(img_tr.glob('*.jpg')))} ultra_workers={ultra_w} batch={batch}", flush=True)
model = YOLO(str(prev) if prev.is_file() else model_name)
model.train(
    data=str(ds / "data.yaml"),
    epochs=55,
    imgsz=imgsz,
    batch=batch,
    workers=ultra_w,
    device="0",
    project=str((det_dir / "ultra_max").resolve()),
    name="site_det_max",
    exist_ok=True,
    patience=12,
    amp=True,
    cache=True,
    cos_lr=True,
)
cands = list((det_dir / "ultra_max").rglob("best.pt")) + list(Path("/workspace/MS-C/runs").rglob("best.pt"))
best = max(cands, key=lambda p: p.stat().st_mtime)
dest = det_dir / "site_yolo_adv_best.pt"
shutil.copy2(best, dest)
shutil.copy2(best, det_dir / "site_yolo_best.pt")
shutil.copy2(best, det_dir / "site_yolov8n_best.pt")
print(f"[w2] ADV_WEIGHTS={dest}", flush=True)
(det_dir / "max_train_meta.json").write_text(json.dumps({
    "best": str(dest), "model": model_name, "imgsz": imgsz, "batch": batch
}, indent=2) + "\n")
PY

WEIGHTS="${DET_DIR}/site_yolo_adv_best.pt"
[[ -f "${WEIGHTS}" ]] || WEIGHTS="${DET_DIR}/site_yolo_best.pt"
export MSC_YOLO_WEIGHTS="${WEIGHTS}"

# -------- WAVE3: hardened parallel attack until deadline --------
echo "[max] WAVE3 parallel attack v2 weights=${WEIGHTS}" | tee -a "${LOG}"
python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, os, time
from pathlib import Path
import numpy as np
from concurrent.futures import ProcessPoolExecutor, as_completed
from models.scenes import SITE_CLASSES, generate_scene
from models.kit_export import export_kit
from models.scorecard import build_scorecard
from models.optimizer import OptimizeResult
from models.detectors import get_detector
from models.renderer import apply_pattern_to_scene
from models.joint_attack import _worker_job

deadline = float(os.environ["MSC_DEADLINE"])
weights = os.environ["MSC_YOLO_WEIGHTS"]
n_workers = int(os.environ["MSC_GPU_WORKERS"])
attack_size = int(os.environ["MSC_ATTACK_SIZE"])
out = Path(os.environ["MSC_OUT"])
best_by = {}
round_i = 0
seed = 5000
print(f"[w3-max] workers={n_workers} size={attack_size} left={deadline-time.time():.0f}s", flush=True)

with ProcessPoolExecutor(max_workers=n_workers) as ex:
    in_flight = {}

    def submit_one(sc, sd, steps):
        in_flight[ex.submit(_worker_job, (sc, sd, steps, weights, attack_size, 0.70))] = sc

    for sc in SITE_CLASSES:
        for _ in range(max(2, n_workers // len(SITE_CLASSES))):
            seed += 1
            submit_one(sc, seed, 260)

    while time.time() < deadline - 180 and in_flight:
        done = next(as_completed(list(in_flight.keys()), timeout=900))
        in_flight.pop(done)
        try:
            r = done.result()
        except Exception as e:
            print(f"[w3-max] FAIL {e}", flush=True)
            continue
        round_i += 1
        res = OptimizeResult(
            pattern_rgb=r["rgb"], pattern_emis=r["emis"], best_score=r["best_score"],
            baseline_score=r["baseline_score"], steps=r["steps"], site_class=r["site_class"], seed=r["seed"],
        )
        cur = best_by.get(res.site_class)
        if cur is None or res.best_score < cur.best_score:
            best_by[res.site_class] = res
        print(
            f"[w3-max] DONE n={round_i} site={res.site_class} best={res.best_score:.3f} "
            f"inflight={len(in_flight)} left={max(0,deadline-time.time()):.0f}s",
            flush=True,
        )
        if time.time() < deadline - 180:
            seed += 1
            submit_one(res.site_class, seed, min(260 + round_i // 2, 480))
        if round_i % max(4, n_workers) == 0:
            keep = list(best_by.values())
            card = build_scorecard(keep, detector_kind="surrogate")
            det = get_detector("yolo", weights=weights)
            yolo = {}
            for site, rr in best_by.items():
                scene = generate_scene(site, seed=rr.seed, size=attack_size)
                cov = apply_pattern_to_scene(scene, rr.pattern_rgb, rr.pattern_emis, alpha=0.70)
                yolo[site] = {
                    "uncovered": round(det.mean_confidence(scene), 4),
                    "mantle": round(det.mean_confidence(cov), 4),
                }
            card["burn"] = {
                "wave": "3-max", "n": round_i, "gpu_workers": n_workers,
                "attack_size": attack_size, "yolo_site_scores": yolo, "complete": False,
            }
            (out / "scorecard.json").write_text(json.dumps(card, indent=2) + "\n")
            export_kit(keep, out)
            for site, rr in best_by.items():
                np.savez(out / f"pattern_{site}.npz", rgb=rr.pattern_rgb, emis=rr.pattern_emis, seed=rr.seed)
            status = {
                "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "stage": "wave3_max_parallel",
                "round": round_i,
                "gpu_workers": n_workers,
                "yolo_site_scores": yolo,
                "seconds_left": max(0, deadline - time.time()),
                "summary": card["summary"],
            }
            (out / "live_status.json").write_text(json.dumps(status, indent=2) + "\n")
            print("[w3-max] STATUS", json.dumps(status), flush=True)

keep = list(best_by.values())
card = build_scorecard(keep, detector_kind="surrogate") if keep else {"summary": {}}
det = get_detector("yolo", weights=weights)
yolo = {}
for site, rr in best_by.items():
    scene = generate_scene(site, seed=rr.seed, size=attack_size)
    cov = apply_pattern_to_scene(scene, rr.pattern_rgb, rr.pattern_emis, alpha=0.70)
    yolo[site] = {
        "uncovered": round(det.mean_confidence(scene), 4),
        "mantle": round(det.mean_confidence(cov), 4),
    }
card["burn"] = {
    "wave": "3-max", "n": round_i, "gpu_workers": n_workers,
    "attack_size": attack_size, "yolo_site_scores": yolo, "complete": True,
}
(out / "scorecard.json").write_text(json.dumps(card, indent=2) + "\n")
if keep:
    export_kit(keep, out)
    for site, rr in best_by.items():
        np.savez(out / f"pattern_{site}.npz", rgb=rr.pattern_rgb, emis=rr.pattern_emis, seed=rr.seed)

report = {
    "title": "MS-C Mantle SOTA MAXX PRO",
    "gpu_workers": n_workers,
    "jobs": round_i,
    "attack_size": attack_size,
    "weights": weights,
    "yolo_site_scores": yolo,
    "summary": card.get("summary", {}),
    "burn": card.get("burn", {}),
    "evidence_class": "digital_surrogate_unvalidated",
}
(out / "SOTA_REPORT.json").write_text(json.dumps(report, indent=2) + "\n")
print("[max] COMPLETE", json.dumps(report), flush=True)
PY

echo "[max] RESULT COMPLETE $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "${LOG}"
nvidia-smi | tee -a "${LOG}" || true
ls -lah "${OUT}" | tee -a "${LOG}"
