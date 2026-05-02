# Link 2 Pro × Windows Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Windows-only Python demo that drives an Insta360 Link 2 Pro via DirectShow + ffmpeg, runs an LLM agent loop with 6 tools against the internal Claude/GPT endpoint, and produces a recordable end-to-end "AI walking partner" experience suitable for a 3-minute demo video.

**Architecture:** FastAPI app on `127.0.0.1:8788`. One `CameraController` (PTZ + MJPEG frame window). One `AgentRuntime` (sequential ReAct loop, OpenAI-compatible tool calls). Six tools (frame fetch, VLM, TTS-speak, record_moment, pan_camera, recommend_nearby_place). Browser SPA shows live MJPEG, dialog stream (SSE), and keepsake panel. End-of-session keepsake = PIL collage of 5 frames + dialog quotes.

**Tech Stack:** Python 3.12, FastAPI + uvicorn, comtypes (DirectShow IAMCameraControl), pygrabber (device enum), ffmpeg (dshow MJPEG capture), pyttsx3 (Windows SAPI TTS), Pillow (keepsake collage), httpx (LLM client), pytest.

**Reference spec:** `docs/superpowers/specs/2026-05-02-link2pro-windows-demo-design.md`
**Reference impl:** `ptz_server_win.py` (working camera + PTZ proof; we copy its DirectShow logic).

---

## File Structure

All new code lives under `demo/`. Existing files (`ptz_server_win.py`, Swift sources, etc.) are untouched.

```
demo/
├── __init__.py
├── server.py              # FastAPI entry point, routes, SSE broker, session lifecycle
├── camera.py              # CameraController: PTZ worker + ffmpeg MJPEG worker + FrameWindow
├── llm.py                 # OpenAI-compatible httpx client (chat completions, vision)
├── agent.py               # AgentRuntime: ReAct loop, tool dispatch
├── tools.py               # Tool base + 6 tool classes
├── tts.py                 # pyttsx3 wrapper (background thread queue)
├── dialog.py              # DialogLog + MomentLog (in-memory append-only)
├── keepsake.py            # PIL collage builder
├── prompts.py             # system prompt + proactive prompt strings
├── data/
│   └── nanjing_pois.json  # 6 frozen POIs
├── static/
│   ├── index.html
│   └── app.js
├── tests/
│   ├── __init__.py
│   ├── test_dialog.py
│   ├── test_tools.py
│   ├── test_agent.py
│   ├── test_keepsake.py
│   └── fixtures/
│       └── sample_frame.jpg   # 1280x720 JPEG fixture for tests
└── README.md
```

**Boundary rules:**
- `camera.py` is the ONLY module that touches DirectShow / ffmpeg / pygrabber.
- `llm.py` is the ONLY module that knows the LLM endpoint URL or auth shape.
- `tools.py` depends on `camera.py`, `llm.py`, `tts.py`, `dialog.py` — never the other direction.
- `agent.py` depends on `tools.py` and `llm.py` only.
- `server.py` is the composition root — it constructs everything and wires routes.

**Test strategy:** `camera.py`, `tts.py`, and `server.py` are I/O-heavy and not unit-tested — they're smoke-tested via the running app. Pure logic (`dialog.py`, `keepsake.py`, the agent loop with mocked LLM, tools with mocked camera/LLM) is unit-tested with pytest.

---

## Task 1: Project skeleton + dependencies

**Files:**
- Create: `demo/__init__.py`
- Create: `demo/tests/__init__.py`
- Create: `demo/requirements.txt`
- Create: `demo/README.md`

- [ ] **Step 1: Create empty package files**

```bash
mkdir -p demo/tests demo/data demo/static demo/tests/fixtures
echo "" > demo/__init__.py
echo "" > demo/tests/__init__.py
```

- [ ] **Step 2: Pin dependencies in `demo/requirements.txt`**

```
fastapi==0.115.0
uvicorn[standard]==0.32.0
httpx==0.27.2
pillow==10.4.0
pyttsx3==2.91
pygrabber==0.2
comtypes==1.4.16
pytest==8.3.3
pytest-asyncio==0.24.0
```

- [ ] **Step 3: Install**

Run from project root:
```
pip install --proxy http://127.0.0.1:7897 -r demo/requirements.txt
```
Expected: all packages resolve; comtypes/pygrabber already present.

- [ ] **Step 4: Write `demo/README.md`**

```markdown
# walk-talk demo (Windows)

End-to-end Insta360 Link 2 Pro × LLM agent demo. See
`docs/superpowers/specs/2026-05-02-link2pro-windows-demo-design.md` for design.

## Prereqs
- Windows 10/11
- Insta360 Link 2 Pro plugged in (DirectShow name "Insta360 Link 2")
- ffmpeg on PATH (or `C:\ffmpeg\bin\ffmpeg.exe`)
- Network access to `http://100.99.139.20:18141` (Tailscale)

## Run
```
pip install -r demo/requirements.txt
python -m demo.server
```
Open http://127.0.0.1:8788/

## Tests
```
pytest demo/tests -v
```
```

- [ ] **Step 5: Commit**

```bash
git add demo/
git commit -m "demo: scaffold package + pinned deps"
```

---

## Task 2: Frozen Nanjing POI dataset

**Files:**
- Create: `demo/data/nanjing_pois.json`

- [ ] **Step 1: Write `demo/data/nanjing_pois.json`**

Six well-known Nanjing landmarks with real GCJ-02 coordinates and short
descriptions written for the agent to read. The "imagined_distance_m" is
what the agent will narrate as "前面 N 米" — they're plausible inter-POI
distances, not real ones.

```json
{
  "anchor": {
    "name": "玄武湖公园",
    "longitude": 118.79532,
    "latitude": 32.07553,
    "note": "Pretend the user starts here at 玄武门."
  },
  "pois": [
    {
      "id": "xuanwu_lake",
      "name": "玄武湖",
      "longitude": 118.79532,
      "latitude": 32.07553,
      "imagined_distance_m": 0,
      "tagline": "南京城内最大的皇家园林湖泊，环湖一圈约 9 公里",
      "vibe": "湖光、樱洲、远山，最适合慢走"
    },
    {
      "id": "jiming_temple",
      "name": "鸡鸣寺",
      "longitude": 118.79077,
      "latitude": 32.06219,
      "imagined_distance_m": 200,
      "tagline": "南朝四百八十寺之首，春天樱花路尽头的素斋名刹",
      "vibe": "黄墙、香火、台城旁的高地视野"
    },
    {
      "id": "zifeng_tower",
      "name": "紫峰大厦",
      "longitude": 118.78095,
      "latitude": 32.06303,
      "imagined_distance_m": 600,
      "tagline": "南京第一高楼，450 米 89 层，鼓楼广场地标",
      "vibe": "玻璃幕墙、城市天际线背景板"
    },
    {
      "id": "xinjiekou",
      "name": "新街口",
      "longitude": 118.78030,
      "latitude": 32.04210,
      "imagined_distance_m": 1800,
      "tagline": "中华第一商圈，地铁 1/2 号线交汇",
      "vibe": "人潮、霓虹、孙中山雕像下的车流"
    },
    {
      "id": "fuzimiao",
      "name": "夫子庙",
      "longitude": 118.78890,
      "latitude": 32.02250,
      "imagined_distance_m": 4500,
      "tagline": "秦淮河畔孔庙建筑群，灯会与小吃集散地",
      "vibe": "河、画舫、糖芋苗、鸭血粉丝汤"
    },
    {
      "id": "ming_xiaoling",
      "name": "明孝陵",
      "longitude": 118.84408,
      "latitude": 32.05600,
      "imagined_distance_m": 5200,
      "tagline": "明太祖朱元璋陵墓，紫金山南麓神道两侧石象路",
      "vibe": "石象、银杏、秋色"
    }
  ]
}
```

- [ ] **Step 2: Verify it parses**

Run:
```
python -c "import json; d=json.load(open('demo/data/nanjing_pois.json',encoding='utf-8')); print(len(d['pois']),'pois')"
```
Expected: `6 pois`

- [ ] **Step 3: Commit**

```bash
git add demo/data/nanjing_pois.json
git commit -m "demo: add frozen Nanjing POI dataset (6 landmarks)"
```

---

## Task 3: DialogLog & MomentLog (TDD)

**Files:**
- Create: `demo/dialog.py`
- Create: `demo/tests/test_dialog.py`

- [ ] **Step 1: Write the failing tests**

```python
# demo/tests/test_dialog.py
import time
from demo.dialog import DialogLog, MomentLog, DialogTurn, Moment


def test_dialog_log_append_and_iter():
    log = DialogLog()
    log.append("user", "你好")
    log.append("assistant", "你好，今天去哪儿？")
    turns = list(log)
    assert [t.role for t in turns] == ["user", "assistant"]
    assert turns[0].text == "你好"
    assert turns[0].timestamp <= turns[1].timestamp


def test_dialog_log_subscribe_receives_new_turns():
    log = DialogLog()
    received: list[DialogTurn] = []
    unsub = log.subscribe(received.append)
    log.append("user", "嘿")
    log.append("assistant", "在")
    assert len(received) == 2
    assert received[0].text == "嘿"
    unsub()
    log.append("user", "no one home")
    assert len(received) == 2  # unsubscribed


def test_moment_log_append_and_list():
    ml = MomentLog()
    ml.append(label="记一下这个", frame_path="/tmp/a.jpg")
    ml.append(label="还有那个", frame_path="/tmp/b.jpg")
    moments = list(ml)
    assert len(moments) == 2
    assert moments[0].label == "记一下这个"
    assert isinstance(moments[0].timestamp, float)
```

- [ ] **Step 2: Run tests to confirm they fail**

Run: `pytest demo/tests/test_dialog.py -v`
Expected: ImportError on `demo.dialog`.

- [ ] **Step 3: Implement `demo/dialog.py`**

```python
"""Append-only logs for the demo session."""
from __future__ import annotations
import threading
import time
from dataclasses import dataclass, field
from typing import Callable, Iterator, Literal

Role = Literal["user", "assistant", "system", "tool"]


@dataclass(frozen=True)
class DialogTurn:
    role: Role
    text: str
    timestamp: float


@dataclass(frozen=True)
class Moment:
    label: str
    frame_path: str
    timestamp: float


class DialogLog:
    def __init__(self) -> None:
        self._turns: list[DialogTurn] = []
        self._subs: list[Callable[[DialogTurn], None]] = []
        self._lock = threading.Lock()

    def append(self, role: Role, text: str) -> DialogTurn:
        turn = DialogTurn(role=role, text=text, timestamp=time.time())
        with self._lock:
            self._turns.append(turn)
            subs = list(self._subs)
        for fn in subs:
            try:
                fn(turn)
            except Exception:
                pass  # subscriber failure is never fatal
        return turn

    def __iter__(self) -> Iterator[DialogTurn]:
        with self._lock:
            return iter(list(self._turns))

    def subscribe(self, fn: Callable[[DialogTurn], None]) -> Callable[[], None]:
        with self._lock:
            self._subs.append(fn)

        def unsub() -> None:
            with self._lock:
                if fn in self._subs:
                    self._subs.remove(fn)

        return unsub


class MomentLog:
    def __init__(self) -> None:
        self._items: list[Moment] = []
        self._lock = threading.Lock()

    def append(self, *, label: str, frame_path: str) -> Moment:
        m = Moment(label=label, frame_path=frame_path, timestamp=time.time())
        with self._lock:
            self._items.append(m)
        return m

    def __iter__(self) -> Iterator[Moment]:
        with self._lock:
            return iter(list(self._items))
```

- [ ] **Step 4: Run tests to confirm they pass**

Run: `pytest demo/tests/test_dialog.py -v`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add demo/dialog.py demo/tests/test_dialog.py
git commit -m "demo: DialogLog + MomentLog with subscribe pattern"
```

---

## Task 4: CameraController (extracted from ptz_server_win.py)

This is a refactor of the existing `ptz_server_win.py` into a single class with a clean public API. **No behavior change.** I/O-bound, not unit-tested — verified by running the smoke script in step 3.

**Files:**
- Create: `demo/camera.py`
- Create: `scripts/smoke_camera.py`

- [ ] **Step 1: Implement `demo/camera.py`**

Copy the full module contents from `ptz_server_win.py` lines 49-260, refactored into a `CameraController` class with this exact public surface:

```python
@dataclass(frozen=True)
class Frame:
    jpeg: bytes
    captured_at: float

@dataclass(frozen=True)
class Position:
    pan: int
    tilt: int
    zoom: int

class CameraController:
    DEVICE_NAME = "Insta360 Link 2"
    FRAME_WINDOW_SECONDS = 300

    def __init__(self) -> None: ...
    @property
    def ranges(self) -> dict[str, tuple[int, int]]: ...
    def position(self) -> Position: ...
    def set_position(self, *, pan=None, tilt=None, zoom=None) -> Position: ...
    def move(self, direction: str, step: int) -> Position: ...
    def sweep(self) -> None: ...   # left -60, right +60, back to 0; ~3s total
    def latest_frame(self) -> Frame | None: ...
    def frame_at(self, t: float) -> Frame | None: ...   # closest <= t
    def mjpeg_iter(self) -> Iterator[bytes]: ...   # blocks per frame
```

Internal structure (one PTZ worker thread for COM, one ffmpeg I/O thread for frames). Frames stored in a `deque[Frame]`, evicted older than `FRAME_WINDOW_SECONDS`. Use `threading.Condition` to wake the MJPEG iterator. Direction strings for `move`: `left/right/up/down/center/zoom_in/zoom_out`. `find_ffmpeg()` helper checks `shutil.which("ffmpeg")` then `C:\ffmpeg\bin\ffmpeg.exe`.

The DirectShow `IAMCameraControl` definition, the `_PTZWorker` thread class, `_spawn_ffmpeg`, and `_camera_loop` are direct ports of `ptz_server_win.py` — copy them verbatim into the module.

- [ ] **Step 2: Write smoke script `scripts/smoke_camera.py`**

```python
import time
from demo.camera import CameraController

cam = CameraController()
print("ranges:", cam.ranges)
print("pos:", cam.position())
print("waiting for first frame...")
deadline = time.time() + 5
while time.time() < deadline:
    f = cam.latest_frame()
    if f:
        print(f"first frame: {len(f.jpeg)} bytes at {f.captured_at}")
        break
    time.sleep(0.1)
else:
    raise SystemExit("no frame in 5s")

print("set_position pan=20...")
print(cam.set_position(pan=20))
time.sleep(0.5)
print(cam.set_position(pan=0, tilt=0, zoom=100))
print("OK")
```

- [ ] **Step 3: Run smoke test**

```bash
mkdir -p scripts
python scripts/smoke_camera.py
```

Expected: ranges printed, first frame >5 KB within 5s, camera physically moves to pan=20 then back to 0. If "camera not found" — confirm device name with `ffmpeg -f dshow -list_devices true -i dummy` and update `DEVICE_NAME` if needed.

- [ ] **Step 4: Commit**

```bash
git add demo/camera.py scripts/smoke_camera.py
git commit -m "demo: CameraController (PTZ + MJPEG frame window)"
```

---

## Task 5: LLM client (`llm.py`)

**Files:**
- Create: `demo/llm.py`
- Create: `demo/tests/test_llm.py`

- [ ] **Step 1: Write the failing test (mocked httpx)**

```python
# demo/tests/test_llm.py
import json
import pytest
from unittest.mock import patch, MagicMock
from demo.llm import LLMClient, ToolCall


def _fake_response(payload):
    r = MagicMock()
    r.status_code = 200
    r.json.return_value = payload
    r.raise_for_status = MagicMock()
    return r


def test_chat_returns_text_when_no_tool_calls():
    client = LLMClient(base_url="http://x", api_key="", model="m")
    payload = {"choices": [{"message": {"role": "assistant", "content": "hello"}}]}
    with patch.object(client._http, "post", return_value=_fake_response(payload)) as p:
        msg = client.chat(messages=[{"role": "user", "content": "hi"}], tools=[])
    assert msg.content == "hello"
    assert msg.tool_calls == []
    sent = p.call_args.kwargs["json"]
    assert sent["model"] == "m"


def test_chat_parses_tool_calls():
    client = LLMClient(base_url="http://x", api_key="", model="m")
    payload = {"choices": [{"message": {
        "role": "assistant", "content": None,
        "tool_calls": [{
            "id": "c1", "type": "function",
            "function": {"name": "foo", "arguments": '{"a": 1}'}
        }]}}]}
    with patch.object(client._http, "post", return_value=_fake_response(payload)):
        msg = client.chat(messages=[], tools=[])
    assert msg.tool_calls == [ToolCall(id="c1", name="foo", arguments={"a": 1})]
```

- [ ] **Step 2: Run tests to confirm they fail**

`pytest demo/tests/test_llm.py -v` → ImportError on `demo.llm`.

- [ ] **Step 3: Implement `demo/llm.py`**

```python
"""OpenAI-compatible client for the internal endpoint."""
from __future__ import annotations
import base64
import json
from dataclasses import dataclass, field
from typing import Any
import httpx

DEFAULT_BASE_URL = "http://100.99.139.20:18141"
DEFAULT_PLANNER_MODEL = "claude-sonnet-4.5"
DEFAULT_VLM_MODEL = "gpt-4o-2024-11-20"


@dataclass(frozen=True)
class ToolCall:
    id: str
    name: str
    arguments: dict[str, Any]


@dataclass(frozen=True)
class AssistantMessage:
    content: str | None
    tool_calls: list[ToolCall] = field(default_factory=list)


class LLMClient:
    def __init__(self, *, base_url: str = DEFAULT_BASE_URL, api_key: str = "",
                 model: str = DEFAULT_PLANNER_MODEL, vlm_model: str = DEFAULT_VLM_MODEL,
                 timeout: float = 60.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.vlm_model = vlm_model
        self._http = httpx.Client(timeout=timeout, headers={
            "authorization": f"Bearer {api_key}",
            "content-type": "application/json",
        })

    def chat(self, *, messages: list[dict], tools: list[dict],
             model: str | None = None) -> AssistantMessage:
        body = {"model": model or self.model, "messages": messages}
        if tools:
            body["tools"] = tools
            body["tool_choice"] = "auto"
        r = self._http.post(f"{self.base_url}/v1/chat/completions", json=body)
        r.raise_for_status()
        msg = r.json()["choices"][0]["message"]
        tcs: list[ToolCall] = []
        for tc in msg.get("tool_calls") or []:
            try:
                args = json.loads(tc["function"]["arguments"] or "{}")
            except json.JSONDecodeError:
                args = {"_raw": tc["function"]["arguments"]}
            tcs.append(ToolCall(id=tc["id"], name=tc["function"]["name"], arguments=args))
        return AssistantMessage(content=msg.get("content"), tool_calls=tcs)

    def vlm(self, *, jpeg_bytes: bytes, question: str) -> str:
        b64 = base64.b64encode(jpeg_bytes).decode()
        messages = [{
            "role": "user",
            "content": [
                {"type": "text", "text": question},
                {"type": "image_url",
                 "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
            ],
        }]
        r = self._http.post(f"{self.base_url}/v1/chat/completions",
                            json={"model": self.vlm_model, "messages": messages})
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"] or ""
```

- [ ] **Step 4: Run tests to confirm they pass**

`pytest demo/tests/test_llm.py -v` → 2 passed.

- [ ] **Step 5: Live smoke test against real endpoint**

Run:
```
python -c "from demo.llm import LLMClient; c=LLMClient(); print(c.chat(messages=[{'role':'user','content':'用一句话介绍南京玄武湖'}], tools=[]).content)"
```
Expected: a Chinese sentence about 玄武湖. If timeout/network error: confirm Tailscale is up.

- [ ] **Step 6: Commit**

```bash
git add demo/llm.py demo/tests/test_llm.py
git commit -m "demo: LLM client (chat with tools + vision)"
```

---

## Task 6: TTS service (`tts.py`)

**Files:**
- Create: `demo/tts.py`
- Create: `scripts/smoke_tts.py`

- [ ] **Step 1: Implement `demo/tts.py`**

```python
"""pyttsx3-backed TTS, runs in a dedicated thread with a queue."""
from __future__ import annotations
import queue
import threading
from typing import Optional


class TTSService:
    def __init__(self, *, voice_substring: str = "Huihui", rate: int = 200) -> None:
        # pyttsx3 init must happen on the speaker thread on Windows.
        self._q: queue.Queue[Optional[str]] = queue.Queue()
        self._voice_substring = voice_substring
        self._rate = rate
        self._t = threading.Thread(target=self._run, name="tts", daemon=True)
        self._t.start()

    def _run(self) -> None:
        import pyttsx3
        engine = pyttsx3.init()
        engine.setProperty("rate", self._rate)
        for v in engine.getProperty("voices"):
            if self._voice_substring.lower() in v.name.lower():
                engine.setProperty("voice", v.id)
                break
        while True:
            text = self._q.get()
            if text is None:
                break
            try:
                engine.say(text)
                engine.runAndWait()
            except Exception:
                pass

    def say(self, text: str) -> None:
        self._q.put(text)

    def shutdown(self) -> None:
        self._q.put(None)
```

- [ ] **Step 2: Smoke test**

`scripts/smoke_tts.py`:
```python
import time
from demo.tts import TTSService
tts = TTSService()
tts.say("你好，我是本地引力。")
time.sleep(4)
```

Run: `python scripts/smoke_tts.py` — you should hear a Chinese voice. If it speaks English, the Huihui voice isn't installed; either install Microsoft Huihui (Settings → Time & Language → Speech) or change `voice_substring` to "Zira" / "" and accept English for the demo.

- [ ] **Step 3: Commit**

```bash
git add demo/tts.py scripts/smoke_tts.py
git commit -m "demo: TTS service backed by pyttsx3"
```

---

## Task 7: Prompts and POI accessor

**Files:**
- Create: `demo/prompts.py`

- [ ] **Step 1: Write `demo/prompts.py`**

```python
"""All prompt strings live here, single source of truth."""
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
6. **说话用 speak_to_user 工具**，不要直接在 content 里写要说的话。
7. **每个用户回合最多 8 步**。能一次说清的不要分两次。"""

PROACTIVE_PROMPT = """这是一个"主动检查"——用户没说话，你只是在散步。
你要决定现在要不要主动开口。绝大多数时候你应该保持沉默——只有当：
- 距离上次主动发言至少 60 秒，且
- 你想推荐一个还没推荐过的附近地点

才调 recommend_nearby_place + speak_to_user。否则什么都别做（返回一个
空的 assistant message 即可）。"""
```

- [ ] **Step 2: Commit**

```bash
git add demo/prompts.py
git commit -m "demo: system + proactive prompts"
```

---

## Task 8: Tools (TDD with mocks)

**Files:**
- Create: `demo/tools.py`
- Create: `demo/tests/test_tools.py`
- Create: `demo/tests/fixtures/sample_frame.jpg`

- [ ] **Step 1: Create the JPEG fixture**

```python
# one-off: python -c "..."
python -c "from PIL import Image; Image.new('RGB',(640,360),(80,120,160)).save('demo/tests/fixtures/sample_frame.jpg','JPEG')"
```

Verify: `ls -l demo/tests/fixtures/sample_frame.jpg` shows >1 KB.

- [ ] **Step 2: Write the failing tests**

```python
# demo/tests/test_tools.py
import json
from pathlib import Path
from unittest.mock import MagicMock
import pytest
from demo.dialog import DialogLog, MomentLog
from demo.tools import (
    GetCameraFrameTool, AnalyzeFrameVLMTool, SpeakToUserTool,
    RecordMomentTool, PanCameraTool, RecommendNearbyPlaceTool,
)
from demo.camera import Frame, Position

FIXTURE = Path(__file__).parent / "fixtures" / "sample_frame.jpg"


def _fake_camera():
    cam = MagicMock()
    cam.latest_frame.return_value = Frame(jpeg=FIXTURE.read_bytes(), captured_at=1.0)
    cam.position.return_value = Position(pan=0, tilt=0, zoom=100)
    cam.set_position.return_value = Position(pan=20, tilt=0, zoom=100)
    cam.ranges = {"pan": (-145, 145), "tilt": (-90, 100), "zoom": (100, 400)}
    return cam


def test_get_camera_frame_returns_b64():
    tool = GetCameraFrameTool(camera=_fake_camera())
    out = tool.invoke({})
    assert out["status"] == "ok"
    assert len(out["image_b64"]) > 100


def test_get_camera_frame_no_frame():
    cam = MagicMock(); cam.latest_frame.return_value = None
    out = GetCameraFrameTool(camera=cam).invoke({})
    assert out == {"status": "no_frame"}


def test_analyze_frame_vlm_calls_llm_with_jpeg():
    cam = _fake_camera()
    llm = MagicMock(); llm.vlm.return_value = "一面蓝色的墙"
    out = AnalyzeFrameVLMTool(camera=cam, llm=llm).invoke({"question": "那是什么"})
    assert out == {"status": "ok", "answer": "一面蓝色的墙"}
    llm.vlm.assert_called_once()
    assert llm.vlm.call_args.kwargs["question"] == "那是什么"


def test_speak_to_user_appends_dialog_and_calls_tts():
    log = DialogLog(); tts = MagicMock()
    SpeakToUserTool(dialog=log, tts=tts).invoke({"text": "你好"})
    turns = list(log)
    assert turns[-1].role == "assistant" and turns[-1].text == "你好"
    tts.say.assert_called_once_with("你好")


def test_record_moment_writes_jpeg_and_logs(tmp_path):
    cam = _fake_camera()
    ml = MomentLog()
    out = RecordMomentTool(camera=cam, moments=ml,
                           save_dir=tmp_path).invoke({"label": "好看"})
    assert out["status"] == "ok"
    saved = Path(out["frame_path"])
    assert saved.exists() and saved.stat().st_size > 100
    moments = list(ml)
    assert moments[0].label == "好看"


def test_pan_camera_sweep_calls_camera_sweep():
    cam = _fake_camera()
    out = PanCameraTool(camera=cam).invoke({"direction": "sweep_room"})
    cam.sweep.assert_called_once()
    assert out["status"] == "ok"


def test_pan_camera_left_calls_move():
    cam = _fake_camera()
    PanCameraTool(camera=cam).invoke({"direction": "left", "degrees": 30})
    cam.move.assert_called_once_with("left", 30)


def test_recommend_nearby_place_returns_unique_each_call(tmp_path):
    poi_file = tmp_path / "p.json"
    poi_file.write_text(json.dumps({
        "anchor": {}, "pois": [
            {"id": "a", "name": "A", "tagline": "ta", "vibe": "va",
             "imagined_distance_m": 100},
            {"id": "b", "name": "B", "tagline": "tb", "vibe": "vb",
             "imagined_distance_m": 200},
        ]}), encoding="utf-8")
    tool = RecommendNearbyPlaceTool(poi_path=poi_file)
    a = tool.invoke({})["place"]["id"]
    b = tool.invoke({})["place"]["id"]
    assert {a, b} == {"a", "b"}
    out = tool.invoke({})
    assert out["status"] == "exhausted"
```

- [ ] **Step 3: Run tests to confirm they fail**

`pytest demo/tests/test_tools.py -v` → ImportError.

- [ ] **Step 4: Implement `demo/tools.py`**

```python
"""Six tools the agent can call. Each returns a JSON-serializable dict."""
from __future__ import annotations
import base64
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol


class Tool(Protocol):
    name: str
    description: str
    parameters: dict  # JSON Schema

    def invoke(self, args: dict) -> dict: ...


@dataclass
class GetCameraFrameTool:
    camera: Any
    name: str = "get_camera_frame"
    description: str = "返回相机当前画面的 base64 JPEG。"
    parameters: dict = None

    def __post_init__(self):
        self.parameters = {"type": "object", "properties": {}}

    def invoke(self, args: dict) -> dict:
        f = self.camera.latest_frame()
        if not f:
            return {"status": "no_frame"}
        return {"status": "ok",
                "image_b64": base64.b64encode(f.jpeg).decode(),
                "captured_at": f.captured_at}


@dataclass
class AnalyzeFrameVLMTool:
    camera: Any
    llm: Any
    name: str = "analyze_frame_vlm"
    description: str = "用视觉模型分析当前相机画面。问题用中文。"
    parameters: dict = None

    def __post_init__(self):
        self.parameters = {
            "type": "object",
            "properties": {"question": {"type": "string"}},
            "required": ["question"],
        }

    def invoke(self, args: dict) -> dict:
        f = self.camera.latest_frame()
        if not f:
            return {"status": "no_frame"}
        ans = self.llm.vlm(jpeg_bytes=f.jpeg, question=args["question"])
        return {"status": "ok", "answer": ans}


@dataclass
class SpeakToUserTool:
    dialog: Any
    tts: Any
    name: str = "speak_to_user"
    description: str = "通过耳机/扬声器对用户说话。说一句中文。"
    parameters: dict = None

    def __post_init__(self):
        self.parameters = {
            "type": "object",
            "properties": {"text": {"type": "string"}},
            "required": ["text"],
        }

    def invoke(self, args: dict) -> dict:
        text = args["text"]
        self.dialog.append("assistant", text)
        self.tts.say(text)
        return {"status": "ok"}


@dataclass
class RecordMomentTool:
    camera: Any
    moments: Any
    save_dir: Path
    name: str = "record_moment"
    description: str = "把当前画面存成关键帧并打标签。"
    parameters: dict = None

    def __post_init__(self):
        self.parameters = {
            "type": "object",
            "properties": {"label": {"type": "string"}},
            "required": ["label"],
        }
        Path(self.save_dir).mkdir(parents=True, exist_ok=True)

    def invoke(self, args: dict) -> dict:
        f = self.camera.latest_frame()
        if not f:
            return {"status": "no_frame"}
        path = Path(self.save_dir) / f"moment_{int(f.captured_at * 1000)}.jpg"
        path.write_bytes(f.jpeg)
        self.moments.append(label=args["label"], frame_path=str(path))
        return {"status": "ok", "frame_path": str(path)}


@dataclass
class PanCameraTool:
    camera: Any
    name: str = "pan_camera"
    description: str = ("控制相机方向。direction 可以是 left/right/up/down/center/"
                        "zoom_in/zoom_out 或 sweep_room（环视一圈）。"
                        "degrees 是步长，默认 20。")
    parameters: dict = None

    def __post_init__(self):
        self.parameters = {
            "type": "object",
            "properties": {
                "direction": {"type": "string"},
                "degrees": {"type": "integer", "default": 20},
            },
            "required": ["direction"],
        }

    def invoke(self, args: dict) -> dict:
        direction = args["direction"]
        if direction == "sweep_room":
            self.camera.sweep()
            return {"status": "ok", "action": "swept"}
        degrees = int(args.get("degrees", 20))
        pos = self.camera.move(direction, degrees)
        return {"status": "ok", "position": {"pan": pos.pan,
                                              "tilt": pos.tilt,
                                              "zoom": pos.zoom}}


class RecommendNearbyPlaceTool:
    name = "recommend_nearby_place"
    description = "随机推荐一个尚未被推荐过的附近地点。每次返回一个不同的。"
    parameters = {"type": "object", "properties": {}}

    def __init__(self, poi_path: Path) -> None:
        data = json.loads(Path(poi_path).read_text(encoding="utf-8"))
        self._pois: list[dict] = list(data["pois"])
        self._used: set[str] = set()

    def invoke(self, args: dict) -> dict:
        for p in self._pois:
            if p["id"] not in self._used:
                self._used.add(p["id"])
                return {"status": "ok", "place": p}
        return {"status": "exhausted"}


def to_openai_schema(tool: Tool) -> dict:
    return {"type": "function", "function": {
        "name": tool.name, "description": tool.description,
        "parameters": tool.parameters,
    }}
```

- [ ] **Step 5: Run tests to confirm they pass**

`pytest demo/tests/test_tools.py -v` → 8 passed.

- [ ] **Step 6: Commit**

```bash
git add demo/tools.py demo/tests/test_tools.py demo/tests/fixtures/sample_frame.jpg
git commit -m "demo: 6 tools (frame/VLM/speak/moment/pan/recommend)"
```

---

## Task 9: AgentRuntime (TDD with mocked LLM)

**Files:**
- Create: `demo/agent.py`
- Create: `demo/tests/test_agent.py`

- [ ] **Step 1: Write the failing tests**

```python
# demo/tests/test_agent.py
from unittest.mock import MagicMock
from demo.agent import AgentRuntime
from demo.dialog import DialogLog
from demo.llm import AssistantMessage, ToolCall


class FakeTool:
    def __init__(self, name, result):
        self.name, self._result = name, result
        self.description = "x"; self.parameters = {"type": "object", "properties": {}}
        self.calls = []
    def invoke(self, args):
        self.calls.append(args); return self._result


def test_agent_loop_one_tool_then_final():
    llm = MagicMock()
    llm.chat.side_effect = [
        AssistantMessage(content=None, tool_calls=[ToolCall("c1", "say", {"text": "hi"})]),
        AssistantMessage(content="done", tool_calls=[]),
    ]
    say = FakeTool("say", {"status": "ok"})
    log = DialogLog()
    rt = AgentRuntime(llm=llm, tools=[say], dialog=log, system_prompt="SYS")
    rt.handle_user_turn("hello")
    assert say.calls == [{"text": "hi"}]
    assert llm.chat.call_count == 2


def test_agent_loop_caps_iterations():
    llm = MagicMock()
    looping = AssistantMessage(
        content=None,
        tool_calls=[ToolCall(f"c{i}", "noop", {}) for i in [1]])
    llm.chat.return_value = looping
    noop = FakeTool("noop", {"status": "ok"})
    rt = AgentRuntime(llm=llm, tools=[noop], dialog=DialogLog(),
                      system_prompt="SYS", max_iterations=3)
    rt.handle_user_turn("loop please")
    assert llm.chat.call_count == 3


def test_agent_unknown_tool_returns_error_to_model():
    llm = MagicMock()
    llm.chat.side_effect = [
        AssistantMessage(content=None,
                         tool_calls=[ToolCall("c1", "missing", {})]),
        AssistantMessage(content="ok", tool_calls=[]),
    ]
    rt = AgentRuntime(llm=llm, tools=[], dialog=DialogLog(),
                      system_prompt="SYS")
    rt.handle_user_turn("x")
    second_call_msgs = llm.chat.call_args_list[1].kwargs["messages"]
    tool_msg = [m for m in second_call_msgs if m["role"] == "tool"][0]
    assert "unknown tool" in tool_msg["content"]
```

- [ ] **Step 2: Run tests to confirm they fail**

`pytest demo/tests/test_agent.py -v` → ImportError.

- [ ] **Step 3: Implement `demo/agent.py`**

```python
"""Sequential ReAct loop. One instance per session."""
from __future__ import annotations
import json
import threading
from dataclasses import dataclass
from typing import Any
from demo.dialog import DialogLog
from demo.llm import AssistantMessage, LLMClient
from demo.tools import to_openai_schema


class AgentRuntime:
    def __init__(self, *, llm: LLMClient, tools: list, dialog: DialogLog,
                 system_prompt: str, max_iterations: int = 8) -> None:
        self.llm = llm
        self.tools_by_name = {t.name: t for t in tools}
        self.tool_schemas = [to_openai_schema(t) for t in tools]
        self.dialog = dialog
        self.system_prompt = system_prompt
        self.max_iterations = max_iterations
        self._lock = threading.Lock()  # serialize turns

    def _build_messages(self, extra_user_text: str | None) -> list[dict]:
        msgs: list[dict] = [{"role": "system", "content": self.system_prompt}]
        for t in self.dialog:
            if t.role in ("user", "assistant"):
                msgs.append({"role": t.role, "content": t.text})
        if extra_user_text is not None:
            msgs.append({"role": "user", "content": extra_user_text})
        return msgs

    def handle_user_turn(self, user_text: str) -> None:
        with self._lock:
            self.dialog.append("user", user_text)
            messages = self._build_messages(extra_user_text=None)
            self._loop(messages)

    def handle_proactive_check(self, proactive_prompt: str) -> None:
        with self._lock:
            messages = self._build_messages(extra_user_text=proactive_prompt)
            self._loop(messages)

    def _loop(self, messages: list[dict]) -> None:
        for _ in range(self.max_iterations):
            msg: AssistantMessage = self.llm.chat(
                messages=messages, tools=self.tool_schemas)
            if not msg.tool_calls:
                # final message; we don't speak content directly — agent should
                # have used speak_to_user. Just stop.
                return
            messages.append({
                "role": "assistant",
                "content": msg.content,
                "tool_calls": [{
                    "id": tc.id, "type": "function",
                    "function": {"name": tc.name,
                                 "arguments": json.dumps(tc.arguments,
                                                         ensure_ascii=False)},
                } for tc in msg.tool_calls],
            })
            for tc in msg.tool_calls:
                tool = self.tools_by_name.get(tc.name)
                if tool is None:
                    result: Any = {"error": f"unknown tool: {tc.name}"}
                else:
                    try:
                        result = tool.invoke(tc.arguments)
                    except Exception as e:
                        result = {"error": str(e)}
                messages.append({
                    "role": "tool", "tool_call_id": tc.id,
                    "content": json.dumps(result, ensure_ascii=False),
                })
```

- [ ] **Step 4: Run tests to confirm they pass**

`pytest demo/tests/test_agent.py -v` → 3 passed.

- [ ] **Step 5: Commit**

```bash
git add demo/agent.py demo/tests/test_agent.py
git commit -m "demo: AgentRuntime ReAct loop with mocked-LLM tests"
```

---

## Task 10: KeepsakeBuilder (TDD)

**Files:**
- Create: `demo/keepsake.py`
- Create: `demo/tests/test_keepsake.py`

- [ ] **Step 1: Write the failing test**

```python
# demo/tests/test_keepsake.py
from pathlib import Path
from PIL import Image
from demo.dialog import DialogLog, MomentLog
from demo.keepsake import KeepsakeBuilder


def _make_jpeg(path: Path, color: tuple[int, int, int]):
    Image.new("RGB", (640, 360), color).save(path, "JPEG")


def test_builds_collage_with_5_frames_and_quotes(tmp_path):
    moments = MomentLog()
    for i, c in enumerate([(200,80,80),(80,200,80),(80,80,200),(200,200,80),(200,80,200)]):
        p = tmp_path / f"f{i}.jpg"; _make_jpeg(p, c)
        moments.append(label=f"m{i}", frame_path=str(p))
    log = DialogLog()
    log.append("user", "开始散步")
    log.append("assistant", "好，去玄武湖吧")
    log.append("user", "这是什么")
    log.append("assistant", "是一株散尾葵")
    log.append("user", "记一下")

    out = tmp_path / "keepsake.png"
    builder = KeepsakeBuilder()
    builder.build(dialog=log, moments=moments, out_path=out)
    assert out.exists()
    img = Image.open(out)
    assert img.size == (1080, 1920)
```

- [ ] **Step 2: Run test to confirm it fails**

`pytest demo/tests/test_keepsake.py -v` → ImportError.

- [ ] **Step 3: Implement `demo/keepsake.py`**

```python
"""Render a 1080x1920 portrait collage of the walk."""
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from demo.dialog import DialogLog, MomentLog

W, H = 1080, 1920
PAD = 30
HEADER_H = 140


def _load_font(size: int) -> ImageFont.FreeTypeFont:
    for name in ("msyh.ttc", "simhei.ttf", "C:/Windows/Fonts/msyh.ttc",
                 "C:/Windows/Fonts/simhei.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _select_quotes(dialog: DialogLog, n: int = 6) -> list[str]:
    turns = list(dialog)
    if len(turns) <= n:
        return [f"{t.role}：{t.text}" for t in turns]
    # heuristic: first 2 + last 2 + 2 evenly spaced from middle
    picks = [turns[0], turns[1], turns[-2], turns[-1]]
    mid = turns[2:-2]
    if mid:
        step = max(1, len(mid) // 2)
        picks.insert(2, mid[0])
        if len(mid) > step:
            picks.insert(3, mid[step])
    return [f"{t.role}：{t.text}" for t in picks[:n]]


class KeepsakeBuilder:
    def build(self, *, dialog: DialogLog, moments: MomentLog,
              out_path: Path) -> Path:
        canvas = Image.new("RGB", (W, H), (24, 28, 36))
        d = ImageDraw.Draw(canvas)
        title_font = _load_font(56)
        body_font = _load_font(28)

        d.text((PAD, PAD), "本地引力 · 一次散步", fill=(238, 241, 244),
               font=title_font)

        # frame strip: up to 5 frames, 2x3 grid in upper 2/3
        frame_paths = [m.frame_path for m in moments][:5]
        if len(frame_paths) < 5:
            # pad with the last frame if available
            frame_paths += [frame_paths[-1]] * (5 - len(frame_paths)) if frame_paths else []

        cols, rows = 2, 3
        cell_w = (W - PAD * (cols + 1)) // cols
        cell_h = 320
        y0 = HEADER_H
        for i, fp in enumerate(frame_paths):
            r, c = divmod(i, cols)
            x = PAD + c * (cell_w + PAD)
            y = y0 + r * (cell_h + PAD)
            try:
                im = Image.open(fp).convert("RGB")
            except Exception:
                continue
            im = im.resize((cell_w, cell_h))
            canvas.paste(im, (x, y))

        # quotes
        quotes = _select_quotes(dialog)
        qy = y0 + rows * (cell_h + PAD) + PAD
        for q in quotes:
            d.multiline_text((PAD, qy), q, fill=(200, 210, 224),
                             font=body_font, spacing=6)
            qy += 70

        Path(out_path).parent.mkdir(parents=True, exist_ok=True)
        canvas.save(out_path, "PNG")
        return out_path
```

- [ ] **Step 4: Run test to confirm it passes**

`pytest demo/tests/test_keepsake.py -v` → 1 passed.

- [ ] **Step 5: Commit**

```bash
git add demo/keepsake.py demo/tests/test_keepsake.py
git commit -m "demo: keepsake collage builder (1080x1920 PNG)"
```

---

## Task 11: FastAPI server + SSE + browser UI

**Files:**
- Create: `demo/server.py`
- Create: `demo/static/index.html`
- Create: `demo/static/app.js`

This task wires everything together. Verified by manual smoke test in step 4.

- [ ] **Step 1: Implement `demo/server.py`**

```python
"""FastAPI composition root. Run: python -m demo.server"""
from __future__ import annotations
import asyncio
import json
import threading
import time
from pathlib import Path
from typing import AsyncIterator
from fastapi import FastAPI, Request
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

ROOT = Path(__file__).parent
SESSION_DIR = ROOT.parent / "demo_runtime"
SESSION_DIR.mkdir(exist_ok=True)
HTTP_PORT = 8788

app = FastAPI()
app.mount("/static", StaticFiles(directory=str(ROOT / "static")), name="static")

# Singletons (built at startup)
camera: CameraController
dialog: DialogLog
moments: MomentLog
tts: TTSService
llm: LLMClient
agent: AgentRuntime
keepsake_builder = KeepsakeBuilder()
event_bus: asyncio.Queue = asyncio.Queue()
proactive_thread: threading.Thread | None = None
session_active = threading.Event()
session_id = "session"


@app.on_event("startup")
def _startup():
    global camera, dialog, moments, tts, llm, agent
    camera = CameraController()
    dialog = DialogLog()
    moments = MomentLog()
    tts = TTSService()
    llm = LLMClient()
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
                         system_prompt=SYSTEM_PROMPT)

    # Bridge dialog events → SSE bus (thread-safe by stashing the loop)
    loop = asyncio.get_event_loop()
    def on_turn(t):
        loop.call_soon_threadsafe(
            event_bus.put_nowait,
            {"type": f"{t.role}.say", "text": t.text, "ts": t.timestamp})
    dialog.subscribe(on_turn)
    print(f"demo server up: http://127.0.0.1:{HTTP_PORT}/")


@app.get("/", response_class=HTMLResponse)
def index():
    return (ROOT / "static" / "index.html").read_text(encoding="utf-8")


@app.get("/video.mjpg")
def video():
    def gen():
        for jpg in camera.mjpeg_iter():
            yield (b"--frame\r\nContent-Type: image/jpeg\r\n"
                   b"Content-Length: " + str(len(jpg)).encode() + b"\r\n\r\n"
                   + jpg + b"\r\n")
    return StreamingResponse(
        gen(), media_type="multipart/x-mixed-replace; boundary=frame")


@app.get("/events")
async def events(request: Request) -> StreamingResponse:
    async def stream() -> AsyncIterator[bytes]:
        while True:
            if await request.is_disconnected():
                break
            try:
                ev = await asyncio.wait_for(event_bus.get(), timeout=15.0)
                yield f"data: {json.dumps(ev, ensure_ascii=False)}\n\n".encode()
            except asyncio.TimeoutError:
                yield b": keepalive\n\n"
    return StreamingResponse(stream(), media_type="text/event-stream")


@app.post("/api/start")
def start_session():
    if not session_active.is_set():
        session_active.set()
        global proactive_thread
        proactive_thread = threading.Thread(
            target=_proactive_loop, daemon=True, name="proactive")
        proactive_thread.start()
        # opening greeting
        agent.handle_user_turn("（用户刚按下"开始散步"按钮，请简短打招呼并说明今天我们就在玄武湖周边走一圈。）")
    return {"status": "ok"}


@app.post("/api/say")
async def say(req: Request):
    body = await req.json()
    text = (body.get("text") or "").strip()
    if not text:
        return JSONResponse({"error": "empty"}, status_code=400)
    # Run agent on a thread so we don't block the event loop
    await asyncio.get_event_loop().run_in_executor(None,
        agent.handle_user_turn, text)
    return {"status": "ok"}


@app.post("/api/end")
async def end_session():
    session_active.clear()
    out = SESSION_DIR / f"keepsake_{int(time.time())}.png"
    await asyncio.get_event_loop().run_in_executor(None,
        lambda: keepsake_builder.build(dialog=dialog, moments=moments,
                                        out_path=out))
    return {"status": "ok", "keepsake_url": f"/keepsake/{out.name}"}


@app.get("/keepsake/{name}")
def get_keepsake(name: str):
    p = SESSION_DIR / name
    if not p.exists():
        return JSONResponse({"error": "not found"}, status_code=404)
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

- [ ] **Step 2: Implement `demo/static/index.html`**

```html
<!doctype html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>本地引力 · 散步原型</title>
<style>
:root{color-scheme:light dark;font-family:-apple-system,"Segoe UI",sans-serif;background:#0e1116;color:#e8ecf1}
body{margin:0;display:grid;grid-template-columns:minmax(0,1.5fr) minmax(360px,1fr);min-height:100vh}
.left{padding:18px;display:flex;flex-direction:column;gap:14px}
.right{padding:18px;border-left:1px solid #1f242c;display:flex;flex-direction:column;gap:14px;background:#10141a}
.video{background:#000;border-radius:8px;overflow:hidden;aspect-ratio:16/9}
.video img{width:100%;height:100%;object-fit:cover;display:block}
h1{margin:0;font-size:18px}
button{background:#1f6f5e;border:0;color:white;padding:10px 14px;border-radius:6px;cursor:pointer;font-size:14px}
button.ghost{background:#1f242c}
input{background:#161b22;color:inherit;border:1px solid #2a323d;border-radius:6px;padding:10px;flex:1;font-size:14px}
.row{display:flex;gap:8px;align-items:center}
#log{flex:1;overflow-y:auto;background:#161b22;border-radius:6px;padding:12px;font-size:14px;line-height:1.5}
.turn{margin-bottom:10px}
.turn.user{color:#9bd1ff}
.turn.assistant{color:#a8e6c1}
.turn.system{color:#888}
#flash{position:fixed;top:20px;right:20px;background:#1f6f5e;color:white;padding:10px 16px;border-radius:6px;opacity:0;transition:opacity .3s}
.keepsake{margin-top:10px;border:1px solid #2a323d;border-radius:6px;overflow:hidden}
.keepsake img{display:block;width:100%}
</style></head>
<body>
<div class="left">
  <h1>本地引力 — Insta360 Link 2 Pro 桌面原型</h1>
  <div class="video"><img src="/video.mjpg" alt="live"></div>
  <div class="row">
    <button id="start">开始散步</button>
    <button id="end" class="ghost">结束散步</button>
  </div>
</div>
<div class="right">
  <h1>对话</h1>
  <div id="log"></div>
  <div class="row">
    <input id="text" placeholder="对 AI 说点什么…（回车发送）">
    <button id="send">发送</button>
  </div>
  <div id="keepsake-panel"></div>
</div>
<div id="flash"></div>
<script src="/static/app.js"></script>
</body></html>
```

- [ ] **Step 3: Implement `demo/static/app.js`**

```javascript
const log = document.getElementById('log');
const flash = document.getElementById('flash');
const text = document.getElementById('text');

function appendTurn(role, content){
  const div = document.createElement('div');
  div.className = `turn ${role}`;
  div.textContent = content;
  log.appendChild(div);
  log.scrollTop = log.scrollHeight;
}
function flashMsg(s){flash.textContent=s;flash.style.opacity=1;
  setTimeout(()=>flash.style.opacity=0,1500);}

const es = new EventSource('/events');
es.onmessage = (e)=>{
  const ev = JSON.parse(e.data);
  if(ev.type==='user.say') appendTurn('user', `你：${ev.text}`);
  else if(ev.type==='assistant.say') appendTurn('assistant', `AI：${ev.text}`);
  else if(ev.type==='moment') flashMsg(`记下了：${ev.label}`);
};

async function send(t){
  if(!t) return;
  text.value='';
  await fetch('/api/say',{method:'POST',headers:{'content-type':'application/json'},
    body:JSON.stringify({text:t})});
}
document.getElementById('send').onclick=()=>send(text.value.trim());
text.addEventListener('keydown',(e)=>{if(e.key==='Enter')send(text.value.trim());});
document.getElementById('start').onclick=async()=>{
  await fetch('/api/start',{method:'POST'});appendTurn('system','— 开始散步 —');};
document.getElementById('end').onclick=async()=>{
  appendTurn('system','— 生成纪念品中… —');
  const r = await fetch('/api/end',{method:'POST'});
  const d = await r.json();
  if(d.keepsake_url){
    const panel = document.getElementById('keepsake-panel');
    panel.innerHTML = `<div class="keepsake"><img src="${d.keepsake_url}"></div>`;
  }};
```

- [ ] **Step 4: Smoke test the full app**

Run from project root:
```
python -m demo.server
```
Open `http://127.0.0.1:8788/`. Verify in this order:
1. Live video appears within 3 seconds.
2. Click "开始散步" — within ~5s an "AI：…" turn appears in the log AND audio plays.
3. Type "嘿，那是什么？" + Enter — a VLM response appears + audio.
4. Type "记一下，这个挺好看" + Enter — flash "记下了：…" appears (will only happen if agent uses `record_moment` tool; if it doesn't, fine — verified separately).
5. Type "周围有什么" + Enter — camera physically sweeps left-right-center.
6. Click "结束散步" — within ~3s the keepsake collage image appears in the right panel.

If any step fails, check the terminal for stack traces. Common fixes:
- Camera not found → see Task 4 troubleshooting.
- LLM timeout → check Tailscale.
- No audio → see Task 6.
- Agent doesn't call tools → check it's actually choosing the right model (`claude-sonnet-4.5`); if it ignores tool schemas, try `claude-opus-4.5`.

- [ ] **Step 5: Commit**

```bash
git add demo/server.py demo/static/
git commit -m "demo: FastAPI server + browser UI + SSE event bus"
```

---

## Task 12: Demo runbook

**Files:**
- Create: `demo/RUNBOOK.md`

- [ ] **Step 1: Write `demo/RUNBOOK.md`**

```markdown
# Demo Runbook (≈3 min recording)

## Pre-flight (do once before recording)
1. Camera plugged in, light on.
2. `tasklist | findstr python` shows no leftover Python processes.
3. Tailscale connected; `curl http://100.99.139.20:18141/v1/models` returns JSON.
4. Speakers unmuted; volume around 50%.
5. Place 1-2 desk objects in front of camera (a plant, a mug, a notebook).
6. Have OBS / Windows Game Bar (`Win+G`) ready to record the browser window
   + system audio.

## Run
```
python -m demo.server
```
Wait for `demo server up: http://127.0.0.1:8788/`. Open in browser, fullscreen
the window.

## Recording script
Lines you actually type are in **bold**.

1. (Recording starts. Click "开始散步".) AI greets within ~5s.
2. Aim the camera at a desk object using the on-screen `/video.mjpg` feed.
   Type: **嘿，那是什么？** AI looks + describes.
3. Wait ~10s for proactive turn (or skip and continue).
4. Type: **附近有什么好玩的？** AI should call recommend_nearby_place
   and mention 鸡鸣寺 / 紫峰 / etc.
5. Type: **记一下，下次想再来。** Flash banner appears.
6. Type: **周围有什么？让我看看。** Camera physically sweeps the room
   (left-right-center, ~3s).
7. Click "结束散步". Keepsake collage renders in right panel.
8. Stop recording.

Total wall-clock: 2:30 – 3:30.

## If something goes wrong mid-take
- Camera frozen → leave it, the agent will say "我没看清".
- LLM timeout → wait or restart the server, re-take.
- Audio cuts out → re-record (TTS isn't critical to the visual story).

## Re-takes
Each session writes to `demo_runtime/`. Delete that directory between takes
if you want a clean slate, otherwise old moments and keepsakes accumulate.
```

- [ ] **Step 2: Commit**

```bash
git add demo/RUNBOOK.md
git commit -m "demo: recording runbook"
```

---

## Done criteria

- All 12 tasks committed.
- `pytest demo/tests -v` is green (15+ tests).
- `python -m demo.server` boots cleanly, browser UI works, end-to-end
  recording-script in `demo/RUNBOOK.md` produces a keepsake PNG.
- One screen recording exists at `demo_runtime/recording.mp4` (or wherever
  OBS saves it).

---

