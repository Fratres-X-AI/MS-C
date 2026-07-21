# RunPod — MS-C Mantle (CPU gate + optional GPU)

Laptop may be slow; prefer a cheap RunPod for **all** `make check` + YOLO optimize.

## One-shot fire (Git Bash)

```bash
# CPU gate only
bash scripts/_pod_fire.sh HOST PORT

# CPU gate + YOLO GPU optimize
bash scripts/_pod_fire.sh HOST PORT --gpu
```

Uses `~/.ssh/id_ed25519` (override with `SSH_KEY=...`). Syncs to `/workspace/MS-C`.

## Manual

```bash
cd /workspace/MS-C
python -m pip install -e ".[dev]"          # CPU gate
python -m pytest tests/ -q
python -m sim.reproduce --validate-only

python -m pip install -e ".[dev,yolo]"     # optional GPU
python -m sim.run_optimize --preset gpu --detector yolo --steps 200 \
  --out analysis/results/runs/gpu_pod
```

**Do not** paste GPU scores into README as fielded effectiveness.
Label outputs as digital / unvalidated.
