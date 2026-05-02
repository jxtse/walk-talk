import io
from pathlib import Path
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient


def _client(tmp_path, monkeypatch):
    monkeypatch.setenv("AMAP_KEY", "ak")
    monkeypatch.setenv("OPENAI_NEXT_API_KEY", "sk")
    monkeypatch.setenv("PLANNER_BASE_URL", "http://x:1")
    cache = tmp_path / "demo_runtime" / "cache" / "images"
    cache.mkdir(parents=True)
    for img_id in ["jiming_temple_card", "companion_keepsake",
                   "beans_solo_storefront", "beans_solo_interior",
                   "serendipity_keepsake"]:
        (cache / f"{img_id}.png").write_bytes(b"fake")
    monkeypatch.chdir(tmp_path)

    with patch("demo.server.CameraController") as Cam, \
         patch("demo.server.LLMClient") as LLM, \
         patch("demo.server.TTSService") as TTS, \
         patch("demo.server.MediaClient") as Media, \
         patch("demo.server.AmapClient"):
        Media.return_value.transcribe.return_value = "你好"
        Cam.return_value.mjpeg_iter.return_value = iter([])
        from demo import server
        return TestClient(server.app), Media


def test_voice_route_calls_whisper(tmp_path, monkeypatch):
    client, Media = _client(tmp_path, monkeypatch)
    r = client.post("/api/voice",
                    files={"audio": ("a.webm", b"\x00\x01", "audio/webm")})
    assert r.status_code == 200
    assert r.json() == {"text": "你好"}
    Media.return_value.transcribe.assert_called_once()


def test_poi_image_route(tmp_path, monkeypatch):
    client, _ = _client(tmp_path, monkeypatch)
    r = client.get("/poi_image/beans_solo_storefront.png")
    assert r.status_code == 200
    assert r.content == b"fake"


def test_poi_image_404(tmp_path, monkeypatch):
    client, _ = _client(tmp_path, monkeypatch)
    r = client.get("/poi_image/nonexistent.png")
    assert r.status_code == 404


def test_script_start_stop(tmp_path, monkeypatch):
    client, _ = _client(tmp_path, monkeypatch)
    r = client.post("/api/script/start", json={"scenario": "companion"})
    assert r.status_code == 200
    r2 = client.post("/api/script/stop")
    assert r2.status_code == 200


def test_script_start_unknown_scenario(tmp_path, monkeypatch):
    client, _ = _client(tmp_path, monkeypatch)
    r = client.post("/api/script/start", json={"scenario": "nope"})
    assert r.status_code == 400


def test_camera_set_position_emits_ptz_event(tmp_path, monkeypatch):
    client, _ = _client(tmp_path, monkeypatch)
    from demo import server
    # Configure mocked camera's underlying set_position to return a Position-like
    fake_pos = MagicMock(pan=10, tilt=20, zoom=100)
    # The wrapped set_position is what's installed on server.camera.
    # Underneath it calls the original (mock) which returns whatever we set.
    # Re-invoke wrapped via a fresh mock on the original-bound captured fn:
    # easiest: just call server.camera.set_position and ensure publish is hit.
    published = []
    server.event_bus.publish = lambda ev: published.append(ev)
    # The original captured by closure is the mock at install time; configure
    # its return value retroactively:
    server.camera.set_position(pan=10, tilt=20, zoom=100)
    ptz_events = [e for e in published if e.get("type") == "ptz"]
    assert len(ptz_events) == 1
