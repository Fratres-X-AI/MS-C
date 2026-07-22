#!/usr/bin/env bash
# Remote: hard-kill stalled pool, relaunch abuse. Invoked via SSH.
set -euo pipefail
ps -eo pid,cmd | grep -E 'python|_pod_sota' | grep -v grep | grep -v jupyter || true
pkill -9 -f '_pod_sota' 2>/dev/null || true
sleep 1
# Kill non-jupyter python burn workers (venv + bare python -)
ps -eo pid,cmd | while read -r pid cmd; do
  case "${cmd}" in
    *jupyter*) continue ;;
    *python*)
      kill -9 "${pid}" 2>/dev/null || true
      ;;
  esac
done
sleep 2
nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader || true
ps -eo pid,cmd | grep -E 'python|_pod_sota' | grep -v grep | head -20 || echo CLEARED

export MSC_BURN_MINUTES=300
export MSC_IMGSZ=640
export MSC_ATTACK_SIZE=640
export MSC_BATCH=128
export MSC_YOLO_MODEL=yolov8m.pt

nohup bash /workspace/MS-C/scripts/_pod_sota_abuse.sh > /workspace/logs/msc_sota_abuse.log 2>&1 &
echo $! > /workspace/logs/msc_sota_abuse.pid
ln -sf /workspace/logs/msc_sota_abuse.log /workspace/logs/msc_sota_burn.log
ln -sf /workspace/logs/msc_sota_abuse.log /workspace/logs/msc_sota_max.log
sleep 6
echo "pid=$(cat /workspace/logs/msc_sota_abuse.pid)"
tail -n 40 /workspace/logs/msc_sota_abuse.log || true
nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader || true
ps aux | grep -E '_pod_sota_abuse|python' | grep -v grep | head -15 || true
