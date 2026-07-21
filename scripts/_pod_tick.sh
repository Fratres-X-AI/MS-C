#!/usr/bin/env bash
# One status tick. Git Bash ONLY.
# Usage: bash scripts/_pod_tick.sh HOST PORT
set -euo pipefail
HOST="${1:?}"
PORT="${2:?}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=20 \
  -i "$KEY" -p "$PORT" "root@$HOST" bash -s <<'EOF'
set +e
date -u +%H:%M:%SZ
echo "--- gpu ---"
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null
echo "--- cgroup workers ---"
bash /workspace/MS-C/scripts/_pod_cgroup_workers.sh 2>/dev/null || echo "?"
echo "nproc_lie=$(nproc)"
echo "--- procs ---"
ps aux | grep -E '_pod_sota_burn|optimize_pattern|ultralytics|python' | grep -v grep | head -12 || echo NO_PROCS
echo "--- live ---"
if [[ -f /workspace/MS-C/analysis/results/runs/sota_2h/live_status.json ]]; then
  cat /workspace/MS-C/analysis/results/runs/sota_2h/live_status.json
elif [[ -f /workspace/MS-C/analysis/results/runs/sota_hour/live_status.json ]]; then
  cat /workspace/MS-C/analysis/results/runs/sota_hour/live_status.json
else
  echo NO_LIVE_STATUS
fi
echo "--- log ---"
tail -n 22 /workspace/logs/msc_sota_2h.log 2>/dev/null \
  || tail -n 22 /workspace/logs/msc_sota_burn.log 2>/dev/null \
  || echo NO_LOG
EOF
