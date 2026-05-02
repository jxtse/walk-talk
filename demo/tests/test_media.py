# demo/tests/test_media.py
import base64
from pathlib import Path
from unittest.mock import MagicMock
import pytest
from demo.media import MediaClient


_PNG_1x1 = base64.b64decode(
    b"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNg"
    b"AAIAAAUAAeImBZsAAAAASUVORK5CYII=")


def _client_with(post_response):
    fake_resp = MagicMock()
    fake_resp.json.return_value = post_response
    fake_resp.raise_for_status.return_value = None
    fake_http = MagicMock()
    fake_http.post.return_value = fake_resp
    return MediaClient(api_key="sk_test", http=fake_http), fake_http


def test_generate_image_writes_png(tmp_path: Path):
    b64 = base64.b64encode(_PNG_1x1).decode()
    c, http = _client_with({"data": [{"b64_json": b64}]})
    out = tmp_path / "x.png"
    result = c.generate_image(prompt="a cat", size="1024x1024", save_to=out)
    assert result == out
    assert out.exists()
    assert out.read_bytes() == _PNG_1x1
    call = http.post.call_args
    assert call.args[0].endswith("/v1/images/generations")
    body = call.kwargs["json"]
    assert body["prompt"] == "a cat"
    assert body["size"] == "1024x1024"
    assert body["model"] == "gemini-3.1-flash-image-preview"
    assert body["response_format"] == "b64_json"


def test_generate_image_raises_when_no_data(tmp_path):
    c, _ = _client_with({"data": []})
    with pytest.raises(RuntimeError, match="no image"):
        c.generate_image(prompt="x", size="1024x1024",
                         save_to=tmp_path / "y.png")


def test_transcribe_returns_text():
    c, http = _client_with({"text": "你好世界"})
    text = c.transcribe(audio_bytes=b"\x00\x01", mime="audio/webm")
    assert text == "你好世界"
    call = http.post.call_args
    assert call.args[0].endswith("/v1/audio/transcriptions")
    files = call.kwargs["files"]
    assert "file" in files
    assert files["file"][2] == "audio/webm"
    data = call.kwargs["data"]
    assert data["model"] == "whisper-1"
    assert data["language"] == "zh"


def test_transcribe_returns_empty_when_missing():
    c, _ = _client_with({})
    assert c.transcribe(audio_bytes=b"\x00", mime="audio/webm") == ""
