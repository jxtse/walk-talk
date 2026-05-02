from unittest.mock import MagicMock
from demo.agent import AgentRuntime
from demo.dialog import DialogLog
from demo.llm import AssistantMessage, ToolCall


class FakeTool:
    def __init__(self, name, result):
        self.name, self._result = name, result
        self.description = "x"; self.parameters = {"type": "object", "properties": {}}
        self.calls = []
    def invoke(self, args):
        self.calls.append(args); return self._result


def test_agent_loop_one_tool_then_final():
    llm = MagicMock()
    llm.chat.side_effect = [
        AssistantMessage(content=None, tool_calls=[ToolCall("c1", "say", {"text": "hi"})]),
        AssistantMessage(content="done", tool_calls=[]),
    ]
    say = FakeTool("say", {"status": "ok"})
    log = DialogLog()
    rt = AgentRuntime(llm=llm, tools=[say], dialog=log, system_prompt="SYS")
    rt.handle_user_turn("hello")
    assert say.calls == [{"text": "hi"}]
    assert llm.chat.call_count == 2


def test_agent_loop_caps_iterations():
    llm = MagicMock()
    looping = AssistantMessage(
        content=None,
        tool_calls=[ToolCall(f"c{i}", "noop", {}) for i in [1]])
    llm.chat.return_value = looping
    noop = FakeTool("noop", {"status": "ok"})
    rt = AgentRuntime(llm=llm, tools=[noop], dialog=DialogLog(),
                      system_prompt="SYS", max_iterations=3)
    rt.handle_user_turn("loop please")
    assert llm.chat.call_count == 3


def test_agent_unknown_tool_returns_error_to_model():
    llm = MagicMock()
    llm.chat.side_effect = [
        AssistantMessage(content=None,
                         tool_calls=[ToolCall("c1", "missing", {})]),
        AssistantMessage(content="ok", tool_calls=[]),
    ]
    rt = AgentRuntime(llm=llm, tools=[], dialog=DialogLog(),
                      system_prompt="SYS")
    rt.handle_user_turn("x")
    second_call_msgs = llm.chat.call_args_list[1].kwargs["messages"]
    tool_msg = [m for m in second_call_msgs if m["role"] == "tool"][0]
    assert "unknown tool" in tool_msg["content"]
