#!/usr/bin/env bash
set +e
pkill -9 -f _pod_sota_max 2>/dev/null
pkill -9 -f 'concurrent.futures' 2>/dev/null
# kill non-jupyter python burn leftovers carefully
for pid in $(pgrep -f 'python -' || true); do
  cmd=$(ps -p "$pid" -o args= 2>/dev/null || true)
  case "$cmd" in
    *jupyter*) ;;
    *) kill -9 "$pid" 2>/dev/null || true ;;
  esac
done
sleep 2
echo "--- procs ---"
ps aux | grep python | grep -v grep || echo NO_PYTHON
echo "--- gpu ---"
nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader
echo IDLE_CHECK_DONE
