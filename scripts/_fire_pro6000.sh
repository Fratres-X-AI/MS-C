#!/usr/bin/env bash
# Git Bash ONLY. Full sync + MAXX burn on RTX PRO 6000-class pod.
# Usage: bash scripts/_fire_pro6000.sh HOST PORT [MINUTES]
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?HOST}"
PORT="${2:?PORT}"
MINUTES="${3:-360}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH=(ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=45 -i "$KEY" -p "$PORT" "root@$HOST")
SCP=(scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=45 -i "$KEY" -P "$PORT")

die() { echo "[fire-pro] FATAL: $*" >&2; exit 1; }
[[ -f "$KEY" ]] || die "no SSH key at $KEY"

# strip CRLF on launch scripts
sed -i 's/\r$//' scripts/_pod_sota_max.sh scripts/_pod_cgroup_workers.sh scripts/_probe_pod.sh 2>/dev/null || true

echo "[fire-pro] pack $(date -u +%H:%M:%SZ)"
rm -f /tmp/msc_pro.tgz
tar czf /tmp/msc_pro.tgz \
  --exclude='.git' --exclude='.venv' --exclude='__pycache__' \
  --exclude='.mypy_cache' --exclude='.ruff_cache' --exclude='.pytest_cache' \
  --exclude='analysis/results/runs' \
  --exclude='*.egg-info' \
  .

echo "[fire-pro] upload tarball + max scripts"
"${SCP[@]}" /tmp/msc_pro.tgz "root@$HOST:/tmp/msc_pro.tgz"
"${SCP[@]}" scripts/_pod_sota_max.sh "root@$HOST:/tmp/_pod_sota_max.sh"
"${SCP[@]}" scripts/_pod_cgroup_workers.sh "root@$HOST:/tmp/_pod_cgroup_workers.sh"

echo "[fire-pro] extract + launch ${MINUTES}min burn"
"${SSH[@]}" "bash -s" <<EOF
set -euo pipefail
mkdir -p /workspace/MS-C /workspace/logs
cd /workspace
rm -rf MS-C.tmp
mkdir MS-C.tmp
tar xzf /tmp/msc_pro.tgz -C MS-C.tmp --no-same-owner --no-same-permissions
# preserve prior detector weights if any
if [[ -d MS-C/analysis/results/runs/site_detector ]]; then
  mkdir -p MS-C.tmp/analysis/results/runs
  cp -a MS-C/analysis/results/runs/site_detector MS-C.tmp/analysis/results/runs/ 2>/dev/null || true
fi
rm -rf MS-C
mv MS-C.tmp MS-C
cp /tmp/_pod_sota_max.sh /workspace/MS-C/scripts/_pod_sota_max.sh
cp /tmp/_pod_cgroup_workers.sh /workspace/MS-C/scripts/_pod_cgroup_workers.sh
sed -i 's/\r\$//' /workspace/MS-C/scripts/*.sh
chmod +x /workspace/MS-C/scripts/*.sh

# kill anything old hard
pkill -9 -f '_pod_sota|_pod_resume|joint_attack|optimize_joint|train_site|ultralytics|msc_sota' 2>/dev/null || true
sleep 2
pkill -9 -f 'python -' 2>/dev/null || true
sleep 1

WORKERS=\$(bash /workspace/MS-C/scripts/_pod_cgroup_workers.sh)
echo "[fire-pro] cgroup_workers=\${WORKERS} nproc_lie=\$(nproc) minutes=${MINUTES}"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader

export MSC_BURN_MINUTES=${MINUTES}
export MSC_IMGSZ=640
export MSC_ATTACK_SIZE=512
export MSC_BATCH=192
export MSC_YOLO_MODEL=yolov8s.pt

nohup bash /workspace/MS-C/scripts/_pod_sota_max.sh > /workspace/logs/msc_sota_max.log 2>&1 &
echo \$! > /workspace/logs/msc_sota_max.pid
ln -sf /workspace/logs/msc_sota_max.log /workspace/logs/msc_sota_burn.log
sleep 6
echo "pid=\$(cat /workspace/logs/msc_sota_max.pid)"
tail -n 50 /workspace/logs/msc_sota_max.log || true
ps aux | grep -E 'python|_pod_sota_max' | grep -v grep | head -25 || true
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader || true
EOF

echo "[fire-pro] LAUNCHED $(date -u +%H:%M:%SZ) minutes=${MINUTES}"
echo "[fire-pro] tick: bash scripts/_pod_tick.sh ${HOST} ${PORT}"
