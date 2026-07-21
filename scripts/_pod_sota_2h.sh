#!/usr/bin/env bash
# 2-hour SOTA arms race: harden detector ↔ joint multi-view attack ↔ retrain ↔ final kits
# cgroup workers ONLY (not nproc). Git Bash / Linux.
set -euo pipefail
cd /workspace/MS-C

WORKERS=$(bash scripts/_pod_cgroup_workers.sh)
export OMP_NUM_THREADS="${WORKERS}"
export MKL_NUM_THREADS="${WORKERS}"
export OPENBLAS_NUM_THREADS="${WORKERS}"
export NUMEXPR_NUM_THREADS="${WORKERS}"
ULTRA_WORKERS=$(( WORKERS > 8 ? 8 : WORKERS ))
MINUTES="${MSC_BURN_MINUTES:-120}"
START_TS=$(date +%s)
DEADLINE=$((START_TS + MINUTES * 60))
LOG=/workspace/logs/msc_sota_2h.log
OUT=analysis/results/runs/sota_2h
DET_DIR=analysis/results/runs/site_detector
mkdir -p /workspace/logs "${OUT}" "${DET_DIR}"
: > "${LOG}"

{
  echo "=== MS-C SOTA 2H START $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
  echo "workers_cgroup=${WORKERS} ultra_workers=${ULTRA_WORKERS} nproc_lie=$(nproc) minutes=${MINUTES}"
  nvidia-smi --query-gpu=name,memory.total --format=csv,noheader || true
} | tee -a "${LOG}"

python -m pip install -e ".[dev,yolo]" >>"${LOG}" 2>&1

write_status() {
  python - <<'PY'
import json, os, time
from pathlib import Path
st = {
  "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
  "stage": os.environ.get("MSC_STAGE", "?"),
  "seconds_left": max(0, float(os.environ.get("MSC_DEADLINE", "0")) - time.time()),
  "note": os.environ.get("MSC_NOTE", ""),
}
Path("analysis/results/runs/sota_2h/live_status.json").write_text(json.dumps(st, indent=2)+"\n")
print("[status]", json.dumps(st), flush=True)
PY
}

export MSC_DEADLINE="${DEADLINE}"

# ---------- WAVE 0: ensure base detector ----------
export MSC_STAGE=wave0_detector
export MSC_NOTE="ensure site YOLO weights"
write_status | tee -a "${LOG}"

WEIGHTS="${DET_DIR}/site_yolov8n_best.pt"
if [[ ! -f "${WEIGHTS}" ]]; then
  SRC=$(find /workspace/MS-C/runs /workspace/MS-C/analysis -name 'best.pt' 2>/dev/null | head -1 || true)
  if [[ -n "${SRC}" ]]; then
    cp -f "${SRC}" "${WEIGHTS}"
  else
    python - <<PY 2>&1 | tee -a "${LOG}"
from models.train_detector import train_site_detector
from pathlib import Path
import os
w = int(os.environ["OMP_NUM_THREADS"])
best = train_site_detector(Path("${DET_DIR}"), epochs=40, imgsz=320, batch=32, workers=min(8,w), device="0", n_train=400, n_val=80)
print("BEST", best)
PY
  fi
fi
echo "[2h] weights0=${WEIGHTS}" | tee -a "${LOG}"

# ---------- WAVE 1: joint multi-view attack ----------
export MSC_STAGE=wave1_joint_attack
export MSC_NOTE="multi-view YOLO + beat commercial + naturalness"
write_status | tee -a "${LOG}"

export MSC_YOLO_WEIGHTS="${WEIGHTS}"
python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, os, time
from pathlib import Path
from models.joint_attack import optimize_joint, evaluate_joint
from models.detectors import get_detector
from models.scenes import SITE_CLASSES, generate_scene
from models.kit_export import export_kit
from models.scorecard import build_scorecard
from models.renderer import apply_pattern_to_scene

deadline = float(os.environ["MSC_DEADLINE"])
# spend ~35% of remaining on wave1
wave_end = time.time() + max(600, 0.35 * (deadline - time.time()))
weights = os.environ["MSC_YOLO_WEIGHTS"]
out = Path("analysis/results/runs/sota_2h")
out.mkdir(parents=True, exist_ok=True)
det = get_detector("yolo", weights=weights)
results = []
round_i = 0
seed0 = 100
while time.time() < wave_end and time.time() < deadline:
    round_i += 1
    seed = seed0 + round_i
    steps = min(100 + round_i * 15, 280)
    for sc in SITE_CLASSES:
        if time.time() >= wave_end:
            break
        t0 = time.time()
        print(f"[w1] ROUND={round_i} site={sc} steps={steps}", flush=True)
        res = optimize_joint(sc, seed=seed, steps=steps, detector_weights=weights, size=320, alpha=0.72)
        results.append(res)
        metrics = evaluate_joint(sc, seed, res.pattern_rgb, res.pattern_emis, det, size=320, alpha=0.72)
        print(f"[w1] DONE {sc} base={res.baseline_score:.3f} best={res.best_score:.3f} obj={metrics['objective']:.3f} "
              f"com={metrics['commercial_nadir']:.3f} uniq={metrics['uniq_colors']} sec={time.time()-t0:.1f}", flush=True)
        best_by = {}
        for r in results:
            cur = best_by.get(r.site_class)
            if cur is None or r.best_score < cur.best_score:
                best_by[r.site_class] = r
        keep = list(best_by.values())
        card = build_scorecard(keep, detector_kind="surrogate")
        yolo = {}
        for site, r in best_by.items():
            scene = generate_scene(site, seed=r.seed, size=320)
            cov = apply_pattern_to_scene(scene, r.pattern_rgb, r.pattern_emis, alpha=0.72)
            yolo[site] = {"uncovered": round(det.mean_confidence(scene),4), "mantle": round(det.mean_confidence(cov),4)}
        card["burn"] = {"wave": 1, "rounds": round_i, "yolo_site_scores": yolo, "n": len(results)}
        (out/"scorecard_w1.json").write_text(json.dumps(card, indent=2)+"\n")
        export_kit(keep, out / "kits_w1")
        status = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "stage":"wave1_joint_attack",
                  "round": round_i, "yolo_site_scores": yolo, "seconds_left": max(0, deadline-time.time()),
                  "summary": card["summary"]}
        (out/"live_status.json").write_text(json.dumps(status, indent=2)+"\n")
        print("[w1] STATUS", json.dumps(status), flush=True)

# persist best patterns for hard-negative mining
best_by = {}
for r in results:
    cur = best_by.get(r.site_class)
    if cur is None or r.best_score < cur.best_score:
        best_by[r.site_class] = r
keep = list(best_by.values())
meta = {"n": len(results), "sites": list(best_by)}
(out/"wave1_meta.json").write_text(json.dumps(meta, indent=2)+"\n")
# save pattern npz
import numpy as np
for site, r in best_by.items():
    np.savez(out / f"pattern_{site}.npz", rgb=r.pattern_rgb, emis=r.pattern_emis, seed=r.seed)
print("[w1] COMPLETE", flush=True)
PY

# ---------- WAVE 2: adversarial retrain (harden detector on covered scenes) ----------
export MSC_STAGE=wave2_adv_retrain
export MSC_NOTE="retrain YOLO on uncovered + Mantle-covered hard negatives"
write_status | tee -a "${LOG}"

python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, shutil, time
from pathlib import Path
import numpy as np
from PIL import Image
from models.scenes import SITE_CLASSES, generate_scene
from models.renderer import apply_pattern_to_scene
from models.train_detector import CLASS_TO_ID, CLASS_NAMES, train_site_detector, build_synth_dataset

out = Path("analysis/results/runs/sota_2h")
det_dir = Path("analysis/results/runs/site_detector")
# Build augmented dataset: base synth + covered hard negatives with SAME labels
yaml = build_synth_dataset(det_dir / "adv_data", n_train=320, n_val=64, size=320, seed=42)
ds = det_dir / "adv_data" / "synth_sites"
img_tr = ds / "images" / "train"
lbl_tr = ds / "labels" / "train"
# append covered variants
idx = 90000
for site in SITE_CLASSES:
    npz = out / f"pattern_{site}.npz"
    if not npz.is_file():
        continue
    z = np.load(npz)
    rgb, emis = z["rgb"], z["emis"]
    for k in range(40):
        scene = generate_scene(site, seed=2000+k, size=320, view=("nadir","oblique")[k%2], lighting=("nominal","harsh","dim")[k%3])
        cov = apply_pattern_to_scene(scene, rgb, emis, alpha=0.72)
        stem = f"adv_{idx:05d}"
        Image.fromarray(cov.rgb).save(img_tr / f"{stem}.jpg", quality=92)
        h, w = cov.rgb.shape[:2]
        lines=[]
        for box in cov.boxes:
            cid = CLASS_TO_ID.get(box.label)
            if cid is None: continue
            x0,y0,x1,y1 = box.as_tuple()
            cx=((x0+x1)/2)/w; cy=((y0+y1)/2)/h; bw=(x1-x0)/w; bh=(y1-y0)/h
            lines.append(f"{cid} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}")
        (lbl_tr / f"{stem}.txt").write_text("\n".join(lines)+("\n" if lines else ""), encoding="utf-8")
        idx += 1
print(f"[w2] hard_negatives_added total_train_imgs~={len(list(img_tr.glob('*.jpg')))}", flush=True)

from ultralytics import YOLO
import os
workers = min(8, int(os.environ.get("OMP_NUM_THREADS","4")))
# continue from previous best
prev = det_dir / "site_yolov8n_best.pt"
model = YOLO(str(prev) if prev.is_file() else "yolov8n.pt")
model.train(
    data=str(ds/"data.yaml"),
    epochs=35,
    imgsz=320,
    batch=32,
    workers=workers,
    device="0",
    project=str((det_dir/"ultra_adv").resolve()),
    name="site_det_adv",
    exist_ok=True,
    patience=12,
)
cands = list((det_dir/"ultra_adv").rglob("best.pt")) + list(Path("/workspace/MS-C/runs").rglob("best.pt"))
best = max(cands, key=lambda p: p.stat().st_mtime)
dest = det_dir / "site_yolov8n_adv_best.pt"
shutil.copy2(best, dest)
shutil.copy2(best, det_dir / "site_yolov8n_best.pt")
print(f"[w2] ADV_WEIGHTS={dest}", flush=True)
(out/"wave2_meta.json").write_text(json.dumps({"best": str(dest), "ts": time.time()}, indent=2)+"\n")
PY

WEIGHTS="${DET_DIR}/site_yolov8n_adv_best.pt"
[[ -f "${WEIGHTS}" ]] || WEIGHTS="${DET_DIR}/site_yolov8n_best.pt"
export MSC_YOLO_WEIGHTS="${WEIGHTS}"

# ---------- WAVE 3: second joint attack vs hardened detector ----------
export MSC_STAGE=wave3_joint_attack_v2
export MSC_NOTE="attack hardened detector; export final kits"
write_status | tee -a "${LOG}"

python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, os, time
from pathlib import Path
import numpy as np
from models.joint_attack import optimize_joint, evaluate_joint
from models.detectors import get_detector
from models.scenes import SITE_CLASSES, generate_scene
from models.kit_export import export_kit
from models.scorecard import build_scorecard
from models.renderer import apply_pattern_to_scene

deadline = float(os.environ["MSC_DEADLINE"])
weights = os.environ["MSC_YOLO_WEIGHTS"]
out = Path("analysis/results/runs/sota_2h")
det = get_detector("yolo", weights=weights)
results = []
round_i = 0
seed0 = 500
while time.time() < deadline - 180:  # leave 3 min for final package
    round_i += 1
    seed = seed0 + round_i
    steps = min(120 + round_i * 20, 320)
    for sc in SITE_CLASSES:
        if time.time() >= deadline - 180:
            break
        t0 = time.time()
        print(f"[w3] ROUND={round_i} site={sc} steps={steps}", flush=True)
        res = optimize_joint(sc, seed=seed, steps=steps, detector_weights=weights, size=320, alpha=0.70)
        results.append(res)
        metrics = evaluate_joint(sc, seed, res.pattern_rgb, res.pattern_emis, det, size=320, alpha=0.70)
        print(f"[w3] DONE {sc} base={res.baseline_score:.3f} best={res.best_score:.3f} obj={metrics['objective']:.3f} "
              f"beat_com_pen={metrics['beat_com_pen']:.3f} sec={time.time()-t0:.1f}", flush=True)
        best_by = {}
        for r in results:
            cur = best_by.get(r.site_class)
            if cur is None or r.best_score < cur.best_score:
                best_by[r.site_class] = r
        keep = list(best_by.values())
        card = build_scorecard(keep, detector_kind="surrogate")
        yolo = {}
        for site, r in best_by.items():
            scene = generate_scene(site, seed=r.seed, size=320)
            cov = apply_pattern_to_scene(scene, r.pattern_rgb, r.pattern_emis, alpha=0.70)
            yolo[site] = {
                "uncovered": round(det.mean_confidence(scene), 4),
                "mantle": round(det.mean_confidence(cov), 4),
            }
        card["burn"] = {"wave": 3, "rounds": round_i, "weights": weights, "yolo_site_scores": yolo, "n": len(results)}
        (out/"scorecard.json").write_text(json.dumps(card, indent=2)+"\n")
        export_kit(keep, out)
        status = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "stage":"wave3_joint_attack_v2",
                  "round": round_i, "yolo_site_scores": yolo, "seconds_left": max(0, deadline-time.time()),
                  "summary": card["summary"]}
        (out/"live_status.json").write_text(json.dumps(status, indent=2)+"\n")
        print("[w3] STATUS", json.dumps(status), flush=True)
        for site, r in best_by.items():
            np.savez(out / f"pattern_{site}.npz", rgb=r.pattern_rgb, emis=r.pattern_emis, seed=r.seed)

print("[w3] COMPLETE", flush=True)
PY

# ---------- FINAL PACKAGE ----------
export MSC_STAGE=final_package
export MSC_NOTE="write SOTA report + checksums"
write_status | tee -a "${LOG}"

python - <<'PY' 2>&1 | tee -a "${LOG}"
import json, hashlib, time
from pathlib import Path
out = Path("analysis/results/runs/sota_2h")
files = sorted(p for p in out.rglob("*") if p.is_file())
manifest = {
  "product": "MS-C Mantle",
  "run": "sota_2h_arms_race",
  "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
  "evidence_class": "digital_surrogate_unvalidated",
  "files": {str(p.relative_to(out)).replace("\\","/"): hashlib.sha256(p.read_bytes()).hexdigest() for p in files if p.name != "reproduce_manifest.json"},
}
sc = {}
if (out/"scorecard.json").is_file():
    sc = json.loads((out/"scorecard.json").read_text())
report = {
  "title": "MS-C Mantle SOTA 2H Arms Race",
  "claim_allowed": "Digital prototype only — not fielded stealth.",
  "pipeline": ["site YOLO train", "joint multi-view attack", "adv retrain", "joint attack v2", "kit export"],
  "scorecard_summary": sc.get("summary", {}),
  "burn": sc.get("burn", {}),
  "manifest_files": len(manifest["files"]),
}
(out/"SOTA_REPORT.json").write_text(json.dumps(report, indent=2)+"\n")
(out/"reproduce_manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
print(json.dumps(report, indent=2), flush=True)
PY

echo "[2h] RESULT COMPLETE $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "${LOG}"
ls -lah "${OUT}" | tee -a "${LOG}"
nvidia-smi | tee -a "${LOG}" || true
