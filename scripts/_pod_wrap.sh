#!/usr/bin/env bash
# Safe wrap: stop burn after packaging current bests. On-pod.
set -euo pipefail
cd /workspace/MS-C
OUT=analysis/results/runs/sota_2h
LOG=/workspace/logs/msc_sota_2h.log
mkdir -p "${OUT}"

echo "[wrap] STOPPING workers $(date -u +%H:%M:%SZ)" | tee -a "${LOG}"
# Stop orchestrator + children (safe: we re-export from disk artifacts next)
pkill -f '_pod_sota_max|wave3_max|wave1_max|ProcessPool|optimize_joint|_worker_job' 2>/dev/null || true
sleep 2
# Don't kill jupyter
pkill -f 'models.joint_attack|train_site|ultralytics' 2>/dev/null || true
sleep 2

echo "[wrap] package current bests" | tee -a "${LOG}"
python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, hashlib, time
from pathlib import Path
import numpy as np
from models.optimizer import OptimizeResult
from models.kit_export import export_kit
from models.scorecard import build_scorecard
from models.detectors import get_detector
from models.scenes import generate_scene, SITE_CLASSES
from models.renderer import apply_pattern_to_scene

out = Path("analysis/results/runs/sota_2h")
out.mkdir(parents=True, exist_ok=True)
det_w = Path("analysis/results/runs/site_detector/site_yolov8n_adv_best.pt")
if not det_w.is_file():
    det_w = Path("analysis/results/runs/site_detector/site_yolov8n_best.pt")

results = []
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
    if det_w.is_file():
        det = get_detector("yolo", weights=str(det_w))
        scene = generate_scene(site, seed=seed, size=320)
        cov = apply_pattern_to_scene(scene, rgb, emis, alpha=0.70)
        baseline = det.mean_confidence(scene)
        best = det.mean_confidence(cov)
    results.append(OptimizeResult(
        pattern_rgb=rgb, pattern_emis=emis, best_score=float(best),
        baseline_score=float(baseline), steps=0, site_class=site, seed=seed,
    ))
    print(f"[wrap] {site} uncovered={baseline:.4f} mantle={best:.4f}", flush=True)

card = build_scorecard(results, detector_kind="surrogate") if results else {"summary": {}}
yolo = {}
if det_w.is_file() and results:
    det = get_detector("yolo", weights=str(det_w))
    for r in results:
        scene = generate_scene(r.site_class, seed=r.seed, size=320)
        cov = apply_pattern_to_scene(scene, r.pattern_rgb, r.pattern_emis, alpha=0.70)
        yolo[r.site_class] = {
            "uncovered": round(det.mean_confidence(scene), 4),
            "mantle": round(det.mean_confidence(cov), 4),
        }
card["burn"] = {
    "wave": "wrap_finalize",
    "wrapped_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "weights": str(det_w),
    "yolo_site_scores": yolo,
    "complete": True,
    "note": "Graceful wrap — digital evidence only, not FLIR-validated.",
}
(out / "scorecard.json").write_text(json.dumps(card, indent=2) + "\n")
if results:
    export_kit(results, out)

files = sorted(p for p in out.rglob("*") if p.is_file() and p.name != "reproduce_manifest.json")
manifest = {
    "product": "MS-C Mantle",
    "run": "sota_2h_wrap",
    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    "evidence_class": "digital_surrogate_unvalidated",
    "files": {str(p.relative_to(out)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
}
(out / "reproduce_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
report = {
    "title": "MS-C Mantle SOTA digital wrap",
    "claim_allowed": "Digital prototype only — not fielded stealth, not FLIR-validated.",
    "pipeline": ["site YOLO", "joint multi-view attack", "adv retrain", "joint attack v2", "graceful wrap"],
    "yolo_site_scores": yolo,
    "scorecard_summary": card.get("summary", {}),
    "burn": card.get("burn", {}),
    "n_files": len(manifest["files"]),
}
(out / "SOTA_REPORT.json").write_text(json.dumps(report, indent=2) + "\n")
status = {"ts": report["burn"]["wrapped_at"], "stage": "WRAPPED", "seconds_left": 0, "yolo_site_scores": yolo}
(out / "live_status.json").write_text(json.dumps(status, indent=2) + "\n")
print(json.dumps(report, indent=2), flush=True)
print("[wrap] PACKAGE OK", flush=True)
PY

# tarball for pull
cd /workspace
tar czf /tmp/msc_sota_pull.tgz \
  --exclude='__pycache__' \
  MS-C/analysis/results/runs/sota_2h \
  MS-C/analysis/results/runs/site_detector/*.pt \
  MS-C/analysis/results/runs/site_detector/*meta*.json \
  MS-C/docs MS-C/README.md MS-C/rtm \
  2>/dev/null || tar czf /tmp/msc_sota_pull.tgz MS-C/analysis/results/runs/sota_2h MS-C/analysis/results/runs/site_detector
ls -lah /tmp/msc_sota_pull.tgz | tee -a "${LOG}"
echo "[wrap] SAFE_TO_STOP_POD $(date -u +%H:%M:%SZ)" | tee -a "${LOG}"
