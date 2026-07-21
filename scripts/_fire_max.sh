#!/usr/bin/env bash
# Hot-swap to MAXXED burn. Git Bash ONLY.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?}"
PORT="${2:?}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH=(ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -p "$PORT" "root@$HOST")
SCP=(scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -P "$PORT")

sed -i 's/\r$//' scripts/_pod_sota_max.sh scripts/_pod_cgroup_workers.sh models/joint_attack.py

"${SCP[@]}" scripts/_pod_sota_max.sh "root@$HOST:/tmp/_pod_sota_max.sh"
"${SCP[@]}" models/joint_attack.py "root@$HOST:/workspace/MS-C/models/joint_attack.py"
"${SCP[@]}" scripts/_pod_cgroup_workers.sh "root@$HOST:/workspace/MS-C/scripts/_pod_cgroup_workers.sh"

"${SSH[@]}" 'bash -s' <<'EOF'
set -euo pipefail
sed -i 's/\r$//' /tmp/_pod_sota_max.sh /workspace/MS-C/models/joint_attack.py
cp /tmp/_pod_sota_max.sh /workspace/MS-C/scripts/_pod_sota_max.sh
chmod +x /workspace/MS-C/scripts/*.sh
# kill old burn hard
pkill -9 -f '_pod_sota|_pod_resume|joint_attack|optimize_joint|train_site|ultralytics' 2>/dev/null || true
sleep 2
# leftover python burns
pkill -9 -f 'python -' 2>/dev/null || true
sleep 1
WORKERS=$(bash /workspace/MS-C/scripts/_pod_cgroup_workers.sh)
echo "[fire-max] cgroup_workers=${WORKERS} nproc=$(nproc)"
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
# remaining time ~105 min safety
export MSC_BURN_MINUTES=105
nohup bash /workspace/MS-C/scripts/_pod_sota_max.sh > /workspace/logs/msc_sota_2h.log 2>&1 &
echo $! > /workspace/logs/msc_sota_2h.pid
ln -sf /workspace/logs/msc_sota_2h.log /workspace/logs/msc_sota_burn.log
sleep 4
echo "pid=$(cat /workspace/logs/msc_sota_2h.pid)"
tail -n 40 /workspace/logs/msc_sota_2h.log || true
ps aux | grep -E 'python|_pod_sota_max' | grep -v grep | head -20
EOF
echo "[fire-max] LAUNCHED $(date -u +%H:%M:%SZ)"
