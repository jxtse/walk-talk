# demo/tests/test_xhs.py
"""XhsClient: 缺失退化、超时、JSON 清洗。"""
import json
import subprocess
from unittest.mock import MagicMock
from demo import xhs as xhs_mod
from demo.xhs import XhsClient, _clean_note, _normalize_payload


def test_unavailable_when_no_path():
    c = XhsClient(xhs_path=None)
    assert c.available is False
    out = c.search(query="任意")
    assert out == {"available": False, "items": [],
                   "hint": "xhs CLI 未安装"}


def test_clean_note_extracts_core_fields():
    note = {
        "id": "n1", "title": "T", "desc": "D",
        "user": {"nickname": "alice"},
        "interact_info": {"liked_count": 99, "comment_count": 7},
        "image_list": [{"url": "u1"}, {"url_default": "u2"}, "u3"],
        "tag_list": [{"name": "tag1"}, "tag2"],
    }
    out = _clean_note(note)
    assert out["id"] == "n1"
    assert out["nickname"] == "alice"
    assert out["liked_count"] == 99
    assert out["images"] == ["u1", "u2", "u3"]


def test_normalize_handles_wrappers():
    assert _normalize_payload({"items": [{"id": "x"}]})[0]["id"] == "x"
    assert _normalize_payload({"data": {"notes": [{"id": "y"}]}})[0]["id"] == "y"
    assert _normalize_payload([{"id": "z"}])[0]["id"] == "z"


def test_search_returns_items_when_subprocess_ok(monkeypatch):
    payload = {"items": [{"id": "n1", "title": "玄武湖", "desc": "好看",
                          "image_list": [{"url": "https://x/1.jpg"}],
                          "interact_info": {"liked_count": 10}}]}
    fake = MagicMock()
    fake.stdout = json.dumps(payload)
    fake.stderr = ""
    monkeypatch.setattr(xhs_mod, "subprocess", MagicMock(
        run=MagicMock(return_value=fake),
        TimeoutExpired=subprocess.TimeoutExpired,
    ))
    c = XhsClient(xhs_path="/fake/xhs")
    out = c.search(query="玄武湖", limit=3)
    assert out["available"] is True
    assert out["items"][0]["title"] == "玄武湖"
    assert out["items"][0]["images"] == ["https://x/1.jpg"]


def test_search_swallows_timeout(monkeypatch):
    def boom(*a, **kw):
        raise subprocess.TimeoutExpired(cmd="xhs", timeout=1)
    monkeypatch.setattr(xhs_mod, "subprocess", MagicMock(
        run=boom, TimeoutExpired=subprocess.TimeoutExpired,
    ))
    c = XhsClient(xhs_path="/fake/xhs")
    out = c.search(query="任意")
    assert out["available"] is True
    assert out["items"] == []


def test_search_handles_garbage_then_json(monkeypatch):
    """xhs 偶尔输出 banner 行+JSON。"""
    fake = MagicMock()
    fake.stdout = "loading...\n[{\"id\":\"q\"}]"
    fake.stderr = ""
    monkeypatch.setattr(xhs_mod, "subprocess", MagicMock(
        run=MagicMock(return_value=fake),
        TimeoutExpired=subprocess.TimeoutExpired,
    ))
    c = XhsClient(xhs_path="/fake/xhs")
    out = c.search(query="q")
    assert out["items"][0]["id"] == "q"
