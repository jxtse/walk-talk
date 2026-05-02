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
    assert "reason" not in out
    assert calls == [("left", 20)]
