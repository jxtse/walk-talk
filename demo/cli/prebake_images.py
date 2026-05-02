# demo/cli/prebake_images.py
"""启动 demo 之前跑一次：预生成 5 张 gemini 插画到本地缓存。

用法：
    python -m demo.cli.prebake_images          # 缺哪张补哪张
    python -m demo.cli.prebake_images --force  # 全部重生成
"""
from __future__ import annotations
import argparse
import json
import sys
import time
from pathlib import Path

from demo.config import load_config
from demo.media import MediaClient

ROOT = Path(__file__).resolve().parent.parent
PREBAKE_JSON = ROOT / "data" / "scenarios" / "prebake.json"
CACHE_DIR = ROOT.parent / "demo_runtime" / "cache" / "images"


def _generate_one(client: MediaClient, item: dict, out: Path,
                  retries: int = 3) -> tuple[bool, str]:
    last_err = ""
    for attempt in range(1, retries + 1):
        try:
            t0 = time.time()
            client.generate_image(
                prompt=item["prompt"], size=item["size"], save_to=out)
            return True, f"{out.stat().st_size // 1024}KB / {time.time()-t0:.1f}s"
        except Exception as e:  # noqa: BLE001
            last_err = f"attempt {attempt}: {e}"
            time.sleep(2.0 * attempt)
    return False, last_err


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true",
                    help="忽略缓存，全部重生成")
    args = ap.parse_args()

    cfg = load_config()
    items = json.loads(PREBAKE_JSON.read_text(encoding="utf-8"))
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    client = MediaClient(api_key=cfg.openai_next_api_key)
    print(f"预生成 {len(items)} 张图 -> {CACHE_DIR}")

    failed = 0
    for item in items:
        out = CACHE_DIR / f"{item['id']}.png"
        if out.exists() and not args.force:
            print(f"  [skip] {item['id']}  ({out.stat().st_size//1024}KB)")
            continue
        ok, info = _generate_one(client, item, out)
        tag = "ok  " if ok else "FAIL"
        print(f"  [{tag}] {item['id']}  {info}")
        if not ok:
            failed += 1
    if failed:
        print(f"FAILED {failed}/{len(items)}", file=sys.stderr)
        return 1
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
