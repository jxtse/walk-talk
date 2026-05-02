# demo/amap.py
"""高德 Web Service v3 客户端，限定 search_around。"""
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
        # 高德是公网，需要走系统代理 -> trust_env=True
        self._http = http or httpx.Client(timeout=timeout, trust_env=True)

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
        self._bus.publish({
            "type": "amap_raw",
            "endpoint": "/v3/place/around",
            "params": {k: v for k, v in params.items() if k != "key"},
            "status": data.get("status"),
            "info": data.get("info"),
            "count": len(pois),
            "first": pois[0].raw if pois else None,
        })
        if data.get("status") != "1":
            return []
        return pois
