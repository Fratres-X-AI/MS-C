#!/usr/bin/env bash
# Kill stalled wave1, hot-swap abuse burn. Git Bash ONLY.
# Usage: bash scripts/_fire_abuse.sh HOST PORT [MINUTES]
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?}"
PORT="${2:?}"
MINUTES="${3:-300}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH=(ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -p "$PORT" "root@$HOST")
SCP=(scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -P "$PORT")

sed -i 's/\r$//' scripts/_pod_sota_abuse.sh scripts/_pod_cgroup_workers.sh models/joint_attack.py

"${SCP[@]}" scripts/_pod_sota_abuse.sh "root@$HOST:/tmp/_pod_sota_abuse.sh"
"${SCP[@]}" scripts/_pod_cgroup_workers.sh "root@$HOST:/workspace/MS-C/scripts/_pod_cgroup_workers.sh"
"${SCP[@]}" models/joint_attack.py "root@$HOST:/workspace/MS-C/models/joint_attack.py"

"${SSH[@]}" "bash -s" <<EOF
set -euo pipefail
sed -i 's/\r\$//' /tmp/_pod_sota_abuse.sh /workspace/MS-C/models/joint_attack.py
cp /tmp/_pod_sota_abuse.sh /workspace/MS-C/scripts/_pod_sota_abuse.sh
chmod +x /workspace/MS-C/scripts/*.sh

# hard kill burn — keep jupyter
pkill -9 -f '_pod_sota_max|_pod_sota_abuse|_pod_sota_burn|_pod_resume' 2>/dev/null || true
sleep 1
pkill -9 -f '/workspace/MS-C/.venv/bin/python' 2>/dev/null || true
sleep 2

WORKERS=\$(bash /workspace/MS-C/scripts/_pod_cgroup_workers.sh)
echo "[fire-abuse] cgroup_workers=\${WORKERS} nproc_lie=\$(nproc) minutes=${MINUTES}"
nvidia-smi --query-gpu=name,memory.total,memory.used,utilization.gpu --format=csv,noheader
ls -la /workspace/MS-C/analysis/results/runs/sota_max/pattern_*.npz 2>/dev/null || echo "no patterns yet"

export MSC_BURN_MINUTES=${MINUTES}
export MSC_IMGSZ=640
export MSC_ATTACK_SIZE=640
export MSC_BATCH=128
export MSC_YOLO_MODEL=yolov8m.pt

nohup bash /workspace/MS-C/scripts/_pod_sota_abuse.sh > /workspace/logs/msc_sota_abuse.log 2>&1 &
echo \$! > /workspace/logs/msc_sota_abuse.pid
ln -sf /workspace/logs/msc_sota_abuse.log /workspace/logs/msc_sota_burn.log
ln -sf /workspace/logs/msc_sota_abuse.log /workspace/logs/msc_sota_max.log
sleep 6
echo "pid=\$(cat /workspace/logs/msc_sota_abuse.pid)"
tail -n 40 /workspace/logs/msc_sota_abuse.log || true
ps aux | grep -E '_pod_sota_abuse|python' | grep -v grep | head -15 || true
EOF
echo "[fire-abuse] LAUNCHED $(date -u +%H:%M:%SZ)"
