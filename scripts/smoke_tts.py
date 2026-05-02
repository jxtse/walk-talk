import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from demo.tts import TTSService

tts = TTSService()
tts.say("你好，我是步语。")
time.sleep(4)
