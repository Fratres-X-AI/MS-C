#!/usr/bin/env bash
# Remote status dump — no fluff.
set -euo pipefail
date -u +%H:%M:%SZ
echo "=== GPU ==="
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader
echo "=== CGROUP ==="
bash /workspace/MS-C/scripts/_pod_cgroup_workers.sh 2>/dev/null || echo "?"
echo "nproc_lie=$(nproc)"
echo "=== PROCS ==="
ps aux | grep -E '_pod_sota|python' | grep -v grep | head -25 || echo NONE
echo "=== PIDS ==="
ls -la /workspace/logs/msc_sota_*.pid 2>/dev/null || true
for f in /workspace/logs/msc_sota_*.pid; do
  [[ -f "$f" ]] || continue
  p=$(cat "$f")
  echo "$f -> $p alive=$(kill -0 "$p" 2>/dev/null && echo yes || echo NO)"
done
echo "=== LIVE ==="
cat /workspace/MS-C/analysis/results/runs/sota_max/live_status.json 2>/dev/null || echo NO_LIVE
echo
echo "=== LOG TAIL ==="
tail -n 50 /workspace/logs/msc_sota_abuse.log 2>/dev/null \
  || tail -n 50 /workspace/logs/msc_sota_max.log 2>/dev/null \
  || echo NO_LOG
echo "=== PATTERNS ==="
ls -la /workspace/MS-C/analysis/results/runs/sota_max/pattern_*.npz 2>/dev/null || echo none
ls -la /workspace/MS-C/analysis/results/runs/site_detector/*.pt 2>/dev/null || echo no_weights
