#!/usr/bin/env bash
# Git Bash ONLY. Probe RunPod via TCP SSH.
set -euo pipefail
HOST="${1:?HOST}"
PORT="${2:?PORT}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 \
  -i "$KEY" -p "$PORT" "root@$HOST" 'bash -s' <<'EOF'
set -euo pipefail
echo "=== GPU ==="
nvidia-smi --query-gpu=name,memory.total,driver_version,utilization.gpu --format=csv
echo "=== CGROUP ==="
[[ -f /sys/fs/cgroup/cpu.max ]] && echo "cpu.max=$(cat /sys/fs/cgroup/cpu.max)"
[[ -f /sys/fs/cgroup/cpuset.cpus.effective ]] && echo "cpuset=$(cat /sys/fs/cgroup/cpuset.cpus.effective)"
echo "nproc_lie=$(nproc)"
if [[ -f /workspace/MS-C/scripts/_pod_cgroup_workers.sh ]]; then
  echo "cgroup_workers=$(bash /workspace/MS-C/scripts/_pod_cgroup_workers.sh)"
else
  # inline same logic
  w=""
  if [[ -f /sys/fs/cgroup/cpu.max ]]; then
    read -r quota period < /sys/fs/cgroup/cpu.max || true
    if [[ -n "${quota:-}" && "${quota}" != "max" && -n "${period:-}" && "${period}" -gt 0 ]]; then
      w=$((quota / period))
    fi
  fi
  if [[ -z "${w}" && -f /sys/fs/cgroup/cpuset.cpus.effective ]]; then
    cpus=$(tr -d '[:space:]' </sys/fs/cgroup/cpuset.cpus.effective)
    w=0
    IFS=',' read -ra parts <<<"${cpus}"
    for p in "${parts[@]}"; do
      if [[ "${p}" == *-* ]]; then a=${p%-*}; b=${p#*-}; w=$((w + b - a + 1)); else w=$((w + 1)); fi
    done
  fi
  echo "cgroup_workers_inline=${w:-?}"
fi
echo "=== MEM / DISK ==="
free -h | head -2
df -h /workspace | tail -1
echo "=== TORCH ==="
python - <<'PY'
import torch
print("torch", torch.__version__)
print("cuda", torch.cuda.is_available(), torch.version.cuda)
if torch.cuda.is_available():
    print("device", torch.cuda.get_device_name(0))
    print("vram_gb", round(torch.cuda.get_device_properties(0).total_memory / 1e9, 1))
PY
EOF
