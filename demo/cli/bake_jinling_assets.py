# demo/cli/bake_jinling_assets.py
"""Bake all assets needed for scenario C (jinling / 阿里中心).

Outputs everything under demo/static/scenes/concepts/ and
demo/static/scenes/jinling_keepsake.png so the scripted scenario
can reference them at runtime via stable URLs.

Usage:
    python -m demo.cli.bake_jinling_assets             # only missing
    python -m demo.cli.bake_jinling_assets --force     # regenerate all
    python -m demo.cli.bake_jinling_assets --only map  # subset

Pieces:
  1. Concept cards (text-to-image, 16:10 illustrations) ─
     agent_network, rag_grounding, multi_agent_handoff, tool_use_loop.
  2. Route map: matplotlib-renders a hand-drawn-ish map from real
     POI lat/lngs, then sends it together with the s6 mockup as a
     style reference to the image-edit endpoint to get a final
     "散步笔记"-style keepsake. Falls back to the matplotlib render
     if the edit call fails.
"""
from __future__ import annotations
import argparse
import json
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from demo.config import load_config
from demo.media import MediaClient

ROOT = Path(__file__).resolve().parent.parent
POIS_V2 = ROOT / "data" / "pois_v2.json"
S6_MOCKUP = ROOT / "static" / "mockup" / "s6.png"
OUT_DIR = ROOT / "static" / "scenes" / "concepts"
KEEPSAKE_OUT = ROOT / "static" / "scenes" / "jinling_keepsake.png"
LOCAL_MAP_OUT = OUT_DIR / "_route_base.png"  # intermediate reference

# ---- concept cards ---------------------------------------------------------

CONCEPTS: list[dict] = [
    {
        "key": "agent_network",
        "size": "1024x640",
        "prompt": (
            "Editorial flat-illustration explainer image of an 'Agent Network': "
            "five friendly small robot characters standing on glowing nodes "
            "of a connected graph, soft pastel palette (mint, peach, lavender), "
            "thin clean lines, slight paper-grain texture, white background, "
            "subtle hand-drawn arrows between agents passing colored message tokens. "
            "Tech-magazine aesthetic, no text, no logos, 16:10."
        ),
    },
    {
        "key": "rag_grounding",
        "size": "1024x640",
        "prompt": (
            "Friendly flat illustration explaining Retrieval-Augmented Generation: "
            "a small robot reading from a tall stack of opened books and document "
            "cards floating in front of it, with glowing keywords being plucked out "
            "and woven into a speech bubble. Pastel palette, soft shadows, hand-drawn "
            "lines, white background, no text, 16:10."
        ),
    },
    {
        "key": "multi_agent_handoff",
        "size": "1024x640",
        "prompt": (
            "Cute illustration of two robots passing a glowing baton between them "
            "across a chasm, while a third robot watches and takes notes. Each robot "
            "wears a tiny labelled badge (no readable text, abstract shapes). "
            "Pastel palette, hand-drawn lines, white background, 16:10."
        ),
    },
    {
        "key": "tool_use_loop",
        "size": "1024x640",
        "prompt": (
            "Illustration of a robot at the centre of a circular conveyor belt, "
            "picking tools off the belt one at a time — a magnifying glass, a "
            "wrench, a camera, a tiny map — using each then putting it back. "
            "Soft pastel colours, hand-drawn outlines, white background, 16:10."
        ),
    },
]


def _bake_concept(client: MediaClient, item: dict, out_path: Path,
                  retries: int = 3) -> tuple[bool, str]:
    last = ""
    for n in range(1, retries + 1):
        try:
            t0 = time.time()
            client.generate_image(
                prompt=item["prompt"], size=item["size"], save_to=out_path)
            return True, f"{out_path.stat().st_size//1024}KB / {time.time()-t0:.1f}s"
        except Exception as e:  # noqa: BLE001
            last = f"attempt {n}: {e}"
            time.sleep(1.5 * n)
    return False, last


# ---- route map -------------------------------------------------------------

# Order along the walk (north-bound along Jiangdong Middle Rd → cross to
# Nanjing Eye → loop back). Matches scenario's narrative.
ROUTE_ORDER: list[str] = [
    "jinling_tiandi",
    "yunmeng_park",
    "qingao_center",
    "nanjing_eye",
    "hexi_ecology",
    "youyi_park",
]
START_LABEL = "START\n阿里中心"
START_LATLNG = (118.738, 32.012)  # near 金陵天地, used as walk start


def _load_route_pois() -> list[dict]:
    raw = json.loads(POIS_V2.read_text(encoding="utf-8"))
    by_id = {p["poi_id"]: p for p in raw["scripted"]}
    return [by_id[k] for k in ROUTE_ORDER if k in by_id]


def _draw_local_map(out_path: Path, pois: list[dict]) -> Path:
    """Hand-drawn-ish base map rendered with matplotlib + PIL polish."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import FancyBboxPatch
    from matplotlib.patheffects import withStroke
    import numpy as np
    from scipy.interpolate import splprep, splev  # may be missing; handled below

    coords = [START_LATLNG] + [(p["location"][0], p["location"][1]) for p in pois]
    xs = [c[0] for c in coords]
    ys = [c[1] for c in coords]

    # paper-ish background colour
    fig = plt.figure(figsize=(6.6, 11.0), dpi=200, facecolor="#FBFAF5")
    ax = fig.add_axes([0.04, 0.05, 0.92, 0.78])
    ax.set_facecolor("#FBFAF5")
    ax.set_xticks([]); ax.set_yticks([])
    for spine in ax.spines.values():
        spine.set_visible(False)

    # padding around extents
    pad_x = (max(xs) - min(xs)) * 0.18 + 0.001
    pad_y = (max(ys) - min(ys)) * 0.15 + 0.001
    ax.set_xlim(min(xs) - pad_x, max(xs) + pad_x)
    ax.set_ylim(min(ys) - pad_y, max(ys) + pad_y)

    # smooth curving "ink" path through the points
    try:
        tck, _ = splprep([xs, ys], s=0.0, k=min(3, len(xs) - 1))
        u = np.linspace(0, 1, 240)
        sx, sy = splev(u, tck)
    except Exception:
        sx, sy = xs, ys

    ax.plot(sx, sy, color="#3A6CF4", linewidth=4.5, solid_capstyle="round",
            alpha=0.95, path_effects=[withStroke(linewidth=7, foreground="white")])
    # dotted "footprints" trailing the line for a hand-drawn feel
    ax.plot(sx[::18], sy[::18], "o", color="#3A6CF4", markersize=4, alpha=0.55)

    # POI pins
    pin_colors = ["#E45757", "#F0A93B", "#6FB46C", "#3A6CF4", "#9061C2", "#C0567E"]
    # START flag
    ax.plot(xs[0], ys[0], marker="s", markersize=14, color="#F4C84A",
            markeredgecolor="#1a1d24", zorder=5)
    ax.annotate(START_LABEL, (xs[0], ys[0]),
                xytext=(-44, -28), textcoords="offset points",
                fontsize=8, color="#1a1d24",
                bbox=dict(boxstyle="round,pad=0.3", fc="#FFF6CC",
                          ec="#1a1d24", lw=0.8),
                fontfamily="Microsoft YaHei",
                zorder=6)
    # numbered POI pins
    for i, p in enumerate(pois, start=1):
        x, y = p["location"]
        c = pin_colors[(i - 1) % len(pin_colors)]
        ax.plot(x, y, marker="o", markersize=18, color=c,
                markeredgecolor="white", markeredgewidth=2, zorder=5)
        ax.text(x, y, str(i), ha="center", va="center",
                color="white", fontsize=10, fontweight="bold", zorder=6)
        ax.annotate(p["name"], (x, y),
                    xytext=(14, 6), textcoords="offset points",
                    fontsize=8, color="#1a1d24",
                    fontfamily="Microsoft YaHei",
                    bbox=dict(boxstyle="round,pad=0.25", fc="white",
                              ec=c, lw=0.8, alpha=0.95),
                    zorder=6)

    # title strip
    fig.text(0.06, 0.945, "散步笔记", fontsize=22, fontweight="bold",
             color="#1a1d24", fontfamily="Microsoft YaHei")
    fig.text(0.06, 0.905, "金陵天地 · 河西黄昏一圈", fontsize=11,
             color="#5a6072", fontfamily="Microsoft YaHei")
    fig.text(0.06, 0.885, f"~ {len(pois)} stops · river-side loop",
             fontsize=9, color="#8a93a6", fontfamily="Microsoft YaHei")

    # key-points list at bottom
    kp_y = 0.21
    fig.text(0.06, kp_y, "Key Points", fontsize=12, fontweight="bold",
             color="#1a1d24", fontfamily="Microsoft YaHei")
    bullets = [
        f"· 走 ~3.5km，沿江东中路一路向北",
        f"· {len(pois)} 个停留点：黄昏蓝调 → 夜樱 → 双塔 → 桥拱 → 水杉 → 红房子",
        "· 全程基本临水，适合慢走与拍照",
    ]
    for i, b in enumerate(bullets):
        fig.text(0.06, kp_y - 0.035 * (i + 1), b, fontsize=9,
                 color="#3a3f4b", fontfamily="Microsoft YaHei")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=200, facecolor="#FBFAF5",
                bbox_inches=None, pad_inches=0)
    plt.close(fig)
    return out_path


def _bake_keepsake(client: MediaClient) -> tuple[bool, str]:
    """Render local base map, then ask the image-edit endpoint to restyle
    it like the s6 散步笔记 mockup. Falls back to copying the local render
    if the API call fails."""
    pois = _load_route_pois()
    base = _draw_local_map(LOCAL_MAP_OUT, pois)
    prompt = (
        "Reference image #1 is a hand-drawn 'walking notes' page in a soft "
        "pastel illustrated style — paper background, marker line route, "
        "doodled trees and a coffee cup, casual handwritten Chinese title "
        "'散步笔记', a 'Key Points' bullet list. Reference image #2 is a "
        "geographically-correct version of a real walking route through the "
        "Hexi neighbourhood of Nanjing with numbered pins along a curving "
        "blue line. Produce one output image: keep the EXACT geometry, pin "
        "positions, numbering, and Chinese place-name labels of image #2, "
        "but redraw it in the warm hand-drawn illustrated style of image #1 "
        "— paper-textured cream background, slightly wobbly hand-inked route "
        "line, small doodled trees / buildings / a riverline next to the "
        "route, a cute cartoon 'START' flag at the start pin, and the title "
        "'散步笔记' at the top in handwritten Chinese. Portrait, "
        "phone-screen friendly proportions."
    )
    try:
        client.edit_image(
            prompt=prompt, size="1024x1536",
            image_paths=[S6_MOCKUP, base],
            save_to=KEEPSAKE_OUT,
        )
        return True, "edit ok"
    except Exception as e:  # noqa: BLE001
        # Fallback: just promote the local matplotlib render.
        try:
            import shutil
            shutil.copyfile(base, KEEPSAKE_OUT)
            return True, f"edit failed ({e}); using local render"
        except Exception as e2:  # noqa: BLE001
            return False, f"edit failed: {e}; copy failed: {e2}"


# ---- entry -----------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", choices=["concepts", "map"], default=None)
    args = ap.parse_args()

    cfg = load_config()
    client = MediaClient(api_key=cfg.openai_next_api_key)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    rc = 0
    if args.only in (None, "concepts"):
        for item in CONCEPTS:
            out = OUT_DIR / f"{item['key']}.png"
            if out.exists() and not args.force:
                print(f"[skip] {out.name} ({out.stat().st_size//1024}KB)")
                continue
            ok, msg = _bake_concept(client, item, out)
            print(f"[{'ok' if ok else 'FAIL'}] {out.name} :: {msg}")
            if not ok:
                rc = 1
    if args.only in (None, "map"):
        if KEEPSAKE_OUT.exists() and not args.force:
            print(f"[skip] {KEEPSAKE_OUT.name} "
                  f"({KEEPSAKE_OUT.stat().st_size//1024}KB)")
        else:
            ok, msg = _bake_keepsake(client)
            print(f"[{'ok' if ok else 'FAIL'}] {KEEPSAKE_OUT.name} :: {msg}")
            if not ok:
                rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
