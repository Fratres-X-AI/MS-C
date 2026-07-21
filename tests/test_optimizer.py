from models.optimizer import collapse_ratio, optimize_pattern


def test_optimize_reduces_or_holds_confidence():
    res = optimize_pattern("substation", seed=1, steps=15, size=128)
    assert res.best_score <= res.baseline_score + 1e-6
    assert 0.0 <= res.best_score <= 1.0


def test_collapse_ratio():
    assert collapse_ratio(0.8, 0.4) == 0.5
    assert collapse_ratio(0.0, 0.1) == 0.0
