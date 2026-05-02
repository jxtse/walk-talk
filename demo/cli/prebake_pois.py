# demo/cli/prebake_pois.py
"""启动 demo 之前可选跑一次：把 amap 查询缓存到本地，避免 demo 中网络抖。

用法：
    python -m demo.cli.prebake_pois
    python -m demo.cli.prebake_pois --force   # 忽略缓存重新拉
"""
from __future__ import annotations
import argparse
import asyncio
import dataclasses
import json
import time
from pathlib import Path

from demo.config import load_config
from demo.event_bus import EventBus
from demo.amap import AmapClient

ROOT = Path(__file__).resolve().parent.parent
DATA_FILE = ROOT / "data" / "pois_v2.json"
CACHE_FILE = ROOT.parent / "demo_runtime" / "cache" / "pois_real.json"
TTL_SECONDS = 24 * 3600


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    if (CACHE_FILE.exists()
            and (time.time() - CACHE_FILE.stat().st_mtime) < TTL_SECONDS
            and not args.force):
        print(f"cache 已存在且 < 24h: {CACHE_FILE}; 跳过（--force 强制）")
        return 0

    cfg = load_config()
    bus = EventBus()
    bus.bind_loop(asyncio.new_event_loop())  # 仅 publish 用，不 await
    client = AmapClient(key=cfg.amap_key, event_bus=bus)

    spec = json.loads(DATA_FILE.read_text(encoding="utf-8"))
    out: dict[str, list[dict]] = {}
    for q in spec["amap_queries"]:
        print(f"-> {q['name']}: keywords={q['keywords']}")
        pois = client.search_around(
            location=q["location"], keywords=q["keywords"],
            radius=q["radius"], offset=20)
        rows = []
        for p in pois:
            d = dataclasses.asdict(p)
            d["location"] = list(p.location)
            rows.append(d)
        out[q["name"]] = rows
        print(f"   got {len(rows)} pois")

    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    CACHE_FILE.write_text(
        json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"写入 {CACHE_FILE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
