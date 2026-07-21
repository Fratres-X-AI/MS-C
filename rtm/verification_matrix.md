# Verification Matrix — MS-C Mantle

**Document ID:** MS-C-RTM-001 · **Rule:** Digital PASS ≠ physical PASS

| REQ | Verification | Method | Status |
|-----|--------------|--------|--------|
| REQ-M-001 | Tile kits for 3 site classes | `models.scenes` + optimize/export | **DIGITAL PASS** |
| REQ-M-002 | Emissivity layer in manifest | materials table + kit export | **DIGITAL PASS** |
| REQ-M-003 | Palette / tile / freq constraints | optimizer unit tests | **DIGITAL PASS** |
| REQ-M-004 | Baseline scorecard | golden `scorecard.json` | **DIGITAL PASS** |
| REQ-M-005 | Adversarial view/light stack | scorecard `adversarial` block | **DIGITAL PASS** |
| REQ-M-006 | PNG + kit_manifest.json | export + golden manifest | **DIGITAL PASS** |
| REQ-H-001 | Homeland CONOPS | `docs/CONOPS_HOMELAND.md` | **DOC PASS** |
| REQ-H-002 | Kill-Web ICD | `docs/KILLWEB_INTERFACE_NOTE.md` | **DOC PASS** |
| REQ-S-001 | Honesty labels | repo invariant tests | **DIGITAL PASS** |
| REQ-S-002 | Export screening stub | `docs/EXPORT_CONTROL_SCREENING.md` | **DOC PASS** |
| REQ-P-001 | Print durability | physical | **OPEN** |
| REQ-P-002 | FLIR chamber | physical | **OPEN** |
