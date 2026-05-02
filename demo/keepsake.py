"""Render a 1080x1920 portrait collage of the walk."""
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from demo.dialog import DialogLog, MomentLog

W, H = 1080, 1920
PAD = 30
HEADER_H = 140


def _load_font(size: int) -> ImageFont.FreeTypeFont:
    for name in ("msyh.ttc", "simhei.ttf", "C:/Windows/Fonts/msyh.ttc",
                 "C:/Windows/Fonts/simhei.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _select_quotes(dialog: DialogLog, n: int = 6) -> list[str]:
    turns = list(dialog)
    if len(turns) <= n:
        return [f"{t.role}：{t.text}" for t in turns]
    picks = [turns[0], turns[1], turns[-2], turns[-1]]
    mid = turns[2:-2]
    if mid:
        step = max(1, len(mid) // 2)
        picks.insert(2, mid[0])
        if len(mid) > step:
            picks.insert(3, mid[step])
    return [f"{t.role}：{t.text}" for t in picks[:n]]


class KeepsakeBuilder:
    def build(self, *, dialog: DialogLog, moments: MomentLog,
              out_path: Path) -> Path:
        canvas = Image.new("RGB", (W, H), (24, 28, 36))
        d = ImageDraw.Draw(canvas)
        title_font = _load_font(56)
        body_font = _load_font(28)

        d.text((PAD, PAD), "步语 · 一次散步", fill=(238, 241, 244),
               font=title_font)

        frame_paths = [m.frame_path for m in moments][:5]
        if frame_paths and len(frame_paths) < 5:
            frame_paths += [frame_paths[-1]] * (5 - len(frame_paths))

        cols, rows = 2, 3
        cell_w = (W - PAD * (cols + 1)) // cols
        cell_h = 320
        y0 = HEADER_H
        for i, fp in enumerate(frame_paths):
            r, c = divmod(i, cols)
            x = PAD + c * (cell_w + PAD)
            y = y0 + r * (cell_h + PAD)
            try:
                im = Image.open(fp).convert("RGB")
            except Exception:
                continue
            im = im.resize((cell_w, cell_h))
            canvas.paste(im, (x, y))

        quotes = _select_quotes(dialog)
        qy = y0 + rows * (cell_h + PAD) + PAD
        for q in quotes:
            d.multiline_text((PAD, qy), q, fill=(200, 210, 224),
                             font=body_font, spacing=6)
            qy += 70

        Path(out_path).parent.mkdir(parents=True, exist_ok=True)
        canvas.save(out_path, "PNG")
        return out_path
