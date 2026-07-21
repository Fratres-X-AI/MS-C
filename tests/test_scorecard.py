from models.optimizer import optimize_pattern
from models.scenes import SITE_CLASSES
from models.scorecard import build_scorecard


def test_scorecard_honesty_and_sites():
    results = [optimize_pattern(sc, seed=2, steps=8, size=128) for sc in SITE_CLASSES]
    card = build_scorecard(results)
    assert card["summary"]["evidence_class"] == "digital_surrogate_unvalidated"
    assert set(card["by_site"]) == set(SITE_CLASSES)
    assert "adversarial" in card["by_site"]["substation"]
