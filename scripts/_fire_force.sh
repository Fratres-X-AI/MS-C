#!/usr/bin/env bash
# Git Bash ONLY. Status → kill → relaunch abuse → verify GPU.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?}"
PORT="${2:?}"
MINUTES="${3:-300}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH=(ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -p "$PORT" "root@$HOST")
SCP=(scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -P "$PORT")

sed -i 's/\r$//' scripts/_pod_sota_abuse.sh scripts/_pod_force_status.sh scripts/_pod_cgroup_workers.sh models/joint_attack.py

echo "[force] STATUS BEFORE"
"${SSH[@]}" 'bash -s' < scripts/_pod_force_status.sh || true

echo "[force] UPLOAD + KILL + RELAUNCH"
"${SCP[@]}" scripts/_pod_sota_abuse.sh scripts/_pod_force_status.sh models/joint_attack.py \
  "root@$HOST:/tmp/"

"${SSH[@]}" "bash -s" <<EOF
set -euo pipefail
cp /tmp/_pod_sota_abuse.sh /workspace/MS-C/scripts/_pod_sota_abuse.sh
cp /tmp/joint_attack.py /workspace/MS-C/models/joint_attack.py
cp /tmp/_pod_force_status.sh /workspace/MS-C/scripts/_pod_force_status.sh
sed -i 's/\r\$//' /workspace/MS-C/scripts/*.sh /workspace/MS-C/models/joint_attack.py
chmod +x /workspace/MS-C/scripts/*.sh

# nuke all burn processes; keep jupyter
pkill -9 -f '_pod_sota' 2>/dev/null || true
sleep 1
ps -eo pid,cmd | while read -r pid rest; do
  case "\$rest" in
    *jupyter*) continue ;;
    *python*)
      # only kill if cwd or cmdline touches MS-C / ultralytics burn
      case "\$rest" in
        *MS-C*|*ultralytics*|*venv/bin/python*|*'python -'*)
          kill -9 "\$pid" 2>/dev/null || true
          ;;
      esac
      ;;
  esac
done
sleep 3
# free GPU memory
nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | while read -r gpupid; do
  [[ -z "\$gpupid" ]] && continue
  # don't kill jupyter if somehow listed
  cmd=\$(ps -p "\$gpupid" -o cmd= 2>/dev/null || true)
  case "\$cmd" in
    *jupyter*) continue ;;
    *) kill -9 "\$gpupid" 2>/dev/null || true ;;
  esac
done
sleep 2
echo "[force] GPU after kill:"
nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader

export MSC_BURN_MINUTES=${MINUTES}
export MSC_IMGSZ=640
export MSC_ATTACK_SIZE=640
export MSC_BATCH=128
export MSC_YOLO_MODEL=yolov8m.pt

# ensure venv exists
if [[ ! -x /workspace/MS-C/.venv/bin/python ]]; then
  python3 -m venv --system-site-packages /workspace/MS-C/.venv
  /workspace/MS-C/.venv/bin/pip install -U pip
  /workspace/MS-C/.venv/bin/pip install -e '/workspace/MS-C[dev,yolo]'
fi

nohup bash /workspace/MS-C/scripts/_pod_sota_abuse.sh > /workspace/logs/msc_sota_abuse.log 2>&1 &
echo \$! > /workspace/logs/msc_sota_abuse.pid
ln -sf /workspace/logs/msc_sota_abuse.log /workspace/logs/msc_sota_burn.log
ln -sf /workspace/logs/msc_sota_abuse.log /workspace/logs/msc_sota_max.log
sleep 8
echo "[force] LAUNCHED pid=\$(cat /workspace/logs/msc_sota_abuse.pid)"
tail -n 40 /workspace/logs/msc_sota_abuse.log
ps aux | grep -E '_pod_sota_abuse|python' | grep -v grep | head -12
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader
EOF

echo "[force] DONE $(date -u +%H:%M:%SZ)"
