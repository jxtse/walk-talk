import time
from demo.dialog import DialogLog, MomentLog, DialogTurn, Moment


def test_dialog_log_append_and_iter():
    log = DialogLog()
    log.append("user", "你好")
    log.append("assistant", "你好，今天去哪儿？")
    turns = list(log)
    assert [t.role for t in turns] == ["user", "assistant"]
    assert turns[0].text == "你好"
    assert turns[0].timestamp <= turns[1].timestamp


def test_dialog_log_subscribe_receives_new_turns():
    log = DialogLog()
    received: list[DialogTurn] = []
    unsub = log.subscribe(received.append)
    log.append("user", "嘿")
    log.append("assistant", "在")
    assert len(received) == 2
    assert received[0].text == "嘿"
    unsub()
    log.append("user", "no one home")
    assert len(received) == 2


def test_moment_log_append_and_list():
    ml = MomentLog()
    ml.append(label="记一下这个", frame_path="/tmp/a.jpg")
    ml.append(label="还有那个", frame_path="/tmp/b.jpg")
    moments = list(ml)
    assert len(moments) == 2
    assert moments[0].label == "记一下这个"
    assert isinstance(moments[0].timestamp, float)
