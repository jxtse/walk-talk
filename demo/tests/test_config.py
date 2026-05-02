# demo/tests/test_config.py
from pathlib import Path
from demo.config import load_config, Config


def test_load_from_env_file(tmp_path: Path, monkeypatch):
    env = tmp_path / ".env"
    env.write_text(
        "AMAP_KEY=ak_123\n"
        "OPENAI_NEXT_API_KEY=sk_xyz\n"
        "PLANNER_BASE_URL=http://example:1\n",
        encoding="utf-8",
    )
    for k in ("AMAP_KEY", "OPENAI_NEXT_API_KEY", "PLANNER_BASE_URL"):
        monkeypatch.delenv(k, raising=False)
    cfg = load_config(env_path=env)
    assert isinstance(cfg, Config)
    assert cfg.amap_key == "ak_123"
    assert cfg.openai_next_api_key == "sk_xyz"
    assert cfg.planner_base_url == "http://example:1"


def test_env_overrides_file(tmp_path: Path, monkeypatch):
    env = tmp_path / ".env"
    env.write_text("AMAP_KEY=from_file\nOPENAI_NEXT_API_KEY=b\n", encoding="utf-8")
    monkeypatch.setenv("AMAP_KEY", "from_env")
    monkeypatch.delenv("OPENAI_NEXT_API_KEY", raising=False)
    monkeypatch.delenv("PLANNER_BASE_URL", raising=False)
    cfg = load_config(env_path=env)
    assert cfg.amap_key == "from_env"


def test_missing_required_raises(tmp_path: Path, monkeypatch):
    for k in ("AMAP_KEY", "OPENAI_NEXT_API_KEY", "PLANNER_BASE_URL"):
        monkeypatch.delenv(k, raising=False)
    env = tmp_path / ".env"
    try:
        load_config(env_path=env)
    except RuntimeError as e:
        assert "AMAP_KEY" in str(e)
    else:
        raise AssertionError("expected RuntimeError")


def test_planner_base_url_has_default(tmp_path, monkeypatch):
    env = tmp_path / ".env"
    env.write_text(
        "AMAP_KEY=a\nOPENAI_NEXT_API_KEY=b\n", encoding="utf-8")
    for k in ("AMAP_KEY", "OPENAI_NEXT_API_KEY", "PLANNER_BASE_URL"):
        monkeypatch.delenv(k, raising=False)
    cfg = load_config(env_path=env)
    assert cfg.planner_base_url == "http://100.99.139.20:18141"
