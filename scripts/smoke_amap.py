"""真打一次高德 search_around，确认 key + 网络可用。"""
import asyncio, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from demo.config import load_config
from demo.event_bus import EventBus
from demo.amap import AmapClient

cfg = load_config()
bus = EventBus(); bus.bind_loop(asyncio.new_event_loop())
client = AmapClient(key=cfg.amap_key, event_bus=bus)
pois = client.search_around(
    location="118.795,32.075", keywords="咖啡", radius=2000)
print(f"got {len(pois)} pois")
for p in pois[:3]:
    print(f"  {p.name}  {p.distance_m}m  rating={p.rating}  ¥{p.cost}")
