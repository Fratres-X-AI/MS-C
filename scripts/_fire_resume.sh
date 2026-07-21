#!/usr/bin/env bash
# Push resume scripts + fixed train_detector; launch 55min attack.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?}"
PORT="${2:?}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH=(ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -p "$PORT" "root@$HOST")
SCP=(scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -P "$PORT")

sed -i 's/\r$//' scripts/_pod_resume_attack.sh scripts/_pod_cgroup_workers.sh models/train_detector.py
"${SCP[@]}" scripts/_pod_resume_attack.sh "root@$HOST:/tmp/_pod_resume_attack.sh"
"${SCP[@]}" scripts/_pod_cgroup_workers.sh "root@$HOST:/workspace/MS-C/scripts/_pod_cgroup_workers.sh"
"${SCP[@]}" models/train_detector.py "root@$HOST:/workspace/MS-C/models/train_detector.py"

"${SSH[@]}" 'bash -s' <<'EOF'
set -euo pipefail
sed -i 's/\r$//' /tmp/_pod_resume_attack.sh
cp /tmp/_pod_resume_attack.sh /workspace/MS-C/scripts/_pod_resume_attack.sh
chmod +x /workspace/MS-C/scripts/*.sh
pkill -f '_pod_sota_burn|_pod_resume_attack|optimize_pattern' 2>/dev/null || true
export MSC_BURN_MINUTES=55
nohup bash /workspace/MS-C/scripts/_pod_resume_attack.sh \
  > /workspace/logs/msc_sota_burn.log 2>&1 &
echo $! > /workspace/logs/msc_sota_burn.pid
sleep 2
echo "pid=$(cat /workspace/logs/msc_sota_burn.pid)"
tail -n 25 /workspace/logs/msc_sota_burn.log || true
EOF
echo "[fire-resume] LAUNCHED $(date -u +%H:%M:%SZ)"
