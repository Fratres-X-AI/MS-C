#!/usr/bin/env bash
# Hot-swap to MAXXED burn (venv-aware). Git Bash ONLY.
# Usage: bash scripts/_fire_max.sh HOST PORT [MINUTES]
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?}"
PORT="${2:?}"
MINUTES="${3:-360}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH=(ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -p "$PORT" "root@$HOST")
SCP=(scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -P "$PORT")

sed -i 's/\r$//' scripts/_pod_sota_max.sh scripts/_pod_cgroup_workers.sh models/joint_attack.py

"${SCP[@]}" scripts/_pod_sota_max.sh "root@$HOST:/tmp/_pod_sota_max.sh"
"${SCP[@]}" scripts/_pod_cgroup_workers.sh "root@$HOST:/workspace/MS-C/scripts/_pod_cgroup_workers.sh"
"${SCP[@]}" models/joint_attack.py "root@$HOST:/workspace/MS-C/models/joint_attack.py"
# also push pyproject/requirements in case deps changed
"${SCP[@]}" pyproject.toml requirements.txt "root@$HOST:/workspace/MS-C/" 2>/dev/null || true

"${SSH[@]}" "bash -s" <<EOF
set -euo pipefail
sed -i 's/\r\$//' /tmp/_pod_sota_max.sh /workspace/MS-C/models/joint_attack.py /workspace/MS-C/scripts/_pod_cgroup_workers.sh
cp /tmp/_pod_sota_max.sh /workspace/MS-C/scripts/_pod_sota_max.sh
chmod +x /workspace/MS-C/scripts/*.sh
# kill old burn — do NOT kill jupyter
pkill -9 -f '_pod_sota_max|_pod_sota_burn|_pod_resume' 2>/dev/null || true
pkill -9 -f 'models.joint_attack|train_site_detector|ultralytics' 2>/dev/null || true
sleep 2
# kill orphan burn pythons under MS-C venv only
pkill -9 -f '/workspace/MS-C/.venv/bin/python' 2>/dev/null || true
sleep 1
WORKERS=\$(bash /workspace/MS-C/scripts/_pod_cgroup_workers.sh)
echo "[fire-max] cgroup_workers=\${WORKERS} nproc_lie=\$(nproc) minutes=${MINUTES}"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
export MSC_BURN_MINUTES=${MINUTES}
export MSC_IMGSZ=640
export MSC_ATTACK_SIZE=512
export MSC_BATCH=192
export MSC_YOLO_MODEL=yolov8s.pt
nohup bash /workspace/MS-C/scripts/_pod_sota_max.sh > /workspace/logs/msc_sota_max.log 2>&1 &
echo \$! > /workspace/logs/msc_sota_max.pid
ln -sf /workspace/logs/msc_sota_max.log /workspace/logs/msc_sota_burn.log
sleep 8
echo "pid=\$(cat /workspace/logs/msc_sota_max.pid)"
tail -n 60 /workspace/logs/msc_sota_max.log || true
ps aux | grep -E 'python|_pod_sota_max' | grep -v grep | head -20 || true
EOF
echo "[fire-max] LAUNCHED $(date -u +%H:%M:%SZ)"
