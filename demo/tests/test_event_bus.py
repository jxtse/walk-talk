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
