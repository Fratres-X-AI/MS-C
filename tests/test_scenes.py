from models.scenes import SITE_CLASSES, fixture_bundle, generate_scene


def test_all_site_classes_have_boxes():
    for sc in SITE_CLASSES:
        scene = generate_scene(sc, seed=0, size=128)
        assert scene.rgb.shape == (128, 128, 3)
        assert scene.emissivity.shape == (128, 128)
        assert len(scene.boxes) >= 1


def test_fixture_bundle_count():
    bundle = fixture_bundle(seed=3, size=64)
    assert len(bundle) == len(SITE_CLASSES) * 2
