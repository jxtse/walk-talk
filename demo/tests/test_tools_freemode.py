# demo/tests/test_tools_freemode.py
"""自由模式新工具：图片降级链 + event_bus 推送 + LLM 友好返回。"""
from pathlib import Path
from unittest.mock import MagicMock
from demo.amap import POI
from demo.tools import (
    SearchAroundTool, LookupPlaceTool, SearchXhsTool,
    RecommendPoiCardTool, ShowConceptCardTool,
)


def _poi(name="鸡鸣寺", photos=None, location=(118.79, 32.07)):
    return POI(
        id=name, name=name, location=location, distance_m=10,
        address="addr", typecode="00", rating=None, cost=None,
        tags=[], photos=list(photos or []), raw={},
    )


def _media_with_gen(tmp_path):
    media = MagicMock()
    target = tmp_path / "gen_abc.png"
    target.write_bytes(b"fake")
    media.generate_image_to_cache.return_value = target
    return media, target


# ================= search_around =================

def test_search_around_returns_brief():
    amap = MagicMock()
    amap.search_around.return_value = [_poi(), _poi(name="梅园")]
    t = SearchAroundTool(amap=amap, location_provider=lambda: "118.79,32.07")
    out = t.invoke({"keywords": "寺", "radius": 800})
    assert out["status"] == "ok"
    assert out["count"] == 2
    assert out["pois"][0]["name"] == "鸡鸣寺"
    amap.search_around.assert_called_once()
    assert amap.search_around.call_args.kwargs["location"] == "118.79,32.07"


# ================= lookup_place 三条降级链 =================

def test_lookup_place_uses_amap_photo(monkeypatch, tmp_path):
    amap = MagicMock()
    amap.text_search.return_value = [_poi(photos=["https://amap/a.jpg"])]
    bus = MagicMock()

    from demo import tools as tmod
    monkeypatch.setattr(tmod, "download_to_cache",
                        lambda **kw: tmp_path / "dl_x.jpg",
                        raising=False)
    # tools 模块里是局部 import；patch 真实路径
    from demo import media as mmod
    monkeypatch.setattr(mmod, "download_to_cache",
                        lambda **kw: tmp_path / "dl_x.jpg")

    t = LookupPlaceTool(amap=amap, xhs=MagicMock(available=False),
                        media=MagicMock(),
                        cache_dir=tmp_path,
                        location_provider=lambda: "118.79,32.07",
                        event_bus=bus)
    out = t.invoke({"name": "鸡鸣寺"})
    assert out["status"] == "ok"
    assert out["image_source"] == "amap"
    assert out["image_url"].startswith("/poi_image/")


def test_lookup_place_falls_back_to_generated(monkeypatch, tmp_path):
    amap = MagicMock()
    amap.text_search.return_value = [_poi(photos=[])]  # no amap photo
    xhs = MagicMock(available=False)
    media, target = _media_with_gen(tmp_path)

    t = LookupPlaceTool(amap=amap, xhs=xhs, media=media,
                        cache_dir=tmp_path,
                        location_provider=lambda: "118.79,32.07")
    out = t.invoke({"name": "鸡鸣寺"})
    assert out["status"] == "ok"
    assert out["image_source"] == "generated"
    assert out["image_url"] == f"/poi_image/{target.name}"


def test_lookup_place_no_match_still_returns_image(tmp_path):
    amap = MagicMock(); amap.text_search.return_value = []
    media, target = _media_with_gen(tmp_path)
    t = LookupPlaceTool(amap=amap, xhs=MagicMock(available=False),
                        media=media, cache_dir=tmp_path,
                        location_provider=lambda: "118.79,32.07")
    out = t.invoke({"name": "不存在的地方"})
    assert out["status"] == "no_match"
    assert out["image_source"] == "generated"


# ================= search_xiaohongshu =================

def test_search_xhs_unavailable():
    xhs = MagicMock(); xhs.available = False
    out = SearchXhsTool(xhs=xhs).invoke({"query": "玄武湖"})
    assert out["status"] == "unavailable"


def test_search_xhs_returns_clean_items():
    xhs = MagicMock(); xhs.available = True
    xhs.search.return_value = {"available": True, "items": [
        {"title": "T", "desc": "D" * 500, "images": ["u1", "u2", "u3", "u4"],
         "url": "https://x", "liked_count": 5, "nickname": "alice"},
    ]}
    out = SearchXhsTool(xhs=xhs).invoke({"query": "玄武湖", "limit": 1})
    assert out["status"] == "ok"
    item = out["items"][0]
    assert len(item["desc"]) == 400
    assert len(item["images"]) == 3


# ================= recommend_poi_card =================

def test_recommend_poi_card_publishes(tmp_path):
    bus = MagicMock()
    media, target = _media_with_gen(tmp_path)
    amap = MagicMock(); amap.text_search.return_value = []  # 走到 gen
    t = RecommendPoiCardTool(amap=amap, xhs=MagicMock(available=False),
                             media=media, cache_dir=tmp_path,
                             event_bus=bus)
    out = t.invoke({"name": "湖边咖啡", "tagline": "坐窗边的位置最好"})
    assert out["status"] == "ok"
    assert out["place"]["image_url"].startswith("/poi_image/")
    bus.publish.assert_called_once()
    ev = bus.publish.call_args.args[0]
    assert ev["type"] == "poi_card"
    assert ev["name"] == "湖边咖啡"
    assert ev["image_url"].startswith("/poi_image/")


def test_recommend_poi_card_provided_url_keeps_external_when_local(tmp_path):
    bus = MagicMock()
    t = RecommendPoiCardTool(amap=MagicMock(), xhs=MagicMock(available=False),
                             media=MagicMock(), cache_dir=tmp_path,
                             event_bus=bus)
    out = t.invoke({"name": "X", "tagline": "x",
                    "image_url": "/static/foo.jpg"})
    assert out["place"]["image_url"] == "/static/foo.jpg"
    assert out["place"]["image_source"] == "provided"


# ================= show_concept_card =================

def test_show_concept_card_publishes_with_image(tmp_path):
    bus = MagicMock()
    media, target = _media_with_gen(tmp_path)
    amap = MagicMock(); amap.text_search.return_value = []
    t = ShowConceptCardTool(amap=amap, xhs=MagicMock(available=False),
                            media=media, cache_dir=tmp_path, event_bus=bus)
    out = t.invoke({
        "title": "扎哈双塔",
        "subtitle": "青奥中心",
        "body": "扎哈·哈迪德设计的曲面双塔……",
        "tags": ["建筑", "扎哈", "南京"],
        "image_query": "南京青奥中心 扎哈双塔",
    })
    assert out["status"] == "ok"
    bus.publish.assert_called_once()
    ev = bus.publish.call_args.args[0]
    assert ev["type"] == "concept_card"
    assert ev["title"] == "扎哈双塔"
    assert ev["tags"] == ["建筑", "扎哈", "南京"]
    assert ev["image_url"].startswith("/poi_image/")
