# demo/xhs.py
"""小红书子进程封装：通过 xiaohongshu-cli (`xhs`) 搜索/读取笔记。

特点：
- 缺失 / 超时 / 异常都不抛，统一返回结构 {"available": bool, "items": [...]}。
- 解析逻辑参考 Agent-Reach 仓库 agent_reach/channels/xiaohongshu.py 的清洗规则
  （只保留 title/desc/images/url/liked_count，避免把整坨 raw 灌给 LLM）。

依赖：
- pipx install xiaohongshu-cli && xhs login
- 在 .env 里设 XHS_CLI=/path/to/xhs，或留空让我们 shutil.which("xhs")。
"""
from __future__ import annotations
import json
import shutil
import subprocess
from typing import Any


def _clean_note(note: Any) -> dict:
    if not isinstance(note, dict):
        return {}
    inner = note.get("note_card") or note.get("note") or note
    out: dict[str, Any] = {}
    for k in ("id", "note_id", "title", "desc", "type", "url"):
        if k in inner:
            out[k] = inner[k]
    if "content" in inner and "desc" not in out:
        out["desc"] = inner["content"]
    user = inner.get("user") or inner.get("author")
    if isinstance(user, dict):
        nick = user.get("nickname") or user.get("nick_name")
        if nick:
            out["nickname"] = nick
    interact = (inner.get("interact_info")
                or inner.get("note_interact_info") or {})
    src = interact if isinstance(interact, dict) else {}
    for k in ("liked_count", "collected_count",
              "comment_count", "share_count"):
        if k in src:
            out[k] = src[k]
        elif k in inner:
            out[k] = inner[k]
    images = inner.get("image_list") or inner.get("images_list") or []
    if isinstance(images, list):
        urls: list[str] = []
        for img in images:
            if isinstance(img, dict):
                u = img.get("url") or img.get("url_default") or img.get("original")
                if u:
                    urls.append(u)
            elif isinstance(img, str):
                urls.append(img)
        if urls:
            out["images"] = urls
    return out


def _normalize_payload(raw: Any) -> list[dict]:
    """xhs CLI 返回可能是 list / {items:[...]} / {data:{items:[...]}} / 单条 note。"""
    if isinstance(raw, list):
        return [_clean_note(x) for x in raw]
    if isinstance(raw, dict):
        for key in ("items", "notes"):
            if isinstance(raw.get(key), list):
                return [_clean_note(x) for x in raw[key]]
        data = raw.get("data")
        if isinstance(data, dict):
            for key in ("items", "notes"):
                if isinstance(data.get(key), list):
                    return [_clean_note(x) for x in data[key]]
        cleaned = _clean_note(raw)
        return [cleaned] if cleaned else []
    return []


class XhsClient:
    """缺 xhs CLI 时退化为永远不可用，调用方自然降级。"""

    def __init__(self, *, xhs_path: str | None = None,
                 timeout: float = 15.0) -> None:
        self._path = xhs_path or shutil.which("xhs")
        self._timeout = timeout

    @property
    def available(self) -> bool:
        return bool(self._path)

    def _run(self, args: list[str]) -> dict | list | None:
        if not self._path:
            return None
        try:
            r = subprocess.run(
                [self._path, *args, "--json"],
                capture_output=True, text=True, encoding="utf-8",
                errors="replace", timeout=self._timeout,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
            return None
        out = (r.stdout or "").strip()
        if not out:
            return None
        try:
            return json.loads(out)
        except json.JSONDecodeError:
            # 部分子命令首行是 banner，截掉非 JSON 前缀
            for marker in ("{", "["):
                idx = out.find(marker)
                if idx >= 0:
                    try:
                        return json.loads(out[idx:])
                    except json.JSONDecodeError:
                        continue
            return None

    def search(self, *, query: str, limit: int = 5) -> dict:
        if not self.available:
            return {"available": False, "items": [],
                    "hint": "xhs CLI 未安装"}
        raw = self._run(["search", query])
        items = _normalize_payload(raw)[:limit]
        return {"available": True, "items": items}

    def read(self, *, note_url_or_id: str) -> dict:
        if not self.available:
            return {"available": False, "note": None,
                    "hint": "xhs CLI 未安装"}
        raw = self._run(["read", note_url_or_id])
        items = _normalize_payload(raw)
        return {"available": True, "note": items[0] if items else None}
