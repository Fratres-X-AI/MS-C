#!/usr/bin/env bash
# Local Git Bash: tick pod every 2 minutes into /tmp/msc_ticks.log
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:-213.192.2.93}"
PORT="${2:-40087}"
LOG="${TMPDIR:-/tmp}/msc_ticks.log"
: > "${LOG}"
while true; do
  {
    echo "==== TICK $(date -u +%H:%M:%SZ) ===="
    bash scripts/_pod_tick.sh "${HOST}" "${PORT}" || echo TICK_FAIL
    echo
  } | tee -a "${LOG}"
  sleep 120
done
