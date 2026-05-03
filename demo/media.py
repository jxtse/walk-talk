# demo/media.py
"""openai-next 媒体客户端：图片生成 + Whisper 语音转写 + 远程图片缓存。

与 demo.llm.LLMClient 完全独立——不同 base_url、不同 key、走公网（trust_env=True）。
"""
from __future__ import annotations
import base64
import hashlib
import re
from pathlib import Path
import httpx

DEFAULT_BASE = "https://api.openai-next.com"
DEFAULT_IMAGE_MODEL = "gemini-3.1-flash-image-preview"
DEFAULT_WHISPER_MODEL = "whisper-1"

_EXT_RE = re.compile(r"\.(png|jpe?g|webp|gif)(?:$|\?)", re.IGNORECASE)


def _ext_for_url(url: str) -> str:
    m = _EXT_RE.search(url)
    if m:
        e = m.group(1).lower()
        return ".jpg" if e == "jpeg" else f".{e}"
    return ".jpg"


def download_to_cache(*, url: str, cache_dir: Path,
                      timeout: float = 15.0,
                      http: httpx.Client | None = None) -> Path:
    """下载远程图片到 cache_dir，按 sha1(url)[:16] + 扩展名命名。

    已存在且非空直接返回；下载失败抛异常（调用方负责降级）。
    """
    cache_dir.mkdir(parents=True, exist_ok=True)
    h = hashlib.sha1(url.encode("utf-8")).hexdigest()[:16]
    target = cache_dir / f"dl_{h}{_ext_for_url(url)}"
    if target.exists() and target.stat().st_size > 0:
        return target
    client = http or httpx.Client(timeout=timeout, trust_env=False,
                                  follow_redirects=True)
    try:
        r = client.get(url)
        r.raise_for_status()
        target.write_bytes(r.content)
    finally:
        if http is None:
            client.close()
    if target.stat().st_size == 0:
        target.unlink(missing_ok=True)
        raise RuntimeError(f"empty image from {url}")
    return target


class MediaClient:
    def __init__(self, *, api_key: str, base_url: str = DEFAULT_BASE,
                 image_model: str = DEFAULT_IMAGE_MODEL,
                 whisper_model: str = DEFAULT_WHISPER_MODEL,
                 timeout: float = 120.0,
                 http: httpx.Client | None = None) -> None:
        self._base = base_url.rstrip("/")
        self._image_model = image_model
        self._whisper_model = whisper_model
        self._http = http or httpx.Client(
            timeout=timeout,
            headers={"authorization": f"Bearer {api_key}"},
            trust_env=True,
        )

    def generate_image(self, *, prompt: str, size: str,
                       save_to: Path) -> Path:
        body = {
            "model": self._image_model,
            "prompt": prompt,
            "size": size,
            "n": 1,
            "response_format": "b64_json",
        }
        r = self._http.post(f"{self._base}/v1/images/generations", json=body)
        r.raise_for_status()
        data = r.json().get("data") or []
        if not data or "b64_json" not in data[0]:
            raise RuntimeError(
                f"no image returned for prompt: {prompt[:60]!r}")
        save_to.parent.mkdir(parents=True, exist_ok=True)
        save_to.write_bytes(base64.b64decode(data[0]["b64_json"]))
        return save_to

    def edit_image(self, *, prompt: str, size: str,
                   image_paths: list[Path], save_to: Path) -> Path:
        """Multi-image edit/restyle via /v1/images/edits.

        image_paths: 1+ reference images (e.g. style ref + base render).
        """
        files = []
        opened = []
        try:
            for p in image_paths:
                fh = open(p, "rb")
                opened.append(fh)
                files.append(("image[]", (Path(p).name, fh, "image/png")))
            data = {
                "model": self._image_model,
                "prompt": prompt,
                "size": size,
                "n": "1",
                "response_format": "b64_json",
            }
            r = self._http.post(
                f"{self._base}/v1/images/edits", files=files, data=data)
            r.raise_for_status()
            payload = r.json()
        finally:
            for fh in opened:
                try:
                    fh.close()
                except Exception:
                    pass
        items = payload.get("data") or []
        if not items or "b64_json" not in items[0]:
            raise RuntimeError(
                f"no image returned for edit prompt: {prompt[:60]!r}")
        save_to.parent.mkdir(parents=True, exist_ok=True)
        save_to.write_bytes(base64.b64decode(items[0]["b64_json"]))
        return save_to

    def generate_image_to_cache(self, *, prompt: str, cache_dir: Path,
                                size: str = "1024x1024") -> Path:
        """按 prompt 哈希命名落盘，已存在直接返回。"""
        cache_dir.mkdir(parents=True, exist_ok=True)
        h = hashlib.sha1(f"{self._image_model}|{size}|{prompt}".encode("utf-8")).hexdigest()[:16]
        target = cache_dir / f"gen_{h}.png"
        if target.exists() and target.stat().st_size > 0:
            return target
        return self.generate_image(prompt=prompt, size=size, save_to=target)

    def transcribe(self, *, audio_bytes: bytes, mime: str) -> str:
        files = {"file": ("audio", audio_bytes, mime)}
        data = {"model": self._whisper_model, "language": "zh"}
        r = self._http.post(
            f"{self._base}/v1/audio/transcriptions",
            files=files, data=data,
        )
        r.raise_for_status()
        return r.json().get("text") or ""
