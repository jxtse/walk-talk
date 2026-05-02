import json
import time
from pathlib import Path
from unittest.mock import MagicMock
import pytest

from demo.scripts_player import ScriptPlayer
from demo.event_bus import EventBus


@pytest.fixture
def fake_deps(tmp_path):
    pois_v2 = {
        "scripted": [
            {"poi_id": "beans_solo", "name": "Beans Solo",
             "location": [118.787, 32.080], "distance_m": 1040,
             "rating": 4.4, "cost": 23.0, "address": "...",
             "tagline": "tag", "image_id": "beans_solo_storefront",
             "alt_image_id": "beans_solo_interior", "typecode": "050500"},
            {"poi_id": "jiming_temple", "name": "鸡鸣寺",
             "location": [118.794, 32.066], "distance_m": 800,
             "rating": 4.6, "cost": None, "address": "...",
             "tagline": "tag2", "image_id": "jiming_temple_card",
             "alt_image_id": None, "typecode": "110200"}
        ],
        "amap_queries": []
    }
    pois_path = tmp_path / "pois_v2.json"
    pois_path.write_text(json.dumps(pois_v2), encoding="utf-8")
    return {
        "dialog": MagicMock(),
        "moments": MagicMock(),
        "camera": MagicMock(),
        "tts": MagicMock(),
        "bus": MagicMock(spec=EventBus),
        "keepsake": MagicMock(),
        "pois_path": pois_path,
    }


def _scenario(tmp_path: Path, events: list[dict]) -> Path:
    p = tmp_path / "s.json"
    p.write_text(json.dumps({
        "scenario_id": "t", "title": "t", "duration_s": 10,
        "events": events,
    }), encoding="utf-8")
    return p


def _make_player(fake_deps, time_warp=100.0):
    return ScriptPlayer(time_warp=time_warp,
                       pois_v2_path=fake_deps["pois_path"],
                       dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                       camera=fake_deps["camera"], tts=fake_deps["tts"],
                       event_bus=fake_deps["bus"],
                       keepsake_render=fake_deps["keepsake"])


def test_dialog_event_appends_and_speaks(fake_deps, tmp_path):
    sp = _make_player(fake_deps)
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "dialog", "role": "ai", "text": "hi", "speak": True}])
    sp.play(s); sp.wait()
    fake_deps["dialog"].append.assert_called_once_with(role="ai", text="hi")
    fake_deps["tts"].say.assert_called_once_with("hi")


def test_user_dialog_does_not_speak(fake_deps, tmp_path):
    sp = _make_player(fake_deps)
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "dialog", "role": "user", "text": "?"}])
    sp.play(s); sp.wait()
    fake_deps["dialog"].append.assert_called_once_with(role="user", text="?")
    fake_deps["tts"].say.assert_not_called()


def test_ptz_calls_camera(fake_deps, tmp_path):
    sp = _make_player(fake_deps)
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "ptz", "pan": -30, "tilt": 0, "zoom": 100,
         "source": "script"}])
    sp.play(s); sp.wait()
    fake_deps["camera"].set_position.assert_called_once_with(
        pan=-30, tilt=0, zoom=100)


def test_ptz_sweep(fake_deps, tmp_path):
    sp = _make_player(fake_deps)
    s = _scenario(tmp_path, [{"at": 0.0, "type": "ptz_sweep"}])
    sp.play(s); sp.wait()
    fake_deps["camera"].sweep.assert_called_once()


def test_poi_card_published_with_full_data(fake_deps, tmp_path):
    sp = _make_player(fake_deps)
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "poi_card", "poi_id": "beans_solo"}])
    sp.play(s); sp.wait()
    ev = fake_deps["bus"].publish.call_args.args[0]
    assert ev["type"] == "poi_card"
    assert ev["poi_id"] == "beans_solo"
    assert ev["name"] == "Beans Solo"
    assert ev["image_url"] == "/poi_image/beans_solo_storefront.png"
    assert ev["distance_m"] == 1040


def test_poi_image_swap_publishes_swap_event(fake_deps, tmp_path):
    sp = _make_player(fake_deps)
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "poi_image_swap",
         "poi_id": "beans_solo", "to_image_id": "beans_solo_interior"}])
    sp.play(s); sp.wait()
    ev = fake_deps["bus"].publish.call_args.args[0]
    assert ev["type"] == "poi_image_swap"
    assert ev["image_url"] == "/poi_image/beans_solo_interior.png"


def test_tool_call_publishes(fake_deps, tmp_path):
    sp = _make_player(fake_deps)
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "tool_call", "name": "pan_camera",
         "args": {"direction": "left"}}])
    sp.play(s); sp.wait()
    ev = fake_deps["bus"].publish.call_args.args[0]
    assert ev["type"] == "tool_call"
    assert ev["name"] == "pan_camera"
    assert ev["args"] == {"direction": "left"}
    assert ev["source"] == "script"


def test_moment_appends(fake_deps, tmp_path):
    sp = _make_player(fake_deps)
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "moment", "label": "记一下"}])
    sp.play(s); sp.wait()
    fake_deps["moments"].append.assert_called_once()


def test_direction_event(fake_deps, tmp_path):
    sp = _make_player(fake_deps)
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "direction", "arrow": "left",
         "distance_m": 100, "eta_min": 1, "label": "去店里"}])
    sp.play(s); sp.wait()
    ev = fake_deps["bus"].publish.call_args.args[0]
    assert ev["type"] == "direction"
    assert ev["arrow"] == "left"


def test_keepsake_render_called(fake_deps, tmp_path):
    sp = _make_player(fake_deps)
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "keepsake_render", "image_id": "companion_keepsake"}])
    sp.play(s); sp.wait()
    fake_deps["keepsake"].assert_called_once_with("companion_keepsake")


def test_stop_aborts_playback(fake_deps, tmp_path):
    sp = _make_player(fake_deps, time_warp=1.0)
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "dialog", "role": "ai", "text": "a"},
        {"at": 5.0, "type": "dialog", "role": "ai", "text": "b"}])
    sp.play(s)
    time.sleep(0.2)
    sp.stop()
    sp.wait()
    appends = [c.kwargs for c in fake_deps["dialog"].append.call_args_list]
    assert {"role": "ai", "text": "a"} in appends
    assert {"role": "ai", "text": "b"} not in appends
