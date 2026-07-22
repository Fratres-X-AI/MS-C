#!/usr/bin/env bash
# Graceful wrap for sota_max / abuse burn. On-pod. cgroup-irrelevant.
set -euo pipefail
cd /workspace/MS-C
OUT=analysis/results/runs/sota_max
LOG=/workspace/logs/msc_sota_abuse.log
[[ -f "${LOG}" ]] || LOG=/workspace/logs/msc_sota_max.log
mkdir -p "${OUT}" /workspace/logs

echo "[wrap] STOPPING burn $(date -u +%H:%M:%SZ)" | tee -a "${LOG}"
pkill -9 -f '_pod_sota_abuse|_pod_sota_max|_pod_sota_burn' 2>/dev/null || true
sleep 1
# kill venv burn pythons; keep jupyter
ps -eo pid,cmd | while read -r pid rest; do
  case "${rest}" in
    *jupyter*) continue ;;
    */workspace/MS-C/.venv/bin/python*|*'python -'*)
      kill -9 "${pid}" 2>/dev/null || true
      ;;
  esac
done
sleep 3
echo "[wrap] GPU after kill:" | tee -a "${LOG}"
nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader | tee -a "${LOG}" || true

VENV=/workspace/MS-C/.venv
if [[ -x "${VENV}/bin/python" ]]; then
  # shellcheck disable=SC1091
  source "${VENV}/bin/activate"
fi

echo "[wrap] package current bests" | tee -a "${LOG}"
python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, time
from pathlib import Path
import numpy as np
from models.optimizer import OptimizeResult
from models.kit_export import export_kit
from models.scorecard import build_scorecard
from models.detectors import get_detector
from models.scenes import generate_scene, SITE_CLASSES
from models.renderer import apply_pattern_to_scene

out = Path("analysis/results/runs/sota_max")
out.mkdir(parents=True, exist_ok=True)
det_dir = Path("analysis/results/runs/site_detector")
cands = [
    det_dir / "site_yolo_adv_best.pt",
    det_dir / "site_yolo_best.pt",
    det_dir / "site_yolov8n_adv_best.pt",
    det_dir / "site_yolov8n_best.pt",
]
det_w = next((p for p in cands if p.is_file()), None)

# Prefer live_status scores if present
live = {}
live_path = out / "live_status.json"
if live_path.is_file():
    live = json.loads(live_path.read_text(encoding="utf-8"))

results = []
yolo = {}
for site in SITE_CLASSES:
    npz = out / f"pattern_{site}.npz"
    if not npz.is_file():
        print(f"[wrap] missing {npz}", flush=True)
        continue
    z = np.load(npz)
    seed = int(z["seed"]) if "seed" in z.files else 0
    rgb, emis = z["rgb"], z["emis"]
    baseline = 0.0
    best = 0.0
    if det_w is not None:
        det = get_detector("yolo", weights=str(det_w))
        scene = generate_scene(site, seed=seed, size=640)
        cov = apply_pattern_to_scene(scene, rgb, emis, alpha=0.68)
        baseline = float(det.mean_confidence(scene))
        best = float(det.mean_confidence(cov))
        yolo[site] = {"uncovered": round(baseline, 4), "mantle": round(best, 4)}
    results.append(OptimizeResult(
        pattern_rgb=rgb, pattern_emis=emis, best_score=float(best),
        baseline_score=float(baseline), steps=0, site_class=site, seed=seed,
    ))
    print(f"[wrap] {site} uncovered={baseline:.4f} mantle={best:.4f}", flush=True)

card = build_scorecard(results, detector_kind="surrogate") if results else {"summary": {}}
card["burn"] = {
    "wave": "wrap_finalize",
    "wrapped_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "weights": str(det_w) if det_w else None,
    "yolo_site_scores": yolo or live.get("yolo_site_scores", {}),
    "live_at_wrap": live,
    "complete": True,
    "note": "Early wrap per operator — digital evidence only, not FLIR-validated.",
}
(out / "scorecard.json").write_text(json.dumps(card, indent=2) + "\n")
if results:
    export_kit(results, out)

report = {
    "title": "MS-C Mantle SOTA ABUSE — early wrap",
    "wrapped_at": card["burn"]["wrapped_at"],
    "weights": str(det_w) if det_w else None,
    "yolo_site_scores": card["burn"]["yolo_site_scores"],
    "summary": card.get("summary", {}),
    "burn": card["burn"],
    "evidence_class": "digital_surrogate_unvalidated",
}
(out / "SOTA_REPORT.json").write_text(json.dumps(report, indent=2) + "\n")
(out / "live_status.json").write_text(json.dumps({
    "ts": report["wrapped_at"],
    "stage": "wrapped",
    "yolo_site_scores": report["yolo_site_scores"],
    "seconds_left": 0,
}, indent=2) + "\n")
print("[wrap] REPORT", json.dumps(report), flush=True)
PY

echo "[wrap] pack tarball" | tee -a "${LOG}"
rm -f /tmp/msc_sota_pull.tgz
tar czf /tmp/msc_sota_pull.tgz \
  -C /workspace/MS-C \
  analysis/results/runs/sota_max \
  analysis/results/runs/site_detector \
  2>/dev/null || tar czf /tmp/msc_sota_pull.tgz -C /workspace/MS-C analysis/results/runs/sota_max
ls -lah /tmp/msc_sota_pull.tgz | tee -a "${LOG}"
echo "[wrap] GPU idle check:" | tee -a "${LOG}"
nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader | tee -a "${LOG}" || true
ps aux | grep -E '_pod_sota|venv/bin/python' | grep -v grep | head -10 || echo "[wrap] no burn procs"
echo "[wrap] SAFE TO TERMINATE POD $(date -u +%H:%M:%SZ)" | tee -a "${LOG}"
