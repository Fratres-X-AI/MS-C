#!/usr/bin/env bash
# Git Bash ONLY.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:?}"
PORT="${2:?}"
KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
sed -i 's/\r$//' scripts/_pod_kill_relaunch_abuse.sh scripts/_pod_sota_abuse.sh
scp -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i "$KEY" -P "$PORT" \
  scripts/_pod_kill_relaunch_abuse.sh scripts/_pod_sota_abuse.sh models/joint_attack.py \
  "root@${HOST}:/tmp/"
ssh -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -i "$KEY" -p "$PORT" "root@${HOST}" \
  'cp /tmp/_pod_sota_abuse.sh /workspace/MS-C/scripts/_pod_sota_abuse.sh; \
   cp /tmp/joint_attack.py /workspace/MS-C/models/joint_attack.py; \
   sed -i "s/\r$//" /workspace/MS-C/scripts/*.sh /tmp/_pod_kill_relaunch_abuse.sh; \
   bash /tmp/_pod_kill_relaunch_abuse.sh'
