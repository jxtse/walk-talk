# demo/amap.py
"""高德 Web Service v3 客户端。

实现的端点（仅 GET）：
- /v3/place/around   周边 POI 搜索 -> search_around
- /v3/place/text     按关键字搜 POI -> text_search
- /v3/geocode/regeo  逆地理编码 -> regeo
- /v3/direction/walking  步行规划 -> walking_route

所有方法都会通过 event_bus 推送一条 {"type":"amap_raw"} 事件到前端面板。
"""
from __future__ import annotations
from dataclasses import dataclass, field
from typing import Any
import httpx

from demo.event_bus import EventBus

DEFAULT_BASE = "https://restapi.amap.com"


@dataclass(frozen=True)
class POI:
    id: str
    name: str
    location: tuple[float, float]   # (lng, lat)
    distance_m: int
    address: str
    typecode: str
    rating: float | None
    cost: float | None
    tags: list[str] = field(default_factory=list)
    photos: list[str] = field(default_factory=list)
    raw: dict[str, Any] = field(default_factory=dict)


def _parse_float(v: Any) -> float | None:
    try:
        if v in (None, "", []):
            return None
        return float(v)
    except (TypeError, ValueError):
        return None


def _parse_tags(v: Any) -> list[str]:
    if isinstance(v, str) and v:
        return [t.strip() for t in v.split(",") if t.strip()]
    return []


def _parse_photos(v: Any) -> list[str]:
    """高德 photos 字段：list[{title,url}] 或空列表/空字符串/空 dict。"""
    if not isinstance(v, list):
        return []
    out: list[str] = []
    for item in v:
        if isinstance(item, dict):
            url = item.get("url") or item.get("URL")
            if url and isinstance(url, str):
                out.append(url)
    return out


def _parse_poi(d: dict[str, Any]) -> POI:
    lng_s, _, lat_s = (d.get("location") or "0,0").partition(",")
    biz = d.get("biz_ext") or {}
    if not isinstance(biz, dict):
        biz = {}
    return POI(
        id=str(d.get("id", "")),
        name=str(d.get("name", "")),
        location=(float(lng_s or 0), float(lat_s or 0)),
        distance_m=int(_parse_float(d.get("distance")) or 0),
        address=str(d.get("address") or ""),
        typecode=str(d.get("typecode") or ""),
        rating=_parse_float(biz.get("rating")),
        cost=_parse_float(biz.get("cost")),
        tags=_parse_tags(d.get("atag")),
        photos=_parse_photos(d.get("photos")),
        raw=d,
    )


class AmapClient:
    def __init__(self, *, key: str, event_bus: EventBus,
                 base_url: str = DEFAULT_BASE,
                 http: httpx.Client | None = None,
                 timeout: float = 10.0) -> None:
        self._key = key
        self._bus = event_bus
        self._base = base_url.rstrip("/")
        # 高德是国内公网，但本机的 Clash/v2ray 代理（127.0.0.1:7897）会把它当海外
        # 流量路由出去导致 SSL UNEXPECTED_EOF。直连即可：trust_env=False。
        self._http = http or httpx.Client(timeout=timeout, trust_env=False)

    def _publish(self, *, endpoint: str, params: dict, data: dict,
                 extra: dict | None = None) -> None:
        ev = {
            "type": "amap_raw",
            "endpoint": endpoint,
            "params": {k: v for k, v in params.items() if k != "key"},
            "status": data.get("status"),
            "info": data.get("info"),
        }
        if extra:
            ev.update(extra)
        try:
            self._bus.publish(ev)
        except Exception:
            pass

    # -------------------- /v3/place/around --------------------
    def search_around(self, *, location: str, keywords: str,
                      radius: int = 2000, offset: int = 20) -> list[POI]:
        params = {
            "key": self._key, "location": location, "keywords": keywords,
            "radius": str(radius), "offset": str(offset),
            "extensions": "all",
        }
        r = self._http.get(f"{self._base}/v3/place/around", params=params)
        r.raise_for_status()
        data = r.json()
        pois_raw = data.get("pois") or []
        pois = [_parse_poi(p) for p in pois_raw if isinstance(p, dict)]
        self._publish(endpoint="/v3/place/around", params=params, data=data,
                      extra={"count": len(pois),
                             "first": pois[0].raw if pois else None})
        if data.get("status") != "1":
            return []
        return pois

    # -------------------- /v3/place/text --------------------
    def text_search(self, *, keywords: str, region: str = "南京",
                    city_limit: bool = True, offset: int = 10) -> list[POI]:
        """按名称搜 POI。region 限定行政区（city 参数）。"""
        params = {
            "key": self._key, "keywords": keywords,
            "city": region, "citylimit": "true" if city_limit else "false",
            "offset": str(offset), "extensions": "all",
        }
        r = self._http.get(f"{self._base}/v3/place/text", params=params)
        r.raise_for_status()
        data = r.json()
        pois_raw = data.get("pois") or []
        pois = [_parse_poi(p) for p in pois_raw if isinstance(p, dict)]
        self._publish(endpoint="/v3/place/text", params=params, data=data,
                      extra={"count": len(pois)})
        if data.get("status") != "1":
            return []
        return pois

    # -------------------- /v3/geocode/regeo --------------------
    def regeo(self, *, location: str, radius: int = 500) -> dict:
        """经纬度 -> 结构化地址 + 周边 AOI/POI 摘要。"""
        params = {
            "key": self._key, "location": location,
            "radius": str(radius), "extensions": "base",
        }
        r = self._http.get(f"{self._base}/v3/geocode/regeo", params=params)
        r.raise_for_status()
        data = r.json()
        regeo = (data.get("regeocode") or {})
        addr = regeo.get("formatted_address") or ""
        comp = regeo.get("addressComponent") or {}
        out = {
            "formatted_address": addr if isinstance(addr, str) else "",
            "province": comp.get("province") if isinstance(comp, dict) else None,
            "city": comp.get("city") if isinstance(comp, dict) else None,
            "district": comp.get("district") if isinstance(comp, dict) else None,
            "township": comp.get("township") if isinstance(comp, dict) else None,
        }
        self._publish(endpoint="/v3/geocode/regeo", params=params, data=data,
                      extra={"address": out["formatted_address"]})
        return out

    # -------------------- /v3/direction/walking --------------------
    def walking_route(self, *, origin: str, destination: str) -> dict:
        """origin/destination 都是 'lng,lat'。返回总距离/总时长 + 步骤摘要。"""
        params = {
            "key": self._key, "origin": origin, "destination": destination,
        }
        r = self._http.get(f"{self._base}/v3/direction/walking", params=params)
        r.raise_for_status()
        data = r.json()
        route = (data.get("route") or {})
        paths = route.get("paths") or []
        first = paths[0] if isinstance(paths, list) and paths else {}
        dist = _parse_float(first.get("distance"))
        dur = _parse_float(first.get("duration"))
        steps_raw = first.get("steps") or []
        steps = []
        if isinstance(steps_raw, list):
            for s in steps_raw[:8]:
                if isinstance(s, dict):
                    steps.append({
                        "instruction": s.get("instruction") or "",
                        "distance_m": int(_parse_float(s.get("distance")) or 0),
                    })
        out = {
            "distance_m": int(dist) if dist is not None else None,
            "duration_s": int(dur) if dur is not None else None,
            "steps": steps,
        }
        self._publish(endpoint="/v3/direction/walking", params=params, data=data,
                      extra={"distance_m": out["distance_m"]})
        return out
