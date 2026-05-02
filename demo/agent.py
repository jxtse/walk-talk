"""Sequential ReAct loop. One instance per session."""
from __future__ import annotations
import json
import threading
from typing import Any
from demo.dialog import DialogLog
from demo.llm import AssistantMessage, LLMClient
from demo.tools import to_openai_schema


class AgentRuntime:
    def __init__(self, *, llm: LLMClient, tools: list, dialog: DialogLog,
                 system_prompt: str, max_iterations: int = 8,
                 event_bus=None) -> None:
        self.llm = llm
        self.tools_by_name = {t.name: t for t in tools}
        self.tool_schemas = [to_openai_schema(t) for t in tools]
        self.dialog = dialog
        self.system_prompt = system_prompt
        self.max_iterations = max_iterations
        self._lock = threading.Lock()  # serialize turns
        self._bus = event_bus

    def _build_messages(self, extra_user_text: str | None) -> list[dict]:
        msgs: list[dict] = [{"role": "system", "content": self.system_prompt}]
        for t in self.dialog:
            if t.role in ("user", "assistant"):
                msgs.append({"role": t.role, "content": t.text})
        if extra_user_text is not None:
            msgs.append({"role": "user", "content": extra_user_text})
        return msgs

    def handle_user_turn(self, user_text: str) -> None:
        with self._lock:
            self.dialog.append("user", user_text)
            messages = self._build_messages(extra_user_text=None)
            self._loop(messages)

    def handle_proactive_check(self, proactive_prompt: str) -> None:
        with self._lock:
            messages = self._build_messages(extra_user_text=proactive_prompt)
            self._loop(messages)

    def _loop(self, messages: list[dict]) -> None:
        for it in range(self.max_iterations):
            if self._bus is not None:
                self._bus.publish({
                    "type": "llm_raw", "phase": "request",
                    "iteration": it, "model": self.llm.model,
                    "messages": messages[-4:],  # 只发尾部 4 条避免太大
                })
            msg: AssistantMessage = self.llm.chat(
                messages=messages, tools=self.tool_schemas)
            if self._bus is not None:
                self._bus.publish({
                    "type": "llm_raw", "phase": "response",
                    "iteration": it,
                    "content": msg.content,
                    "tool_calls": [{"name": tc.name, "args": tc.arguments}
                                   for tc in msg.tool_calls],
                })
            if not msg.tool_calls:
                # Final message. Prompt asks the model to call speak_to_user
                # for everything it wants to say, but gpt-5.5 sometimes
                # ignores that and dumps the reply straight into `content`.
                # Don't drop it — surface it to the user as if speak_to_user
                # had been called. (Skip if content is empty or looks like
                # a proactive "stay silent" response.)
                text = (msg.content or "").strip()
                if text:
                    speak = self.tools_by_name.get("speak_to_user")
                    if speak is not None:
                        try:
                            speak.invoke({"text": text})
                            if self._bus is not None:
                                self._bus.publish({
                                    "type": "tool_call", "source": "agent",
                                    "name": "speak_to_user",
                                    "args": {"text": text,
                                             "_synthesized": True},
                                })
                        except Exception as e:  # noqa: BLE001
                            self.dialog.append("assistant", text)
                            print(f"[agent] speak fallback failed: {e}")
                    else:
                        self.dialog.append("assistant", text)
                return
            messages.append({
                "role": "assistant",
                "content": msg.content,
                "tool_calls": [{
                    "id": tc.id, "type": "function",
                    "function": {"name": tc.name,
                                 "arguments": json.dumps(tc.arguments,
                                                         ensure_ascii=False)},
                } for tc in msg.tool_calls],
            })
            for tc in msg.tool_calls:
                if self._bus is not None:
                    self._bus.publish({
                        "type": "tool_call", "source": "agent",
                        "name": tc.name, "args": tc.arguments,
                    })
                tool = self.tools_by_name.get(tc.name)
                if tool is None:
                    result: Any = {"error": f"unknown tool: {tc.name}"}
                else:
                    try:
                        result = tool.invoke(tc.arguments)
                    except Exception as e:
                        result = {"error": str(e)}
                messages.append({
                    "role": "tool", "tool_call_id": tc.id,
                    "content": json.dumps(result, ensure_ascii=False),
                })
