"""Six tools the agent can call. Each returns a JSON-serializable dict."""
from __future__ import annotations
import base64
import json
import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Protocol


class Tool(Protocol):
    name: str
    description: str
    parameters: dict

    def invoke(self, args: dict) -> dict: ...


@dataclass
class GetCameraFrameTool:
    camera: Any
    name: str = "get_camera_frame"
    description: str = "返回相机当前画面的 base64 JPEG。"
    parameters: dict = field(default_factory=lambda: {
        "type": "object", "properties": {}
    })

    def invoke(self, args: dict) -> dict:
        f = self.camera.latest_frame()
        if not f:
            return {"status": "no_frame"}
        return {"status": "ok",
                "image_b64": base64.b64encode(f.jpeg).decode(),
                "captured_at": f.captured_at}


@dataclass
class AnalyzeFrameVLMTool:
    camera: Any
    llm: Any
    name: str = "analyze_frame_vlm"
    description: str = "用视觉模型分析当前相机画面。问题用中文。"
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {"question": {"type": "string"}},
        "required": ["question"],
    })

    def invoke(self, args: dict) -> dict:
        f = self.camera.latest_frame()
        if not f:
            return {"status": "no_frame"}
        ans = self.llm.vlm(jpeg_bytes=f.jpeg, question=args["question"])
        return {"status": "ok", "answer": ans}


@dataclass
class SpeakToUserTool:
    dialog: Any
    tts: Any
    name: str = "speak_to_user"
    description: str = "通过耳机/扬声器对用户说话。说一句中文。"
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {"text": {"type": "string"}},
        "required": ["text"],
    })

    def invoke(self, args: dict) -> dict:
        text = args["text"]
        self.dialog.append("assistant", text)
        self.tts.say(text)
        return {"status": "ok"}


@dataclass
class RecordMomentTool:
    camera: Any
    moments: Any
    save_dir: Path
    name: str = "record_moment"
    description: str = "把当前画面存成关键帧并打标签。"
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {"label": {"type": "string"}},
        "required": ["label"],
    })

    def __post_init__(self):
        Path(self.save_dir).mkdir(parents=True, exist_ok=True)

    def invoke(self, args: dict) -> dict:
        f = self.camera.latest_frame()
        if not f:
            return {"status": "no_frame"}
        path = Path(self.save_dir) / f"moment_{int(f.captured_at * 1000)}.jpg"
        path.write_bytes(f.jpeg)
        self.moments.append(label=args["label"], frame_path=str(path))
        return {"status": "ok", "frame_path": str(path)}


@dataclass
class PanCameraTool:
    name: str = "pan_camera"
    description: str = (
        "把相机转到一个方向看一眼。当你想引用画面里的东西、想确认方向、"
        "或想给用户展示某个角度时，主动调它。reason 字段必须填，简短说明为什么转。"
    )
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {
            "direction": {
                "type": "string",
                "enum": ["left", "right", "up", "down", "center",
                         "zoom_in", "zoom_out"],
            },
            "step": {"type": "integer", "default": 20,
                     "description": "步长，pan/tilt 通常 10-30，zoom 5-15"},
            "reason": {"type": "string",
                       "description": "为什么要转，例如：用户提到湖，先看一眼"},
        },
        "required": ["direction", "reason"],
    })
    camera: Any = None

    def run(self, *, direction: str, reason: str, step: int = 20) -> dict:
        _ = reason
        return self.camera.move(direction, step=step)

    def invoke(self, args: dict) -> dict:
        return self.run(
            direction=args["direction"],
            reason=args.get("reason", ""),
            step=int(args.get("step", 20)),
        )


class RecommendNearbyPlaceTool:
    name = "recommend_nearby_place"
    description = (
        "推荐一个附近的地点给用户：会自动把卡片推到前端 S5（图片+介绍+按钮）。"
        "返回该 POI 的完整信息，你可以基于 tagline/vibe 用 speak_to_user 跟"
        "用户说一句，比如：'前面 200 米有家鸡鸣寺，去看看吗？'"
    )
    parameters = {"type": "object", "properties": {}}

    def __init__(self, poi_path: Path, event_bus=None) -> None:
        data = json.loads(Path(poi_path).read_text(encoding="utf-8"))
        self._pois: list[dict] = list(data["pois"])
        self._used: set[str] = set()
        self._bus = event_bus

    def invoke(self, args: dict) -> dict:
        for p in self._pois:
            if p["id"] not in self._used:
                self._used.add(p["id"])
                if self._bus is not None:
                    try:
                        self._bus.publish({
                            "type": "poi_card",
                            "poi_id": p["id"],
                            "name": p["name"],
                            "tagline": p.get("tagline", ""),
                            "vibe": p.get("vibe", ""),
                            "distance_m": p.get("imagined_distance_m"),
                            "rating": p.get("rating"),
                            "image_url": p.get("image_url", ""),
                        })
                    except Exception as e:  # noqa: BLE001
                        print(f"[recommend] publish failed: {e}")
                return {"status": "ok", "place": p}
        return {"status": "exhausted"}


def to_openai_schema(tool) -> dict:
    return {"type": "function", "function": {
        "name": tool.name, "description": tool.description,
        "parameters": tool.parameters,
    }}


# =====================================================================
# Free-mode tools: 让 LLM 真的能基于实时定位 + 高德 + 小红书 + 图像生成回答
# =====================================================================

PLACEHOLDER_IMAGE_URL = "/static/mockup/placeholder.png"


def _haversine_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    """两个 (lng, lat) 之间的米距，足够近的距离用 Haversine 即可。"""
    lng1, lat1 = a
    lng2, lat2 = b
    R = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(min(1.0, math.sqrt(h)))


def _poi_to_brief(p) -> dict:
    return {
        "id": p.id,
        "name": p.name,
        "location": list(p.location),
        "distance_m": p.distance_m,
        "address": p.address,
        "typecode": p.typecode,
        "rating": p.rating,
        "tags": p.tags,
        "first_photo": (p.photos[0] if p.photos else None),
    }


def _resolve_image(*, name: str, hint: str | None,
                   amap, xhs, media, cache_dir: Path,
                   region: str = "南京") -> tuple[str, str]:
    """图片降级链：amap photos -> xhs images -> 图像生成 -> 占位图。

    返回 (local_url, source) ；local_url 形如 '/poi_image/<name>'。
    任何环节抛错都吞掉、继续往下试。
    """
    from demo.media import download_to_cache

    # 1. 高德 text_search
    try:
        if amap is not None:
            pois = amap.text_search(keywords=name, region=region)
            for p in pois:
                if p.photos:
                    path = download_to_cache(url=p.photos[0],
                                             cache_dir=cache_dir)
                    return f"/poi_image/{path.name}", "amap"
    except Exception as e:  # noqa: BLE001
        print(f"[image_resolve] amap photo failed: {e}")

    # 2. 小红书
    try:
        if xhs is not None and getattr(xhs, "available", False):
            res = xhs.search(query=name, limit=3)
            for note in res.get("items") or []:
                imgs = note.get("images") or []
                if imgs:
                    path = download_to_cache(url=imgs[0], cache_dir=cache_dir)
                    return f"/poi_image/{path.name}", "xiaohongshu"
    except Exception as e:  # noqa: BLE001
        print(f"[image_resolve] xhs photo failed: {e}")

    # 3. 图像生成
    try:
        if media is not None:
            prompt = (
                f"{name}，{hint or ''}，自然光摄影写实风格，竖向构图 4:5，"
                "城市散步偶遇感，无人物、无文字水印"
            ).strip()
            path = media.generate_image_to_cache(prompt=prompt,
                                                 cache_dir=cache_dir,
                                                 size="1024x1024")
            return f"/poi_image/{path.name}", "generated"
    except Exception as e:  # noqa: BLE001
        print(f"[image_resolve] gen image failed: {e}")

    return PLACEHOLDER_IMAGE_URL, "placeholder"


@dataclass
class SearchAroundTool:
    amap: Any
    location_provider: Callable[[], str]
    name: str = "search_around"
    description: str = (
        "调用高德『周边搜索』。当用户问『附近有什么 / 周围有没有 X』时使用。"
        "返回最多 5 个 POI 摘要（名字、距离、地址、首图）。"
    )
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {
            "keywords": {"type": "string",
                         "description": "关键词，如 '咖啡' '公园' '书店'"},
            "radius": {"type": "integer", "default": 1000,
                       "description": "搜索半径米，默认 1000"},
        },
        "required": ["keywords"],
    })

    def invoke(self, args: dict) -> dict:
        loc = self.location_provider()
        keywords = str(args.get("keywords") or "").strip()
        if not keywords:
            return {"status": "error", "error": "keywords required"}
        radius = int(args.get("radius") or 1000)
        try:
            pois = self.amap.search_around(
                location=loc, keywords=keywords, radius=radius)
        except Exception as e:  # noqa: BLE001
            return {"status": "error", "error": str(e)}
        return {
            "status": "ok",
            "location": loc,
            "count": len(pois),
            "pois": [_poi_to_brief(p) for p in pois[:5]],
        }


@dataclass
class LookupPlaceTool:
    amap: Any
    xhs: Any
    media: Any
    cache_dir: Path
    location_provider: Callable[[], str]
    event_bus: Any = None
    name: str = "lookup_place"
    description: str = (
        "按名字精确查一个地点。会按距离当前定位最近的那家匹配，"
        "并尽力返回一张本地缓存的图片 URL（高德/小红书/生成图）。"
    )
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {
            "name": {"type": "string", "description": "地点名，如 '鸡鸣寺'"},
            "region": {"type": "string", "default": "南京"},
        },
        "required": ["name"],
    })

    def invoke(self, args: dict) -> dict:
        name = str(args.get("name") or "").strip()
        region = str(args.get("region") or "南京").strip() or "南京"
        if not name:
            return {"status": "error", "error": "name required"}
        try:
            pois = self.amap.text_search(keywords=name, region=region)
        except Exception as e:  # noqa: BLE001
            return {"status": "error", "error": str(e)}
        if not pois:
            # 即便高德找不到，也尝试给一张图，让 LLM 仍能做出回答
            url, src = _resolve_image(
                name=name, hint=None, amap=None, xhs=self.xhs,
                media=self.media, cache_dir=self.cache_dir, region=region)
            return {"status": "no_match", "image_url": url,
                    "image_source": src}
        # 选离当前定位最近的
        try:
            loc_s = self.location_provider()
            lng_s, _, lat_s = loc_s.partition(",")
            here = (float(lng_s), float(lat_s))
            pois.sort(key=lambda p: _haversine_m(here, p.location))
        except Exception:
            pass
        chosen = pois[0]
        url, src = _resolve_image(
            name=chosen.name, hint=chosen.address, amap=self.amap,
            xhs=self.xhs, media=self.media,
            cache_dir=self.cache_dir, region=region)
        return {
            "status": "ok",
            "poi": _poi_to_brief(chosen),
            "image_url": url,
            "image_source": src,
        }


@dataclass
class SearchXhsTool:
    xhs: Any
    name: str = "search_xiaohongshu"
    description: str = (
        "在小红书上搜笔记。适合『有没有人写过 X / X 怎么样』这类需要他人体验的问题。"
        "如果本机没装 xhs CLI 会返回 unavailable，遇到就走别的工具回答。"
    )
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {
            "query": {"type": "string"},
            "limit": {"type": "integer", "default": 3},
        },
        "required": ["query"],
    })

    def invoke(self, args: dict) -> dict:
        q = str(args.get("query") or "").strip()
        if not q:
            return {"status": "error", "error": "query required"}
        if not getattr(self.xhs, "available", False):
            return {"status": "unavailable",
                    "hint": "xhs CLI 未安装，请改用 lookup_place / search_around"}
        limit = int(args.get("limit") or 3)
        res = self.xhs.search(query=q, limit=limit)
        items = []
        for it in res.get("items") or []:
            items.append({
                "title": it.get("title"),
                "desc": (it.get("desc") or "")[:400],
                "images": (it.get("images") or [])[:3],
                "url": it.get("url"),
                "liked_count": it.get("liked_count"),
                "nickname": it.get("nickname"),
            })
        return {"status": "ok", "items": items}


@dataclass
class RecommendPoiCardTool:
    """自由模式专用：推一张 POI 卡到前端 S5。

    image_url 不传时会自动跑降级链拿一张图（amap → xhs → 生成 → 占位）。
    """
    amap: Any
    xhs: Any
    media: Any
    cache_dir: Path
    event_bus: Any = None
    name: str = "recommend_poi_card"
    description: str = (
        "推荐一个地点并把卡片推到前端 S5（图 + 名字 + 一句话 + 是/否/聊聊）。"
        "调这个之前最好已经用 search_around 或 lookup_place 拿过 POI。"
        "传 name + tagline + 距离即可，图会自动找。"
    )
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {
            "name": {"type": "string"},
            "tagline": {"type": "string", "description": "一句话推荐理由 ≤ 40 字"},
            "distance_m": {"type": "integer"},
            "rating": {"type": "number"},
            "image_url": {"type": "string",
                          "description": "可选：已拿到的图片 URL；留空会自动找"},
            "location": {"type": "string",
                         "description": "可选：lng,lat"},
            "reason": {"type": "string",
                       "description": "你为什么推这个，便于复盘"},
        },
        "required": ["name", "tagline"],
    })

    def invoke(self, args: dict) -> dict:
        name = str(args.get("name") or "").strip()
        tagline = str(args.get("tagline") or "").strip()
        if not name:
            return {"status": "error", "error": "name required"}
        image_url = str(args.get("image_url") or "").strip()
        image_source = "provided"
        if not image_url:
            image_url, image_source = _resolve_image(
                name=name, hint=tagline, amap=self.amap, xhs=self.xhs,
                media=self.media, cache_dir=self.cache_dir)
        elif image_url.startswith("http"):
            try:
                from demo.media import download_to_cache
                path = download_to_cache(url=image_url,
                                         cache_dir=self.cache_dir)
                image_url = f"/poi_image/{path.name}"
                image_source = "provided_cached"
            except Exception as e:  # noqa: BLE001
                print(f"[recommend_poi_card] download provided failed: {e}")

        place = {
            "name": name,
            "tagline": tagline,
            "image_url": image_url,
            "image_source": image_source,
            "distance_m": args.get("distance_m"),
            "rating": args.get("rating"),
            "location": args.get("location"),
        }
        if self.event_bus is not None:
            try:
                self.event_bus.publish({
                    "type": "poi_card",
                    "poi_id": f"free_{abs(hash(name)) % 10**8}",
                    "name": name,
                    "tagline": tagline,
                    "image_url": image_url,
                    "distance_m": place["distance_m"],
                    "rating": place["rating"],
                })
            except Exception as e:  # noqa: BLE001
                print(f"[recommend_poi_card] publish failed: {e}")
        return {"status": "ok", "place": place}


@dataclass
class ShowConceptCardTool:
    """概念卡：解释一个建筑/景点/概念，弹出 concept-overlay。"""
    amap: Any
    xhs: Any
    media: Any
    cache_dir: Path
    event_bus: Any = None
    name: str = "show_concept_card"
    description: str = (
        "弹出一张『概念解释卡』。适合用户问『那是什么 / 介绍一下 / 解释下这个』。"
        "body 写中文 ≤ 400 字；tags ≤ 4 个。image_query 用于自动找图。"
    )
    parameters: dict = field(default_factory=lambda: {
        "type": "object",
        "properties": {
            "title": {"type": "string"},
            "subtitle": {"type": "string"},
            "body": {"type": "string", "description": "≤ 400 中文字"},
            "tags": {"type": "array",
                     "items": {"type": "string"},
                     "description": "≤ 4 个短词"},
            "image_query": {"type": "string",
                            "description": "用于检索/生成图的词，如 '南京鸡鸣寺'"},
        },
        "required": ["title", "body"],
    })

    def invoke(self, args: dict) -> dict:
        title = str(args.get("title") or "").strip()
        if not title:
            return {"status": "error", "error": "title required"}
        body = str(args.get("body") or "").strip()
        subtitle = str(args.get("subtitle") or "").strip()
        tags = args.get("tags") or []
        if not isinstance(tags, list):
            tags = []
        tags = [str(t).strip() for t in tags if str(t).strip()][:4]
        image_query = str(args.get("image_query") or title).strip()

        image_url, image_source = _resolve_image(
            name=image_query, hint=subtitle or body[:40],
            amap=self.amap, xhs=self.xhs, media=self.media,
            cache_dir=self.cache_dir)

        ev = {
            "type": "concept_card",
            "title": title,
            "subtitle": subtitle,
            "body": body,
            "tags": tags,
            "image_url": image_url,
        }
        if self.event_bus is not None:
            try:
                self.event_bus.publish(ev)
            except Exception as e:  # noqa: BLE001
                print(f"[show_concept_card] publish failed: {e}")
        return {"status": "ok", "image_source": image_source,
                "card": {"title": title, "subtitle": subtitle,
                         "body": body, "tags": tags,
                         "image_url": image_url}}
