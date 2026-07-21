#!/usr/bin/env bash
# Resume ADV attack using already-trained site YOLO. Remaining wall clock.
set -euo pipefail
cd /workspace/MS-C
LOG=/workspace/logs/msc_sota_burn.log
OUT=analysis/results/runs/sota_hour
DET_DIR=analysis/results/runs/site_detector
mkdir -p "${OUT}" "${DET_DIR}" /workspace/logs

WORKERS=$(bash scripts/_pod_cgroup_workers.sh)
export OMP_NUM_THREADS="${WORKERS}"
export MKL_NUM_THREADS="${WORKERS}"
export OPENBLAS_NUM_THREADS="${WORKERS}"
export NUMEXPR_NUM_THREADS="${WORKERS}"

# Recover weights from Ultralytics nested path if needed
SRC=$(find /workspace/MS-C/runs /workspace/MS-C/analysis -name 'best.pt' 2>/dev/null | head -1 || true)
WEIGHTS="${DET_DIR}/site_yolov8n_best.pt"
if [[ -n "${SRC}" ]]; then
  cp -f "${SRC}" "${WEIGHTS}"
  echo "[resume] copied ${SRC} -> ${WEIGHTS}" | tee -a "${LOG}"
fi
[[ -f "${WEIGHTS}" ]] || { echo "[resume] FATAL no weights"; exit 1; }

MINUTES="${MSC_BURN_MINUTES:-55}"
START_TS=$(date +%s)
DEADLINE=$((START_TS + MINUTES * 60))
export MSC_YOLO_WEIGHTS="${WEIGHTS}"
export MSC_DEADLINE="${DEADLINE}"

echo "[resume] STAGE ADV_ATTACK workers=${WORKERS} nproc_lie=$(nproc) minutes=${MINUTES} weights=${WEIGHTS}" | tee -a "${LOG}"
nvidia-smi --query-gpu=name,utilization.gpu,memory.used --format=csv,noheader | tee -a "${LOG}" || true

python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, os, time
from pathlib import Path
from models.optimizer import optimize_pattern
from models.scenes import SITE_CLASSES, generate_scene
from models.scorecard import build_scorecard
from models.kit_export import export_kit
from models.detectors import get_detector

deadline = float(os.environ["MSC_DEADLINE"])
weights = os.environ["MSC_YOLO_WEIGHTS"]
out = Path("analysis/results/runs/sota_hour")
out.mkdir(parents=True, exist_ok=True)
detector = "yolo"
d = get_detector("yolo", weights=weights)
sc0 = generate_scene("substation", seed=0, size=320)
print(f"[gpu] site_yolo_baseline_mean_conf={d.mean_confidence(sc0):.4f}", flush=True)

results = []
round_i = 0
seed0 = 7
while time.time() < deadline:
    round_i += 1
    seed = seed0 + round_i
    steps = min(80 + round_i * 30, 400)
    for sc in SITE_CLASSES:
        if time.time() >= deadline:
            break
        t0 = time.time()
        print(f"[gpu] ROUND={round_i} site={sc} seed={seed} steps={steps} det={detector}", flush=True)
        try:
            res = optimize_pattern(
                sc, seed=seed, steps=steps, detector_kind=detector,
                detector_weights=weights, size=320, tile=32,
            )
        except Exception as e:
            print(f"[gpu] FAIL {e}; surrogate", flush=True)
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
        # also score vs site yolo if available
        yolo_scores = {}
        if detector == "yolo" and weights:
            yd = get_detector("yolo", weights=weights)
            for site, r in best_by.items():
                scene = generate_scene(site, seed=r.seed, size=320)
                from models.renderer import apply_pattern_to_scene
                cov = apply_pattern_to_scene(scene, r.pattern_rgb, r.pattern_emis)
                yolo_scores[site] = {
                    "uncovered": round(yd.mean_confidence(scene), 4),
                    "mantle": round(yd.mean_confidence(cov), 4),
                }
        card["burn"] = {
            "rounds": round_i,
            "detector_train": detector,
            "weights": weights,
            "n_results": len(results),
            "yolo_site_scores": yolo_scores,
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
            "yolo_site_scores": yolo_scores,
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
keep = list(best_by.values())
card = build_scorecard(keep, detector_kind="surrogate") if keep else {"summary": {}}
card["burn"] = {"rounds": round_i, "detector_train": detector, "weights": weights, "n_results": len(results), "complete": True}
(out / "scorecard.json").write_text(json.dumps(card, indent=2) + "\n")
if keep:
    export_kit(keep, out)
print("[gpu] STAGE ADV_ATTACK COMPLETE", flush=True)
print(json.dumps(card.get("summary", {}), indent=2), flush=True)
PY

echo "[resume] RESULT COMPLETE $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "${LOG}"
ls -lah "${OUT}" | tee -a "${LOG}"
