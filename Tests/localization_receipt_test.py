"""The capture receipt must be consumable without a simulator or real account."""
import hashlib
import importlib.util
import json
from pathlib import Path

import pytest

SPEC = importlib.util.spec_from_file_location(
    "wrongbook_localization_shots", Path(__file__).resolve().parents[1] / "scripts/media/localization_shots.py")
capture = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capture)


def report(tmp_path):
    screens = {}
    for language in capture.LANGUAGES:
        screens[language] = {}
        for name, _ in capture.SCREENS:
            path = tmp_path / language / (name + ".png")
            path.parent.mkdir(exist_ok=True)
            path.write_bytes(b"fixture image bytes")
            screens[language][name] = {
                "path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
    return {"screens": screens}


def test_receipt_indexes_both_languages_with_current_binding(tmp_path):
    value = report(tmp_path)
    capture.bind_screenshots(value, tmp_path, "current", "current")
    assert value["input_sha256"] == "current"
    assert value["screenshots"] == {
        lang: [f"{lang}/{name}.png" for name, _ in capture.SCREENS] for lang in capture.LANGUAGES}


def test_shared_acceptor_reads_capture_contract(tmp_path):
    from PIL import Image
    import localization

    out = tmp_path / "perf/acceptance/l10n"
    out.mkdir(parents=True)
    value = report(out)
    for screens in value["screens"].values():
        for shot in screens.values():
            path = Path(shot["path"])
            Image.new("RGB", (4, 4), "white").save(path)
            shot["sha256"] = capture.sha(path)
    capture.bind_screenshots(value, out, "current", "current")
    value.update(ok=True, status="captured")
    (out / "result.json").write_text(json.dumps(value))
    shots, missing, stale = localization._screenshots(tmp_path, "current")
    assert shots["current_binding"] and not missing and not stale
    _, _, stale = localization._screenshots(tmp_path, "changed")
    assert stale


@pytest.mark.parametrize("failure", ["source", "image", "outside"])
def test_changed_or_uncontained_capture_cannot_publish_binding(tmp_path, failure):
    value = report(tmp_path)
    shot = value["screens"]["en"]["login"]
    if failure == "image":
        Path(shot["path"]).write_bytes(b"changed")
    if failure == "outside":
        shot["path"] = str(tmp_path.parent / "outside.png")
    with pytest.raises(capture.sim_lane.LaneError):
        capture.bind_screenshots(value, tmp_path, "before", "after" if failure == "source" else "before")
    assert "input_sha256" not in value
    assert "screenshots" not in value
