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
            # Prefer explicit image_url (e.g. real photo from /static)
            # over the cached generated image referenced by image_id.
            image_url = poi.get("image_url") or f"/poi_image/{poi['image_id']}.png"
            self._bus.publish({
                "type": "poi_card",
                "poi_id": poi["poi_id"], "name": poi["name"],
                "distance_m": poi["distance_m"],
                "rating": poi["rating"], "cost": poi["cost"],
                "address": poi["address"], "tagline": poi["tagline"],
                "image_url": image_url,
            })
        elif et == "poi_image_swap":
            # If event provides a direct to_image_url, use it; otherwise
            # look up by to_image_id, falling back to /poi_image/<id>.png.
            if ev.get("to_image_url"):
                image_url = ev["to_image_url"]
            else:
                tid = ev["to_image_id"]
                # See if any POI has alt_image_id matching tid with an alt_image_url
                image_url = f"/poi_image/{tid}.png"
                for poi in self._pois.values():
                    if poi.get("alt_image_id") == tid and poi.get("alt_image_url"):
                        image_url = poi["alt_image_url"]
                        break
                    if poi.get("image_id") == tid and poi.get("image_url"):
                        image_url = poi["image_url"]
                        break
            self._bus.publish({
                "type": "poi_image_swap",
                "poi_id": ev["poi_id"],
                "image_url": image_url})
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
