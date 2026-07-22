#!/usr/bin/env bash
# Git Bash entrypoint — probe then fire PRO 6000 max burn.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
HOST="${1:-205.196.144.74}"
PORT="${2:-11754}"
MINUTES="${3:-360}"
sed -i 's/\r$//' scripts/*.sh 2>/dev/null || true
bash scripts/_probe_pod.sh "$HOST" "$PORT"
bash scripts/_fire_pro6000.sh "$HOST" "$PORT" "$MINUTES"
sleep 8
bash scripts/_pod_tick.sh "$HOST" "$PORT"
