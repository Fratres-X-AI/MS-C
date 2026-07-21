import numpy as np
from models.constraints import DEFAULT_CONSTRAINTS, project_manufacturable


def test_palette_and_emis_shapes():
    rng = np.random.default_rng(0)
    raw = rng.integers(0, 256, size=(32, 32, 3), dtype=np.uint8)
    rgb, emis = project_manufacturable(raw, DEFAULT_CONSTRAINTS)
    assert rgb.shape == (32, 32, 3)
    assert emis.shape == (32, 32)
    assert emis.min() >= 0.14 and emis.max() <= 0.93


def test_tiling_edges_match():
    rng = np.random.default_rng(1)
    raw = rng.integers(0, 256, size=(32, 32, 3), dtype=np.uint8)
    rgb, _ = project_manufacturable(raw, DEFAULT_CONSTRAINTS)
    assert np.allclose(rgb[0], rgb[-1], atol=2)
    assert np.allclose(rgb[:, 0], rgb[:, -1], atol=2)
