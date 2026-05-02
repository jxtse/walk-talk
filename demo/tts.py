"""pyttsx3-backed TTS, runs in a dedicated thread with a queue."""
from __future__ import annotations
import queue
import threading
from typing import Optional


class TTSService:
    def __init__(self, *, voice_substring: str = "Huihui", rate: int = 200) -> None:
        # pyttsx3 init must happen on the speaker thread on Windows.
        self._q: queue.Queue[Optional[str]] = queue.Queue()
        self._voice_substring = voice_substring
        self._rate = rate
        self._t = threading.Thread(target=self._run, name="tts", daemon=True)
        self._t.start()

    def _run(self) -> None:
        import pyttsx3
        engine = pyttsx3.init()
        engine.setProperty("rate", self._rate)
        for v in engine.getProperty("voices"):
            if self._voice_substring.lower() in v.name.lower():
                engine.setProperty("voice", v.id)
                break
        while True:
            text = self._q.get()
            if text is None:
                break
            try:
                engine.say(text)
                engine.runAndWait()
            except Exception:
                pass

    def say(self, text: str) -> None:
        self._q.put(text)

    def flush(self) -> None:
        """Drop any pending utterances queued for speech."""
        try:
            while True:
                self._q.get_nowait()
        except queue.Empty:
            pass

    def shutdown(self) -> None:
        self._q.put(None)
