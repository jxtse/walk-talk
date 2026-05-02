# demo/config.py
"""读取 .env + 环境变量，单一配置入口。

优先级：进程环境变量 > .env 文件。AMAP_KEY 和 OPENAI_NEXT_API_KEY 必填，
缺任一抛 RuntimeError。PLANNER_BASE_URL 缺省 100.99.139.20:18141。
"""
from __future__ import annotations
import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_PLANNER_BASE_URL = "http://100.99.139.20:18141"


@dataclass(frozen=True)
class Config:
    amap_key: str
    openai_next_api_key: str
    planner_base_url: str


def _parse_env_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    out: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def load_config(*, env_path: Path | None = None) -> Config:
    file_vals = _parse_env_file(env_path or Path(".env"))

    def pick(name: str, default: str | None = None) -> str | None:
        return os.environ.get(name) or file_vals.get(name) or default

    amap = pick("AMAP_KEY")
    media = pick("OPENAI_NEXT_API_KEY")
    planner = pick("PLANNER_BASE_URL", DEFAULT_PLANNER_BASE_URL)
    missing = [n for n, v in
               [("AMAP_KEY", amap), ("OPENAI_NEXT_API_KEY", media)] if not v]
    if missing:
        raise RuntimeError(
            f"missing required env vars: {missing}. "
            "set them in .env or process env.")
    assert amap and media and planner
    return Config(amap_key=amap, openai_next_api_key=media,
                  planner_base_url=planner)
