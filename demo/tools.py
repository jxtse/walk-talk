"""Six tools the agent can call. Each returns a JSON-serializable dict."""
from __future__ import annotations
import base64
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol


class Tool(Protocol):
    name: str
    description: str
    parameters: dict

    def invoke(self, args: dict) -> dict: ...


@dataclass
class GetCameraFrameTool:
    camera: Any
    name: str = "get_camera_frame"
    description: str = "返回相机当前画面的 base64 JPEG。"
    parameters: dict = field(default_factory=lambda: {
        "type": "object", "properties": {}
    })

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
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {"question": {"type": "string"}},
        "required": ["question"],
    })

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
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {"text": {"type": "string"}},
        "required": ["text"],
    })

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
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {"label": {"type": "string"}},
        "required": ["label"],
    })

    def __post_init__(self):
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
        _ = reason
        return self.camera.move(direction, step=step)

    def invoke(self, args: dict) -> dict:
        return self.run(
            direction=args["direction"],
            reason=args.get("reason", ""),
            step=int(args.get("step", 20)),
        )


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


def to_openai_schema(tool) -> dict:
    return {"type": "function", "function": {
        "name": tool.name, "description": tool.description,
        "parameters": tool.parameters,
    }}
