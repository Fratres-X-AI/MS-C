# Idea Defense Brief — MS-C Mantle

**Document ID:** MS-C-IDF-001  
**Maturity:** Concept / Preliminary Design argument map. **Not performance evidence.**

**Rule:** Prefer “we don’t know yet” over invented confidence.

---

## 1. One-sentence claim (allowed)

> MS-C Mantle is a Preliminary Design + digital prototype for manufacturable
> VIS/IR adversarial pattern kits that degrade Group 1–2 UAS EO/IR detectors on
> critical sites — not a fielded stealth system and not a laser effector.

---

## 2. Why the idea is still rational

| Pillar | Argument | Evidence class |
|--------|----------|----------------|
| **Layer exists in research** | Physical adversarial camouflage against detectors is an active CV literature (CNCA, PGA, dual-band IR patches) | Public papers — not our field data |
| **Homeland gap** | Soft sites need persistent deny when smoke/dazzle are off | Stakeholder language — not market proof |
| **Complementarity** | Mantle ≠ Veil ≠ MPL-D — different time constants and failure modes | Architecture docs |
| **Manufacturability first** | Tileable, palette-quantized patterns beat unconstrained adversarial noise for nets/print | Optimizer constraints — unvalidated in field |
| **Auditability** | Repo admits OPEN physical gates | This TDP |

---

## 3. Attack → response matrix

| # | Attack | Honest response | Status |
|---|--------|-----------------|--------|
| A1 | Prove detectors fail outdoors | We haven’t. Digital surrogate only; G-PRINT / G-IR OPEN. | **Open** |
| A2 | Adversarial patterns look crazy | We constrain palette, tiling, spatial frequency for print/net weave. Naturalness vs ASR trade is explicit. | **Bounded** |
| A3 | Thermal cameras ignore paint | Dual-band stack includes emissivity-layer materials table (literature bounds). Not FLIR-validated. | **Open** |
| A4 | Adaptive AI will retrain | Transfer / adaptive threat is residual risk; refresh cycle is CONOPS, not magic. | **Open** |
| A5 | Just use commercial camo nets | Commercial camo is baseline in scorecard; Mantle targets detector MoE under manufacturability constraints. | **Positioning** |
| A6 | Export / ITAR poison | Screening stub only; no ruling. Counsel before partner data exchange. | **Open (process)** |
| A7 | Incomplete Kill-Web | By design: **passive layer**. C2 audits coverage; escalate when lock persists. | **Bounded** |
| A8 | Paper theater | Docs can be mature while materials are not. Engagement is for **direction**. | **Meta — accepted** |

---

## 4. Kill criteria (would falsify the idea)

1. Physical print + IR bench shows **no** measurable detector degradation vs commercial camo under agreed surrogates.  
2. Manufacturable constraints make digital ASR collapse to noise-level.  
3. Site owners reject any visual change even with strong digital MoE.

---

## 5. Related

[`STAKEHOLDER_ONE_PAGER.md`](STAKEHOLDER_ONE_PAGER.md) · [`SOTA_PASS_1.md`](SOTA_PASS_1.md) · [`LAYERED_STACK.md`](LAYERED_STACK.md)
