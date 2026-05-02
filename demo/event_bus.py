# demo/event_bus.py
"""线程安全 SSE 事件总线。

asyncio.Queue 不是线程安全的，所以从工作线程发事件必须走
loop.call_soon_threadsafe。EventBus 把这个套路封死，并允许
测试 / scripts_player / amap / camera 共用。
"""
from __future__ import annotations
import asyncio
from typing import Any


class EventBus:
    def __init__(self) -> None:
        self.queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue()
        self._loop: asyncio.AbstractEventLoop | None = None

    def bind_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        """在 FastAPI startup 钩子里调一次。"""
        self._loop = loop

    def publish(self, ev: dict[str, Any]) -> None:
        """从任何线程都可调。bind_loop 之前调会 raise。"""
        if self._loop is None:
            raise RuntimeError("EventBus not bound to a loop")
        self._loop.call_soon_threadsafe(self.queue.put_nowait, ev)
