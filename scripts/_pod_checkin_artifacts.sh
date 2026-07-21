#!/usr/bin/env bash
set +e
date -u +%H:%M:%SZ
echo "--- live ---"
cat /workspace/MS-C/analysis/results/runs/sota_2h/live_status.json 2>/dev/null
echo
echo "--- artifacts ---"
ls -lah /workspace/MS-C/analysis/results/runs/sota_2h/ 2>/dev/null | head -40
echo "--- patterns ---"
ls -lah /workspace/MS-C/analysis/results/runs/sota_2h/pattern_*.npz 2>/dev/null
echo "--- kit ---"
if [[ -f /workspace/MS-C/analysis/results/runs/sota_2h/kit_manifest.json ]]; then
  python - <<'PY'
import json
m=json.load(open("/workspace/MS-C/analysis/results/runs/sota_2h/kit_manifest.json"))
print("kits", len(m.get("kits", [])), "bom", len(m.get("bom_stub", [])))
for k in m.get("kits", []):
    print(" ", k.get("site_class"), "tile", k.get("tile_png"), "base", k.get("digital_baseline_confidence"), "best", k.get("digital_best_confidence"))
PY
fi
echo "--- scorecard ---"
if [[ -f /workspace/MS-C/analysis/results/runs/sota_2h/scorecard.json ]]; then
  python - <<'PY'
import json
c=json.load(open("/workspace/MS-C/analysis/results/runs/sota_2h/scorecard.json"))
print(json.dumps(c.get("burn", {}), indent=2)[:800])
print("summary keys", list(c.get("summary", {}).keys()))
s=c.get("summary", {})
for k in ("nominal_mean_collapse_vs_uncovered","adversarial_mean_collapse_vs_uncovered","evidence_class"):
    print(k, s.get(k))
PY
fi
echo "--- weights ---"
ls -lah /workspace/MS-C/analysis/results/runs/site_detector/*.pt 2>/dev/null
echo "--- gpu ---"
nvidia-smi --query-gpu=utilization.gpu,memory.used,power.draw --format=csv,noheader
echo "--- log ---"
tail -n 15 /workspace/logs/msc_sota_2h.log
