# demo/tests/test_amap_extra.py
"""新增的高德端点：text_search / regeo / walking_route，以及 photos 解析。"""
from unittest.mock import MagicMock
from demo.amap import AmapClient
from demo.event_bus import EventBus


def _client(response_json):
    fake_resp = MagicMock()
    fake_resp.json.return_value = response_json
    fake_resp.raise_for_status.return_value = None
    fake_http = MagicMock()
    fake_http.get.return_value = fake_resp
    bus = MagicMock(spec=EventBus)
    return AmapClient(key="k", event_bus=bus, http=fake_http), fake_http, bus


def test_search_around_extracts_photos():
    resp = {
        "status": "1", "info": "OK",
        "pois": [{
            "id": "1", "name": "X", "location": "1,2",
            "distance": "10", "address": "addr", "typecode": "0",
            "biz_ext": {}, "photos": [
                {"title": "门头", "url": "https://img/a.jpg"},
                {"url": "https://img/b.png"},
            ],
        }],
    }
    c, _, _ = _client(resp)
    pois = c.search_around(location="1,2", keywords="x")
    assert pois[0].photos == ["https://img/a.jpg", "https://img/b.png"]


def test_text_search_calls_correct_endpoint():
    resp = {"status": "1", "info": "OK", "pois": []}
    c, http, _ = _client(resp)
    c.text_search(keywords="鸡鸣寺", region="南京")
    url = http.get.call_args.args[0]
    params = http.get.call_args.kwargs["params"]
    assert url.endswith("/v3/place/text")
    assert params["keywords"] == "鸡鸣寺"
    assert params["city"] == "南京"
    assert params["citylimit"] == "true"


def test_regeo_returns_address():
    resp = {
        "status": "1", "info": "OK",
        "regeocode": {
            "formatted_address": "江苏省南京市玄武区某街",
            "addressComponent": {
                "province": "江苏省", "city": "南京市",
                "district": "玄武区", "township": "梅园新村街道",
            },
        },
    }
    c, http, _ = _client(resp)
    out = c.regeo(location="118.79,32.07")
    assert out["formatted_address"].startswith("江苏省")
    assert out["city"] == "南京市"
    assert http.get.call_args.args[0].endswith("/v3/geocode/regeo")


def test_walking_route_extracts_distance_and_steps():
    resp = {
        "status": "1", "info": "OK",
        "route": {"paths": [{
            "distance": "1234", "duration": "900",
            "steps": [
                {"instruction": "向北走", "distance": "100"},
                {"instruction": "右转", "distance": "200"},
            ],
        }]},
    }
    c, http, _ = _client(resp)
    out = c.walking_route(origin="1,2", destination="3,4")
    assert out["distance_m"] == 1234
    assert out["duration_s"] == 900
    assert out["steps"][0]["instruction"] == "向北走"
    assert http.get.call_args.args[0].endswith("/v3/direction/walking")
