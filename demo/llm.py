"""OpenAI-compatible client for the internal endpoint."""
from __future__ import annotations
import base64
import json
from dataclasses import dataclass, field
from typing import Any
import httpx

DEFAULT_BASE_URL = "http://100.99.139.20:18141"
DEFAULT_PLANNER_MODEL = "claude-sonnet-4.5"
DEFAULT_VLM_MODEL = "gpt-4o-2024-11-20"


@dataclass(frozen=True)
class ToolCall:
    id: str
    name: str
    arguments: dict[str, Any]


@dataclass(frozen=True)
class AssistantMessage:
    content: str | None
    tool_calls: list[ToolCall] = field(default_factory=list)


class LLMClient:
    def __init__(self, *, base_url: str = DEFAULT_BASE_URL, api_key: str = "",
                 model: str = DEFAULT_PLANNER_MODEL, vlm_model: str = DEFAULT_VLM_MODEL,
                 timeout: float = 60.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.vlm_model = vlm_model
        headers: dict[str, str] = {"content-type": "application/json"}
        if api_key:
            headers["authorization"] = f"Bearer {api_key}"
        # The internal endpoint sits on Tailscale (100.64/10) and must NOT be
        # routed through any system proxy (Clash/v2ray on 127.0.0.1:7897 will
        # forward it to the public internet and get a 502). Pass an explicit
        # ``trust_env=False`` so httpx ignores HTTP(S)_PROXY env vars and the
        # Windows registry proxy.
        self._http = httpx.Client(
            timeout=timeout,
            headers=headers,
            trust_env=False,
        )

    def chat(self, *, messages: list[dict], tools: list[dict],
             model: str | None = None) -> AssistantMessage:
        body = {"model": model or self.model, "messages": messages}
        if tools:
            body["tools"] = tools
            body["tool_choice"] = "auto"
        r = self._http.post(f"{self.base_url}/v1/chat/completions", json=body)
        r.raise_for_status()
        msg = r.json()["choices"][0]["message"]
        tcs: list[ToolCall] = []
        for tc in msg.get("tool_calls") or []:
            try:
                args = json.loads(tc["function"]["arguments"] or "{}")
            except json.JSONDecodeError:
                args = {"_raw": tc["function"]["arguments"]}
            tcs.append(ToolCall(id=tc["id"], name=tc["function"]["name"], arguments=args))
        return AssistantMessage(content=msg.get("content"), tool_calls=tcs)

    def vlm(self, *, jpeg_bytes: bytes, question: str) -> str:
        b64 = base64.b64encode(jpeg_bytes).decode()
        messages = [{
            "role": "user",
            "content": [
                {"type": "text", "text": question},
                {"type": "image_url",
                 "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
            ],
        }]
        r = self._http.post(f"{self.base_url}/v1/chat/completions",
                            json={"model": self.vlm_model, "messages": messages})
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"] or ""
