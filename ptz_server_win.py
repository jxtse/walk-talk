#!/usr/bin/env python3
"""Insta360 Link 2 (Pro) PTZ + preview server for Windows.

PTZ control: DirectShow IAMCameraControl via comtypes.
Video preview: ffmpeg dshow -> MJPEG pipe.
"""
import json
import os
import queue
import shutil
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

import comtypes
from comtypes import GUID, HRESULT, IUnknown, COMMETHOD
from ctypes import POINTER, c_long
from pygrabber.dshow_graph import SystemDeviceEnum
from pygrabber.dshow_ids import DeviceCategories

ROOT = Path(__file__).resolve().parent

DEVICE_NAME = "Insta360 Link 2"
FFMPEG = (
    shutil.which("ffmpeg")
    or (r"C:\ffmpeg\bin\ffmpeg.exe" if os.path.exists(r"C:\ffmpeg\bin\ffmpeg.exe") else "ffmpeg")
)
HTTP_PORT = 8787

JPEG_SOI = b"\xff\xd8"
JPEG_EOI = b"\xff\xd9"

PROP_PAN = 0
PROP_TILT = 1
PROP_ZOOM = 3
FLAG_MANUAL = 2

DEFAULT_STEP_DEG = 5  # degrees per arrow click


# ---------------------------------------------------------------------------
# DirectShow IAMCameraControl
# ---------------------------------------------------------------------------

class IAMCameraControl(IUnknown):
    _iid_ = GUID("{C6E13370-30AC-11d0-A18C-00A0C9118956}")
    _methods_ = [
        COMMETHOD([], HRESULT, "GetRange",
            (["in"], c_long, "Property"),
            (["out"], POINTER(c_long), "pMin"),
            (["out"], POINTER(c_long), "pMax"),
            (["out"], POINTER(c_long), "pSteppingDelta"),
            (["out"], POINTER(c_long), "pDefault"),
            (["out"], POINTER(c_long), "pCapsFlags"),
        ),
        COMMETHOD([], HRESULT, "Set",
            (["in"], c_long, "Property"),
            (["in"], c_long, "lValue"),
            (["in"], c_long, "Flags"),
        ),
        COMMETHOD([], HRESULT, "Get",
            (["in"], c_long, "Property"),
            (["out"], POINTER(c_long), "lValue"),
            (["out"], POINTER(c_long), "Flags"),
        ),
    ]


# ---------------------------------------------------------------------------
# PTZ worker thread (owns COM)
# ---------------------------------------------------------------------------

class PTZWorker(threading.Thread):
    daemon = True

    def __init__(self):
        super().__init__(name="ptz-worker")
        self.requests = queue.Queue()
        self.ready = threading.Event()
        self.init_error = None
        self.range = {}  # prop -> (min, max, step, default)

    def run(self):
        try:
            comtypes.CoInitialize()
            sde = SystemDeviceEnum()
            devices = sde.get_available_filters(DeviceCategories.VideoInputDevice)
            if DEVICE_NAME not in devices:
                raise RuntimeError(
                    f"DirectShow device '{DEVICE_NAME}' not found. Available: {devices}"
                )
            base, _ = sde.get_filter_by_index(
                DeviceCategories.VideoInputDevice, devices.index(DEVICE_NAME)
            )
            self.cam = base.QueryInterface(IAMCameraControl)
            self._sde = sde  # keep alive
            self._base = base
            for prop in (PROP_PAN, PROP_TILT, PROP_ZOOM):
                mn, mx, step, default, _caps = self.cam.GetRange(prop)
                self.range[prop] = (mn, mx, step, default)
        except Exception as exc:
            self.init_error = str(exc)
            self.ready.set()
            return
        self.ready.set()

        while True:
            fn, args, fut = self.requests.get()
            try:
                fut["result"] = fn(*args)
            except Exception as exc:
                fut["error"] = str(exc)
            finally:
                fut["done"].set()

    def call(self, fn, *args, timeout=3):
        fut = {"done": threading.Event()}
        self.requests.put((fn, args, fut))
        if not fut["done"].wait(timeout):
            raise RuntimeError("ptz worker timeout")
        if "error" in fut:
            raise RuntimeError(fut["error"])
        return fut["result"]

    # operations -----------------------------------------------------------
    def _get(self, prop):
        val, _flags = self.cam.Get(prop)
        return int(val)

    def _set(self, prop, value):
        mn, mx, _step, _def = self.range[prop]
        value = max(mn, min(mx, int(value)))
        self.cam.Set(prop, value, FLAG_MANUAL)
        return self._get(prop)

    def position(self):
        return self.call(lambda: {
            "pan": self._get(PROP_PAN),
            "tilt": self._get(PROP_TILT),
            "zoom": self._get(PROP_ZOOM),
        })

    def set_position(self, pan=None, tilt=None, zoom=None):
        def op():
            if pan is not None:
                self._set(PROP_PAN, pan)
            if tilt is not None:
                self._set(PROP_TILT, tilt)
            if zoom is not None:
                self._set(PROP_ZOOM, zoom)
            return {
                "pan": self._get(PROP_PAN),
                "tilt": self._get(PROP_TILT),
                "zoom": self._get(PROP_ZOOM),
            }
        return self.call(op)

    def ranges(self):
        return self.call(lambda: {
            "pan": self.range[PROP_PAN],
            "tilt": self.range[PROP_TILT],
            "zoom": self.range[PROP_ZOOM],
        })


PTZ = PTZWorker()


def move(direction, step):
    pos = PTZ.position()
    pan, tilt, zoom = pos["pan"], pos["tilt"], pos["zoom"]
    if direction == "left":
        pan -= step
    elif direction == "right":
        pan += step
    elif direction == "up":
        tilt += step
    elif direction == "down":
        tilt -= step
    elif direction == "center":
        pan, tilt = 0, 0
    elif direction == "zoom_in":
        zoom += step
    elif direction == "zoom_out":
        zoom -= step
    else:
        raise ValueError(f"unknown direction: {direction}")
    return PTZ.set_position(pan=pan, tilt=tilt, zoom=zoom)


# ---------------------------------------------------------------------------
# Video preview via ffmpeg
# ---------------------------------------------------------------------------

CAMERA_LOCK = threading.Lock()
FRAME_COND = threading.Condition(CAMERA_LOCK)
LATEST_FRAME = None
LATEST_FRAME_TIME = 0.0
CAMERA_ERROR = ""
CAMERA_THREAD = None


def open_camera_process():
    cmd = [
        FFMPEG,
        "-hide_banner", "-loglevel", "error",
        "-f", "dshow",
        "-rtbufsize", "100M",
        "-video_size", "1280x720",
        "-framerate", "30",
        "-i", f"video={DEVICE_NAME}",
        "-an",
        "-vf", "fps=15",
        "-q:v", "5",
        "-f", "mjpeg",
        "pipe:1",
    ]
    proc = subprocess.Popen(
        cmd,
        cwd=str(ROOT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    deadline = time.monotonic() + 4.0
    data = b""
    while time.monotonic() < deadline and proc.poll() is None:
        chunk = proc.stdout.read(4096)
        if chunk:
            data += chunk
            if JPEG_SOI in data and JPEG_EOI in data:
                return proc, data
        else:
            time.sleep(0.03)
    err = ""
    try:
        err = proc.stderr.read().decode("utf-8", "replace").strip()
    except Exception:
        pass
    proc.terminate()
    try:
        proc.wait(timeout=1)
    except subprocess.TimeoutExpired:
        proc.kill()
    raise RuntimeError(err or "ffmpeg failed to start camera")


def camera_worker():
    global LATEST_FRAME, LATEST_FRAME_TIME, CAMERA_ERROR
    while True:
        try:
            proc, buffered = open_camera_process()
            with CAMERA_LOCK:
                CAMERA_ERROR = ""
            data = buffered
            while True:
                while True:
                    s = data.find(JPEG_SOI)
                    if s < 0:
                        data = data[-2:]
                        break
                    e = data.find(JPEG_EOI, s + 2)
                    if e < 0:
                        data = data[s:]
                        break
                    e += 2
                    frame = data[s:e]
                    data = data[e:]
                    with CAMERA_LOCK:
                        LATEST_FRAME = frame
                        LATEST_FRAME_TIME = time.time()
                        FRAME_COND.notify_all()
                chunk = proc.stdout.read(16384)
                if not chunk:
                    break
                data += chunk
            proc.terminate()
        except Exception as exc:
            with CAMERA_LOCK:
                CAMERA_ERROR = str(exc)
                FRAME_COND.notify_all()
            print(f"[camera] {exc}", file=sys.stderr)
            time.sleep(2)


def ensure_camera():
    global CAMERA_THREAD
    with CAMERA_LOCK:
        if CAMERA_THREAD is None or not CAMERA_THREAD.is_alive():
            CAMERA_THREAD = threading.Thread(target=camera_worker, daemon=True)
            CAMERA_THREAD.start()


def stream_video(handler):
    ensure_camera()
    handler.send_response(200)
    handler.send_header("content-type", "multipart/x-mixed-replace; boundary=frame")
    handler.send_header("cache-control", "no-store")
    handler.end_headers()
    last = 0.0
    try:
        while True:
            with CAMERA_LOCK:
                FRAME_COND.wait_for(
                    lambda: (LATEST_FRAME is not None and LATEST_FRAME_TIME != last) or CAMERA_ERROR,
                    timeout=5,
                )
                if CAMERA_ERROR and LATEST_FRAME is None:
                    raise RuntimeError(CAMERA_ERROR)
                jpg = LATEST_FRAME
                last = LATEST_FRAME_TIME
            if not jpg:
                continue
            handler.wfile.write(b"--frame\r\n")
            handler.wfile.write(b"Content-Type: image/jpeg\r\n")
            handler.wfile.write(f"Content-Length: {len(jpg)}\r\n\r\n".encode("ascii"))
            handler.wfile.write(jpg)
            handler.wfile.write(b"\r\n")
            handler.wfile.flush()
    except (BrokenPipeError, ConnectionResetError):
        pass


# ---------------------------------------------------------------------------
# HTTP UI
# ---------------------------------------------------------------------------

HTML = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Insta360 Link 2 PTZ (Windows)</title>
<style>
:root { color-scheme: light dark; font-family: -apple-system, "Segoe UI", sans-serif; background: #f6f7f8; color: #202124; }
body { margin: 0; min-height: 100vh; display: grid; place-items: center; }
main { width: min(1000px, calc(100vw - 32px)); padding: 24px; }
h1 { margin: 0 0 16px; font-size: 22px; }
.layout { display: grid; grid-template-columns: minmax(0, 1.4fr) minmax(310px, 0.6fr); gap: 16px; }
.panel { background: #fff; border: 1px solid #d7dce1; border-radius: 8px; padding: 18px; box-shadow: 0 8px 24px rgba(0,0,0,.06); }
.video-wrap { background: #111; border-radius: 6px; aspect-ratio: 16/9; overflow: hidden; }
.video-wrap img { width: 100%; height: 100%; object-fit: cover; display: block; }
.grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin: 14px 0; }
button { border: 1px solid #c7cdd4; background: #f7f8fa; color: inherit; padding: 14px 0; border-radius: 6px; font-size: 22px; cursor: pointer; }
button:active { background: #e8edf2; }
button.primary { background: #1d6f5f; border-color: #1d6f5f; color: white; font-size: 14px; }
.row { display: flex; justify-content: space-between; align-items: center; gap: 8px; margin: 8px 0; flex-wrap: wrap; }
label { display: grid; gap: 6px; font-size: 13px; color: #4b5560; margin-top: 10px; }
input[type=range] { width: 100%; }
code { font: 13px ui-monospace, Menlo, monospace; background: #eef1f4; padding: 3px 6px; border-radius: 4px; }
.status { min-height: 20px; font-size: 13px; color: #4b5560; }
.zoombar { display: flex; gap: 6px; }
.zoombar button { font-size: 14px; padding: 10px 0; flex: 1; }
@media (max-width: 820px) { .layout { grid-template-columns: 1fr; } }
@media (prefers-color-scheme: dark) {
  :root { background: #111418; color: #eef1f4; }
  .panel { background: #191e24; border-color: #313943; box-shadow: none; }
  button { background: #222932; border-color: #3a4450; }
  code { background: #252c35; }
  label, .status { color: #a9b3bd; }
}
</style>
</head>
<body><main>
<h1>Insta360 Link 2 云台控制 · Windows</h1>
<section class="layout">
  <div class="panel"><div class="video-wrap"><img id="video" src="/video.mjpg"></div></div>
  <div class="panel">
    <div class="row"><div>位置 <code id="pos">…</code></div><button class="primary" id="refresh">刷新</button></div>
    <div class="row"><div>范围 <code id="rng">…</code></div></div>
    <div class="grid">
      <span></span><button data-move="up">↑</button><span></span>
      <button data-move="left">←</button><button class="primary" data-move="center">回中</button><button data-move="right">→</button>
      <span></span><button data-move="down">↓</button><span></span>
    </div>
    <div class="zoombar">
      <button data-move="zoom_out">– Zoom</button>
      <button data-move="zoom_in">+ Zoom</button>
    </div>
    <label>步长 <span><code id="stepLabel">5</code></span>
      <input id="step" type="range" min="1" max="45" step="1" value="5"></label>
    <div class="status" id="status"></div>
  </div>
</section>
</main>
<script>
const $ = id => document.getElementById(id);
const stepEl = $('step'), stepLabel = $('stepLabel'), statusEl = $('status'), posEl = $('pos'), rngEl = $('rng');
async function api(path, opts) {
  const r = await fetch(path, opts);
  const d = await r.json();
  if (!r.ok || d.error) throw new Error(d.error || r.statusText);
  return d;
}
function renderPos(d) { posEl.textContent = `pan ${d.pan}° tilt ${d.tilt}° zoom ${d.zoom}`; }
async function refresh() {
  try {
    const [p, r] = await Promise.all([api('/api/position'), api('/api/range')]);
    renderPos(p);
    rngEl.textContent = `pan ${r.pan[0]}~${r.pan[1]} tilt ${r.tilt[0]}~${r.tilt[1]} zoom ${r.zoom[0]}~${r.zoom[1]}`;
    statusEl.textContent = '';
  } catch (e) { statusEl.textContent = e.message; }
}
async function move(dir) {
  try {
    statusEl.textContent = '…';
    const d = await api('/api/move', { method: 'POST', headers: {'content-type': 'application/json'},
      body: JSON.stringify({ dir, step: Number(stepEl.value) }) });
    renderPos(d); statusEl.textContent = '完成';
  } catch (e) { statusEl.textContent = e.message; }
}
stepEl.addEventListener('input', () => stepLabel.textContent = stepEl.value);
$('refresh').addEventListener('click', refresh);
document.querySelectorAll('button[data-move]').forEach(b => b.addEventListener('click', () => move(b.dataset.move)));
window.addEventListener('keydown', e => {
  const map = { ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down', Home: 'center', '+': 'zoom_in', '-': 'zoom_out' };
  if (map[e.key]) { e.preventDefault(); move(map[e.key]); }
});
refresh();
</script></body></html>
"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def send_json(self, data, status=200):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            body = HTML.encode("utf-8")
            self.send_response(200)
            self.send_header("content-type", "text/html; charset=utf-8")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/video.mjpg":
            try:
                stream_video(self)
            except Exception:
                pass
            return
        if path == "/api/position":
            try:
                self.send_json(PTZ.position())
            except Exception as e:
                self.send_json({"error": str(e)}, 500)
            return
        if path == "/api/range":
            try:
                r = PTZ.ranges()
                self.send_json({k: list(v[:2]) for k, v in r.items()})
            except Exception as e:
                self.send_json({"error": str(e)}, 500)
            return
        self.send_json({"error": "not found"}, 404)

    def do_POST(self):
        path = urlparse(self.path).path
        if path != "/api/move":
            self.send_json({"error": "not found"}, 404)
            return
        try:
            length = int(self.headers.get("content-length", "0"))
            payload = json.loads(self.rfile.read(length) or b"{}")
            direction = str(payload.get("dir", ""))
            step = int(payload.get("step", DEFAULT_STEP_DEG))
            self.send_json(move(direction, step))
        except Exception as e:
            self.send_json({"error": str(e)}, 500)


def main():
    PTZ.start()
    PTZ.ready.wait()
    if PTZ.init_error:
        print(f"PTZ init failed: {PTZ.init_error}", file=sys.stderr)
        sys.exit(1)
    print(f"PTZ ranges: {PTZ.ranges()}")
    print(f"ffmpeg: {FFMPEG}")
    server = ThreadingHTTPServer(("127.0.0.1", HTTP_PORT), Handler)
    print(f"PTZ control UI: http://127.0.0.1:{HTTP_PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
