#!/usr/bin/env bash
# MAXXED 2H burn: parallel GPU attack workers + fat YOLO retrain.
# cgroup workers ONLY. Git Bash / Linux.
set -euo pipefail
cd /workspace/MS-C

WORKERS=$(bash scripts/_pod_cgroup_workers.sh)
export OMP_NUM_THREADS=1   # avoid oversubscribe inside each process
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export NUMEXPR_NUM_THREADS=1
export PYTHONUNBUFFERED=1
# parallel attack processes (each loads YOLO on GPU) — fill the 4090
GPU_WORKERS=$(( WORKERS > 20 ? 16 : WORKERS / 2 ))
if [[ "${GPU_WORKERS}" -lt 4 ]]; then GPU_WORKERS=4; fi
if [[ "${GPU_WORKERS}" -gt 16 ]]; then GPU_WORKERS=16; fi
ULTRA_WORKERS=$(( WORKERS > 8 ? 8 : WORKERS ))
# leave a few CPUs for orchestration / jupyter
if [[ "${GPU_WORKERS}" -ge "${WORKERS}" ]]; then
  GPU_WORKERS=$((WORKERS - 2))
fi

MINUTES="${MSC_BURN_MINUTES:-110}"
START_TS=$(date +%s)
DEADLINE=$((START_TS + MINUTES * 60))
LOG=/workspace/logs/msc_sota_2h.log
OUT=analysis/results/runs/sota_2h
DET_DIR=analysis/results/runs/site_detector
mkdir -p /workspace/logs "${OUT}" "${DET_DIR}"
: > "${LOG}"

{
  echo "=== MS-C SOTA MAXX START $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "cgroup_workers=${WORKERS} gpu_attack_workers=${GPU_WORKERS} ultra_dl_workers=${ULTRA_WORKERS} nproc_lie=$(nproc) minutes=${MINUTES}"
  nvidia-smi --query-gpu=name,memory.total,utilization.gpu --format=csv,noheader || true
} | tee -a "${LOG}"

python -m pip install -e ".[dev,yolo]" >>"${LOG}" 2>&1

WEIGHTS="${DET_DIR}/site_yolov8n_best.pt"
if [[ ! -f "${WEIGHTS}" ]]; then
  SRC=$(find /workspace/MS-C -name 'best.pt' 2>/dev/null | head -1 || true)
  [[ -n "${SRC}" ]] && cp -f "${SRC}" "${WEIGHTS}"
fi
echo "[max] weights0=${WEIGHTS}" | tee -a "${LOG}"

export MSC_DEADLINE="${DEADLINE}"
export MSC_YOLO_WEIGHTS="${WEIGHTS}"
export MSC_GPU_WORKERS="${GPU_WORKERS}"
export MSC_ULTRA_WORKERS="${ULTRA_WORKERS}"
export MSC_OUT="${OUT}"

# -------- WAVE1: parallel joint attack (max GPU concurrency) --------
python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, os, time, math
from pathlib import Path
import numpy as np
from concurrent.futures import ProcessPoolExecutor, as_completed
from models.scenes import SITE_CLASSES
from models.kit_export import export_kit
from models.scorecard import build_scorecard
from models.optimizer import OptimizeResult
from models.detectors import get_detector
from models.scenes import generate_scene
from models.renderer import apply_pattern_to_scene
from models.joint_attack import _worker_job

deadline = float(os.environ["MSC_DEADLINE"])
wave_end = time.time() + max(900, 0.40 * (deadline - time.time()))
weights = os.environ["MSC_YOLO_WEIGHTS"]
n_workers = int(os.environ["MSC_GPU_WORKERS"])
out = Path(os.environ["MSC_OUT"])
out.mkdir(parents=True, exist_ok=True)

print(f"[w1-max] gpu_workers={n_workers} wave_end_in={wave_end-time.time():.0f}s", flush=True)

best_by: dict = {}
all_results = []
round_i = 0
seed = 1000

# Keep a pool hot for the whole wave
with ProcessPoolExecutor(max_workers=n_workers) as ex:
    in_flight = {}
    def submit_one(sc, sd, steps):
        fut = ex.submit(_worker_job, (sc, sd, steps, weights, 320, 0.72))
        in_flight[fut] = (sc, sd, steps)

    # prime queue
    for sc in SITE_CLASSES:
        for _ in range(max(1, n_workers // len(SITE_CLASSES))):
            seed += 1
            submit_one(sc, seed, 160)

    while time.time() < wave_end and time.time() < deadline:
        if not in_flight:
            break
        done = next(as_completed(list(in_flight.keys()), timeout=600))
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
        # refill
        if time.time() < wave_end:
            seed += 1
            steps = min(160 + (round_i // n_workers) * 20, 300)
            submit_one(res.site_class, seed, steps)

        if round_i % n_workers == 0:
            keep = list(best_by.values())
            card = build_scorecard(keep, detector_kind="surrogate")
            det = get_detector("yolo", weights=weights)
            yolo = {}
            for site, rr in best_by.items():
                scene = generate_scene(site, seed=rr.seed, size=320)
                cov = apply_pattern_to_scene(scene, rr.pattern_rgb, rr.pattern_emis, alpha=0.72)
                yolo[site] = {
                    "uncovered": round(float(det.model.predict(scene.rgb, verbose=False)[0].boxes.conf.max().item()) if det.model.predict(scene.rgb, verbose=False)[0].boxes is not None and len(det.model.predict(scene.rgb, verbose=False)[0].boxes) else 0.0, 4)
                    if False else round(det.mean_confidence(scene), 4),
                    "mantle": round(det.mean_confidence(cov), 4),
                }
            card["burn"] = {"wave": "1-max", "n": round_i, "gpu_workers": n_workers, "yolo_site_scores": yolo}
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

# -------- WAVE2: FAT retrain (max batch / workers / imgsz) --------
echo "[max] WAVE2 fat retrain" | tee -a "${LOG}"
python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, shutil, time, os
from pathlib import Path
import numpy as np
from PIL import Image
from models.scenes import SITE_CLASSES, generate_scene
from models.renderer import apply_pattern_to_scene
from models.train_detector import CLASS_TO_ID, build_synth_dataset
from ultralytics import YOLO

out = Path(os.environ["MSC_OUT"])
det_dir = Path("analysis/results/runs/site_detector")
ultra_w = int(os.environ["MSC_ULTRA_WORKERS"])
yaml = build_synth_dataset(det_dir / "adv_data", n_train=600, n_val=100, size=416, seed=42)
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
    for k in range(80):
        scene = generate_scene(site, seed=3000+k, size=416, view=("nadir","oblique")[k%2], lighting=("nominal","harsh","dim")[k%3])
        cov = apply_pattern_to_scene(scene, rgb, emis, alpha=0.72)
        stem = f"adv_{idx:05d}"
        Image.fromarray(cov.rgb).save(img_tr / f"{stem}.jpg", quality=90)
        h, w = cov.rgb.shape[:2]
        lines=[]
        for box in cov.boxes:
            cid = CLASS_TO_ID.get(box.label)
            if cid is None: continue
            x0,y0,x1,y1 = box.as_tuple()
            lines.append(f"{cid} {(x0+x1)/2/w:.6f} {(y0+y1)/2/h:.6f} {(x1-x0)/w:.6f} {(y1-y0)/h:.6f}")
        (lbl_tr/f"{stem}.txt").write_text("\n".join(lines)+("\n" if lines else ""), encoding="utf-8")
        idx += 1
print(f"[w2] train_imgs={len(list(img_tr.glob('*.jpg')))} ultra_workers={ultra_w}", flush=True)
prev = det_dir / "site_yolov8n_best.pt"
model = YOLO(str(prev) if prev.is_file() else "yolov8n.pt")
# Max batch for 4090 48GB on yolov8n @416 — push hard
model.train(
    data=str(ds/"data.yaml"),
    epochs=45,
    imgsz=416,
    batch=96,
    workers=ultra_w,
    device="0",
    project=str((det_dir/"ultra_max").resolve()),
    name="site_det_max",
    exist_ok=True,
    patience=10,
    amp=True,
    cache=True,
)
cands = list((det_dir/"ultra_max").rglob("best.pt")) + list(Path("/workspace/MS-C/runs").rglob("best.pt"))
best = max(cands, key=lambda p: p.stat().st_mtime)
dest = det_dir / "site_yolov8n_adv_best.pt"
shutil.copy2(best, dest)
shutil.copy2(best, det_dir / "site_yolov8n_best.pt")
print(f"[w2] ADV_WEIGHTS={dest}", flush=True)
os.environ["MSC_YOLO_WEIGHTS"] = str(dest)
Path(det_dir/"max_train_meta.json").write_text(json.dumps({"best": str(dest)}, indent=2)+"\n")
PY

WEIGHTS="${DET_DIR}/site_yolov8n_adv_best.pt"
[[ -f "${WEIGHTS}" ]] || WEIGHTS="${DET_DIR}/site_yolov8n_best.pt"
export MSC_YOLO_WEIGHTS="${WEIGHTS}"

# -------- WAVE3: parallel attack vs hardened detector until deadline --------
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
out = Path(os.environ["MSC_OUT"])
best_by = {}
round_i = 0
seed = 5000
print(f"[w3-max] workers={n_workers} left={deadline-time.time():.0f}s", flush=True)

with ProcessPoolExecutor(max_workers=n_workers) as ex:
    in_flight = {}
    def submit_one(sc, sd, steps):
        in_flight[ex.submit(_worker_job, (sc, sd, steps, weights, 320, 0.70))] = sc
    for sc in SITE_CLASSES:
        for _ in range(max(1, n_workers // len(SITE_CLASSES))):
            seed += 1
            submit_one(sc, seed, 180)
    while time.time() < deadline - 120 and in_flight:
        done = next(as_completed(list(in_flight.keys()), timeout=600))
        in_flight.pop(done)
        r = done.result()
        round_i += 1
        res = OptimizeResult(
            pattern_rgb=r["rgb"], pattern_emis=r["emis"], best_score=r["best_score"],
            baseline_score=r["baseline_score"], steps=r["steps"], site_class=r["site_class"], seed=r["seed"],
        )
        cur = best_by.get(res.site_class)
        if cur is None or res.best_score < cur.best_score:
            best_by[res.site_class] = res
        print(f"[w3-max] DONE n={round_i} site={res.site_class} best={res.best_score:.3f} inflight={len(in_flight)}", flush=True)
        if time.time() < deadline - 120:
            seed += 1
            submit_one(res.site_class, seed, min(180 + round_i, 320))
        if round_i % n_workers == 0:
            keep = list(best_by.values())
            card = build_scorecard(keep, detector_kind="surrogate")
            det = get_detector("yolo", weights=weights)
            yolo = {}
            for site, rr in best_by.items():
                scene = generate_scene(site, seed=rr.seed, size=320)
                cov = apply_pattern_to_scene(scene, rr.pattern_rgb, rr.pattern_emis, alpha=0.70)
                yolo[site] = {"uncovered": round(det.mean_confidence(scene),4), "mantle": round(det.mean_confidence(cov),4)}
            card["burn"] = {"wave": "3-max", "n": round_i, "gpu_workers": n_workers, "yolo_site_scores": yolo, "complete": False}
            (out/"scorecard.json").write_text(json.dumps(card, indent=2)+"\n")
            export_kit(keep, out)
            for site, rr in best_by.items():
                np.savez(out / f"pattern_{site}.npz", rgb=rr.pattern_rgb, emis=rr.pattern_emis, seed=rr.seed)
            status = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "stage":"wave3_max_parallel",
                      "round": round_i, "gpu_workers": n_workers, "yolo_site_scores": yolo,
                      "seconds_left": max(0, deadline-time.time()), "summary": card["summary"]}
            (out/"live_status.json").write_text(json.dumps(status, indent=2)+"\n")
            print("[w3-max] STATUS", json.dumps(status), flush=True)

keep = list(best_by.values())
card = build_scorecard(keep, detector_kind="surrogate") if keep else {"summary": {}}
card["burn"] = {"wave": "3-max", "n": round_i, "gpu_workers": n_workers, "complete": True}
(out/"scorecard.json").write_text(json.dumps(card, indent=2)+"\n")
if keep:
    export_kit(keep, out)
import hashlib
files = sorted(p for p in out.rglob("*") if p.is_file())
report = {"title":"MS-C Mantle SOTA MAXX","gpu_workers": n_workers, "jobs": round_i,
          "summary": card.get("summary",{}), "burn": card.get("burn",{}),
          "evidence_class":"digital_surrogate_unvalidated"}
(out/"SOTA_REPORT.json").write_text(json.dumps(report, indent=2)+"\n")
print("[max] COMPLETE", json.dumps(report), flush=True)
PY

echo "[max] RESULT COMPLETE $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "${LOG}"
nvidia-smi | tee -a "${LOG}" || true
ls -lah "${OUT}" | tee -a "${LOG}"
