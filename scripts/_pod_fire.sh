#!/usr/bin/env bash
# Laptop → RunPod: sync MS-C, install, run CPU gate + optional GPU YOLO optimize.
# Usage (Git Bash): bash scripts/_pod_fire.sh HOST PORT [--gpu]
# Example: bash scripts/_pod_fire.sh 103.196.86.112 17766 --gpu
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?HOST}"
PORT="${2:?PORT}"
MODE="${3:-}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH=(ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -p "$PORT" "root@$HOST")
SCP=(scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -P "$PORT")

die() { echo "[msc-fire] FATAL: $*" >&2; exit 1; }
[[ -f "$KEY" ]] || die "no SSH key at $KEY"

echo "[msc-fire] pack"
rm -f /tmp/msc.tgz
tar czf /tmp/msc.tgz \
  --exclude='.git' --exclude='.venv' --exclude='__pycache__' \
  --exclude='.mypy_cache' --exclude='.ruff_cache' --exclude='.pytest_cache' \
  --exclude='analysis/results/runs' \
  .

echo "[msc-fire] upload + extract"
"${SCP[@]}" /tmp/msc.tgz "root@$HOST:/tmp/msc.tgz"
"${SSH[@]}" 'bash -s' <<'EOF'
set -euo pipefail
mkdir -p /workspace/MS-C
cd /workspace/MS-C
tar xzf /tmp/msc.tgz
python -m pip install -U pip
python -m pip install -e ".[dev]"
echo "[msc-fire] CPU gate"
python -m ruff check sim models analysis tests demo
python -m mypy
python -m pytest tests/ -q
python -m sim.reproduce --validate-only
echo "[msc-fire] CPU OK"
EOF

if [[ "$MODE" == "--gpu" ]]; then
  echo "[msc-fire] GPU YOLO optimize"
  "${SSH[@]}" 'bash -s' <<'EOF'
set -euo pipefail
cd /workspace/MS-C
python -m pip install -e ".[dev,yolo]"
nvidia-smi || true
python -m sim.run_optimize --preset gpu --detector yolo --steps 200 \
  --out analysis/results/runs/gpu_pod
echo "[msc-fire] GPU OK → analysis/results/runs/gpu_pod"
EOF
fi

echo "[msc-fire] done"
