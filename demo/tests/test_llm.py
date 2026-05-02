import json
import pytest
from unittest.mock import patch, MagicMock
from demo.llm import LLMClient, ToolCall


def _fake_response(payload):
    r = MagicMock()
    r.status_code = 200
    r.json.return_value = payload
    r.raise_for_status = MagicMock()
    return r


def test_chat_returns_text_when_no_tool_calls():
    client = LLMClient(base_url="http://x", api_key="", model="m")
    payload = {"choices": [{"message": {"role": "assistant", "content": "hello"}}]}
    with patch.object(client._http, "post", return_value=_fake_response(payload)) as p:
        msg = client.chat(messages=[{"role": "user", "content": "hi"}], tools=[])
    assert msg.content == "hello"
    assert msg.tool_calls == []
    sent = p.call_args.kwargs["json"]
    assert sent["model"] == "m"


def test_chat_parses_tool_calls():
    client = LLMClient(base_url="http://x", api_key="", model="m")
    payload = {"choices": [{"message": {
        "role": "assistant", "content": None,
        "tool_calls": [{
            "id": "c1", "type": "function",
            "function": {"name": "foo", "arguments": '{"a": 1}'}
        }]}}]}
    with patch.object(client._http, "post", return_value=_fake_response(payload)):
        msg = client.chat(messages=[], tools=[])
    assert msg.tool_calls == [ToolCall(id="c1", name="foo", arguments={"a": 1})]
