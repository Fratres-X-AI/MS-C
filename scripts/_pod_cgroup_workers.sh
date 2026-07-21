#!/usr/bin/env bash
# Print real usable CPU worker count from cgroup (not nproc).
set -euo pipefail
workers=""
if [[ -f /sys/fs/cgroup/cpu.max ]]; then
  read -r quota period < /sys/fs/cgroup/cpu.max || true
  if [[ -n "${quota:-}" && "${quota}" != "max" && -n "${period:-}" && "${period}" -gt 0 ]]; then
    workers=$((quota / period))
  fi
fi
if [[ -z "${workers}" && -f /sys/fs/cgroup/cpuset.cpus.effective ]]; then
  cpus=$(tr -d '[:space:]' </sys/fs/cgroup/cpuset.cpus.effective)
  if [[ -n "${cpus}" ]]; then
    workers=0
    IFS=',' read -ra parts <<<"${cpus}"
    for p in "${parts[@]}"; do
      if [[ "${p}" == *-* ]]; then
        a=${p%-*}; b=${p#*-}
        workers=$((workers + b - a + 1))
      else
        workers=$((workers + 1))
      fi
    done
  fi
fi
if [[ -z "${workers}" || "${workers}" -lt 1 ]]; then
  # last-resort: cgroup v1
  if [[ -f /sys/fs/cgroup/cpu/cpu.cfs_quota_us && -f /sys/fs/cgroup/cpu/cpu.cfs_period_us ]]; then
    q=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)
    p=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)
    if [[ "${q}" -gt 0 && "${p}" -gt 0 ]]; then
      workers=$((q / p))
    fi
  fi
fi
if [[ -z "${workers}" || "${workers}" -lt 1 ]]; then
  workers=4
fi
# leave headroom for system
if [[ "${workers}" -gt 2 ]]; then
  workers=$((workers - 1))
fi
echo "${workers}"
