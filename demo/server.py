"""FastAPI composition root v2. Run: python -m demo.server"""
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
from demo.event_bus import EventBus
from demo.media import MediaClient
from demo.amap import AmapClient
from demo.scripts_player import ScriptPlayer
from demo.config import load_config

ROOT = Path(__file__).parent
HTTP_PORT = 8788
SCENARIO_DIR = ROOT / "data" / "scenarios"
POIS_V2_PATH = ROOT / "data" / "pois_v2.json"

# Resolved at init time (against current cwd) so tests using
# monkeypatch.chdir can supply fixture trees.
BASE_RUNTIME: Path
SESSION_DIR: Path
CACHE_IMAGES_DIR: Path

app = FastAPI()
app.mount("/static", StaticFiles(directory=str(ROOT / "static")), name="static")

# Singletons (built by _init_singletons at module import)
camera: CameraController = None  # type: ignore[assignment]
dialog: DialogLog = None  # type: ignore[assignment]
moments: MomentLog = None  # type: ignore[assignment]
tts: TTSService = None  # type: ignore[assignment]
llm: LLMClient = None  # type: ignore[assignment]
agent: AgentRuntime = None  # type: ignore[assignment]
keepsake_builder = KeepsakeBuilder()
event_bus: EventBus = None  # type: ignore[assignment]
media_client: MediaClient = None  # type: ignore[assignment]
amap_client: AmapClient = None  # type: ignore[assignment]
script_player: ScriptPlayer = None  # type: ignore[assignment]
config = None
_loop: asyncio.AbstractEventLoop | None = None
proactive_thread: threading.Thread | None = None
session_active = threading.Event()
_initialized = False


def _init_singletons() -> None:
    """Build all singletons. Idempotent. Called at module import so the
    objects exist regardless of whether the lifespan/startup hook fires
    (which TestClient won't run without a context manager)."""
    global camera, dialog, moments, tts, llm, agent
    global event_bus, media_client, amap_client, script_player, config
    global BASE_RUNTIME, SESSION_DIR, CACHE_IMAGES_DIR, _initialized

    if _initialized:
        return

    BASE_RUNTIME = Path("demo_runtime")
    SESSION_DIR = BASE_RUNTIME
    CACHE_IMAGES_DIR = BASE_RUNTIME / "cache" / "images"
    SESSION_DIR.mkdir(parents=True, exist_ok=True)

    event_bus = EventBus()
    config = load_config()

    camera = CameraController()
    dialog = DialogLog()
    moments = MomentLog()
    tts = TTSService()
    llm = LLMClient()
    media_client = MediaClient(api_key=config.openai_next_api_key)
    amap_client = AmapClient(key=config.amap_key, event_bus=event_bus)

    # Wrap camera.set_position so PTZ moves emit a 'ptz' SSE event.
    _orig_set_position = camera.set_position

    def _wrapped_set_position(*, pan=None, tilt=None, zoom=None):
        pos = _orig_set_position(pan=pan, tilt=tilt, zoom=zoom)
        try:
            event_bus.publish({
                "type": "ptz",
                "pan": getattr(pos, "pan", None),
                "tilt": getattr(pos, "tilt", None),
                "zoom": getattr(pos, "zoom", None),
            })
        except Exception:
            pass
        return pos
    camera.set_position = _wrapped_set_position  # type: ignore[method-assign]

    # Wrap MomentLog.append to publish a 'moment' event
    _orig_append = moments.append

    def _wrapped_append(*, label, frame_path):
        m = _orig_append(label=label, frame_path=frame_path)
        try:
            event_bus.publish(
                {"type": "moment", "label": label, "ts": m.timestamp})
        except Exception:
            pass
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
                         system_prompt=SYSTEM_PROMPT, event_bus=event_bus)

    def _keepsake_render(image_id: str) -> None:
        try:
            event_bus.publish(
                {"type": "keepsake_render", "image_id": image_id})
        except Exception:
            pass

    script_player = ScriptPlayer(
        dialog=dialog, moments=moments, camera=camera, tts=tts,
        event_bus=event_bus, keepsake_render=_keepsake_render,
        pois_v2_path=POIS_V2_PATH,
    )

    def on_turn(t):
        try:
            event_bus.publish(
                {"type": f"{t.role}.say", "text": t.text, "ts": t.timestamp})
        except Exception:
            pass
    dialog.subscribe(on_turn)

    _initialized = True


@app.middleware("http")
async def _ensure_init(request, call_next):
    # Re-bind event bus to current loop (test isolation: each test has a
    # fresh loop). Init itself only runs once, at module import.
    if event_bus is not None:
        try:
            event_bus.bind_loop(asyncio.get_event_loop())
        except Exception:
            pass
    return await call_next(request)


@app.on_event("startup")
def _startup() -> None:
    """Bind the asyncio loop to the event bus once we have one."""
    global _loop
    if not _initialized:
        _init_singletons()
    _loop = asyncio.get_event_loop()
    event_bus.bind_loop(_loop)
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
    if event_bus._loop is None:
        event_bus.bind_loop(asyncio.get_event_loop())

    async def stream() -> AsyncIterator[bytes]:
        while True:
            if await request.is_disconnected():
                break
            try:
                ev = await asyncio.wait_for(event_bus.queue.get(), timeout=15.0)
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
    # fire-and-forget：用户气泡通过 dialog.subscribe -> SSE 立即出现，
    # AI 回复也通过 SSE 推送，不要 await（否则前端会卡 5-30s）
    asyncio.get_event_loop().run_in_executor(
        None, agent.handle_user_turn, text)
    return {"status": "ok"}


@app.post("/api/voice")
async def voice(audio: UploadFile = File(...)):
    data = await audio.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty audio")
    mime = audio.content_type or "audio/webm"
    loop = asyncio.get_event_loop()
    text = await loop.run_in_executor(
        None,
        lambda: media_client.transcribe(audio_bytes=data, mime=mime),
    )
    return {"text": text}


@app.post("/api/script/start")
async def script_start(req: Request):
    body = await req.json()
    scenario = (body.get("scenario") or "").strip()
    if not scenario:
        raise HTTPException(status_code=400, detail="scenario required")
    path = SCENARIO_DIR / f"{scenario}.json"
    if not path.exists():
        raise HTTPException(
            status_code=400, detail=f"unknown scenario: {scenario}")
    try:
        script_player.play(path)
    except RuntimeError as e:
        raise HTTPException(status_code=409, detail=str(e))
    return {"status": "ok", "scenario": scenario}


@app.post("/api/script/stop")
async def script_stop():
    script_player.stop()
    return {"status": "ok"}


@app.get("/poi_image/{name}")
def poi_image(name: str):
    if "/" in name or "\\" in name or ".." in name:
        raise HTTPException(status_code=400, detail="bad name")
    p = CACHE_IMAGES_DIR / name
    if not p.exists():
        raise HTTPException(status_code=404, detail="not found")
    return FileResponse(p, media_type="image/png")


@app.post("/api/end")
async def end_session():
    session_active.clear()
    out = SESSION_DIR / f"keepsake_{int(time.time())}.png"
    await asyncio.get_event_loop().run_in_executor(
        None,
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


# Build singletons lazily on first access of `server.app`. mock.patch
# pre-imports demo.server when resolving its target, so we cannot init
# at module bottom (patches haven't been applied yet). We also can't use
# @app.on_event("startup") because TestClient(app) without a context
# manager doesn't run lifespan events. Lazy-init when the test (or
# uvicorn) accesses `server.app` works: the test does
# `TestClient(server.app)` inside its `with patch(...)` block.

_real_app = app
del app  # remove module attr so __getattr__ kicks in for `app`


def __getattr__(name):  # PEP 562 module-level __getattr__
    if name == "app":
        if not _initialized:
            _init_singletons()
        return _real_app
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


if __name__ == "__main__":
    if not _initialized:
        _init_singletons()
    uvicorn.run(_real_app, host="127.0.0.1", port=HTTP_PORT, log_level="info")
