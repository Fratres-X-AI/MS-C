#!/usr/bin/env bash
# ABUSE MODE — skip stalled wave1, harden detector, fill the PRO 6000.
# cgroup workers ONLY. Git Bash / Linux.
set -euo pipefail
cd /workspace/MS-C

WORKERS=$(bash scripts/_pod_cgroup_workers.sh)
export OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
export PYTHONUNBUFFERED=1
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"

# Pack the GPU: leave 2 CPUs for OS/jupyter
GPU_WORKERS=$(( WORKERS - 2 ))
if [[ "${GPU_WORKERS}" -gt 36 ]]; then GPU_WORKERS=36; fi
if [[ "${GPU_WORKERS}" -lt 16 ]]; then GPU_WORKERS=16; fi
ULTRA_WORKERS=$(( WORKERS > 16 ? 16 : WORKERS / 2 ))
if [[ "${ULTRA_WORKERS}" -lt 8 ]]; then ULTRA_WORKERS=8; fi

IMGSZ="${MSC_IMGSZ:-640}"
ATTACK_SIZE="${MSC_ATTACK_SIZE:-640}"
BATCH="${MSC_BATCH:-128}"          # yolov8m — slightly lower than s-batch
MODEL_NAME="${MSC_YOLO_MODEL:-yolov8m.pt}"
MINUTES="${MSC_BURN_MINUTES:-300}"

START_TS=$(date +%s)
DEADLINE=$((START_TS + MINUTES * 60))
LOG=/workspace/logs/msc_sota_abuse.log
OUT=analysis/results/runs/sota_max
DET_DIR=analysis/results/runs/site_detector
mkdir -p /workspace/logs "${OUT}" "${DET_DIR}"
: > "${LOG}"
ln -sf "${LOG}" /workspace/logs/msc_sota_burn.log
ln -sf "${LOG}" /workspace/logs/msc_sota_max.log

VENV=/workspace/MS-C/.venv
# shellcheck disable=SC1091
source "${VENV}/bin/activate"
export PATH="${VENV}/bin:${PATH}"

{
  echo "=== MS-C SOTA ABUSE START $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "cgroup_workers=${WORKERS} gpu_attack_workers=${GPU_WORKERS} ultra=${ULTRA_WORKERS}"
  echo "nproc_lie=$(nproc) minutes=${MINUTES} imgsz=${IMGSZ} attack=${ATTACK_SIZE} batch=${BATCH} model=${MODEL_NAME}"
  nvidia-smi --query-gpu=name,memory.total,utilization.gpu,memory.used --format=csv,noheader || true
} | tee -a "${LOG}"

export MSC_DEADLINE="${DEADLINE}"
export MSC_GPU_WORKERS="${GPU_WORKERS}"
export MSC_ULTRA_WORKERS="${ULTRA_WORKERS}"
export MSC_OUT="${OUT}"
export MSC_DET_DIR="${DET_DIR}"
export MSC_IMGSZ="${IMGSZ}"
export MSC_ATTACK_SIZE="${ATTACK_SIZE}"
export MSC_BATCH="${BATCH}"
export MSC_YOLO_MODEL="${MODEL_NAME}"

PREV="${DET_DIR}/site_yolo_best.pt"
[[ -f "${PREV}" ]] || PREV="${DET_DIR}/site_yolov8n_best.pt"
export MSC_YOLO_WEIGHTS="${PREV}"

# -------- ABUSE-W2: fat yolov8m retrain + heavy adv augment from existing patterns --------
echo "[abuse] WAVE2 harden ${MODEL_NAME}" | tee -a "${LOG}"
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

# Fast path to GPU: enough data to harden, not a CPU hour of synth
yaml = build_synth_dataset(det_dir / "abuse_data", n_train=900, n_val=150, size=imgsz, seed=99)
ds = det_dir / "abuse_data" / "synth_sites"
img_tr = ds / "images" / "train"
lbl_tr = ds / "labels" / "train"
idx = 80000
n_adv = 0
for site in SITE_CLASSES:
    npz = out / f"pattern_{site}.npz"
    if not npz.is_file():
        print(f"[abuse-w2] missing pattern {site}", flush=True)
        continue
    z = np.load(npz)
    rgb, emis = z["rgb"], z["emis"]
    for k in range(120):
        scene = generate_scene(
            site, seed=7000 + k, size=imgsz,
            view=("nadir", "oblique")[k % 2],
            lighting=("nominal", "harsh", "dim")[k % 3],
        )
        alpha = 0.55 + 0.35 * ((k % 7) / 6.0)
        cov = apply_pattern_to_scene(scene, rgb, emis, alpha=float(alpha))
        stem = f"adv_{idx:05d}"
        Image.fromarray(cov.rgb).save(img_tr / f"{stem}.jpg", quality=90)
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
        n_adv += 1
print(f"[abuse-w2] train_imgs={len(list(img_tr.glob('*.jpg')))} adv_injected={n_adv} batch={batch}", flush=True)

# Prefer continuing from prior weights if arch matches; else fresh m
try:
    model = YOLO(model_name)
except Exception:
    model = YOLO("yolov8m.pt")
# If prev is yolov8s, starting from m pretrained is correct for hard reset
model.train(
    data=str(ds / "data.yaml"),
    epochs=40,
    imgsz=imgsz,
    batch=batch,
    workers=ultra_w,
    device="0",
    project=str((det_dir / "ultra_abuse").resolve()),
    name="site_det_m",
    exist_ok=True,
    patience=8,
    amp=True,
    cache=True,
    cos_lr=True,
    close_mosaic=10,
)
cands = list((det_dir / "ultra_abuse").rglob("best.pt")) + list(Path("/workspace/MS-C/runs").rglob("best.pt"))
best = max(cands, key=lambda p: p.stat().st_mtime)
dest = det_dir / "site_yolo_adv_best.pt"
shutil.copy2(best, dest)
shutil.copy2(best, det_dir / "site_yolo_best.pt")
shutil.copy2(best, det_dir / "site_yolov8n_best.pt")
print(f"[abuse-w2] HARD_WEIGHTS={dest}", flush=True)
(det_dir / "abuse_train_meta.json").write_text(json.dumps({
    "best": str(dest), "model": model_name, "imgsz": imgsz, "batch": batch, "adv": n_adv
}, indent=2) + "\n")
PY

WEIGHTS="${DET_DIR}/site_yolo_adv_best.pt"
export MSC_YOLO_WEIGHTS="${WEIGHTS}"

# -------- ABUSE-W3: pipeline-weighted parallel attack @640, max workers --------
echo "[abuse] WAVE3 attack workers=${GPU_WORKERS} size=${ATTACK_SIZE}" | tee -a "${LOG}"
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
# seed prior patterns if present
for site in SITE_CLASSES:
    npz = out / f"pattern_{site}.npz"
    if npz.is_file():
        z = np.load(npz)
        best_by[site] = OptimizeResult(
            pattern_rgb=z["rgb"], pattern_emis=z["emis"],
            best_score=1.0, baseline_score=1.0, steps=0,
            site_class=site, seed=int(z["seed"]) if "seed" in z else 0,
        )

round_i = 0
seed = 90000
# pipeline gets 50% of jobs — hardest site
SITE_WEIGHT = {"pipeline": 5, "substation": 2, "tank_pad": 2}
weighted = []
for sc, w in SITE_WEIGHT.items():
    weighted.extend([sc] * w)

print(f"[abuse-w3] workers={n_workers} size={attack_size} left={deadline-time.time():.0f}s", flush=True)

with ProcessPoolExecutor(max_workers=n_workers) as ex:
    in_flight = {}

    def submit_one(sc, sd, steps):
        in_flight[ex.submit(_worker_job, (sc, sd, steps, weights, attack_size, 0.68))] = sc

    for i in range(n_workers):
        seed += 1
        submit_one(weighted[i % len(weighted)], seed, 320)

    while time.time() < deadline - 120 and in_flight:
        done = next(as_completed(list(in_flight.keys()), timeout=1200))
        sc_done = in_flight.pop(done)
        try:
            r = done.result()
        except Exception as e:
            print(f"[abuse-w3] FAIL {sc_done} {e}", flush=True)
            seed += 1
            submit_one(sc_done, seed, 320)
            continue
        round_i += 1
        res = OptimizeResult(
            pattern_rgb=r["rgb"], pattern_emis=r["emis"], best_score=r["best_score"],
            baseline_score=r["baseline_score"], steps=r["steps"],
            site_class=r["site_class"], seed=r["seed"],
        )
        cur = best_by.get(res.site_class)
        if cur is None or res.best_score < cur.best_score or cur.steps == 0:
            # replace seed patterns (steps==0) or improve
            if cur is None or cur.steps == 0 or res.best_score < cur.best_score:
                best_by[res.site_class] = res
        print(
            f"[abuse-w3] DONE n={round_i} site={res.site_class} base={res.baseline_score:.3f} "
            f"best={res.best_score:.3f} inflight={len(in_flight)} left={max(0,deadline-time.time()):.0f}s",
            flush=True,
        )
        if time.time() < deadline - 120:
            seed += 1
            # bias refill to pipeline
            sc_next = weighted[seed % len(weighted)]
            steps = min(320 + round_i // 3, 560)
            submit_one(sc_next, seed, steps)

        if round_i % max(3, n_workers // 2) == 0:
            keep = [v for v in best_by.values() if v.steps > 0]
            if not keep:
                keep = list(best_by.values())
            card = build_scorecard(keep, detector_kind="surrogate")
            det = get_detector("yolo", weights=weights)
            yolo = {}
            for site, rr in best_by.items():
                if rr.steps == 0:
                    continue
                scene = generate_scene(site, seed=rr.seed, size=attack_size)
                cov = apply_pattern_to_scene(scene, rr.pattern_rgb, rr.pattern_emis, alpha=0.68)
                yolo[site] = {
                    "uncovered": round(det.mean_confidence(scene), 4),
                    "mantle": round(det.mean_confidence(cov), 4),
                }
            card["burn"] = {
                "wave": "abuse-w3", "n": round_i, "gpu_workers": n_workers,
                "attack_size": attack_size, "yolo_site_scores": yolo, "model": "yolov8m",
            }
            (out / "scorecard.json").write_text(json.dumps(card, indent=2) + "\n")
            export_kit(keep, out)
            for site, rr in best_by.items():
                if rr.steps == 0:
                    continue
                np.savez(out / f"pattern_{site}.npz", rgb=rr.pattern_rgb, emis=rr.pattern_emis, seed=rr.seed)
            status = {
                "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "stage": "abuse_w3_parallel",
                "round": round_i,
                "gpu_workers": n_workers,
                "attack_size": attack_size,
                "yolo_site_scores": yolo,
                "seconds_left": max(0, deadline - time.time()),
                "summary": card["summary"],
            }
            (out / "live_status.json").write_text(json.dumps(status, indent=2) + "\n")
            print("[abuse-w3] STATUS", json.dumps(status), flush=True)

keep = [v for v in best_by.values() if v.steps > 0] or list(best_by.values())
card = build_scorecard(keep, detector_kind="surrogate") if keep else {"summary": {}}
det = get_detector("yolo", weights=weights)
yolo = {}
for site, rr in best_by.items():
    if rr.steps == 0:
        continue
    scene = generate_scene(site, seed=rr.seed, size=attack_size)
    cov = apply_pattern_to_scene(scene, rr.pattern_rgb, rr.pattern_emis, alpha=0.68)
    yolo[site] = {"uncovered": round(det.mean_confidence(scene), 4), "mantle": round(det.mean_confidence(cov), 4)}
card["burn"] = {
    "wave": "abuse-w3", "n": round_i, "gpu_workers": n_workers,
    "attack_size": attack_size, "yolo_site_scores": yolo, "complete": True, "model": "yolov8m",
}
(out / "scorecard.json").write_text(json.dumps(card, indent=2) + "\n")
if keep:
    export_kit(keep, out)
report = {
    "title": "MS-C Mantle SOTA ABUSE",
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
print("[abuse] COMPLETE", json.dumps(report), flush=True)
PY

echo "[abuse] RESULT COMPLETE $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "${LOG}"
nvidia-smi | tee -a "${LOG}" || true
ls -lah "${OUT}" | tee -a "${LOG}"
