#!/usr/bin/env bash
# Wrap burn + pull artifacts. Git Bash ONLY.
# Usage: bash scripts/_fire_wrap.sh HOST PORT
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?}"
PORT="${2:?}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH=(ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -p "$PORT" "root@$HOST")
SCP=(scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$KEY" -P "$PORT")

sed -i 's/\r$//' scripts/_pod_wrap.sh
"${SCP[@]}" scripts/_pod_wrap.sh "root@$HOST:/tmp/_pod_wrap.sh"
"${SSH[@]}" 'sed -i "s/\r$//" /tmp/_pod_wrap.sh && bash /tmp/_pod_wrap.sh'

mkdir -p analysis/results/runs
echo "[pull] fetching tarball"
"${SCP[@]}" "root@$HOST:/tmp/msc_sota_pull.tgz" /tmp/msc_sota_pull.tgz
rm -rf /tmp/msc_pull_extract
mkdir -p /tmp/msc_pull_extract
tar xzf /tmp/msc_sota_pull.tgz -C /tmp/msc_pull_extract
# Canonical copy
if [[ -d /tmp/msc_pull_extract/MS-C/analysis/results/runs/sota_2h ]]; then
  rm -rf analysis/results/runs/sota_2h
  mkdir -p analysis/results/runs
  cp -a /tmp/msc_pull_extract/MS-C/analysis/results/runs/sota_2h analysis/results/runs/
  mkdir -p analysis/results/runs/site_detector
  cp -f /tmp/msc_pull_extract/MS-C/analysis/results/runs/site_detector/*.pt analysis/results/runs/site_detector/ 2>/dev/null || true
elif [[ -d /tmp/msc_pull_extract/sota_2h ]]; then
  rm -rf analysis/results/runs/sota_2h
  cp -a /tmp/msc_pull_extract/sota_2h analysis/results/runs/
fi
echo "[pull] local artifacts:"
ls -lah analysis/results/runs/sota_2h/ | head -30
if [[ -f analysis/results/runs/sota_2h/SOTA_REPORT.json ]]; then
  echo "SOTA_REPORT OK"
  cat analysis/results/runs/sota_2h/SOTA_REPORT.json
else
  echo "SOTA_REPORT MISSING"
fi

echo "[wrap] SAFE TO TERMINATE RUNPOD POD"
