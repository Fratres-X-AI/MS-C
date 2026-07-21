#!/usr/bin/env bash
# Git Bash ONLY. Sync MS-C → RunPod and start 60min SOTA burn.
# Usage: bash scripts/_fire_sota.sh HOST PORT
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?HOST}"
PORT="${2:?PORT}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH=(ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -p "$PORT" "root@$HOST")
SCP=(scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -P "$PORT")

die() { echo "[fire] FATAL: $*" >&2; exit 1; }
[[ -f "$KEY" ]] || die "no SSH key at $KEY"

echo "[fire] pack $(date -u +%H:%M:%SZ)"
rm -f /tmp/msc_sota.tgz
tar czf /tmp/msc_sota.tgz \
  --exclude='.git' --exclude='.venv' --exclude='__pycache__' \
  --exclude='.mypy_cache' --exclude='.ruff_cache' --exclude='.pytest_cache' \
  --exclude='analysis/results/runs' \
  --exclude='*.egg-info' \
  .

echo "[fire] upload"
"${SCP[@]}" /tmp/msc_sota.tgz "root@$HOST:/tmp/msc_sota.tgz"
"${SCP[@]}" scripts/_pod_sota_burn.sh "root@$HOST:/tmp/_pod_sota_burn.sh"
"${SCP[@]}" scripts/_pod_cgroup_workers.sh "root@$HOST:/tmp/_pod_cgroup_workers.sh"

echo "[fire] extract + launch burn"
"${SSH[@]}" 'bash -s' <<'EOF'
set -euo pipefail
mkdir -p /workspace/MS-C /workspace/logs
cd /workspace
rm -rf MS-C.tmp
mkdir MS-C.tmp
tar xzf /tmp/msc_sota.tgz -C MS-C.tmp --no-same-owner --no-same-permissions
rm -rf MS-C
mv MS-C.tmp MS-C
cp /tmp/_pod_sota_burn.sh /workspace/MS-C/scripts/_pod_sota_burn.sh
cp /tmp/_pod_cgroup_workers.sh /workspace/MS-C/scripts/_pod_cgroup_workers.sh
sed -i 's/\r$//' /workspace/MS-C/scripts/*.sh
chmod +x /workspace/MS-C/scripts/*.sh
WORKERS=$(bash /workspace/MS-C/scripts/_pod_cgroup_workers.sh)
echo "[fire] cgroup_workers=${WORKERS} nproc=$(nproc)"
nvidia-smi -L || true
# kill prior burn if any
pkill -f '_pod_sota_burn|sim.run_optimize|sota_hour' 2>/dev/null || true
export MSC_BURN_MINUTES=60
export MSC_WORKERS="${WORKERS}"
nohup bash /workspace/MS-C/scripts/_pod_sota_burn.sh \
  > /workspace/logs/msc_sota_burn.log 2>&1 &
echo $! > /workspace/logs/msc_sota_burn.pid
sleep 2
echo "[fire] pid=$(cat /workspace/logs/msc_sota_burn.pid)"
tail -n 20 /workspace/logs/msc_sota_burn.log || true
EOF

echo "[fire] LAUNCHED $(date -u +%H:%M:%SZ)"
