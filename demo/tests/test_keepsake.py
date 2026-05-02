from pathlib import Path
from PIL import Image
from demo.dialog import DialogLog, MomentLog
from demo.keepsake import KeepsakeBuilder


def _make_jpeg(path: Path, color: tuple[int, int, int]):
    Image.new("RGB", (640, 360), color).save(path, "JPEG")


def test_builds_collage_with_5_frames_and_quotes(tmp_path):
    moments = MomentLog()
    for i, c in enumerate([(200,80,80),(80,200,80),(80,80,200),(200,200,80),(200,80,200)]):
        p = tmp_path / f"f{i}.jpg"; _make_jpeg(p, c)
        moments.append(label=f"m{i}", frame_path=str(p))
    log = DialogLog()
    log.append("user", "开始散步")
    log.append("assistant", "好，去玄武湖吧")
    log.append("user", "这是什么")
    log.append("assistant", "是一株散尾葵")
    log.append("user", "记一下")

    out = tmp_path / "keepsake.png"
    builder = KeepsakeBuilder()
    builder.build(dialog=log, moments=moments, out_path=out)
    assert out.exists()
    img = Image.open(out)
    assert img.size == (1080, 1920)
