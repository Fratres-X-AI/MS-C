# MS-C Mantle — Site-Deployable Adversarial Camouflage

**Persistent VIS + IR deception kits for critical sites · Fratres X AI**

**MS-C Mantle** designs **manufacturable** visual / thermal pattern kits (nets,
coatings, tile sheets) that degrade Group 1–2 UAS EO/IR detectors on substations,
pads, and pipeline corridors — the **passive DENY** layer beside active dazzle
and transient obscuration.

**Status:** Preliminary Design + digital prototype · **Version:** 0.1.0  
**Repository:** https://github.com/Fratres-X-AI/MS-C *(private)*

> **Maturity banner:** Preliminary Design · Digital **PASS** (G-DIG) · Physical print/IR **OPEN** · Field **BLOCKED** · Tier T1  
> **Stack handoff:** Desktop `Fratres_Homeland_KillWeb_Handoff/` · Wicked-Web `docs/STACK_HANDOFF/`  
> **Print path:** [docs/PRINT_SOW_COUPON_CAMPAIGN.md](docs/PRINT_SOW_COUPON_CAMPAIGN.md)

> **Reviewers start here:** [Executive brief](docs/00-executive-brief.md) →
> [Stakeholder one-pager](docs/STAKEHOLDER_ONE_PAGER.md) →
> [Idea defense](docs/IDEA_DEFENSE_BRIEF.md) →
> [Verification matrix](rtm/verification_matrix.md)

> **Conceptual design — NOT validation.** Digital surrogate MoE only.  
> **Not a laser.** Not an obscurant grenade. Not a fielded stealth system.  
> **Placed by** partner survey tools; **audited by** Wicked Web — not a siting product.

---

## Kill-Web slot

```
Detect → MS-C Mantle (passive persistent deny)
      → MS-V Veil (transient VIS+IR obscure)
      → MPL-D (directed NIR dazzle)
      → MFKS / RADR (kinetic)
```

| Sibling | Role | Persistence |
|---------|------|-------------|
| **[MPL-D](https://github.com/Fratres-X-AI/MPL-D)** | Multi-point laser EO sensor denial | Pulse |
| **[MS-V](https://github.com/Fratres-X-AI/MS-V)** | Multispectral obscurant grenade (Veil) | ~120 s |
| **MS-C Mantle** *(this repo)* | Adversarial site camo / pattern kits | Persistent |

**Tour line:** MPL-D dazzles · MS-V obscures · **MS-C Mantle denies EO/IR eyes on the site itself.**

---

## Allowed one-liner

> MS-C Mantle is a Preliminary Design + digital prototype for manufacturable
> VIS/IR adversarial pattern kits that degrade Group 1–2 UAS EO/IR detectors on
> critical sites — not a fielded stealth system and not a laser effector.

Anything stronger is out of bounds until physical print / IR bench gates close.

---

## Program gates

| Gate | Status | Meaning |
|------|--------|---------|
| **G-DOC** | **PASS** (this package) | Reviewable concept + digital evidence path |
| **G-DIG** | **PASS** (fixture / golden) | Laptop reproduce + unit tests |
| **G-PRINT** | **OPEN** | Physical tile print durability untested |
| **G-IR** | **OPEN** | LWIR chamber / FLIR validation not started |
| **G-FIELD** | **BLOCKED** | No site install authorization |

Detail: [`docs/phase0_gate_status.md`](docs/phase0_gate_status.md)

---

## Quick start

```bash
python -m pip install -e ".[dev]"
make check
# Windows: .\scripts\check.ps1
```

Optional demo UI:

```bash
python -m pip install -e ".[dev,demo]"
python -m demo.app
```

Optional YOLO GPU optimize: see [`RUNPOD.md`](RUNPOD.md).

---

## Digital evidence (honest bounds)

Laptop gate runs a **CPU surrogate detector** (contrast / edge / thermal proxy)
on synthetic site fixtures. Results are **planning MoE**, not UAS defeat rates.

| Metric (digital) | Nominal stack | Adversarial view/light stack |
|------------------|---------------|------------------------------|
| Mean confidence collapse vs uncovered | See golden scorecard | Lower margin by design |
| Transfer to held-out views | Reported | Not saturated |

Golden artifacts: [`analysis/results/golden/`](analysis/results/golden/)

---

## Document map

| Doc | Topic |
|-----|--------|
| [00-executive-brief](docs/00-executive-brief.md) | One-page concept |
| [STAKEHOLDER_ONE_PAGER](docs/STAKEHOLDER_ONE_PAGER.md) | External send sheet |
| [IDEA_DEFENSE_BRIEF](docs/IDEA_DEFENSE_BRIEF.md) | Attack → honest response |
| [SOTA_PASS_1](docs/SOTA_PASS_1.md) | Public research positioning |
| [CONOPS_HOMELAND](docs/CONOPS_HOMELAND.md) | Site install / refresh |
| [KILLWEB_INTERFACE_NOTE](docs/KILLWEB_INTERFACE_NOTE.md) | Passive layer ICD |
| [LAYERED_STACK](docs/LAYERED_STACK.md) | Mantle ≠ Veil ≠ MPL-D |
| [REQUIREMENTS](docs/REQUIREMENTS.md) | REQ list |
| [RISK_REGISTER](docs/RISK_REGISTER.md) | Residual risks |
| [EXPORT_CONTROL_SCREENING](docs/EXPORT_CONTROL_SCREENING.md) | Screening stub |

---

## Layout

| Path | Role |
|------|------|
| `models/` | Scenes, materials, dual-band renderer, optimizer, detectors |
| `sim/` | Reproduce, optimize CLI, scorecard, kit export |
| `data/` | Seedable synthetic site fixtures |
| `rtm/` | Verification matrix |
| `analysis/` | Golden evidence + run outputs |
| `demo/` | Gradio tour UI |
| `tests/` | Unit + invariant tests |

---

## Non-goals (v1)

- No laser / dazzler physics → **MPL-D**
- No obscurant plume M&S → **MS-V**
- No 3DGS full-site reconstruction (Phase-1 stretch)
- No physical IR chamber claims; BOM is planning-only

---

*Fratres X AI | Defense Projects — Prototype Documentation · MS-C Mantle*  
*All digital MoE outputs are notional; not authorization to procure, manufacture, export, or field.*
