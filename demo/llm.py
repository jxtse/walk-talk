"""OpenAI-compatible client for the internal endpoint.

Supports two API shapes:
- /v1/chat/completions for classic models (gpt-5.2, sonnet-*, gpt-4o, ...)
- /v1/responses for newer reasoning models (gpt-5.5+) that the planner
  endpoint refuses to serve via /chat/completions.

`chat()` returns the same `AssistantMessage` regardless of route.
"""
from __future__ import annotations
import base64
import json
from dataclasses import dataclass, field
from typing import Any
import httpx

DEFAULT_BASE_URL = "http://100.99.139.20:18141"
DEFAULT_PLANNER_MODEL = "gpt-5.5"
DEFAULT_VLM_MODEL = "gpt-4o-2024-11-20"

# Models that require the Responses API (Chat Completions returns
# unsupported_api_for_model). Match by prefix.
_RESPONSES_API_PREFIXES = ("gpt-5.5", "gpt-5.4-mini")


def _uses_responses_api(model: str) -> bool:
    return any(model.startswith(p) for p in _RESPONSES_API_PREFIXES)


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
        m = model or self.model
        if _uses_responses_api(m):
            return self._chat_responses(messages=messages, tools=tools, model=m)
        return self._chat_completions(messages=messages, tools=tools, model=m)

    # ---------------- Chat Completions (classic) ----------------
    def _chat_completions(self, *, messages: list[dict], tools: list[dict],
                          model: str) -> AssistantMessage:
        body: dict[str, Any] = {"model": model, "messages": messages}
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

    # ---------------- Responses API (gpt-5.5+) ----------------
    def _chat_responses(self, *, messages: list[dict], tools: list[dict],
                        model: str) -> AssistantMessage:
        """Translate Chat-Completions-style history -> /v1/responses input."""
        # Pull out system as `instructions`; rest becomes `input`.
        instructions_parts: list[str] = []
        input_items: list[dict] = []
        for m in messages:
            role = m.get("role")
            if role == "system":
                if isinstance(m.get("content"), str):
                    instructions_parts.append(m["content"])
                continue
            if role == "user":
                input_items.append({"role": "user",
                                    "content": m.get("content") or ""})
            elif role == "assistant":
                # Optional textual content first
                if m.get("content"):
                    input_items.append({"role": "assistant",
                                        "content": m["content"]})
                for tc in m.get("tool_calls") or []:
                    input_items.append({
                        "type": "function_call",
                        "call_id": tc["id"],
                        "name": tc["function"]["name"],
                        "arguments": tc["function"]["arguments"],
                    })
            elif role == "tool":
                input_items.append({
                    "type": "function_call_output",
                    "call_id": m.get("tool_call_id", ""),
                    "output": m.get("content") or "",
                })

        # Translate tool schemas: chat-completions wraps in {"function": {...}};
        # responses API expects flat {type, name, description, parameters}.
        responses_tools: list[dict] = []
        for t in tools:
            fn = t.get("function") if isinstance(t, dict) else None
            if fn:
                responses_tools.append({
                    "type": "function",
                    "name": fn["name"],
                    "description": fn.get("description", ""),
                    "parameters": fn.get("parameters", {}),
                })
            else:
                responses_tools.append(t)

        body: dict[str, Any] = {"model": model, "input": input_items}
        if instructions_parts:
            body["instructions"] = "\n\n".join(instructions_parts)
        if responses_tools:
            body["tools"] = responses_tools
            body["tool_choice"] = "auto"

        r = self._http.post(f"{self.base_url}/v1/responses", json=body)
        r.raise_for_status()
        data = r.json()

        content_text: str | None = data.get("output_text") or None
        tcs: list[ToolCall] = []
        text_chunks: list[str] = []
        for item in data.get("output") or []:
            itype = item.get("type")
            if itype == "function_call":
                try:
                    args = json.loads(item.get("arguments") or "{}")
                except json.JSONDecodeError:
                    args = {"_raw": item.get("arguments")}
                tcs.append(ToolCall(
                    id=item.get("call_id") or item.get("id") or "",
                    name=item.get("name", ""),
                    arguments=args,
                ))
            elif itype == "message":
                for c in item.get("content") or []:
                    if c.get("type") in ("output_text", "text"):
                        text_chunks.append(c.get("text", ""))
        if text_chunks and not content_text:
            content_text = "".join(text_chunks)
        return AssistantMessage(content=content_text, tool_calls=tcs)

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
