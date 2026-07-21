# Contributing — MS-C Mantle

## Claim discipline

Prefer “we don’t know yet” over invented confidence. Digital evidence is
**surrogate / unvalidated**. Physical IR bench and print durability are **OPEN**.

## Local quality gate

```bash
python -m pip install -e ".[dev]"
make check
# or: .\scripts\check.ps1
```

## Layout

| Path | Role |
|------|------|
| `docs/` | Reviewer-facing TDP docs |
| `sim/` | Reproduce gates, scorecards, kit export |
| `models/` | Scene, materials, renderer, optimizer, detectors |
| `rtm/` | Requirements verification matrix |
| `analysis/` | Golden evidence + run outputs |
| `tests/` | Unit + invariant tests |
| `demo/` | Optional Gradio tour UI |

## Pull requests

Keep PRs small. Update RTM rows when requirements change. Never remove honesty
labels from README or executive brief.
