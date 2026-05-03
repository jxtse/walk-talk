# demo/tests/test_server_location.py
"""/api/location 更新后下次工具读到新坐标。

注意：demo.server._init_singletons 只跑一次，因此每个用例都按
test_server_v2 的方式 patch 重型依赖。
"""
from unittest.mock import patch
from fastapi.testclient import TestClient


def _client(tmp_path, monkeypatch):
    monkeypatch.setenv("AMAP_KEY", "ak")
    monkeypatch.setenv("OPENAI_NEXT_API_KEY", "sk")
    monkeypatch.setenv("PLANNER_BASE_URL", "http://x:1")
    cache = tmp_path / "demo_runtime" / "cache" / "images"
    cache.mkdir(parents=True)
    monkeypatch.chdir(tmp_path)
    with patch("demo.server.CameraController") as Cam, \
         patch("demo.server.LLMClient"), \
         patch("demo.server.TTSService"), \
         patch("demo.server.MediaClient") as Media, \
         patch("demo.server.AmapClient"):
        Cam.return_value.mjpeg_iter.return_value = iter([])
        # Singleton MediaClient is shared across tests (init runs once);
        # mirror test_server_v2's transcribe mock so order doesn't matter.
        Media.return_value.transcribe.return_value = "你好"
        from demo import server
        return TestClient(server.app), server


def test_location_get_returns_default(tmp_path, monkeypatch):
    client, _ = _client(tmp_path, monkeypatch)
    r = client.get("/api/location")
    assert r.status_code == 200
    assert "," in r.json()["location"]


def test_location_post_updates_state(tmp_path, monkeypatch):
    client, server = _client(tmp_path, monkeypatch)
    r = client.post("/api/location",
                    json={"lng": 121.490, "lat": 31.235})
    assert r.status_code == 200
    assert r.json()["location"].startswith("121.49")
    assert client.get("/api/location").json()["location"].startswith("121.49")
    assert server.get_current_location().startswith("121.49")


def test_location_post_validates(tmp_path, monkeypatch):
    client, _ = _client(tmp_path, monkeypatch)
    r = client.post("/api/location", json={"foo": "bar"})
    assert r.status_code == 400


def test_location_string_form_accepted(tmp_path, monkeypatch):
    client, _ = _client(tmp_path, monkeypatch)
    r = client.post("/api/location", json={"location": "120.10,30.30"})
    assert r.status_code == 200
    assert r.json()["location"] == "120.10,30.30"
