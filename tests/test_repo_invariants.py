from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_readme_honesty_labels():
    text = (ROOT / "README.md").read_text(encoding="utf-8")
    assert "not a laser" in text.lower() or "Not a laser" in text
    assert "NOT validation" in text or "not validation" in text.lower()
    assert "MPL-D" in text and "MS-V" in text
    assert "Mantle" in text


def test_required_docs_exist():
    required = [
        "docs/00-executive-brief.md",
        "docs/IDEA_DEFENSE_BRIEF.md",
        "docs/SOTA_PASS_1.md",
        "docs/CONOPS_HOMELAND.md",
        "docs/KILLWEB_INTERFACE_NOTE.md",
        "docs/LAYERED_STACK.md",
        "docs/RISK_REGISTER.md",
        "docs/REQUIREMENTS.md",
        "docs/EXPORT_CONTROL_SCREENING.md",
        "docs/phase0_gate_status.md",
        "rtm/verification_matrix.md",
    ]
    for rel in required:
        assert (ROOT / rel).is_file(), rel
