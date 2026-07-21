#!/usr/bin/env bash
# Push SOTA 2H package and launch. Git Bash ONLY.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?}"
PORT="${2:?}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH=(ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -p "$PORT" "root@$HOST")
SCP=(scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -P "$PORT")

sed -i 's/\r$//' scripts/_pod_sota_2h.sh scripts/_pod_cgroup_workers.sh scripts/_pod_tick.sh \
  models/joint_attack.py models/train_detector.py models/detectors.py models/optimizer.py

echo "[fire2h] pack"
rm -f /tmp/msc_2h.tgz
tar czf /tmp/msc_2h.tgz \
  --exclude='.git' --exclude='.venv' --exclude='__pycache__' \
  --exclude='.mypy_cache' --exclude='.ruff_cache' --exclude='.pytest_cache' \
  --exclude='analysis/results/runs' --exclude='*.egg-info' \
  models sim scripts docs rtm tests demo data analysis pyproject.toml README.md \
  requirements.txt Makefile REPRODUCE.md RUNPOD.md LICENSE SECURITY.md CONTRIBUTING.md

echo "[fire2h] upload"
"${SCP[@]}" /tmp/msc_2h.tgz "root@$HOST:/tmp/msc_2h.tgz"
"${SCP[@]}" scripts/_pod_sota_2h.sh "root@$HOST:/tmp/_pod_sota_2h.sh"

"${SSH[@]}" 'bash -s' <<'EOF'
set -euo pipefail
mkdir -p /workspace/MS-C /workspace/logs
cd /workspace
# preserve trained weights
mkdir -p /tmp/msc_keep
cp -f MS-C/analysis/results/runs/site_detector/site_yolov8n_best.pt /tmp/msc_keep/ 2>/dev/null || true
find MS-C/runs -name 'best.pt' -exec cp -f {} /tmp/msc_keep/best_prev.pt \; 2>/dev/null || true
rm -rf MS-C.tmp
mkdir MS-C.tmp
tar xzf /tmp/msc_2h.tgz -C MS-C.tmp --no-same-owner --no-same-permissions
# keep old analysis golden + merge
if [[ -d MS-C/analysis/results/golden ]]; then
  mkdir -p MS-C.tmp/analysis/results
  cp -a MS-C/analysis/results/golden MS-C.tmp/analysis/results/ 2>/dev/null || true
fi
rm -rf MS-C
mv MS-C.tmp MS-C
mkdir -p MS-C/analysis/results/runs/site_detector
cp -f /tmp/msc_keep/site_yolov8n_best.pt MS-C/analysis/results/runs/site_detector/ 2>/dev/null || true
cp -f /tmp/msc_keep/best_prev.pt MS-C/analysis/results/runs/site_detector/site_yolov8n_best.pt 2>/dev/null || true
cp /tmp/_pod_sota_2h.sh MS-C/scripts/_pod_sota_2h.sh
sed -i 's/\r$//' MS-C/scripts/*.sh MS-C/models/*.py
chmod +x MS-C/scripts/*.sh
pkill -f '_pod_sota|_pod_resume|joint_attack|optimize_pattern|train_site' 2>/dev/null || true
sleep 1
WORKERS=$(bash MS-C/scripts/_pod_cgroup_workers.sh)
echo "[fire2h] cgroup_workers=${WORKERS} nproc=$(nproc)"
export MSC_BURN_MINUTES=120
export MSC_WORKERS="${WORKERS}"
nohup bash /workspace/MS-C/scripts/_pod_sota_2h.sh > /workspace/logs/msc_sota_2h.log 2>&1 &
echo $! > /workspace/logs/msc_sota_2h.pid
# also symlink for tick script
ln -sf /workspace/logs/msc_sota_2h.log /workspace/logs/msc_sota_burn.log
sleep 3
echo "pid=$(cat /workspace/logs/msc_sota_2h.pid)"
tail -n 30 /workspace/logs/msc_sota_2h.log || true
EOF
echo "[fire2h] LAUNCHED $(date -u +%H:%M:%SZ)"
