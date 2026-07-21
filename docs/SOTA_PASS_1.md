# SOTA Pass 1 — Adversarial Site Camouflage (Public Landscape)

**Document ID:** MS-C-SOTA-001 · **Maturity:** Literature survey for positioning  
**Not:** A claim that MS-C exceeds published methods in physical trials.

---

## 1. Problem framing

Deny EO/IR machine eyes on fixed soft targets (substations, pads, corridors)
without lasers or obscurant clouds. Product form: coatings, nets, pattern kits.

---

## 2. Public research clusters (2024–2025)

| Cluster | Representative | Relevance to Mantle |
|---------|----------------|---------------------|
| Natural adv-camo textures | CNCA (diffusion-conditioned vehicle camouflage, NeurIPS 2024) | Naturalness vs ASR trade; we prioritize manufacturable tiles over free pixel art |
| Multi-view physical camo | PGA / 3DGS-driven camouflage (ICCV 2025) | Multi-view robustness goal; **3DGS site recon deferred to Phase 1** |
| Dual-band optical+IR | MAC-style optical + IR patch stacks; HOTCOLD / emissivity blocks | Motivates VIS texture + emissivity layer — our dual-band **surrogate** |
| Detector-family patches | YOLO adversarial patch lineages (incl. archived Camolo) | Ensemble / transfer eval pattern; CI uses CPU surrogate, optional YOLO |

---

## 3. Commercial / inventory baselines (not SOTA ML)

| Baseline | Strength | Gap Mantle studies |
|----------|----------|--------------------|
| Military camo nets | Human/visual blend | Not optimized vs modern detectors; IR often weak |
| Thermal blankets / low-e tarps | IR contrast cut | Often visually conspicuous; not detector-aware patterns |
| Paint schemes | Cheap | Single-band; no adversarial optimize |

Scorecard includes **uncovered**, **commercial-camo proxy**, and **random noise**
baselines so Mantle must beat more than “looks weird.”

---

## 4. Positioning (honest)

| Claim we make | Claim we do **not** make |
|---------------|--------------------------|
| Digital prototype with manufacturability constraints | Physical world ASR matching CNCA/PGA papers |
| Dual-band **surrogate** renderer | FLIR-validated thermal stealth |
| Homeland site CONOPS + Kill-Web ICD | Fielded critical-infrastructure program |

---

## 5. Implications for MS-C v1

1. Ship tileable optimizer + dual-band surrogate first.  
2. Hold 3DGS reconstruction until tile path is solid.  
3. Keep MoE language discriminative (not saturated 100% claims).  
4. Treat YOLO ensemble as optional GPU path, not CI blocker.
