from unittest.mock import MagicMock
from demo.agent import AgentRuntime
from demo.event_bus import EventBus
from demo.llm import AssistantMessage, ToolCall


def test_agent_publishes_tool_call_event():
    llm = MagicMock()
    llm.chat.side_effect = [
        AssistantMessage(content=None, tool_calls=[
            ToolCall(id="t1", name="speak_to_user",
                     arguments={"text": "hi"})]),
        AssistantMessage(content="done", tool_calls=[]),
    ]

    spoken = []

    class SpeakTool:
        name = "speak_to_user"
        description = "Speak to user"
        parameters = {"type": "object", "properties": {}, "required": []}

        def invoke(self, arguments):
            spoken.append(arguments.get("text"))
            return {"ok": True}

    bus = MagicMock(spec=EventBus)
    dialog = MagicMock()
    dialog.__iter__ = MagicMock(return_value=iter([]))

    rt = AgentRuntime(llm=llm, tools=[SpeakTool()],
                      dialog=dialog, system_prompt="sys", event_bus=bus)
    rt.handle_user_turn("test")

    tool_events = [c.args[0] for c in bus.publish.call_args_list
                   if c.args[0].get("type") == "tool_call"]
    assert len(tool_events) == 1
    ev = tool_events[0]
    assert ev["name"] == "speak_to_user"
    assert ev["args"] == {"text": "hi"}
    assert ev["source"] == "agent"
