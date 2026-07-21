#!/usr/bin/env bash
# On-pod SOTA burn: CPU gate → fine-tune site YOLO → adversarial kit hour.
# cgroup workers (NOT nproc). Git Bash / Linux only.
set -euo pipefail
cd /workspace/MS-C

WORKERS="${MSC_WORKERS:-}"
if [[ -z "${WORKERS}" ]]; then
  WORKERS=$(bash scripts/_pod_cgroup_workers.sh)
fi
MINUTES="${MSC_BURN_MINUTES:-60}"
LOG=/workspace/logs/msc_sota_burn.log
OUT=analysis/results/runs/sota_hour
DET_DIR=analysis/results/runs/site_detector
mkdir -p /workspace/logs "${OUT}" "${DET_DIR}"
export OMP_NUM_THREADS="${WORKERS}"
export MKL_NUM_THREADS="${WORKERS}"
export OPENBLAS_NUM_THREADS="${WORKERS}"
export NUMEXPR_NUM_THREADS="${WORKERS}"
# Ultralytics dataloader workers — cap reasonably
ULTRA_WORKERS=$(( WORKERS > 8 ? 8 : WORKERS ))

{
  echo "=== MS-C SOTA BURN START $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "workers_cgroup=${WORKERS} ultra_workers=${ULTRA_WORKERS} nproc_lie=$(nproc) minutes=${MINUTES}"
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader || true
  python - <<'PY'
import torch
print(f"torch={torch.__version__} cuda={torch.cuda.is_available()} device={torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'cpu'}")
PY
} | tee -a "${LOG}"

echo "[burn] STAGE INSTALL" | tee -a "${LOG}"
python -m pip install -U pip wheel setuptools >>"${LOG}" 2>&1
python -m pip install -e ".[dev,yolo]" >>"${LOG}" 2>&1

echo "[burn] STAGE CPU_GATE" | tee -a "${LOG}"
python -m ruff check sim models analysis tests demo 2>&1 | tee -a "${LOG}"
python -m mypy 2>&1 | tee -a "${LOG}" || echo "[burn] WARN mypy non-zero (continuing)" | tee -a "${LOG}"
python -m pytest tests/ -q 2>&1 | tee -a "${LOG}"
python -m sim.reproduce --validate-only 2>&1 | tee -a "${LOG}"
echo "[burn] STAGE CPU_GATE PASS" | tee -a "${LOG}"

START_TS=$(date +%s)
DEADLINE=$((START_TS + MINUTES * 60))

echo "[burn] STAGE TRAIN_DETECTOR" | tee -a "${LOG}"
python - <<PY 2>&1 | tee -a "${LOG}"
import json, time, os
from pathlib import Path
from models.train_detector import train_site_detector

workers = int(os.environ.get("OMP_NUM_THREADS", "4"))
ultra_workers = min(8, workers)
out = Path("${DET_DIR}")
# ~15-25 min on 4090 for 50 epochs / 400 train imgs
best = train_site_detector(
    out,
    epochs=50,
    imgsz=320,
    batch=32,
    workers=ultra_workers,
    device="0",
    n_train=400,
    n_val=80,
)
print(f"[train] BEST_WEIGHTS={best}", flush=True)
meta = {"best": str(best), "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
(out / "train_meta.json").write_text(json.dumps(meta, indent=2) + "\n")
PY
echo "[burn] STAGE TRAIN_DETECTOR PASS" | tee -a "${LOG}"

WEIGHTS="${DET_DIR}/site_yolov8n_best.pt"
if [[ ! -f "${WEIGHTS}" ]]; then
  WEIGHTS=$(find "${DET_DIR}" -name 'best.pt' | head -1 || true)
fi
echo "[burn] weights=${WEIGHTS}" | tee -a "${LOG}"

echo "[burn] STAGE ADV_ATTACK remaining wall-clock" | tee -a "${LOG}"
export MSC_YOLO_WEIGHTS="${WEIGHTS}"
export MSC_DEADLINE="${DEADLINE}"
python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, os, time
from pathlib import Path
from models.optimizer import optimize_pattern
from models.scenes import SITE_CLASSES
from models.scorecard import build_scorecard
from models.kit_export import export_kit
from models.detectors import get_detector
from models.scenes import generate_scene

deadline = float(os.environ["MSC_DEADLINE"])
weights = os.environ.get("MSC_YOLO_WEIGHTS") or ""
out = Path("analysis/results/runs/sota_hour")
out.mkdir(parents=True, exist_ok=True)
detector = "yolo"
if not weights or not Path(weights).is_file():
    print("[gpu] NO_WEIGHTS → surrogate", flush=True)
    detector = "surrogate"
    weights = None
else:
    d = get_detector("yolo", weights=weights)
    sc = generate_scene("substation", seed=0, size=320)
    m = d.mean_confidence(sc)
    print(f"[gpu] site_yolo_baseline_mean_conf={m:.4f} weights={weights}", flush=True)

results = []
round_i = 0
seed0 = 7
while time.time() < deadline:
    round_i += 1
    seed = seed0 + round_i
    steps = min(60 + round_i * 25, 350)
    for sc in SITE_CLASSES:
        if time.time() >= deadline:
            break
        t0 = time.time()
        print(f"[gpu] ROUND={round_i} site={sc} seed={seed} steps={steps} det={detector}", flush=True)
        try:
            res = optimize_pattern(
                sc,
                seed=seed,
                steps=steps,
                detector_kind=detector,
                detector_weights=weights,
                size=320,
                tile=32,
            )
        except Exception as e:
            print(f"[gpu] FAIL {e}; surrogate fallback", flush=True)
            detector = "surrogate"
            weights = None
            res = optimize_pattern(sc, seed=seed, steps=steps, detector_kind="surrogate", size=320)
        results.append(res)
        dt = time.time() - t0
        collapse = (res.baseline_score - res.best_score) / max(res.baseline_score, 1e-6)
        print(
            f"[gpu] DONE site={sc} base={res.baseline_score:.4f} best={res.best_score:.4f} "
            f"collapse={collapse:.4f} sec={dt:.1f} left={max(0, deadline-time.time()):.0f}s",
            flush=True,
        )
        best_by = {}
        for r in results:
            cur = best_by.get(r.site_class)
            if cur is None or r.best_score < cur.best_score:
                best_by[r.site_class] = r
        keep = list(best_by.values())
        card = build_scorecard(keep, detector_kind="surrogate")
        card["burn"] = {
            "rounds": round_i,
            "detector_train": detector,
            "weights": weights,
            "n_results": len(results),
        }
        (out / "scorecard.json").write_text(json.dumps(card, indent=2) + "\n")
        export_kit(keep, out)
        status = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "stage": "adv_attack",
            "round": round_i,
            "site": sc,
            "detector": detector,
            "best_by_site": {k: round(v.best_score, 4) for k, v in best_by.items()},
            "summary": card["summary"],
            "seconds_left": max(0, deadline - time.time()),
        }
        (out / "live_status.json").write_text(json.dumps(status, indent=2) + "\n")
        print(f"[gpu] STATUS {json.dumps(status)}", flush=True)

best_by = {}
for r in results:
    cur = best_by.get(r.site_class)
    if cur is None or r.best_score < cur.best_score:
        best_by[r.site_class] = r
keep = list(best_by.values()) or results
card = build_scorecard(keep, detector_kind="surrogate") if keep else {"summary": {}}
card["burn"] = {
    "rounds": round_i,
    "detector_train": detector,
    "weights": weights,
    "n_results": len(results),
    "complete": True,
}
(out / "scorecard.json").write_text(json.dumps(card, indent=2) + "\n")
if keep:
    export_kit(keep, out)
print("[gpu] STAGE ADV_ATTACK COMPLETE", flush=True)
print(json.dumps(card.get("summary", {}), indent=2), flush=True)
PY

echo "[burn] RESULT COMPLETE $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "${LOG}"
ls -lah "${OUT}" | tee -a "${LOG}"
nvidia-smi | tee -a "${LOG}" || true
