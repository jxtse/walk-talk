"""Append-only logs for the demo session."""
from __future__ import annotations
import threading
import time
from dataclasses import dataclass
from typing import Callable, Iterator, Literal

Role = Literal["user", "assistant", "system", "tool"]


@dataclass(frozen=True)
class DialogTurn:
    role: Role
    text: str
    timestamp: float


@dataclass(frozen=True)
class Moment:
    label: str
    frame_path: str
    timestamp: float


class DialogLog:
    def __init__(self) -> None:
        self._turns: list[DialogTurn] = []
        self._subs: list[Callable[[DialogTurn], None]] = []
        self._lock = threading.Lock()

    def append(self, role: Role, text: str) -> DialogTurn:
        turn = DialogTurn(role=role, text=text, timestamp=time.time())
        with self._lock:
            self._turns.append(turn)
            subs = list(self._subs)
        for fn in subs:
            try:
                fn(turn)
            except Exception:
                pass  # subscriber failure is never fatal
        return turn

    def __iter__(self) -> Iterator[DialogTurn]:
        with self._lock:
            return iter(list(self._turns))

    def clear(self) -> None:
        with self._lock:
            self._turns.clear()

    def subscribe(self, fn: Callable[[DialogTurn], None]) -> Callable[[], None]:
        with self._lock:
            self._subs.append(fn)

        def unsub() -> None:
            with self._lock:
                if fn in self._subs:
                    self._subs.remove(fn)

        return unsub


class MomentLog:
    def __init__(self) -> None:
        self._items: list[Moment] = []
        self._lock = threading.Lock()

    def append(self, *, label: str, frame_path: str) -> Moment:
        m = Moment(label=label, frame_path=frame_path, timestamp=time.time())
        with self._lock:
            self._items.append(m)
        return m

    def __iter__(self) -> Iterator[Moment]:
        with self._lock:
            return iter(list(self._items))

    def clear(self) -> None:
        with self._lock:
            self._items.clear()
