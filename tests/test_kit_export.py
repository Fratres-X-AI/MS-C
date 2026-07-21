from pathlib import Path

from models.kit_export import export_kit
from models.optimizer import optimize_pattern


def test_export_writes_manifest(tmp_path: Path):
    res = [optimize_pattern("tank_pad", seed=0, steps=5, size=128)]
    man = export_kit(res, tmp_path, coverage_m2_per_site=10.0)
    assert (tmp_path / "kit_manifest.json").is_file()
    assert len(man["kits"]) == 1
    assert man["bom_stub"]
    tile = tmp_path / man["kits"][0]["tile_png"]
    assert tile.is_file()
