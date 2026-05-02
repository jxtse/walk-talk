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
_loop: asyncio.AbstractEventLoop  # captured at startup
proactive_thread: threading.Thread | None = None
session_active = threading.Event()


def _publish(ev: dict) -> None:
    """Push an event to the SSE bus from any thread."""
    _loop.call_soon_threadsafe(event_bus.put_nowait, ev)


@app.on_event("startup")
def _startup():
    global camera, dialog, moments, tts, llm, agent, _loop
    _loop = asyncio.get_event_loop()
    camera = CameraController()
    dialog = DialogLog()
    moments = MomentLog()
    tts = TTSService()
    llm = LLMClient()

    # Wrap MomentLog.append to publish a 'moment' event
    _orig_append = moments.append
    def _wrapped_append(*, label, frame_path):
        m = _orig_append(label=label, frame_path=frame_path)
        _publish({"type": "moment", "label": label, "ts": m.timestamp})
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
                         system_prompt=SYSTEM_PROMPT)

    # Bridge dialog turns -> SSE
    def on_turn(t):
        _publish({"type": f"{t.role}.say", "text": t.text, "ts": t.timestamp})
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
                ev = await asyncio.wait_for(event_bus.get(), timeout=15.0)
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
        # opening greeting -- run on executor so we don't block the event loop
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
