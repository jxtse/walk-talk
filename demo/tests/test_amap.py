# demo/tests/test_amap.py
from unittest.mock import MagicMock
from demo.amap import AmapClient, POI
from demo.event_bus import EventBus


_FAKE_RESPONSE = {
    "status": "1",
    "info": "OK",
    "pois": [{
        "id": "B0LKXKHOQW",
        "name": "Beans Solo 豆号咖啡(玄武湖国展店)",
        "location": "118.787,32.080",
        "distance": "1040",
        "address": "玄武湖翠洲门进园 · 芙蓉桥旁",
        "typecode": "050500",
        "atag": "手冲,湖景",
        "biz_ext": {"rating": "4.4", "cost": "23.00"},
    }],
}


def _make_client(response_json):
    fake_resp = MagicMock()
    fake_resp.json.return_value = response_json
    fake_resp.raise_for_status.return_value = None
    fake_http = MagicMock()
    fake_http.get.return_value = fake_resp
    bus = MagicMock(spec=EventBus)
    return AmapClient(key="ak_test", event_bus=bus, http=fake_http), fake_http, bus


def test_search_around_parses_poi():
    c, _, _ = _make_client(_FAKE_RESPONSE)
    pois = c.search_around(location="118.795,32.075",
                           keywords="咖啡", radius=2000)
    assert len(pois) == 1
    p = pois[0]
    assert isinstance(p, POI)
    assert p.id == "B0LKXKHOQW"
    assert p.name.startswith("Beans Solo")
    assert p.location == (118.787, 32.080)
    assert p.distance_m == 1040
    assert p.rating == 4.4
    assert p.cost == 23.0
    assert p.tags == ["手冲", "湖景"]


def test_search_around_publishes_amap_raw():
    c, _, bus = _make_client(_FAKE_RESPONSE)
    c.search_around(location="118.795,32.075", keywords="咖啡")
    bus.publish.assert_called_once()
    ev = bus.publish.call_args.args[0]
    assert ev["type"] == "amap_raw"
    assert ev["params"]["keywords"] == "咖啡"
    assert ev["count"] == 1


def test_handles_missing_optional_fields():
    resp = {
        "status": "1", "info": "OK",
        "pois": [{
            "id": "x", "name": "无评分店", "location": "1,2",
            "distance": "100", "address": "...", "typecode": "050000",
            "atag": [], "biz_ext": [],
        }],
    }
    c, _, _ = _make_client(resp)
    pois = c.search_around(location="1,2", keywords="x")
    assert pois[0].rating is None
    assert pois[0].cost is None
    assert pois[0].tags == []


def test_status_zero_returns_empty_list_and_logs():
    resp = {"status": "0", "info": "INVALID_USER_KEY", "pois": []}
    c, _, bus = _make_client(resp)
    pois = c.search_around(location="1,2", keywords="x")
    assert pois == []
    ev = bus.publish.call_args.args[0]
    assert ev["status"] == "0"
