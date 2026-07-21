# Reproduce — MS-C Mantle

## Laptop gate (~30 s)

```bash
python -m pip install -e ".[dev]"
python -m sim.reproduce --validate-only
# or full regenerate + compare:
python -m sim.reproduce
```

`--validate-only` checks golden checksums and scorecard invariants without
rewriting kit tiles.

## Full short optimize (CPU)

```bash
python -m sim.run_optimize --preset laptop --steps 40
```

## What is locked

| Artifact | Path |
|----------|------|
| Golden scorecard | `analysis/results/golden/scorecard.json` |
| Golden kit manifest | `analysis/results/golden/kit_manifest.json` |
| Reproduce manifest | `analysis/results/golden/reproduce_manifest.json` |

## What is not claimed

Digital confidence collapse ≠ physical UAS defeat. Surrogate detectors and
literature-bounded emissivity tables are planning tools only.
