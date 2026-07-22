#!/usr/bin/env bash
# Wrap burn + pull artifacts. Git Bash ONLY.
# Usage: bash scripts/_fire_wrap.sh HOST PORT
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?}"
PORT="${2:?}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH=(ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=45 -i "$KEY" -p "$PORT" "root@$HOST")
SCP=(scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=45 -i "$KEY" -P "$PORT")

sed -i 's/\r$//' scripts/_pod_wrap.sh
"${SCP[@]}" scripts/_pod_wrap.sh "root@$HOST:/tmp/_pod_wrap.sh"
echo "[wrap] remote finalize"
"${SSH[@]}" 'sed -i "s/\r$//" /tmp/_pod_wrap.sh && bash /tmp/_pod_wrap.sh'

mkdir -p analysis/results/runs
echo "[pull] fetching tarball"
"${SCP[@]}" "root@$HOST:/tmp/msc_sota_pull.tgz" /tmp/msc_sota_pull.tgz
rm -rf /tmp/msc_pull_extract
mkdir -p /tmp/msc_pull_extract
tar xzf /tmp/msc_sota_pull.tgz -C /tmp/msc_pull_extract

# Layout may be sota_max/ at top or nested under analysis/...
if [[ -d /tmp/msc_pull_extract/analysis/results/runs/sota_max ]]; then
  SRC=/tmp/msc_pull_extract/analysis/results/runs
elif [[ -d /tmp/msc_pull_extract/sota_max ]]; then
  SRC=/tmp/msc_pull_extract
else
  SRC=/tmp/msc_pull_extract
  find /tmp/msc_pull_extract -maxdepth 3 -type d -name sota_max -print
fi

rm -rf analysis/results/runs/sota_max
mkdir -p analysis/results/runs
if [[ -d "${SRC}/sota_max" ]]; then
  cp -a "${SRC}/sota_max" analysis/results/runs/
fi
mkdir -p analysis/results/runs/site_detector
if [[ -d "${SRC}/site_detector" ]]; then
  cp -f "${SRC}/site_detector"/*.pt analysis/results/runs/site_detector/ 2>/dev/null || true
  cp -f "${SRC}/site_detector"/*.json analysis/results/runs/site_detector/ 2>/dev/null || true
fi

echo "[pull] local artifacts:"
ls -lah analysis/results/runs/sota_max/ 2>/dev/null | head -40 || echo "NO sota_max"
ls -lah analysis/results/runs/site_detector/*.pt 2>/dev/null | head -20 || echo "NO weights"
if [[ -f analysis/results/runs/sota_max/SOTA_REPORT.json ]]; then
  echo "==== SOTA_REPORT ===="
  cat analysis/results/runs/sota_max/SOTA_REPORT.json
else
  echo "SOTA_REPORT MISSING"
fi

echo
echo "[wrap] SAFE TO TERMINATE RUNPOD POD"
echo "[wrap] local path: analysis/results/runs/sota_max/"
