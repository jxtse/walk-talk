"""真打一次 openai-next：生成 1 张图 + 转写 1 段 wav。"""
import sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from demo.config import load_config
from demo.media import MediaClient

cfg = load_config()
client = MediaClient(api_key=cfg.openai_next_api_key)
out = Path("demo_runtime/smoke_media.png")
out.parent.mkdir(exist_ok=True)
t0 = time.time()
client.generate_image(
    prompt="一只在玄武湖边散步的橘猫，水彩",
    size="1024x1024", save_to=out)
print(f"image ok: {out} ({out.stat().st_size//1024}KB, {time.time()-t0:.1f}s)")

import wave, struct
wav = Path("demo_runtime/smoke_silence.wav")
with wave.open(str(wav), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
    w.writeframes(struct.pack("<" + "h" * 16000, *([0] * 16000)))
text = client.transcribe(audio_bytes=wav.read_bytes(), mime="audio/wav")
print(f"whisper ok: text={text!r}")
