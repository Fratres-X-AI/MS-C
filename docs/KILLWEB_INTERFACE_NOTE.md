# Kill-Web Interface Note — Passive Deny Contract

**Document ID:** MS-C-KW-001  
**Maturity:** Concept. Defines what the **site / C2** owns vs what Mantle owns.

---

## 1. Boundary

```
[Site sensors + C2] --audit schedule--> [MS-C Mantle coverage]
                              \-> escalate --> [MS-V / MPL-D / Kinetic]
```

MS-C does **not** detect, classify, dazzle, or throw obscurant. It is a
**passive material / pattern layer**.

---

## 2. Inputs from the Kill-Web (planning)

| Input | Why | If missing |
|-------|-----|------------|
| Coverage map / zones | Which assets get kits | Incomplete deny |
| Audit cadence | When to re-score detector lock | Silent degradation |
| Acceptable visual envelope | Public / owner constraints | Install rejected |
| Escalate policy | Soft layers may fail | Operator decides |

**No arm / pulse permit** — unlike MPL-D. Mantle has no emission state.

---

## 3. Outputs to C2 (planning)

| Output | Meaning |
|--------|---------|
| Kit manifest | Tile IDs, coverage m², material stack |
| Digital MoE scorecard | Planning only — not BDA |
| Audit delta | Confidence / lock rate vs baseline (when measured) |
| Integrity flag | Missing / damaged coverage (manual or future sensor) |

---

## 4. Failure / escalate vignette

1. Audit shows detectors still lock on covered assets.  
2. C2 checks integrity → refresh kit or accept residual.  
3. Active threat → transient obscure (MS-V) and/or dazzle (MPL-D) per ROE.  
4. Persist → kinetic / LE. **No automatic kinetic fire from Mantle.**

---

## 5. Reviewer sound-bite

> We’re a boring passive layer on purpose — nets and coatings with a detector-aware
> pattern tool. The Kill-Web’s brains stay at the site. If the pattern fails, you
> escalate; we don’t pretend to be an effector brick.
