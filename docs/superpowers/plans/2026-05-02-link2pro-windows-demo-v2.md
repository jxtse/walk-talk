# 本地引力 / 步语 v2 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 v1 已上线基础上新增：AI 主动 PTZ + 真实高德 POI 卡片 + 两个脚本演示场景 + openai-next 媒体 client（图片预生成 + Whisper），并把前端重做成"左 iPhone mock + 右技术面板"。

**Architecture:** 新增 4 个独立模块（`amap.py` / `media.py` / `scripts.py` / `event_bus.py`），把 v1 的 SSE 队列抽到独立 `event_bus`，新增几条 SSE 通道（ptz / tool_call / poi_card / amap_raw / direction / script / llm_raw）。脚本播放器走独立线程，不调 LLM 也不调 Amap（POI 用启动期 prebake 缓存，图片用启动前 CLI 预生成）。前端整页重做，但服务端兼容旧路由。

**Tech Stack:** FastAPI + httpx + 高德 REST + openai-next（gemini-3.1-flash-image-preview / whisper-1）+ MediaRecorder（前端）+ pytest。

**Spec:** `docs/superpowers/specs/2026-05-02-link2pro-windows-demo-v2-design.md`

---

## 文件总览

**新建：**

| 路径 | 职责 |
|---|---|
| `demo/event_bus.py` | 线程安全发布订阅（v1 server.py 里 `_publish` 抽出） |
| `demo/config.py` | 读 `.env` + 暴露 `AMAP_KEY` / `OPENAI_NEXT_API_KEY` / `PLANNER_BASE_URL` |
| `demo/amap.py` | `AmapClient` + `POI` dataclass，调高德并发布 `amap_raw` |
| `demo/media.py` | `MediaClient`（openai-next） — `generate_image` / `transcribe` |
| `demo/scripts_player.py` | `ScriptPlayer` 按时间轴回放事件 |
| `demo/data/scenarios/companion.json` | 场景 A 时间轴 |
| `demo/data/scenarios/serendipity.json` | 场景 B 时间轴 |
| `demo/data/scenarios/prebake.json` | 5 张图的 prompt 清单 |
| `demo/cli/prebake_images.py` | 独立 CLI：拉 gemini 生成 5 张图到缓存 |
| `demo/cli/prebake_pois.py` | 独立 CLI：拉高德 POI 缓存到 `pois_real.json` |
| `demo/tests/test_amap.py` | mock httpx 断 POI 解析 |
| `demo/tests/test_media.py` | mock httpx 断图/语音 |
| `demo/tests/test_scripts_player.py` | 注入假依赖跑场景 A 加速 |
| `demo/tests/test_server_voice.py` | TestClient + mock MediaClient |
| `scripts/smoke_media.py` | 真打一次 gemini + whisper |
| `.env.example` | 三个 key 的占位文件 |

**修改：**

| 路径 | 改动概述 |
|---|---|
| `.gitignore` | 加 `.env`、`demo_runtime/cache/` |
| `demo/requirements.txt` | 加 `python-multipart`（FastAPI 文件上传需要） |
| `demo/server.py` | 接 event_bus / amap / media / scripts_player；加 `/api/voice` `/api/script/start` `/api/script/stop` `/poi_image/{name}`；启动期 prebake 校验 |
| `demo/prompts.py` | SYSTEM_PROMPT 加"主动看"条款 |
| `demo/tools.py` | `PanCameraTool` schema 加必填 `reason` 字段 |
| `demo/agent.py` | 把 `tool_call` 也发到 event_bus |
| `demo/static/index.html` | 整页重做：左 iPhone mock + 右技术面板 |
| `demo/static/app.js` | 重写：按 SSE type 分发，POI 卡片，方向浮条，MediaRecorder |
| `demo/static/styles.css` | **新建**：从 `app.js` 内联样式抽出来 |
| `demo/RUNBOOK.md` | 加 v2 启动序：`prebake_images` → `prebake_pois` → `server` |

---

## 任务列表

共 18 个 task，分成 4 个阶段：

- **阶段 1：基础设施**（Task 1-4）—— config / event_bus / amap / media client
- **阶段 2：图片 & POI 预生成 CLI**（Task 5-6）
- **阶段 3：脚本播放器 + 服务端接入**（Task 7-11）
- **阶段 4：前端重做 + 联调**（Task 12-18）

每个 task 独立可测 + 立刻 commit。

---

### Task 1: config 模块 + .env 加载

**Files:**
- Create: `demo/config.py`
- Create: `.env.example`
- Modify: `.gitignore`
- Test: `demo/tests/test_config.py`

- [ ] **Step 1: 写失败测试**

```python
# demo/tests/test_config.py
from pathlib import Path
from demo.config import load_config, Config


def test_load_from_env_file(tmp_path: Path, monkeypatch):
    env = tmp_path / ".env"
    env.write_text(
        "AMAP_KEY=ak_123\n"
        "OPENAI_NEXT_API_KEY=sk_xyz\n"
        "PLANNER_BASE_URL=http://example:1\n",
        encoding="utf-8",
    )
    for k in ("AMAP_KEY", "OPENAI_NEXT_API_KEY", "PLANNER_BASE_URL"):
        monkeypatch.delenv(k, raising=False)
    cfg = load_config(env_path=env)
    assert isinstance(cfg, Config)
    assert cfg.amap_key == "ak_123"
    assert cfg.openai_next_api_key == "sk_xyz"
    assert cfg.planner_base_url == "http://example:1"


def test_env_overrides_file(tmp_path: Path, monkeypatch):
    env = tmp_path / ".env"
    env.write_text("AMAP_KEY=from_file\n", encoding="utf-8")
    monkeypatch.setenv("AMAP_KEY", "from_env")
    monkeypatch.delenv("OPENAI_NEXT_API_KEY", raising=False)
    monkeypatch.delenv("PLANNER_BASE_URL", raising=False)
    cfg = load_config(env_path=env)
    assert cfg.amap_key == "from_env"


def test_missing_required_raises(tmp_path: Path, monkeypatch):
    for k in ("AMAP_KEY", "OPENAI_NEXT_API_KEY", "PLANNER_BASE_URL"):
        monkeypatch.delenv(k, raising=False)
    env = tmp_path / ".env"
    try:
        load_config(env_path=env)
    except RuntimeError as e:
        assert "AMAP_KEY" in str(e)
    else:
        raise AssertionError("expected RuntimeError")


def test_planner_base_url_has_default(tmp_path, monkeypatch):
    env = tmp_path / ".env"
    env.write_text(
        "AMAP_KEY=a\nOPENAI_NEXT_API_KEY=b\n", encoding="utf-8")
    for k in ("AMAP_KEY", "OPENAI_NEXT_API_KEY", "PLANNER_BASE_URL"):
        monkeypatch.delenv(k, raising=False)
    cfg = load_config(env_path=env)
    assert cfg.planner_base_url == "http://100.99.139.20:18141"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pytest demo/tests/test_config.py -v`
Expected: 4 个 FAIL（`ModuleNotFoundError: demo.config`）

- [ ] **Step 3: 实现 demo/config.py**

```python
# demo/config.py
"""读取 .env + 环境变量，单一配置入口。

优先级：进程环境变量 > .env 文件。AMAP_KEY 和 OPENAI_NEXT_API_KEY 必填，
缺任一抛 RuntimeError。PLANNER_BASE_URL 缺省 100.99.139.20:18141。
"""
from __future__ import annotations
import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_PLANNER_BASE_URL = "http://100.99.139.20:18141"


@dataclass(frozen=True)
class Config:
    amap_key: str
    openai_next_api_key: str
    planner_base_url: str


def _parse_env_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def load_config(*, env_path: Path | None = None) -> Config:
    file_vals = _parse_env_file(env_path or Path(".env"))

    def pick(name: str, default: str | None = None) -> str | None:
        return os.environ.get(name) or file_vals.get(name) or default

    amap = pick("AMAP_KEY")
    media = pick("OPENAI_NEXT_API_KEY")
    planner = pick("PLANNER_BASE_URL", DEFAULT_PLANNER_BASE_URL)
    missing = [n for n, v in
               [("AMAP_KEY", amap), ("OPENAI_NEXT_API_KEY", media)] if not v]
    if missing:
        raise RuntimeError(
            f"missing required env vars: {missing}. "
            "set them in .env or process env.")
    assert amap and media and planner
    return Config(amap_key=amap, openai_next_api_key=media,
                  planner_base_url=planner)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `pytest demo/tests/test_config.py -v`
Expected: 4 PASS

- [ ] **Step 5: 创建 .env.example**

文件内容：

```
# 复制为 .env 后填入真实值（.env 已被 .gitignore）
AMAP_KEY=ff287a156a20b1b95830b719d6c6a047
OPENAI_NEXT_API_KEY=sk-your-openai-next-key
PLANNER_BASE_URL=http://100.99.139.20:18141
```

- [ ] **Step 6: 更新 .gitignore**

把以下两行加到 `.gitignore` 末尾（保留原有内容）：

```
.env
demo_runtime/cache/
```

- [ ] **Step 7: 提交**

```bash
git add demo/config.py demo/tests/test_config.py .env.example .gitignore
git commit -m "feat(config): .env loader with required var validation"
```

---

### Task 2: event_bus 抽离

**Files:**
- Create: `demo/event_bus.py`
- Test: `demo/tests/test_event_bus.py`

**Why:** v1 的 `_publish` 直接耦合在 `server.py` 全局 `_loop` 上。后面 scripts_player / amap / camera / agent 都要发事件，必须抽成可注入对象。SSE 队列消费方式不变。

- [ ] **Step 1: 写失败测试**

```python
# demo/tests/test_event_bus.py
import asyncio
import threading
import pytest
from demo.event_bus import EventBus


def test_publish_from_main_thread():
    async def go():
        bus = EventBus()
        bus.bind_loop(asyncio.get_running_loop())
        bus.publish({"type": "ptz", "pan": 10})
        ev = await asyncio.wait_for(bus.queue.get(), timeout=1.0)
        assert ev == {"type": "ptz", "pan": 10}
    asyncio.run(go())


def test_publish_from_worker_thread():
    async def go():
        bus = EventBus()
        bus.bind_loop(asyncio.get_running_loop())

        def worker():
            bus.publish({"type": "tool_call", "name": "pan_camera"})

        t = threading.Thread(target=worker)
        t.start(); t.join()
        ev = await asyncio.wait_for(bus.queue.get(), timeout=1.0)
        assert ev["name"] == "pan_camera"
    asyncio.run(go())


def test_publish_before_bind_raises():
    bus = EventBus()
    with pytest.raises(RuntimeError, match="not bound"):
        bus.publish({"type": "x"})
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pytest demo/tests/test_event_bus.py -v`
Expected: 3 FAIL（`ModuleNotFoundError`）

- [ ] **Step 3: 实现 demo/event_bus.py**

```python
# demo/event_bus.py
"""线程安全 SSE 事件总线。

asyncio.Queue 不是线程安全的，所以从工作线程发事件必须走
loop.call_soon_threadsafe。EventBus 把这个套路封死，并允许
测试 / scripts_player / amap / camera 共用。
"""
from __future__ import annotations
import asyncio
from typing import Any


class EventBus:
    def __init__(self) -> None:
        self.queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        self._loop: asyncio.AbstractEventLoop | None = None

    def bind_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        """在 FastAPI startup 钩子里调一次。"""
        self._loop = loop

    def publish(self, ev: dict[str, Any]) -> None:
        """从任何线程都可调。bind_loop 之前调会 raise。"""
        if self._loop is None:
            raise RuntimeError("EventBus not bound to a loop")
        self._loop.call_soon_threadsafe(self.queue.put_nowait, ev)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `pytest demo/tests/test_event_bus.py -v`
Expected: 3 PASS

- [ ] **Step 5: 提交**

```bash
git add demo/event_bus.py demo/tests/test_event_bus.py
git commit -m "feat(event_bus): thread-safe SSE publisher extracted from server.py"
```

---

### Task 3: Amap client + POI dataclass

**Files:**
- Create: `demo/amap.py`
- Test: `demo/tests/test_amap.py`

**Why:** 真实高德调用 + 把响应解析成稳定 `POI` 结构 + 同步往 event_bus 发 `amap_raw` 让技术面板能看到。仅 `search_around`，不做 `search_text`（YAGNI——v2 只用 around）。

- [ ] **Step 1: 写失败测试**

```python
# demo/tests/test_amap.py
from unittest.mock import MagicMock
from demo.amap import AmapClient, POI
from demo.event_bus import EventBus


_FAKE_RESPONSE = {
    "status": "1",
    "info": "OK",
    "pois": [{
        "id": "B0LKXKHOQW",
        "name": "Beans Solo 豆号咖啡(玄武湖国展店)",
        "location": "118.787,32.080",
        "distance": "1040",
        "address": "玄武湖翠洲门进园 · 芙蓉桥旁",
        "typecode": "050500",
        "atag": "手冲,湖景",
        "biz_ext": {"rating": "4.4", "cost": "23.00"},
    }],
}


def _make_client(response_json):
    fake_resp = MagicMock()
    fake_resp.json.return_value = response_json
    fake_resp.raise_for_status.return_value = None
    fake_http = MagicMock()
    fake_http.get.return_value = fake_resp
    bus = MagicMock(spec=EventBus)
    return AmapClient(key="ak_test", event_bus=bus, http=fake_http), fake_http, bus


def test_search_around_parses_poi():
    c, _, _ = _make_client(_FAKE_RESPONSE)
    pois = c.search_around(location="118.795,32.075",
                           keywords="咖啡", radius=2000)
    assert len(pois) == 1
    p = pois[0]
    assert isinstance(p, POI)
    assert p.id == "B0LKXKHOQW"
    assert p.name.startswith("Beans Solo")
    assert p.location == (118.787, 32.080)
    assert p.distance_m == 1040
    assert p.rating == 4.4
    assert p.cost == 23.0
    assert p.tags == ["手冲", "湖景"]


def test_search_around_publishes_amap_raw():
    c, _, bus = _make_client(_FAKE_RESPONSE)
    c.search_around(location="118.795,32.075", keywords="咖啡")
    bus.publish.assert_called_once()
    ev = bus.publish.call_args.args[0]
    assert ev["type"] == "amap_raw"
    assert ev["params"]["keywords"] == "咖啡"
    assert ev["count"] == 1


def test_handles_missing_optional_fields():
    resp = {
        "status": "1", "info": "OK",
        "pois": [{
            "id": "x", "name": "无评分店", "location": "1,2",
            "distance": "100", "address": "...", "typecode": "050000",
            "atag": [], "biz_ext": [],
        }],
    }
    c, _, _ = _make_client(resp)
    pois = c.search_around(location="1,2", keywords="x")
    assert pois[0].rating is None
    assert pois[0].cost is None
    assert pois[0].tags == []


def test_status_zero_returns_empty_list_and_logs():
    resp = {"status": "0", "info": "INVALID_USER_KEY", "pois": []}
    c, _, bus = _make_client(resp)
    pois = c.search_around(location="1,2", keywords="x")
    assert pois == []
    ev = bus.publish.call_args.args[0]
    assert ev["status"] == "0"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pytest demo/tests/test_amap.py -v`
Expected: 4 FAIL（`ModuleNotFoundError: demo.amap`）

- [ ] **Step 3: 实现 demo/amap.py**

```python
# demo/amap.py
"""高德 Web Service v3 客户端，限定 search_around。"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any
import httpx

from demo.event_bus import EventBus

DEFAULT_BASE = "https://restapi.amap.com"


@dataclass(frozen=True)
class POI:
    id: str
    name: str
    location: tuple[float, float]   # (lng, lat)
    distance_m: int
    address: str
    typecode: str
    rating: float | None
    cost: float | None
    tags: list[str] = field(default_factory=list)
    raw: dict[str, Any] = field(default_factory=dict)


def _parse_float(v: Any) -> float | None:
    try:
        if v in (None, "", []):
            return None
        return float(v)
    except (TypeError, ValueError):
        return None


def _parse_tags(v: Any) -> list[str]:
    if isinstance(v, str) and v:
        return [t.strip() for t in v.split(",") if t.strip()]
    return []


def _parse_poi(d: dict[str, Any]) -> POI:
    lng_s, _, lat_s = (d.get("location") or "0,0").partition(",")
    biz = d.get("biz_ext") or {}
    if not isinstance(biz, dict):
        biz = {}
    return POI(
        id=str(d.get("id", "")),
        name=str(d.get("name", "")),
        location=(float(lng_s or 0), float(lat_s or 0)),
        distance_m=int(_parse_float(d.get("distance")) or 0),
        address=str(d.get("address") or ""),
        typecode=str(d.get("typecode") or ""),
        rating=_parse_float(biz.get("rating")),
        cost=_parse_float(biz.get("cost")),
        tags=_parse_tags(d.get("atag")),
        raw=d,
    )


class AmapClient:
    def __init__(self, *, key: str, event_bus: EventBus,
                 base_url: str = DEFAULT_BASE,
                 http: httpx.Client | None = None,
                 timeout: float = 10.0) -> None:
        self._key = key
        self._bus = event_bus
        self._base = base_url.rstrip("/")
        # 高德是公网，需要走系统代理 -> trust_env=True
        self._http = http or httpx.Client(timeout=timeout, trust_env=True)

    def search_around(self, *, location: str, keywords: str,
                      radius: int = 2000, offset: int = 20) -> list[POI]:
        params = {
            "key": self._key, "location": location, "keywords": keywords,
            "radius": str(radius), "offset": str(offset),
            "extensions": "all",
        }
        r = self._http.get(f"{self._base}/v3/place/around", params=params)
        r.raise_for_status()
        data = r.json()
        pois_raw = data.get("pois") or []
        pois = [_parse_poi(p) for p in pois_raw if isinstance(p, dict)]
        self._bus.publish({
            "type": "amap_raw",
            "endpoint": "/v3/place/around",
            "params": {k: v for k, v in params.items() if k != "key"},
            "status": data.get("status"),
            "info": data.get("info"),
            "count": len(pois),
            "first": pois[0].raw if pois else None,
        })
        if data.get("status") != "1":
            return []
        return pois
```

- [ ] **Step 4: 跑测试确认通过**

Run: `pytest demo/tests/test_amap.py -v`
Expected: 4 PASS

- [ ] **Step 5: 提交**

```bash
git add demo/amap.py demo/tests/test_amap.py
git commit -m "feat(amap): search_around client with POI dataclass and amap_raw events"
```

---

### Task 4: MediaClient（openai-next：图片生成 + Whisper）

**Files:**
- Create: `demo/media.py`
- Test: `demo/tests/test_media.py`

**Why:** 把 openai-next 公网端点的两件事（gemini-3.1-flash-image-preview 图生 + whisper-1 转写）封装成一个 client。和 `LLMClient` 完全独立——不同 base_url、不同 key、不同 trust_env。

**关于响应格式：** 遵循 OpenAI 兼容协议——`/v1/images/generations` 返回 `{"data":[{"b64_json":"..."}]}`，`/v1/audio/transcriptions` 返回 `{"text":"..."}`。openai-next 文档与 OpenAI 兼容。

- [ ] **Step 1: 写失败测试**

```python
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
    # 调用参数
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pytest demo/tests/test_media.py -v`
Expected: 4 FAIL（`ModuleNotFoundError: demo.media`）

- [ ] **Step 3: 实现 demo/media.py**

```python
# demo/media.py
"""openai-next 媒体客户端：图片生成 + Whisper 语音转写。

与 demo.llm.LLMClient 完全独立——不同 base_url、不同 key、走公网（trust_env=True）。
"""
from __future__ import annotations
import base64
from pathlib import Path
import httpx

DEFAULT_BASE = "https://api.openai-next.com"
DEFAULT_IMAGE_MODEL = "gemini-3.1-flash-image-preview"
DEFAULT_WHISPER_MODEL = "whisper-1"


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

    def transcribe(self, *, audio_bytes: bytes, mime: str) -> str:
        files = {"file": ("audio", audio_bytes, mime)}
        data = {"model": self._whisper_model, "language": "zh"}
        r = self._http.post(
            f"{self._base}/v1/audio/transcriptions",
            files=files, data=data,
        )
        r.raise_for_status()
        return r.json().get("text") or ""
```

- [ ] **Step 4: 跑测试确认通过**

Run: `pytest demo/tests/test_media.py -v`
Expected: 4 PASS

- [ ] **Step 5: 在 requirements.txt 加 python-multipart**

`demo/requirements.txt` 末尾追加一行（FastAPI 接收 file upload 必须）：

```
python-multipart==0.0.12
```

- [ ] **Step 6: 提交**

```bash
git add demo/media.py demo/tests/test_media.py demo/requirements.txt
git commit -m "feat(media): openai-next client for image gen and whisper"
```

---

### Task 5: 图片预生成 CLI

**Files:**
- Create: `demo/data/scenarios/prebake.json`
- Create: `demo/cli/__init__.py`
- Create: `demo/cli/prebake_images.py`

**Why:** demo 期间 5 张图必须命中本地缓存（gemini 单张 5-15s，演示中等不起）。这个 CLI 单独跑、可重跑、缺哪张补哪张。失败重试 3 次。

- [ ] **Step 1: 创建 prebake.json**

写到 `demo/data/scenarios/prebake.json`，**严格用这份内容**：

```json
[
  {
    "id": "jiming_temple_card",
    "size": "1024x1024",
    "prompt": "中国南京鸡鸣寺，黄墙琉璃顶，秋天上午雾气，远景，水墨与水彩结合的插画风格，柔和日光，竖幅构图"
  },
  {
    "id": "companion_keepsake",
    "size": "1024x1536",
    "prompt": "玄武湖晨走的散步收藏卡，湖边、塔影、一杯咖啡，文艺散步剪贴风，柔和米色背景，留白可写字"
  },
  {
    "id": "beans_solo_storefront",
    "size": "1024x1024",
    "prompt": "玄武湖边一家小木屋独立咖啡馆门面，店招写'Beans Solo'，临湖窗，夏末傍晚柔光，文艺纪实摄影"
  },
  {
    "id": "beans_solo_interior",
    "size": "1024x1024",
    "prompt": "Beans Solo 咖啡馆室内，木桌木椅，靠窗座位能看到湖面波光，吧台后咖啡师在做手冲，温暖灯光"
  },
  {
    "id": "serendipity_keepsake",
    "size": "1024x1536",
    "prompt": "一次小小的偶遇——湖边咖啡店明信片，店面剪影、一杯拉花、印章式日期，文艺散步剪贴风，竖幅"
  }
]
```

- [ ] **Step 2: 创建 demo/cli/__init__.py**

空文件即可：

```python
```

- [ ] **Step 3: 实现 demo/cli/prebake_images.py**

```python
# demo/cli/prebake_images.py
"""启动 demo 之前跑一次：预生成 5 张 gemini 插画到本地缓存。

用法：
    python -m demo.cli.prebake_images          # 缺哪张补哪张
    python -m demo.cli.prebake_images --force  # 全部重生成
"""
from __future__ import annotations
import argparse
import json
import sys
import time
from pathlib import Path

from demo.config import load_config
from demo.media import MediaClient

ROOT = Path(__file__).resolve().parent.parent
PREBAKE_JSON = ROOT / "data" / "scenarios" / "prebake.json"
CACHE_DIR = ROOT.parent / "demo_runtime" / "cache" / "images"


def _generate_one(client: MediaClient, item: dict, out: Path,
                  retries: int = 3) -> tuple[bool, str]:
    last_err = ""
    for attempt in range(1, retries + 1):
        try:
            t0 = time.time()
            client.generate_image(
                prompt=item["prompt"], size=item["size"], save_to=out)
            return True, f"{out.stat().st_size // 1024}KB / {time.time()-t0:.1f}s"
        except Exception as e:  # noqa: BLE001
            last_err = f"attempt {attempt}: {e}"
            time.sleep(2.0 * attempt)
    return False, last_err


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true",
                    help="忽略缓存，全部重生成")
    args = ap.parse_args()

    cfg = load_config()
    items = json.loads(PREBAKE_JSON.read_text(encoding="utf-8"))
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    client = MediaClient(api_key=cfg.openai_next_api_key)
    print(f"预生成 {len(items)} 张图 -> {CACHE_DIR}")

    failed = 0
    for item in items:
        out = CACHE_DIR / f"{item['id']}.png"
        if out.exists() and not args.force:
            print(f"  [skip] {item['id']}  ({out.stat().st_size//1024}KB)")
            continue
        ok, info = _generate_one(client, item, out)
        tag = "ok  " if ok else "FAIL"
        print(f"  [{tag}] {item['id']}  {info}")
        if not ok:
            failed += 1
    if failed:
        print(f"FAILED {failed}/{len(items)}", file=sys.stderr)
        return 1
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: 不写 unit test**

理由：这是 thin CLI wrapper，所有有意思的逻辑（generate_image、文件落盘）已在 Task 4 测过。下一步是真打一次。

- [ ] **Step 5: 真打一次**

Run: `python -m demo.cli.prebake_images`
Expected: 5 行 `[ok ]`，每张 5-30s。`demo_runtime/cache/images/` 下 5 个 png 文件，每张 100KB+。

如果某张失败：手工再跑一次 `python -m demo.cli.prebake_images`（已成功的会 skip）。3 次都失败说明 openai-next 当前不可用——记录失败 prompt + 错误，停下来报告。

- [ ] **Step 6: 提交**

```bash
git add demo/data/scenarios/prebake.json demo/cli/__init__.py demo/cli/prebake_images.py
git commit -m "feat(prebake): CLI to pregenerate 5 demo images via gemini-3.1-flash-image"
```

---

### Task 6: POI 预拉 CLI + 锁定 demo POI

**Files:**
- Create: `demo/cli/prebake_pois.py`
- Create: `demo/data/pois_v2.json`（手写的 fallback + Beans Solo 锁定数据）

**Why:** 启动期把"玄武湖周边咖啡 / 鸡鸣寺周边" 两个查询拉一次，写到 `demo_runtime/cache/pois_real.json`，让 server 启动时能直接 load。同时把 Beans Solo 的稳定数据写到 git 仓里 `demo/data/pois_v2.json`，作为脚本场景的硬依赖。

- [ ] **Step 1: 创建 demo/data/pois_v2.json**

把以下内容**完整**写入 `demo/data/pois_v2.json`：

```json
{
  "scripted": [
    {
      "poi_id": "beans_solo",
      "name": "Beans Solo 豆号咖啡(玄武湖国展店)",
      "location": [118.787, 32.080],
      "distance_m": 1040,
      "rating": 4.4,
      "cost": 23.0,
      "address": "玄武湖翠洲门进园 · 芙蓉桥旁",
      "tagline": "藏在湖边木屋里的独立咖啡，靠水那张桌子常常没人",
      "image_id": "beans_solo_storefront",
      "alt_image_id": "beans_solo_interior",
      "typecode": "050500"
    },
    {
      "poi_id": "jiming_temple",
      "name": "鸡鸣寺",
      "location": [118.794, 32.066],
      "distance_m": 800,
      "rating": 4.6,
      "cost": null,
      "address": "鸡鸣寺路 1 号",
      "tagline": "南朝四百八十寺，剩下的那几座之一",
      "image_id": "jiming_temple_card",
      "alt_image_id": null,
      "typecode": "110200"
    }
  ],
  "amap_queries": [
    {
      "name": "xuanwu_indie_cafe",
      "location": "118.795,32.075",
      "keywords": "咖啡|甜品|手工冰淇淋|小酒馆",
      "radius": 2500
    },
    {
      "name": "xuanwu_landmarks",
      "location": "118.795,32.075",
      "keywords": "鸡鸣寺|紫峰大厦",
      "radius": 3000
    }
  ]
}
```

- [ ] **Step 2: 实现 demo/cli/prebake_pois.py**

```python
# demo/cli/prebake_pois.py
"""启动 demo 之前可选跑一次：把 amap 查询缓存到本地，避免 demo 中网络抖。

用法：
    python -m demo.cli.prebake_pois
    python -m demo.cli.prebake_pois --force   # 忽略缓存重新拉
"""
from __future__ import annotations
import argparse
import asyncio
import dataclasses
import json
import time
from pathlib import Path

from demo.config import load_config
from demo.event_bus import EventBus
from demo.amap import AmapClient

ROOT = Path(__file__).resolve().parent.parent
DATA_FILE = ROOT / "data" / "pois_v2.json"
CACHE_FILE = ROOT.parent / "demo_runtime" / "cache" / "pois_real.json"
TTL_SECONDS = 24 * 3600


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    if (CACHE_FILE.exists()
            and (time.time() - CACHE_FILE.stat().st_mtime) < TTL_SECONDS
            and not args.force):
        print(f"cache 已存在且 < 24h: {CACHE_FILE}; 跳过（--force 强制）")
        return 0

    cfg = load_config()
    bus = EventBus()
    bus.bind_loop(asyncio.new_event_loop())  # 仅 publish 用，不 await
    client = AmapClient(key=cfg.amap_key, event_bus=bus)

    spec = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    out: dict[str, list[dict]] = {}
    for q in spec["amap_queries"]:
        print(f"-> {q['name']}: keywords={q['keywords']}")
        pois = client.search_around(
            location=q["location"], keywords=q["keywords"],
            radius=q["radius"], offset=20)
        # 序列化用 dataclass.asdict，但 location 是 tuple -> list
        rows = []
        for p in pois:
            d = dataclasses.asdict(p)
            d["location"] = list(p.location)
            rows.append(d)
        out[q["name"]] = rows
        print(f"   got {len(rows)} pois")

    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    CACHE_FILE.write_text(
        json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"写入 {CACHE_FILE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 3: 真打一次**

Run: `python -m demo.cli.prebake_pois`
Expected: 两行 `got N pois`（N 通常 5-20），最终 `demo_runtime/cache/pois_real.json` 文件存在。

- [ ] **Step 4: 提交**

```bash
git add demo/data/pois_v2.json demo/cli/prebake_pois.py
git commit -m "feat(prebake): pois_v2.json + amap cache CLI"
```

---

### Task 7: 脚本场景 JSON + ScriptPlayer

**Files:**
- Create: `demo/data/scenarios/companion.json`
- Create: `demo/data/scenarios/serendipity.json`
- Create: `demo/scripts_player.py`
- Test: `demo/tests/test_scripts_player.py`

**Why:** 脚本播放器是 v2 的核心交互——按时间轴触发 dialog / ptz / poi_card / tool_call / moment / direction / keepsake_render，全部走依赖注入，不调 LLM。提供 `time_warp` 让测试加速。

- [ ] **Step 1: 创建 companion.json**

写到 `demo/data/scenarios/companion.json`：

```json
{
  "scenario_id": "companion",
  "title": "陪伴散步",
  "duration_s": 90,
  "events": [
    {"at": 0.0, "type": "dialog", "role": "ai",
     "text": "早，今天玄武湖风不大，往湖边走走？", "speak": true},
    {"at": 8.0, "type": "tool_call", "name": "pan_camera",
     "args": {"direction": "left", "reason": "看湖"}},
    {"at": 8.2, "type": "ptz", "pan": -30, "tilt": 0, "zoom": 100,
     "source": "script"},
    {"at": 12.0, "type": "dialog", "role": "ai",
     "text": "看，对面紫峰大厦还在云里。", "speak": true},
    {"at": 18.0, "type": "dialog", "role": "user",
     "text": "那是什么塔？"},
    {"at": 19.5, "type": "tool_call", "name": "analyze_frame_vlm",
     "args": {"question": "画面右侧那座塔是什么"}},
    {"at": 22.0, "type": "dialog", "role": "ai",
     "text": "鸡鸣寺的药师塔，南朝四百八十寺剩下的之一。", "speak": true},
    {"at": 35.0, "type": "poi_card", "poi_id": "jiming_temple"},
    {"at": 36.0, "type": "dialog", "role": "ai",
     "text": "要不要绕过去？走过去 8 分钟。", "speak": true},
    {"at": 50.0, "type": "dialog", "role": "user", "text": "记一下"},
    {"at": 51.0, "type": "tool_call", "name": "record_moment",
     "args": {"label": "鸡鸣寺·下次再来"}},
    {"at": 51.5, "type": "moment", "label": "鸡鸣寺·下次再来"},
    {"at": 65.0, "type": "dialog", "role": "ai",
     "text": "我转一圈给你看看。", "speak": true},
    {"at": 66.0, "type": "ptz_sweep"},
    {"at": 85.0, "type": "keepsake_render",
     "image_id": "companion_keepsake"}
  ]
}
```

- [ ] **Step 2: 创建 serendipity.json**

写到 `demo/data/scenarios/serendipity.json`：

```json
{
  "scenario_id": "serendipity",
  "title": "偶遇推荐",
  "duration_s": 60,
  "events": [
    {"at": 0.0, "type": "dialog", "role": "ai",
     "text": "走着走着……", "speak": true},
    {"at": 10.0, "type": "dialog", "role": "ai",
     "text": "你左边 100m 那家叫豆号的小咖啡，藏在湖边木屋里，靠水那张桌子常常没人，要不要去坐坐？",
     "speak": true},
    {"at": 11.0, "type": "poi_card", "poi_id": "beans_solo"},
    {"at": 11.5, "type": "direction", "arrow": "left",
     "distance_m": 100, "eta_min": 1, "label": "Beans Solo 豆号咖啡"},
    {"at": 25.0, "type": "dialog", "role": "user", "text": "长什么样？"},
    {"at": 26.0, "type": "poi_image_swap", "poi_id": "beans_solo",
     "to_image_id": "beans_solo_interior"},
    {"at": 27.0, "type": "dialog", "role": "ai",
     "text": "里面是这样，木桌临窗，吧台后那位在做手冲。", "speak": true},
    {"at": 40.0, "type": "dialog", "role": "user", "text": "走吧"},
    {"at": 41.0, "type": "tool_call", "name": "pan_camera",
     "args": {"direction": "left", "reason": "看一眼咖啡馆方向"}},
    {"at": 41.2, "type": "ptz", "pan": -25, "tilt": 0, "zoom": 100,
     "source": "script"},
    {"at": 55.0, "type": "dialog", "role": "ai",
     "text": "到了，门口排了 3 个人。", "speak": true},
    {"at": 58.0, "type": "keepsake_render",
     "image_id": "serendipity_keepsake"}
  ]
}
```

- [ ] **Step 3: 写失败测试**

```python
# demo/tests/test_scripts_player.py
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


def test_dialog_event_appends_and_speaks(fake_deps, tmp_path):
    sp = ScriptPlayer(time_warp=100.0, pois_v2_path=fake_deps["pois_path"],
                      dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                      camera=fake_deps["camera"], tts=fake_deps["tts"],
                      event_bus=fake_deps["bus"],
                      keepsake_render=fake_deps["keepsake"])
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "dialog", "role": "ai",
         "text": "hi", "speak": True}])
    sp.play(s)
    sp.wait()
    fake_deps["dialog"].append.assert_called_once_with(role="ai", text="hi")
    fake_deps["tts"].say.assert_called_once_with("hi")


def test_user_dialog_does_not_speak(fake_deps, tmp_path):
    sp = ScriptPlayer(time_warp=100.0, pois_v2_path=fake_deps["pois_path"],
                      dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                      camera=fake_deps["camera"], tts=fake_deps["tts"],
                      event_bus=fake_deps["bus"],
                      keepsake_render=fake_deps["keepsake"])
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "dialog", "role": "user", "text": "?"}])
    sp.play(s); sp.wait()
    fake_deps["dialog"].append.assert_called_once_with(role="user", text="?")
    fake_deps["tts"].say.assert_not_called()


def test_ptz_calls_camera(fake_deps, tmp_path):
    sp = ScriptPlayer(time_warp=100.0, pois_v2_path=fake_deps["pois_path"],
                      dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                      camera=fake_deps["camera"], tts=fake_deps["tts"],
                      event_bus=fake_deps["bus"],
                      keepsake_render=fake_deps["keepsake"])
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "ptz", "pan": -30, "tilt": 0, "zoom": 100,
         "source": "script"}])
    sp.play(s); sp.wait()
    fake_deps["camera"].set_position.assert_called_once_with(
        pan=-30, tilt=0, zoom=100)


def test_ptz_sweep(fake_deps, tmp_path):
    sp = ScriptPlayer(time_warp=100.0, pois_v2_path=fake_deps["pois_path"],
                      dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                      camera=fake_deps["camera"], tts=fake_deps["tts"],
                      event_bus=fake_deps["bus"],
                      keepsake_render=fake_deps["keepsake"])
    s = _scenario(tmp_path, [{"at": 0.0, "type": "ptz_sweep"}])
    sp.play(s); sp.wait()
    fake_deps["camera"].sweep.assert_called_once()


def test_poi_card_published_with_full_data(fake_deps, tmp_path):
    sp = ScriptPlayer(time_warp=100.0, pois_v2_path=fake_deps["pois_path"],
                      dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                      camera=fake_deps["camera"], tts=fake_deps["tts"],
                      event_bus=fake_deps["bus"],
                      keepsake_render=fake_deps["keepsake"])
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
    sp = ScriptPlayer(time_warp=100.0, pois_v2_path=fake_deps["pois_path"],
                      dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                      camera=fake_deps["camera"], tts=fake_deps["tts"],
                      event_bus=fake_deps["bus"],
                      keepsake_render=fake_deps["keepsake"])
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "poi_image_swap",
         "poi_id": "beans_solo", "to_image_id": "beans_solo_interior"}])
    sp.play(s); sp.wait()
    ev = fake_deps["bus"].publish.call_args.args[0]
    assert ev["type"] == "poi_image_swap"
    assert ev["image_url"] == "/poi_image/beans_solo_interior.png"


def test_tool_call_publishes(fake_deps, tmp_path):
    sp = ScriptPlayer(time_warp=100.0, pois_v2_path=fake_deps["pois_path"],
                      dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                      camera=fake_deps["camera"], tts=fake_deps["tts"],
                      event_bus=fake_deps["bus"],
                      keepsake_render=fake_deps["keepsake"])
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
    sp = ScriptPlayer(time_warp=100.0, pois_v2_path=fake_deps["pois_path"],
                      dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                      camera=fake_deps["camera"], tts=fake_deps["tts"],
                      event_bus=fake_deps["bus"],
                      keepsake_render=fake_deps["keepsake"])
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "moment", "label": "记一下"}])
    sp.play(s); sp.wait()
    fake_deps["moments"].append.assert_called_once()


def test_direction_event(fake_deps, tmp_path):
    sp = ScriptPlayer(time_warp=100.0, pois_v2_path=fake_deps["pois_path"],
                      dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                      camera=fake_deps["camera"], tts=fake_deps["tts"],
                      event_bus=fake_deps["bus"],
                      keepsake_render=fake_deps["keepsake"])
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "direction", "arrow": "left",
         "distance_m": 100, "eta_min": 1, "label": "去店里"}])
    sp.play(s); sp.wait()
    ev = fake_deps["bus"].publish.call_args.args[0]
    assert ev["type"] == "direction"
    assert ev["arrow"] == "left"


def test_keepsake_render_called(fake_deps, tmp_path):
    sp = ScriptPlayer(time_warp=100.0, pois_v2_path=fake_deps["pois_path"],
                      dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                      camera=fake_deps["camera"], tts=fake_deps["tts"],
                      event_bus=fake_deps["bus"],
                      keepsake_render=fake_deps["keepsake"])
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "keepsake_render",
         "image_id": "companion_keepsake"}])
    sp.play(s); sp.wait()
    fake_deps["keepsake"].assert_called_once_with("companion_keepsake")


def test_stop_aborts_playback(fake_deps, tmp_path):
    sp = ScriptPlayer(time_warp=1.0, pois_v2_path=fake_deps["pois_path"],
                      dialog=fake_deps["dialog"], moments=fake_deps["moments"],
                      camera=fake_deps["camera"], tts=fake_deps["tts"],
                      event_bus=fake_deps["bus"],
                      keepsake_render=fake_deps["keepsake"])
    s = _scenario(tmp_path, [
        {"at": 0.0, "type": "dialog", "role": "ai", "text": "a"},
        {"at": 5.0, "type": "dialog", "role": "ai", "text": "b"}])
    sp.play(s)
    time.sleep(0.2)
    sp.stop()
    sp.wait()
    # 只发了第 0 个；第二个不该出现
    appends = [c.kwargs for c in fake_deps["dialog"].append.call_args_list]
    assert {"role": "ai", "text": "a"} in appends
    assert {"role": "ai", "text": "b"} not in appends
```

- [ ] **Step 4: 跑测试确认失败**

Run: `pytest demo/tests/test_scripts_player.py -v`
Expected: 11 FAIL（`ModuleNotFoundError`）

- [ ] **Step 5: 实现 demo/scripts_player.py**

```python
# demo/scripts_player.py
"""按时间轴回放预设场景，不调 LLM。

事件类型：dialog / ptz / ptz_sweep / poi_card / poi_image_swap /
tool_call / moment / direction / keepsake_render

依赖通过构造函数注入，方便测试。time_warp > 1 时按倍速播放（仅测试用）。
"""
from __future__ import annotations
import json
import threading
import time
from pathlib import Path
from typing import Any, Callable

from demo.event_bus import EventBus


class ScriptPlayer:
    def __init__(self, *, dialog, moments, camera, tts,
                 event_bus: EventBus,
                 keepsake_render: Callable[[str], None],
                 pois_v2_path: Path,
                 time_warp: float = 1.0) -> None:
        self._dialog = dialog
        self._moments = moments
        self._camera = camera
        self._tts = tts
        self._bus = event_bus
        self._keepsake = keepsake_render
        self._time_warp = max(time_warp, 0.001)
        self._pois = self._load_pois(pois_v2_path)
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    @staticmethod
    def _load_pois(path: Path) -> dict[str, dict]:
        spec = json.loads(path.read_text(encoding="utf-8"))
        return {p["poi_id"]: p for p in spec.get("scripted", [])}

    def play(self, scenario_path: Path) -> None:
        if self._thread and self._thread.is_alive():
            raise RuntimeError("scenario already playing")
        scenario = json.loads(scenario_path.read_text(encoding="utf-8"))
        events = sorted(scenario.get("events", []), key=lambda e: e["at"])
        self._stop.clear()
        self._thread = threading.Thread(
            target=self._run, args=(scenario["scenario_id"], events),
            daemon=True, name=f"script-{scenario['scenario_id']}")
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()

    def wait(self, timeout: float = 30.0) -> None:
        if self._thread:
            self._thread.join(timeout=timeout)

    def _run(self, scenario_id: str, events: list[dict]) -> None:
        t0 = time.monotonic()
        for idx, ev in enumerate(events):
            if self._stop.is_set():
                return
            target = ev["at"] / self._time_warp
            now = time.monotonic() - t0
            wait = target - now
            if wait > 0:
                # 用 stop event 的 wait 让 stop() 能即时打断
                if self._stop.wait(timeout=wait):
                    return
            self._bus.publish({
                "type": "script", "scenario": scenario_id,
                "step_index": idx, "beat": ev.get("type")})
            try:
                self._dispatch(ev)
            except Exception as e:  # noqa: BLE001
                print(f"[script] dispatch failed at {idx}/{ev}: {e}")

    def _dispatch(self, ev: dict[str, Any]) -> None:
        et = ev["type"]
        if et == "dialog":
            self._dialog.append(role=ev["role"], text=ev["text"])
            if ev.get("speak") and ev["role"] == "ai":
                self._tts.say(ev["text"])
        elif et == "ptz":
            self._camera.set_position(
                pan=ev.get("pan", 0), tilt=ev.get("tilt", 0),
                zoom=ev.get("zoom", 100))
        elif et == "ptz_sweep":
            self._camera.sweep()
        elif et == "tool_call":
            self._bus.publish({
                "type": "tool_call", "source": "script",
                "name": ev["name"], "args": ev.get("args", {})})
        elif et == "poi_card":
            poi = self._pois[ev["poi_id"]]
            self._bus.publish({
                "type": "poi_card",
                "poi_id": poi["poi_id"], "name": poi["name"],
                "distance_m": poi["distance_m"],
                "rating": poi["rating"], "cost": poi["cost"],
                "address": poi["address"], "tagline": poi["tagline"],
                "image_url": f"/poi_image/{poi['image_id']}.png",
            })
        elif et == "poi_image_swap":
            self._bus.publish({
                "type": "poi_image_swap",
                "poi_id": ev["poi_id"],
                "image_url": f"/poi_image/{ev['to_image_id']}.png"})
        elif et == "direction":
            self._bus.publish({
                "type": "direction",
                "arrow": ev["arrow"], "distance_m": ev["distance_m"],
                "eta_min": ev["eta_min"], "label": ev.get("label", "")})
        elif et == "moment":
            self._moments.append(label=ev["label"], frame_path=None)
        elif et == "keepsake_render":
            self._keepsake(ev.get("image_id", "companion_keepsake"))
        else:
            print(f"[script] unknown event type: {et}")
```

- [ ] **Step 6: 跑测试确认通过**

Run: `pytest demo/tests/test_scripts_player.py -v`
Expected: 11 PASS

- [ ] **Step 7: 提交**

```bash
git add demo/data/scenarios/companion.json demo/data/scenarios/serendipity.json \
        demo/scripts_player.py demo/tests/test_scripts_player.py
git commit -m "feat(scripts): timeline player + companion/serendipity scenarios"
```

---

### Task 8: PanCameraTool 加 reason + prompt 鼓励主动看

**Files:**
- Modify: `demo/tools.py`（PanCameraTool schema）
- Modify: `demo/prompts.py`（SYSTEM_PROMPT 加一条）
- Test: `demo/tests/test_pan_camera_reason.py`

- [ ] **Step 1: 写失败测试**

```python
# demo/tests/test_pan_camera_reason.py
from demo.tools import PanCameraTool, to_openai_schema


def test_pan_camera_schema_requires_reason():
    schema = to_openai_schema(PanCameraTool(camera=None))
    params = schema["function"]["parameters"]
    assert "reason" in params["properties"]
    assert "reason" in params["required"]


def test_pan_camera_run_records_reason(monkeypatch):
    calls = []
    class FakeCam:
        def move(self, direction, step=20):
            calls.append((direction, step))
            return {"pan": -20, "tilt": 0, "zoom": 100}
    tool = PanCameraTool(camera=FakeCam())
    out = tool.run(direction="left", reason="用户提到湖")
    assert "reason" not in out  # 不污染 LLM 上下文
    assert calls == [("left", 20)]
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pytest demo/tests/test_pan_camera_reason.py -v`
Expected: 2 FAIL（reason 不在 required；run 不接 reason 参数）

- [ ] **Step 3: 修改 demo/tools.py**

打开 `demo/tools.py`，找到 `PanCameraTool`，把它替换成下面这版（保留同名同位置）：

```python
@dataclass
class PanCameraTool:
    name: str = "pan_camera"
    description: str = (
        "把相机转到一个方向看一眼。当你想引用画面里的东西、想确认方向、"
        "或想给用户展示某个角度时，主动调它。reason 字段必须填，简短说明为什么转。"
    )
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {
            "direction": {
                "type": "string",
                "enum": ["left", "right", "up", "down", "center",
                         "zoom_in", "zoom_out"],
            },
            "step": {"type": "integer", "default": 20,
                     "description": "步长，pan/tilt 通常 10-30，zoom 5-15"},
            "reason": {"type": "string",
                       "description": "为什么要转，例如：用户提到湖，先看一眼"},
        },
        "required": ["direction", "reason"],
    })
    camera: Any = None

    def run(self, *, direction: str, reason: str, step: int = 20) -> dict:
        # reason 仅为日志面板可读性，不返回给 LLM
        _ = reason
        return self.camera.move(direction, step=step)
```

- [ ] **Step 4: 修改 demo/prompts.py**

`demo/prompts.py` 里的 SYSTEM_PROMPT，在第 5 条"环视"之后插入新条目（旧 5/6/7 顺延）：

```python
SYSTEM_PROMPT = """你是"本地引力"——一个陪用户散步的 AI 伙伴。

设定：用户和你正在南京玄武湖周边散步。用户戴着一台影石 Link 2 Pro 相机，
你能通过工具看到画面、控制相机方向，并通过 TTS 对用户说话。

你的核心准则：
1. **少说话**。除非用户问你，或你看到了真的值得分享的东西，否则保持安静。
2. **看了再说**。回答"那是什么"之类的问题时，先调 analyze_frame_vlm。
3. **本地引力**。你了解周边几个地点（玄武湖、鸡鸣寺、紫峰大厦、明孝陵、
   夫子庙、新街口）；偶尔可以推荐用户绕过去看看，每次推荐前调
   recommend_nearby_place 拿到具体描述。
4. **记一下**。当用户说"记一下""标记一下"之类的话，调 record_moment。
5. **环视**。当用户问"周围有什么"之类的话，可以调 pan_camera 让相机
   自己环视一圈再回答。
6. **主动看**。当你想引用画面里某个东西、或想确认方向时，直接调
   pan_camera 转过去（reason 必须填，例如"用户提到湖，先转向湖面"），
   再调 analyze_frame_vlm 确认，再说话。
7. **说话用 speak_to_user 工具**，不要直接在 content 里写要说的话。
8. **每个用户回合最多 8 步**。能一次说清的不要分两次。"""
```

- [ ] **Step 5: 跑测试确认通过**

Run: `pytest demo/tests/test_pan_camera_reason.py -v`
Expected: 2 PASS

- [ ] **Step 6: 跑全量测试确保没破其它**

Run: `pytest demo/tests -v`
Expected: 全部 PASS（v1 老测试加 v2 新测试）

- [ ] **Step 7: 提交**

```bash
git add demo/tools.py demo/prompts.py demo/tests/test_pan_camera_reason.py
git commit -m "feat(tools): pan_camera requires reason; prompt encourages proactive look"
```

---

### Task 9: agent 调用工具时往 event_bus 发 tool_call

**Files:**
- Modify: `demo/agent.py`
- Test: `demo/tests/test_agent_tool_events.py`

**Why:** 让技术面板能实时看到 AI 调了哪些工具、参数是啥。和 ScriptPlayer 发的同 type 事件结构对齐（`source` 字段区分 `agent` / `script`）。

- [ ] **Step 1: 写失败测试**

```python
# demo/tests/test_agent_tool_events.py
from unittest.mock import MagicMock
from demo.agent import AgentRuntime
from demo.event_bus import EventBus
from demo.llm import AssistantMessage, ToolCall


def test_agent_publishes_tool_call_event():
    llm = MagicMock()
    # 第一轮返回一个 tool_call，第二轮返回纯文本结束
    llm.chat.side_effect = [
        AssistantMessage(content=None, tool_calls=[
            ToolCall(id="t1", name="speak_to_user",
                     arguments={"text": "hi"})]),
        AssistantMessage(content="done", tool_calls=[]),
    ]

    spoken = []
    class SpeakTool:
        name = "speak_to_user"
        def to_openai_schema(self): return {}
        def run(self, *, text):
            spoken.append(text); return {"ok": True}

    bus = MagicMock(spec=EventBus)
    dialog = MagicMock()

    rt = AgentRuntime(llm=llm, tools=[SpeakTool()],
                     dialog=dialog, system_prompt="sys", event_bus=bus)
    rt.handle_user_turn("test")

    # 至少有一条 tool_call 事件
    tool_events = [c.args[0] for c in bus.publish.call_args_list
                   if c.args[0].get("type") == "tool_call"]
    assert len(tool_events) == 1
    ev = tool_events[0]
    assert ev["name"] == "speak_to_user"
    assert ev["args"] == {"text": "hi"}
    assert ev["source"] == "agent"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pytest demo/tests/test_agent_tool_events.py -v`
Expected: FAIL（`AgentRuntime` 不接 event_bus 参数 / 没发事件）

- [ ] **Step 3: 修改 demo/agent.py**

打开 `demo/agent.py`，找到 `AgentRuntime.__init__`，把签名改成：

```python
def __init__(self, *, llm, tools, dialog, system_prompt,
             event_bus=None, max_iterations: int = 8) -> None:
    self._llm = llm
    self._tools = {t.name: t for t in tools}
    self._dialog = dialog
    self._system = system_prompt
    self._bus = event_bus
    self._max_iter = max_iterations
    self._lock = threading.Lock()
```

然后在 `_loop` 方法里，每次准备执行一个 tool_call 之前**新增**这段：

```python
if self._bus is not None:
    self._bus.publish({
        "type": "tool_call", "source": "agent",
        "name": tc.name, "args": tc.arguments,
    })
```

（具体插入位置：在拿到 `tc = ...` 之后、调 `tool.run(**tc.arguments)` 之前。）

- [ ] **Step 4: 跑测试确认通过**

Run: `pytest demo/tests/test_agent_tool_events.py -v`
Expected: PASS

- [ ] **Step 5: 跑全量回归**

Run: `pytest demo/tests -v`
Expected: 全部 PASS（已存在的 agent 测试 event_bus 默认 None，行为不变）

- [ ] **Step 6: 提交**

```bash
git add demo/agent.py demo/tests/test_agent_tool_events.py
git commit -m "feat(agent): publish tool_call SSE events with source=agent"
```

---

### Task 10: server.py 接入新 client + 新路由

**Files:**
- Modify: `demo/server.py`
- Test: `demo/tests/test_server_v2.py`

**Why:** 把 EventBus / AmapClient / MediaClient / ScriptPlayer 全部 wire 起来，新增 `/api/voice` `/api/script/start` `/api/script/stop` `/poi_image/{name}` 路由。Camera.set_position 也要发 `ptz` 事件。

- [ ] **Step 1: 写失败测试（server 路由）**

```python
# demo/tests/test_server_v2.py
import io
from pathlib import Path
from unittest.mock import patch, MagicMock
from fastapi.testclient import TestClient


def _client(tmp_path, monkeypatch):
    # 准备一个最小 .env，假 cache 目录
    monkeypatch.setenv("AMAP_KEY", "ak")
    monkeypatch.setenv("OPENAI_NEXT_API_KEY", "sk")
    monkeypatch.setenv("PLANNER_BASE_URL", "http://x:1")
    # 假图片缓存（让启动期 prebake 校验通过）
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
        # 让 Media.transcribe 返回固定文本
        Media.return_value.transcribe.return_value = "你好"
        Cam.return_value.mjpeg_iter.return_value = iter([])
        from demo import server
        return TestClient(server.app), Media


def test_voice_route_calls_whisper(tmp_path, monkeypatch):
    client, Media = _client(tmp_path, monkeypatch)
    r = client.post("/api/voice",
                    files={"audio": ("a.webm", b"\x00\x01",
                                     "audio/webm")})
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
```

- [ ] **Step 2: 跑测试确认失败**

Run: `pytest demo/tests/test_server_v2.py -v`
Expected: 5 FAIL（路由不存在 / startup 校验 / Media 未注入）

- [ ] **Step 3: 重写 demo/server.py**

完整替换 `demo/server.py` 为下面内容：

```python
"""FastAPI composition root. Run: python -m demo.server"""
from __future__ import annotations
import asyncio
import json
import threading
import time
from pathlib import Path
from typing import AsyncIterator
from fastapi import FastAPI, Request, UploadFile, File, HTTPException
from fastapi.responses import (
    HTMLResponse, JSONResponse, StreamingResponse, FileResponse,
)
from fastapi.staticfiles import StaticFiles
import uvicorn

from demo.camera import CameraController
from demo.dialog import DialogLog, MomentLog
from demo.llm import LLMClient
from demo.tts import TTSService
from demo.tools import (
    GetCameraFrameTool, AnalyzeFrameVLMTool, SpeakToUserTool,
    RecordMomentTool, PanCameraTool, RecommendNearbyPlaceTool,
)
from demo.agent import AgentRuntime
from demo.keepsake import KeepsakeBuilder
from demo.prompts import SYSTEM_PROMPT, PROACTIVE_PROMPT
from demo.config import load_config
from demo.event_bus import EventBus
from demo.media import MediaClient
from demo.amap import AmapClient
from demo.scripts_player import ScriptPlayer

ROOT = Path(__file__).parent
SESSION_DIR = ROOT.parent / "demo_runtime"
SESSION_DIR.mkdir(exist_ok=True)
CACHE_IMAGES_DIR = SESSION_DIR / "cache" / "images"
SCENARIOS_DIR = ROOT / "data" / "scenarios"
POIS_V2_PATH = ROOT / "data" / "pois_v2.json"
HTTP_PORT = 8788
REQUIRED_IMAGE_IDS = [
    "jiming_temple_card", "companion_keepsake",
    "beans_solo_storefront", "beans_solo_interior", "serendipity_keepsake",
]

app = FastAPI()
app.mount("/static", StaticFiles(directory=str(ROOT / "static")), name="static")

# Singletons
camera: CameraController
dialog: DialogLog
moments: MomentLog
tts: TTSService
llm: LLMClient
media: MediaClient
amap: AmapClient
agent: AgentRuntime
script_player: ScriptPlayer
keepsake_builder = KeepsakeBuilder()
bus = EventBus()
proactive_thread: threading.Thread | None = None
session_active = threading.Event()


@app.on_event("startup")
def _startup():
    global camera, dialog, moments, tts, llm, media, amap, agent, script_player
    bus.bind_loop(asyncio.get_event_loop())

    # 校验：5 张 prebake 图必须存在
    missing = [i for i in REQUIRED_IMAGE_IDS
               if not (CACHE_IMAGES_DIR / f"{i}.png").exists()]
    if missing:
        raise RuntimeError(
            f"missing prebaked images: {missing}. "
            "run: python -m demo.cli.prebake_images")

    cfg = load_config()
    camera = CameraController()
    dialog = DialogLog()
    moments = MomentLog()
    tts = TTSService()
    llm = LLMClient(base_url=cfg.planner_base_url)
    media = MediaClient(api_key=cfg.openai_next_api_key)
    amap = AmapClient(key=cfg.amap_key, event_bus=bus)

    # 包装 camera.set_position -> 同时发 ptz 事件
    _orig_set = camera.set_position
    def _set_position_with_event(*, pan=None, tilt=None, zoom=None):
        out = _orig_set(pan=pan, tilt=tilt, zoom=zoom)
        bus.publish({"type": "ptz",
                     "pan": out.get("pan"), "tilt": out.get("tilt"),
                     "zoom": out.get("zoom"), "source": "agent"})
        return out
    camera.set_position = _set_position_with_event  # type: ignore[method-assign]

    # 包装 moments.append -> 发 moment 事件
    _orig_append = moments.append
    def _wrapped_append(*, label, frame_path):
        m = _orig_append(label=label, frame_path=frame_path)
        bus.publish({"type": "moment", "label": label, "ts": m.timestamp})
        return m
    moments.append = _wrapped_append  # type: ignore[method-assign]

    tools = [
        GetCameraFrameTool(camera=camera),
        AnalyzeFrameVLMTool(camera=camera, llm=llm),
        SpeakToUserTool(dialog=dialog, tts=tts),
        RecordMomentTool(camera=camera, moments=moments,
                         save_dir=SESSION_DIR / "moments"),
        PanCameraTool(camera=camera),
        RecommendNearbyPlaceTool(poi_path=ROOT / "data" / "nanjing_pois.json"),
    ]
    agent = AgentRuntime(llm=llm, tools=tools, dialog=dialog,
                         system_prompt=SYSTEM_PROMPT, event_bus=bus)

    def _render_keepsake(image_id: str) -> None:
        out = SESSION_DIR / f"keepsake_{int(time.time())}.png"
        keepsake_builder.build(dialog=dialog, moments=moments, out_path=out)
        bus.publish({"type": "keepsake", "url": f"/keepsake/{out.name}"})

    script_player = ScriptPlayer(
        dialog=dialog, moments=moments, camera=camera, tts=tts,
        event_bus=bus, keepsake_render=_render_keepsake,
        pois_v2_path=POIS_V2_PATH)

    def on_turn(t):
        bus.publish({"type": "dialog", "role": t.role,
                     "text": t.text, "ts": t.timestamp})
    dialog.subscribe(on_turn)
    print(f"demo server up: http://127.0.0.1:{HTTP_PORT}/")


@app.get("/", response_class=HTMLResponse)
def index():
    return (ROOT / "static" / "index.html").read_text(encoding="utf-8")


@app.get("/video.mjpg")
def video():
    return StreamingResponse(
        camera.mjpeg_iter(),
        media_type="multipart/x-mixed-replace; boundary=frame",
    )


@app.get("/events")
async def events(request: Request) -> StreamingResponse:
    async def stream() -> AsyncIterator[bytes]:
        while True:
            if await request.is_disconnected():
                break
            try:
                ev = await asyncio.wait_for(bus.queue.get(), timeout=15.0)
                yield f"data: {json.dumps(ev, ensure_ascii=False)}\n\n".encode()
            except asyncio.TimeoutError:
                yield b": keepalive\n\n"
    return StreamingResponse(stream(), media_type="text/event-stream")


@app.post("/api/start")
async def start_session():
    if not session_active.is_set():
        session_active.set()
        global proactive_thread
        proactive_thread = threading.Thread(
            target=_proactive_loop, daemon=True, name="proactive")
        proactive_thread.start()
        greeting = (
            "（用户刚按下「开始散步」按钮，请简短打招呼并说明今天我们就在玄武湖周边走一圈。）"
        )
        asyncio.get_event_loop().run_in_executor(
            None, agent.handle_user_turn, greeting)
    return {"status": "ok"}


@app.post("/api/say")
async def say(req: Request):
    body = await req.json()
    text = (body.get("text") or "").strip()
    if not text:
        return JSONResponse({"error": "empty"}, status_code=400)
    await asyncio.get_event_loop().run_in_executor(
        None, agent.handle_user_turn, text)
    return {"status": "ok"}


@app.post("/api/end")
async def end_session():
    session_active.clear()
    out = SESSION_DIR / f"keepsake_{int(time.time())}.png"
    await asyncio.get_event_loop().run_in_executor(
        None,
        lambda: keepsake_builder.build(dialog=dialog, moments=moments,
                                        out_path=out))
    return {"status": "ok", "keepsake_url": f"/keepsake/{out.name}"}


@app.post("/api/voice")
async def voice(audio: UploadFile = File(...)):
    data = await audio.read()
    text = await asyncio.get_event_loop().run_in_executor(
        None,
        lambda: media.transcribe(
            audio_bytes=data, mime=audio.content_type or "audio/webm"))
    return {"text": text}


@app.post("/api/script/start")
async def script_start(req: Request):
    body = await req.json()
    scenario = (body.get("scenario") or "").strip()
    path = SCENARIOS_DIR / f"{scenario}.json"
    if not path.exists():
        raise HTTPException(status_code=400, detail=f"unknown scenario: {scenario}")
    try:
        script_player.play(path)
    except RuntimeError as e:
        raise HTTPException(status_code=409, detail=str(e))
    return {"status": "ok", "scenario": scenario}


@app.post("/api/script/stop")
async def script_stop():
    script_player.stop()
    return {"status": "ok"}


@app.get("/keepsake/{name}")
def get_keepsake(name: str):
    p = SESSION_DIR / name
    if not p.exists():
        return JSONResponse({"error": "not found"}, status_code=404)
    return FileResponse(p, media_type="image/png")


@app.get("/poi_image/{name}")
def get_poi_image(name: str):
    p = CACHE_IMAGES_DIR / name
    if not p.exists() or not p.is_file():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(p, media_type="image/png")


def _proactive_loop():
    while session_active.is_set():
        time.sleep(60)
        if not session_active.is_set():
            break
        try:
            agent.handle_proactive_check(PROACTIVE_PROMPT)
        except Exception as e:
            print(f"[proactive] {e}")


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=HTTP_PORT, log_level="info")
```

- [ ] **Step 4: 跑测试确认通过**

Run: `pytest demo/tests/test_server_v2.py -v`
Expected: 5 PASS

- [ ] **Step 5: 跑全量回归**

Run: `pytest demo/tests -v`
Expected: 全部 PASS

- [ ] **Step 6: 提交**

```bash
git add demo/server.py demo/tests/test_server_v2.py
git commit -m "feat(server): wire EventBus/Amap/Media/ScriptPlayer + voice/script routes"
```

---

### Task 11: smoke 脚本（真打 openai-next + amap）

**Files:**
- Create: `scripts/smoke_media.py`
- Create: `scripts/smoke_amap.py`

**Why:** unit test 全 mock，真实端点抖动只能跑 smoke 才知道。这两个脚本不是 pytest 套件的一部分——只在手工或 demo 录制前跑一次。

- [ ] **Step 1: 写 scripts/smoke_media.py**

```python
"""真打一次 openai-next：生成 1 张图 + 转写 1 段 wav。"""
import sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from demo.config import load_config
from demo.media import MediaClient

cfg = load_config()
client = MediaClient(api_key=cfg.openai_next_api_key)
out = Path("demo_runtime/smoke_media.png")
out.parent.mkdir(exist_ok=True)
t0 = time.time()
client.generate_image(
    prompt="一只在玄武湖边散步的橘猫，水彩",
    size="1024x1024", save_to=out)
print(f"image ok: {out} ({out.stat().st_size//1024}KB, {time.time()-t0:.1f}s)")

# 拿一段 1s 静音 wav 测 whisper（不强求识别准确）
import wave, struct
wav = Path("demo_runtime/smoke_silence.wav")
with wave.open(str(wav), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(struct.pack("<" + "h" * 16000, *([0] * 16000)))
text = client.transcribe(audio_bytes=wav.read_bytes(), mime="audio/wav")
print(f"whisper ok: text={text!r}")
```

- [ ] **Step 2: 写 scripts/smoke_amap.py**

```python
"""真打一次高德 search_around，确认 key + 网络可用。"""
import asyncio, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from demo.config import load_config
from demo.event_bus import EventBus
from demo.amap import AmapClient

cfg = load_config()
bus = EventBus(); bus.bind_loop(asyncio.new_event_loop())
client = AmapClient(key=cfg.amap_key, event_bus=bus)
pois = client.search_around(
    location="118.795,32.075", keywords="咖啡", radius=2000)
print(f"got {len(pois)} pois")
for p in pois[:3]:
    print(f"  {p.name}  {p.distance_m}m  rating={p.rating}  ¥{p.cost}")
```

- [ ] **Step 3: 跑两个 smoke**

```
python scripts/smoke_media.py
python scripts/smoke_amap.py
```

Expected: media 打印 image ok（5-30s）+ whisper ok（text 多半空字符串，不报错就行）；amap 打印 3 个 POI。

- [ ] **Step 4: 提交**

```bash
git add scripts/smoke_media.py scripts/smoke_amap.py
git commit -m "test: smoke scripts for openai-next + amap real endpoints"
```

---

### Task 12: 前端 — styles.css（双面板基础布局）

**Files:**
- Create: `demo/static/styles.css`

**Why:** 把样式从内联抽出来，参照 `buyu-demo(3).html` 风格——iPhone 393×852 mock 在左、技术面板在右、主色 `#7BC67E`、卡片 16px 圆角。后续 Task 13-17 共用这个 CSS。

- [ ] **Step 1: 创建 demo/static/styles.css**

完整内容如下（直接 Write 整文件）：

```css
:root {
  --green: #7BC67E;
  --green-dark: #5DA561;
  --bg: #F4F1EC;
  --panel: #FFFFFF;
  --tech-bg: #1A1F26;
  --tech-panel: #232932;
  --tech-text: #C9D1D9;
  --tech-muted: #6E7681;
  --user-bubble: #E8F5E9;
  --ai-bubble: #FFFFFF;
  --shadow: 0 8px 32px rgba(0,0,0,.12);
  font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
}
* { box-sizing: border-box; }
html, body { margin: 0; height: 100%; background: var(--bg); }
body { display: flex; gap: 24px; padding: 24px; overflow: hidden; }

/* ======== iPhone mock 左侧 ======== */
.iphone {
  width: 393px; height: 852px; flex-shrink: 0;
  background: #fff; border-radius: 48px;
  border: 8px solid #1A1F26; box-shadow: var(--shadow);
  position: relative; overflow: hidden;
  display: flex; flex-direction: column;
}
.iphone .status-bar {
  height: 47px; padding: 12px 28px 0;
  display: flex; justify-content: space-between; align-items: flex-start;
  font-size: 15px; font-weight: 600;
}
.iphone .notch {
  position: absolute; top: 8px; left: 50%; transform: translateX(-50%);
  width: 120px; height: 28px; background: #1A1F26; border-radius: 18px;
}
.iphone .home-indicator {
  position: absolute; bottom: 8px; left: 50%; transform: translateX(-50%);
  width: 134px; height: 5px; background: #1A1F26; border-radius: 3px;
}
.iphone-content {
  flex: 1; padding: 8px 16px 24px; display: flex; flex-direction: column;
  gap: 12px; overflow: hidden;
}
.app-title { font-size: 17px; font-weight: 700; padding: 4px 4px 0; }

/* 对话气泡区 */
.dialog-area {
  flex: 1; overflow-y: auto; padding: 8px 4px; display: flex;
  flex-direction: column; gap: 10px;
}
.bubble {
  max-width: 80%; padding: 10px 14px; border-radius: 16px;
  font-size: 15px; line-height: 1.45; word-wrap: break-word;
  animation: bubble-in .3s ease;
}
@keyframes bubble-in {
  from { opacity: 0; transform: translateY(8px); }
  to { opacity: 1; transform: translateY(0); }
}
.bubble.ai { background: var(--ai-bubble); align-self: flex-start;
             border: 1px solid #E5E7EB; }
.bubble.user { background: var(--green); color: #fff;
               align-self: flex-end; }

/* POI 卡片 */
.poi-card {
  background: #fff; border-radius: 16px; overflow: hidden;
  box-shadow: var(--shadow); margin: 8px 0;
  animation: bubble-in .3s ease;
}
.poi-card .poi-img {
  width: 100%; height: 160px; object-fit: cover; display: block;
}
.poi-card .poi-body { padding: 12px 14px; }
.poi-card .poi-name { font-size: 16px; font-weight: 700; margin-bottom: 4px; }
.poi-card .poi-meta { font-size: 13px; color: #6B7280; margin-bottom: 8px; }
.poi-card .poi-tag { font-size: 13px; color: #4B5563; margin-bottom: 12px; }
.poi-card .poi-actions { display: flex; gap: 8px; }
.poi-card .poi-actions button {
  flex: 1; padding: 10px; border-radius: 10px; border: 0;
  font-size: 14px; cursor: pointer;
}
.poi-card .btn-go { background: var(--green); color: #fff; }
.poi-card .btn-chat { background: transparent; color: var(--green);
                     border: 1px solid var(--green); }

/* 方向浮条 */
.direction-bar {
  background: rgba(123,198,126,.95); color: #fff; padding: 10px 14px;
  border-radius: 12px; font-size: 14px; font-weight: 600;
  display: flex; align-items: center; gap: 12px;
  animation: bubble-in .3s ease;
}
.direction-bar .arrow { font-size: 20px; }

/* Flash banner */
.flash {
  position: absolute; top: 60px; left: 50%; transform: translateX(-50%);
  background: rgba(26,31,38,.92); color: #fff; padding: 10px 18px;
  border-radius: 24px; font-size: 14px; opacity: 0;
  transition: opacity .3s; pointer-events: none; z-index: 10;
}
.flash.show { opacity: 1; }

/* keepsake 渲染区 */
.keepsake { border-radius: 16px; overflow: hidden;
            box-shadow: var(--shadow); margin: 8px 0; }
.keepsake img { display: block; width: 100%; }

/* 输入栏 */
.input-bar {
  display: flex; gap: 8px; align-items: center;
  background: #F3F4F6; border-radius: 24px; padding: 8px 12px;
}
.input-bar input {
  flex: 1; border: 0; background: transparent; font-size: 15px;
  outline: none; padding: 6px 0;
}
.input-bar button {
  border: 0; background: var(--green); color: #fff;
  width: 36px; height: 36px; border-radius: 50%; cursor: pointer;
  display: flex; align-items: center; justify-content: center;
  font-size: 16px;
}
.input-bar .mic { background: #E5E7EB; color: #1F2937; }
.input-bar .mic.recording { background: #DC2626; color: #fff;
                            animation: pulse 1s infinite; }
@keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: .5; } }

.session-btns { display: flex; gap: 8px; padding: 0 4px; }
.session-btns button {
  flex: 1; padding: 12px; border-radius: 12px; border: 0;
  font-size: 15px; font-weight: 600; cursor: pointer;
}
.session-btns .start { background: var(--green); color: #fff; }
.session-btns .end { background: #F3F4F6; color: #1F2937; }

/* ======== 技术面板 右侧 ======== */
.tech {
  flex: 1; min-width: 480px; background: var(--tech-bg);
  border-radius: 16px; padding: 20px; overflow-y: auto;
  display: flex; flex-direction: column; gap: 14px;
  color: var(--tech-text); font-family: ui-monospace, "SF Mono",
    Consolas, monospace; font-size: 13px;
}
.tech h2 {
  margin: 0; font-size: 11px; text-transform: uppercase;
  letter-spacing: .08em; color: var(--tech-muted); font-family: inherit;
}
.tech-block {
  background: var(--tech-panel); border-radius: 10px; padding: 12px;
  display: flex; flex-direction: column; gap: 8px;
}
.tech-block.collapsible summary {
  cursor: pointer; font-weight: 600; color: var(--tech-text);
  list-style: none; display: flex; justify-content: space-between;
}
.tech-block.collapsible summary::after {
  content: "▾"; transition: transform .2s;
}
.tech-block.collapsible[open] summary::after { transform: rotate(180deg); }

.scenario-btns { display: flex; gap: 8px; flex-wrap: wrap; }
.scenario-btns button {
  padding: 8px 12px; border-radius: 8px; border: 1px solid var(--green);
  background: transparent; color: var(--green); cursor: pointer;
  font-size: 13px; font-family: inherit;
}
.scenario-btns button:hover { background: rgba(123,198,126,.12); }
.scenario-btns button.stop { border-color: #DC2626; color: #DC2626; }

.cam-frame {
  background: #000; border-radius: 8px; overflow: hidden;
  aspect-ratio: 16/9;
}
.cam-frame img { width: 100%; height: 100%; object-fit: cover; display: block; }
.ptz-readout { display: flex; gap: 16px; font-variant-numeric: tabular-nums; }
.ptz-readout span { color: var(--tech-muted); }
.ptz-readout b { color: var(--green); margin-left: 4px; }

.log-list {
  max-height: 200px; overflow-y: auto; display: flex;
  flex-direction: column; gap: 4px; font-size: 12px;
}
.log-row {
  display: flex; gap: 8px; padding: 4px 0;
  border-bottom: 1px solid rgba(255,255,255,.05);
}
.log-row .ts { color: var(--tech-muted); flex-shrink: 0; }
.log-row .name { color: var(--green); flex-shrink: 0; }
.log-row .src { color: var(--tech-muted); font-size: 11px; }
.raw-pre {
  background: #0D1117; padding: 10px; border-radius: 6px;
  font-size: 11px; max-height: 240px; overflow: auto;
  white-space: pre-wrap; word-break: break-all; margin: 0;
}
```

- [ ] **Step 2: 提交**

```bash
git add demo/static/styles.css
git commit -m "feat(ui): styles.css for iPhone mock + tech panel layout"
```

---

### Task 13: 前端 — index.html 整页重做

**Files:**
- Modify: `demo/static/index.html`（完整覆写）

**Why:** 把 v1 简单的 grid 替换成 iPhone mock + 技术面板的双区结构。所有动态内容由 app.js（Task 14）注入。

- [ ] **Step 1: 完整覆写 demo/static/index.html**

```html
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=1400">
<title>本地引力 · 步语 demo</title>
<link rel="stylesheet" href="/static/styles.css">
</head>
<body>

<!-- ============ 左：iPhone mock ============ -->
<div class="iphone">
  <div class="notch"></div>
  <div class="status-bar">
    <span>9:41</span>
    <span>● ● ●</span>
  </div>
  <div class="iphone-content">
    <div class="app-title">本地引力 · 步语</div>
    <div class="dialog-area" id="dialog"></div>
    <div class="input-bar">
      <input id="text-input" placeholder="对它说点什么…（回车发送）" />
      <button id="mic-btn" class="mic" title="点击录音">🎙</button>
      <button id="send-btn" title="发送">↑</button>
    </div>
    <div class="session-btns">
      <button class="start" id="start-btn">开始散步</button>
      <button class="end" id="end-btn">结束散步</button>
    </div>
  </div>
  <div class="flash" id="flash"></div>
  <div class="home-indicator"></div>
</div>

<!-- ============ 右：技术面板 ============ -->
<div class="tech">
  <div class="tech-block">
    <h2>演示控制</h2>
    <div class="scenario-btns">
      <button data-scenario="companion">▶ 场景 A · 陪伴</button>
      <button data-scenario="serendipity">▶ 场景 B · 偶遇</button>
      <button data-scenario="free">⌨ 自由模式</button>
      <button class="stop" id="script-stop-btn">■ 停止脚本</button>
    </div>
  </div>

  <div class="tech-block">
    <h2>摄像头 / live MJPEG</h2>
    <div class="cam-frame"><img src="/video.mjpg" alt="cam"></div>
    <div class="ptz-readout">
      <span>pan<b id="ptz-pan">0</b></span>
      <span>tilt<b id="ptz-tilt">0</b></span>
      <span>zoom<b id="ptz-zoom">100</b></span>
      <span>src<b id="ptz-src">-</b></span>
    </div>
  </div>

  <div class="tech-block">
    <h2>工具调用</h2>
    <div class="log-list" id="tool-log"></div>
  </div>

  <details class="tech-block collapsible">
    <summary>LLM 原始消息</summary>
    <pre class="raw-pre" id="llm-raw">（尚无）</pre>
  </details>

  <details class="tech-block collapsible">
    <summary>高德 POI 原始 JSON</summary>
    <pre class="raw-pre" id="amap-raw">（尚无）</pre>
  </details>
</div>

<script src="/static/app.js"></script>
</body>
</html>
```

- [ ] **Step 2: 提交**

```bash
git add demo/static/index.html
git commit -m "feat(ui): index.html iPhone mock + tech panel layout"
```

---

### Task 14: 前端 — app.js SSE 分发 + 对话气泡 + 场景按钮

**Files:**
- Modify: `demo/static/app.js`（完整覆写）

**Why:** v1 app.js 只处理 dialog/moment 两种事件、且 DOM 结构已变。重写：按 SSE `type` 字段分发到对应渲染函数；保留原有 `/api/start` `/api/say` `/api/end`；新增场景按钮 / POI 卡 / 方向浮条 / keepsake / ptz 读数。MediaRecorder 录音留到 Task 15。

- [ ] **Step 1: 完整覆写 demo/static/app.js**

```javascript
// 步语 demo 前端：SSE 分发 + 控制
const $ = sel => document.querySelector(sel);
const dialog = $('#dialog');
const flash = $('#flash');
const toolLog = $('#tool-log');
const llmRaw = $('#llm-raw');
const amapRaw = $('#amap-raw');

function addBubble(role, text) {
  const div = document.createElement('div');
  div.className = `bubble ${role === 'user' ? 'user' : 'ai'}`;
  div.textContent = text;
  dialog.appendChild(div);
  dialog.scrollTop = dialog.scrollHeight;
}

function showFlash(text, ms = 2200) {
  flash.textContent = text;
  flash.classList.add('show');
  setTimeout(() => flash.classList.remove('show'), ms);
}

function addPoiCard(p) {
  const card = document.createElement('div');
  card.className = 'poi-card';
  card.dataset.poiId = p.poi_id;
  card.innerHTML = `
    <img class="poi-img" src="${p.image_url}" alt="${p.name}">
    <div class="poi-body">
      <div class="poi-name">${p.name}</div>
      <div class="poi-meta">
        ${p.rating ? `${p.rating}★ · ` : ''}
        ${p.cost ? `¥${p.cost} · ` : ''}
        ${p.distance_m}m · 步行约 ${Math.max(1, Math.round(p.distance_m / 80))} 分钟
      </div>
      <div class="poi-tag">${p.tagline || ''}</div>
      <div class="poi-actions">
        <button class="btn-go">去看看</button>
        <button class="btn-chat">聊聊它</button>
      </div>
    </div>`;
  card.querySelector('.btn-go').onclick = () => {
    showFlash(`已为你标记方向：${p.name}`);
  };
  card.querySelector('.btn-chat').onclick = () => {
    sendText(`聊聊${p.name}`);
  };
  dialog.appendChild(card);
  dialog.scrollTop = dialog.scrollHeight;
}

function swapPoiImage(poi_id, image_url) {
  const card = dialog.querySelector(`.poi-card[data-poi-id="${poi_id}"]`);
  if (!card) return;
  const img = card.querySelector('.poi-img');
  if (img) img.src = image_url;
}

function addDirection(d) {
  const arrows = { left: '←', right: '→', up: '↑', down: '↓' };
  const div = document.createElement('div');
  div.className = 'direction-bar';
  div.innerHTML = `<span class="arrow">${arrows[d.arrow] || '•'}</span>
    <span>${d.label || ''} · ${d.distance_m}m · 步行约 ${d.eta_min} 分钟</span>`;
  dialog.appendChild(div);
  dialog.scrollTop = dialog.scrollHeight;
}

function addKeepsake(url) {
  const div = document.createElement('div');
  div.className = 'keepsake';
  div.innerHTML = `<img src="${url}?t=${Date.now()}" alt="散步合影">`;
  dialog.appendChild(div);
  dialog.scrollTop = dialog.scrollHeight;
}

function addToolLog(ev) {
  const ts = new Date().toLocaleTimeString().slice(3, 8);
  const row = document.createElement('div');
  row.className = 'log-row';
  row.innerHTML = `<span class="ts">${ts}</span>
    <span class="name">${ev.name}</span>
    <span class="src">[${ev.source || '?'}]</span>
    <span>${JSON.stringify(ev.args || {}).slice(0, 80)}</span>`;
  toolLog.prepend(row);
  while (toolLog.childElementCount > 50) toolLog.lastChild.remove();
}

function updatePtz(ev) {
  $('#ptz-pan').textContent = ev.pan ?? '-';
  $('#ptz-tilt').textContent = ev.tilt ?? '-';
  $('#ptz-zoom').textContent = ev.zoom ?? '-';
  $('#ptz-src').textContent = ev.source || '-';
}

// ============ SSE ============
const es = new EventSource('/events');
es.onmessage = (e) => {
  let ev;
  try { ev = JSON.parse(e.data); } catch { return; }
  switch (ev.type) {
    case 'dialog': addBubble(ev.role, ev.text); break;
    // 兼容 v1 老事件名
    case 'assistant.say': addBubble('ai', ev.text); break;
    case 'user.say': addBubble('user', ev.text); break;
    case 'moment': showFlash(`已记下：${ev.label}`); break;
    case 'poi_card': addPoiCard(ev); break;
    case 'poi_image_swap': swapPoiImage(ev.poi_id, ev.image_url); break;
    case 'direction': addDirection(ev); break;
    case 'keepsake': addKeepsake(ev.url); break;
    case 'tool_call': addToolLog(ev); break;
    case 'ptz': updatePtz(ev); break;
    case 'amap_raw':
      amapRaw.textContent = JSON.stringify(ev, null, 2);
      break;
    case 'llm_raw':
      llmRaw.textContent = JSON.stringify(ev, null, 2);
      break;
    case 'script':
      // 静默：可在 console 看
      console.debug('script step', ev);
      break;
  }
};

// ============ 控制 ============
async function sendText(text) {
  if (!text.trim()) return;
  await fetch('/api/say', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ text }),
  });
}

$('#send-btn').onclick = () => {
  const inp = $('#text-input');
  const t = inp.value;
  inp.value = '';
  sendText(t);
};
$('#text-input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter') $('#send-btn').click();
});

$('#start-btn').onclick = async () => {
  await fetch('/api/start', { method: 'POST' });
};
$('#end-btn').onclick = async () => {
  const r = await fetch('/api/end', { method: 'POST' });
  const d = await r.json();
  if (d.keepsake_url) addKeepsake(d.keepsake_url);
};

// 场景按钮
document.querySelectorAll('.scenario-btns button[data-scenario]').forEach(btn => {
  btn.onclick = async () => {
    const scenario = btn.dataset.scenario;
    if (scenario === 'free') {
      await fetch('/api/script/stop', { method: 'POST' });
      showFlash('已切到自由模式');
      return;
    }
    const r = await fetch('/api/script/start', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ scenario }),
    });
    if (!r.ok) showFlash('启动失败：' + (await r.text()));
  };
});
$('#script-stop-btn').onclick = async () => {
  await fetch('/api/script/stop', { method: 'POST' });
  showFlash('脚本已停止');
};
```

- [ ] **Step 2: 手工冒烟（启动 server）**

Run（先确保 Task 5 / 6 已跑过，5 张图 + .env 都到位）：

```
python -m demo.server
```

然后浏览器开 `http://127.0.0.1:8788/`：
- 左边能看到 iPhone mock + 输入栏 + 开始/结束按钮
- 右边能看到 4 个场景按钮 + camera live + PTZ readout（会显示 0/0/100）
- 点 "▶ 场景 A · 陪伴"：90s 内时间轴推进，气泡 / POI 卡 / flash / ptz 读数 / tool_log 全有动作

如果 SSE 不连：F12 console 看 EventSource 报错。

- [ ] **Step 3: 提交**

```bash
git add demo/static/app.js
git commit -m "feat(ui): app.js SSE dispatch + scenario buttons + POI cards"
```

---

### Task 15: 前端 — MediaRecorder 录音 + /api/voice 集成

**Files:**
- Modify: `demo/static/app.js`（追加录音逻辑）

**Why:** Task 14 已经搭好 mic 按钮 DOM 和后端路由，这一步只接 MediaRecorder。点击切 toggle，松手不发——拿到 text 只填到输入框，由用户决定发不发。

- [ ] **Step 1: 在 app.js 末尾追加**

把以下代码加到 `demo/static/app.js` 末尾（不要替换，是 append）：

```javascript
// ============ Whisper 录音 ============
let recorder = null;
let chunks = [];
let stream = null;
const micBtn = $('#mic-btn');

async function startRecording() {
  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  } catch (e) {
    showFlash('麦克风权限被拒');
    return false;
  }
  const mime = MediaRecorder.isTypeSupported('audio/webm;codecs=opus')
    ? 'audio/webm;codecs=opus' : 'audio/webm';
  recorder = new MediaRecorder(stream, { mimeType: mime });
  chunks = [];
  recorder.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data); };
  recorder.onstop = async () => {
    const blob = new Blob(chunks, { type: mime });
    stream.getTracks().forEach(t => t.stop());
    micBtn.classList.remove('recording');
    showFlash('转写中…', 1200);
    const fd = new FormData();
    fd.append('audio', blob, 'voice.webm');
    try {
      const r = await fetch('/api/voice', { method: 'POST', body: fd });
      const d = await r.json();
      if (d.text) {
        $('#text-input').value = d.text;
        $('#text-input').focus();
      } else {
        showFlash('没听清');
      }
    } catch (e) {
      showFlash('转写失败');
    }
  };
  recorder.start();
  micBtn.classList.add('recording');
  return true;
}

function stopRecording() {
  if (recorder && recorder.state === 'recording') {
    recorder.stop();
    recorder = null;
  }
}

micBtn.onclick = async () => {
  if (recorder && recorder.state === 'recording') {
    stopRecording();
  } else {
    await startRecording();
  }
};
```

- [ ] **Step 2: 手工冒烟**

启动 server（`python -m demo.server`），浏览器开 8788，点麦克风（首次会弹权限对话框）→ 说一句话 → 再次点击 → 等 2-5s → 输入框出现转写文本 → 按发送。

如果 chrome 报 `NotAllowedError`：地址栏点 🔒 改权限。

- [ ] **Step 3: 提交**

```bash
git add demo/static/app.js
git commit -m "feat(ui): MediaRecorder voice input via /api/voice"
```

---

### Task 16: RUNBOOK 更新（v2 启动序）

**Files:**
- Modify: `demo/RUNBOOK.md`（完整覆写）

**Why:** v2 多了两步预生成 + 场景按钮 + 录音；老 runbook 不够用。

- [ ] **Step 1: 完整覆写 demo/RUNBOOK.md**

```markdown
# Demo Runbook v2 (≈3 min recording)

## Pre-flight (一次性)

1. `.env` 已存在且填了 `AMAP_KEY` / `OPENAI_NEXT_API_KEY`
   （参考 `.env.example`）
2. 摄像头插好；`tasklist | findstr python` 没有遗留 python
3. Tailscale 连上；`curl http://100.99.139.20:18141/v1/models` 正常
4. 浏览器允许麦克风（首次开 8788 会弹权限）
5. OBS / Win+G 准备好录浏览器窗口 + 系统音

## 一次性预生成（首装时跑一次；之后缓存即可）

```
python -m demo.cli.prebake_images   # ~1-2 min, 5 张图
python -m demo.cli.prebake_pois     # ~5s, 1 个缓存文件
```

## 启动

```
python -m demo.server
```

等 `demo server up: http://127.0.0.1:8788/`，浏览器全屏打开。

## 录制脚本（≈3 min）

### 段 1：场景 A 陪伴（90s）
1. 开始录像
2. 右侧点 "▶ 场景 A · 陪伴"
3. 跟着脚本看：AI 自动主动开口 → 转向湖 → 用户问"那是什么塔" →
   AI 调 VLM → POI 卡片（鸡鸣寺）→ 记一下 → 环视 → keepsake

### 段 2：场景 B 偶遇（60s）
4. 点 "▶ 场景 B · 偶遇"
5. AI 主动推荐 Beans Solo → POI 卡片 + 方向浮条 → 用户问"长什么样" →
   卡片图换成内景 → 用户"走吧" → keepsake

### 段 3：自由模式真演（30s）
6. 点 "⌨ 自由模式"
7. 点麦克风说一句"周围有什么"，松手等转写 → 按发送 → 看真实 AI 反应

8. 停止录像

总长 ≈ 3 min。

## 出错恢复
- 摄像头帧停：忽略，AI 会说"我没看清"
- LLM 超时：等或重启 server，重录
- 脚本卡住：右上角 "■ 停止脚本"

## 重录
每次录完删 `demo_runtime/`（保留 `cache/`，那里是预生成的图和 POI）。

```
rm -rf demo_runtime/keepsake_*.png demo_runtime/moments
```

cache 不删，下次启动秒开。
```

- [ ] **Step 2: 提交**

```bash
git add demo/RUNBOOK.md
git commit -m "docs: v2 RUNBOOK with prebake + scenarios + voice"
```

---

### Task 17: 端到端联调

**Files:**
- 不改代码，只联调 + 修问题 + 记录

**Why:** 单 task 全 mock 测过，但 demo 上线前必须人肉跑一遍三个场景，看节拍 / 视觉 / 错误对话框。

- [ ] **Step 1: 启动 server**

```
python -m demo.server
```

浏览器开 8788，F12 console 打开备用。

- [ ] **Step 2: 跑场景 A 全流程**

点 "▶ 场景 A · 陪伴"，看：
- 0s 第一句气泡是否出现 + TTS 出声
- 8s 摄像头是否物理转向 + 右侧 PTZ readout 数字变化
- 18s scripted_user 气泡是否右侧绿色
- 35s POI 卡片是否带图 + meta 行 + 两个按钮
- 50s flash banner 是否弹出"已记下"
- 65s 摄像头 sweep 是否真的左右扫
- 85s keepsake 图是否渲染到对话区底部

任一项失败：看 console 报错 / server 终端 traceback，修了再跑。

- [ ] **Step 3: 跑场景 B 全流程**

刷新页面（清空对话），点 "▶ 场景 B · 偶遇"，看：
- 11s POI 卡片图是否是 storefront
- 26s 同一个卡片图是否换成 interior（不是新加卡片）
- 41s 摄像头是否左转
- 58s keepsake 是否渲染

- [ ] **Step 4: 跑自由模式 + 录音**

点 "⌨ 自由模式"，再点麦克风录 "周围有什么"，松手等转写 → 输入框文本对 → 发送 → 看真实 agent 是否调 pan_camera/analyze_frame_vlm。

- [ ] **Step 5: 修问题 + 提交**

如果有问题在 Task 17 阶段修：直接改对应文件，单独 commit：

```bash
git add <files>
git commit -m "fix(v2): <具体问题>"
```

如果没问题，加一个空 commit 标记里程碑：

```bash
git commit --allow-empty -m "chore(v2): end-to-end smoke passed"
```

---

### Task 18: 全量回归 + tag

**Files:**
- 无代码改动

- [ ] **Step 1: 跑全部单元测试**

Run: `pytest demo/tests -v`
Expected: 全部 PASS（v1 + v2 累计 30+ test）

- [ ] **Step 2: 跑 smoke**

```
python scripts/smoke_camera.py
python scripts/smoke_amap.py
python scripts/smoke_media.py
```

Expected: 三个都打印 ok。

- [ ] **Step 3: 打 tag**

```bash
git tag -a v2-demo-ready -m "v2 demo: PTZ active + Amap POIs + scripted scenarios + openai-next media"
```

- [ ] **Step 4: 验证 tag**

Run: `git tag -l v2-*`
Expected: `v2-demo-ready`

---

## 自审清单（计划写完后检查）

**Spec 覆盖核对：**

| spec 章节 | 实现 task |
|---|---|
| §2.1 进程拓扑 / 路由 | Task 10 |
| §2.2 SSE 通道 9 种 type | Task 7（script 发） + Task 9（agent 发） + Task 10（ptz / dialog / moment / keepsake / amap_raw） |
| §3.1 双面板布局 | Task 12 + 13 |
| §3.2 录音交互 | Task 15 |
| §3.3 POI 卡片 | Task 14 |
| §3.4 方向指引 | Task 14（addDirection） |
| §4.1 AmapClient | Task 3 |
| §4.2 启动期预拉 | Task 6 |
| §4.3 Beans Solo 锁定 | Task 6（pois_v2.json） |
| §5 主动 PTZ prompt + reason | Task 8 |
| §6 MediaClient | Task 4 |
| §7 ScriptPlayer + 两场景 | Task 7 |
| §8 图片预生成 5 张 | Task 5 |
| §9 Whisper 前后端 | Task 4 + 10 + 15 |
| §10 .env / 启动序 | Task 1 + 16 |
| §11 错误降级 | Task 5（重试 3 次）+ Task 10（启动期校验图）+ Task 15（toast） |
| §12 测试 | Task 1/2/3/4/7/8/9/10 都带测试；smoke = Task 11 |

**类型 / 命名一致性：**

- `EventBus.publish(ev: dict)` ✅（Task 2/3/7/9/10 全用同签名）
- `POI` dataclass 字段 ✅（Task 3 定义、Task 7 测试用、Task 14 前端读 `image_url/distance_m/rating/cost/tagline/name`）
- `pois_v2.json` schema：`scripted[].image_id` ✅（Task 6 写、Task 7 读、Task 10 校验路径 `/poi_image/{image_id}.png`）
- ScriptPlayer 构造函数参数顺序在 Task 7 测试 / Task 10 server 注入处一致 ✅

**Placeholder 扫描：**

- 没有 TODO / TBD / "类似 Task N"
- 每个 Step 要么是命令、要么是完整 code block

无需要修补的 gap。

---

## 执行交接

Plan 写完，存 `docs/superpowers/plans/2026-05-02-link2pro-windows-demo-v2.md`。两种执行方式：

1. **Subagent-Driven（推荐）** — 我每个 task 派一个 fresh subagent，跑完做 spec compliance + code quality 两道 review，再提交，再下一个。
2. **Inline Execution** — 我在当前 session 里串行做 Task 1~18，每完成一组停下来等你 checkpoint。

你选哪个？

