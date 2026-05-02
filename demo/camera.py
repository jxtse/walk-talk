"""CameraController for Insta360 Link 2 (Pro) on Windows.

Encapsulates DirectShow PTZ control (IAMCameraControl via comtypes) on a
dedicated COM-affine worker thread, plus an ffmpeg-backed MJPEG capture
thread that maintains a sliding deque of recent JPEG frames.

This is a refactor of ``insta360_sdk_ref/ptz_server_win.py`` -- behaviour
must not change.
"""
from __future__ import annotations

import os
import queue
import shutil
import subprocess
import sys
import threading
import time
from collections import deque
from dataclasses import dataclass
from typing import Iterator

import comtypes
from comtypes import GUID, HRESULT, IUnknown, COMMETHOD
from ctypes import POINTER, c_long
from pygrabber.dshow_graph import SystemDeviceEnum
from pygrabber.dshow_ids import DeviceCategories


# --- module constants -------------------------------------------------------

JPEG_SOI = b"\xff\xd8"
JPEG_EOI = b"\xff\xd9"

PROP_PAN = 0
PROP_TILT = 1
PROP_ZOOM = 3
FLAG_MANUAL = 2

_FFMPEG_FALLBACK = r"C:\ffmpeg\bin\ffmpeg.exe"


def find_ffmpeg() -> str:
    """Return path to an ffmpeg binary or raise FileNotFoundError."""
    found = shutil.which("ffmpeg")
    if found:
        return found
    if os.path.exists(_FFMPEG_FALLBACK):
        return _FFMPEG_FALLBACK
    raise FileNotFoundError(
        "ffmpeg not found on PATH and not at " + _FFMPEG_FALLBACK
    )


# --- DirectShow IAMCameraControl --------------------------------------------

class _IAMCameraControl(IUnknown):
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


# --- public dataclasses -----------------------------------------------------

@dataclass(frozen=True)
class Frame:
    jpeg: bytes
    captured_at: float


@dataclass(frozen=True)
class Position:
    pan: int
    tilt: int
    zoom: int


# --- PTZ worker thread (owns COM) -------------------------------------------

class _PTZWorker(threading.Thread):
    daemon = True

    def __init__(self, device_name: str) -> None:
        super().__init__(name="ptz-worker")
        self.device_name = device_name
        self.requests: queue.Queue = queue.Queue()
        self.ready = threading.Event()
        self.init_error: str | None = None
        self.range: dict[int, tuple[int, int, int, int]] = {}

    def run(self) -> None:
        try:
            comtypes.CoInitialize()
            sde = SystemDeviceEnum()
            devices = sde.get_available_filters(DeviceCategories.VideoInputDevice)
            if self.device_name not in devices:
                raise RuntimeError(
                    f"DirectShow device '{self.device_name}' not found. "
                    f"Available: {devices}"
                )
            base, _ = sde.get_filter_by_index(
                DeviceCategories.VideoInputDevice,
                devices.index(self.device_name),
            )
            self.cam = base.QueryInterface(_IAMCameraControl)
            self._sde = sde   # keep alive
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

    def call(self, fn, *args, timeout: float = 3.0):
        fut: dict = {"done": threading.Event()}
        self.requests.put((fn, args, fut))
        if not fut["done"].wait(timeout):
            raise RuntimeError("ptz worker timeout")
        if "error" in fut:
            raise RuntimeError(fut["error"])
        return fut["result"]

    # ops (always invoked on worker thread) --------------------------------
    def get_prop(self, prop: int) -> int:
        val, _flags = self.cam.Get(prop)
        return int(val)

    def set_prop(self, prop: int, value: int) -> int:
        mn, mx, _step, _def = self.range[prop]
        value = max(mn, min(mx, int(value)))
        self.cam.Set(prop, value, FLAG_MANUAL)
        return self.get_prop(prop)


# --- CameraController -------------------------------------------------------

class _StubPTZ:
    """Fallback when Insta360 PTZ-capable camera isn't connected.
    Pretends pan/tilt/zoom move, so the rest of the system keeps working
    against a plain integrated camera."""
    def __init__(self) -> None:
        self.init_error = None
        self._state = {PROP_PAN: 0, PROP_TILT: 0, PROP_ZOOM: 100}
        self.range = {
            PROP_PAN:  (-180, 180, 1, 0),
            PROP_TILT: (-90,   90, 1, 0),
            PROP_ZOOM: (100,  400, 1, 100),
        }

    def get_prop(self, prop): return self._state[prop]
    def set_prop(self, prop, value):
        mn, mx, *_ = self.range[prop]
        v = max(mn, min(mx, int(value)))
        self._state[prop] = v
        return v
    def call(self, fn, *args, timeout=3.0): return fn(*args)


class CameraController:
    DEVICE_NAME = "Insta360 Link 2"
    FALLBACK_DEVICE_NAME = "Integrated Camera"
    FRAME_WINDOW_SECONDS = 300

    def __init__(self) -> None:
        self._ffmpeg = find_ffmpeg()

        self._ptz = _PTZWorker(self.DEVICE_NAME)
        self._ptz.start()
        self._ptz.ready.wait()
        if self._ptz.init_error:
            print(f"[camera] Insta360 unavailable: {self._ptz.init_error}; "
                  f"falling back to {self.FALLBACK_DEVICE_NAME} with stub PTZ.")
            self._ptz = _StubPTZ()
            self._device_in_use = self.FALLBACK_DEVICE_NAME
        else:
            self._device_in_use = self.DEVICE_NAME

        # frame state
        self._frames: deque[Frame] = deque()
        self._frame_lock = threading.Lock()
        self._frame_cond = threading.Condition(self._frame_lock)
        self._frame_index = 0   # monotonically increasing id of latest appended frame
        self._camera_error: str = ""

        self._camera_thread = threading.Thread(
            target=self._camera_loop, name="camera-loop", daemon=True
        )
        self._camera_thread.start()

    # --- PTZ public API ----------------------------------------------------
    @property
    def ranges(self) -> dict[str, tuple[int, int]]:
        r = self._ptz.range
        return {
            "pan":  (r[PROP_PAN][0],  r[PROP_PAN][1]),
            "tilt": (r[PROP_TILT][0], r[PROP_TILT][1]),
            "zoom": (r[PROP_ZOOM][0], r[PROP_ZOOM][1]),
        }

    def position(self) -> Position:
        def op() -> Position:
            return Position(
                pan=self._ptz.get_prop(PROP_PAN),
                tilt=self._ptz.get_prop(PROP_TILT),
                zoom=self._ptz.get_prop(PROP_ZOOM),
            )
        return self._ptz.call(op)

    def set_position(
        self,
        *,
        pan: int | None = None,
        tilt: int | None = None,
        zoom: int | None = None,
    ) -> Position:
        def op() -> Position:
            if pan is not None:
                self._ptz.set_prop(PROP_PAN, pan)
            if tilt is not None:
                self._ptz.set_prop(PROP_TILT, tilt)
            if zoom is not None:
                self._ptz.set_prop(PROP_ZOOM, zoom)
            return Position(
                pan=self._ptz.get_prop(PROP_PAN),
                tilt=self._ptz.get_prop(PROP_TILT),
                zoom=self._ptz.get_prop(PROP_ZOOM),
            )
        return self._ptz.call(op)

    def move(self, direction: str, step: int) -> Position:
        if direction == "center":
            return self.set_position(pan=0, tilt=0, zoom=100)
        pos = self.position()
        pan, tilt, zoom = pos.pan, pos.tilt, pos.zoom
        if direction == "left":
            pan -= step
        elif direction == "right":
            pan += step
        elif direction == "up":
            tilt += step
        elif direction == "down":
            tilt -= step
        elif direction == "zoom_in":
            zoom += step
        elif direction == "zoom_out":
            zoom -= step
        else:
            raise ValueError(f"unknown direction: {direction}")
        return self.set_position(pan=pan, tilt=tilt, zoom=zoom)

    def sweep(self) -> None:
        """Pan -60, pause ~1s, pan +60, pause ~1s, return to 0. ~3s total."""
        self.set_position(pan=-60)
        time.sleep(1.0)
        self.set_position(pan=60)
        time.sleep(1.0)
        self.set_position(pan=0)

    # --- frame public API --------------------------------------------------
    def latest_frame(self) -> Frame | None:
        with self._frame_lock:
            return self._frames[-1] if self._frames else None

    def frame_at(self, t: float) -> Frame | None:
        """Closest frame whose captured_at <= t; None if none / deque empty."""
        with self._frame_lock:
            best: Frame | None = None
            for f in self._frames:
                if f.captured_at <= t:
                    if best is None or f.captured_at > best.captured_at:
                        best = f
                else:
                    break  # deque is chronologically ordered
            return best

    def mjpeg_iter(self) -> Iterator[bytes]:
        """Yield multipart-ready JPEG chunks for ``multipart/x-mixed-replace``.

        Each yielded chunk is ``--frame\\r\\nContent-Type: image/jpeg\\r\\n
        Content-Length: N\\r\\n\\r\\n<jpeg bytes>\\r\\n`` -- matching the
        framing the reference ptz_server_win.py writes to its HTTP response,
        so existing client code keeps working unchanged. Blocks until the
        next new frame arrives.
        """
        last_index = 0
        while True:
            with self._frame_cond:
                self._frame_cond.wait_for(
                    lambda: self._frame_index != last_index or self._camera_error,
                    timeout=5,
                )
                if self._camera_error and not self._frames:
                    raise RuntimeError(self._camera_error)
                if self._frame_index == last_index:
                    continue
                frame = self._frames[-1]
                last_index = self._frame_index
            jpg = frame.jpeg
            yield (
                b"--frame\r\n"
                b"Content-Type: image/jpeg\r\n"
                + f"Content-Length: {len(jpg)}\r\n\r\n".encode("ascii")
                + jpg
                + b"\r\n"
            )

    # --- internals ---------------------------------------------------------
    def _spawn_ffmpeg(self) -> tuple[subprocess.Popen, bytes]:
        cmd = [
            self._ffmpeg,
            "-hide_banner", "-loglevel", "error",
            "-f", "dshow",
            "-rtbufsize", "100M",
            "-video_size", "1280x720",
            "-framerate", "30",
            "-i", f"video={self._device_in_use}",
            "-an",
            "-vf", "fps=15",
            "-q:v", "5",
            "-f", "mjpeg",
            "pipe:1",
        ]
        proc = subprocess.Popen(
            cmd,
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

    def _append_frame(self, jpeg: bytes) -> None:
        now = time.time()
        cutoff = now - self.FRAME_WINDOW_SECONDS
        with self._frame_cond:
            self._frames.append(Frame(jpeg=jpeg, captured_at=now))
            while self._frames and self._frames[0].captured_at < cutoff:
                self._frames.popleft()
            self._frame_index += 1
            self._frame_cond.notify_all()

    def _camera_loop(self) -> None:
        while True:
            try:
                proc, buffered = self._spawn_ffmpeg()
                with self._frame_cond:
                    self._camera_error = ""
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
                        self._append_frame(data[s:e])
                        data = data[e:]
                    chunk = proc.stdout.read(16384)
                    if not chunk:
                        break
                    data += chunk
                proc.terminate()
            except Exception as exc:
                with self._frame_cond:
                    self._camera_error = str(exc)
                    self._frame_cond.notify_all()
                print(f"[camera] {exc}", file=sys.stderr)
                time.sleep(2)
