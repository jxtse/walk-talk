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


def test_pan_camera_left_calls_move():
    cam = _fake_camera()
    PanCameraTool(camera=cam).invoke({"direction": "left", "step": 30, "reason": "test"})
    cam.move.assert_called_once_with("left", step=30)


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
