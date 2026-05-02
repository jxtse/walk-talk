import sys
import time
from pathlib import Path

# Allow `python scripts/smoke_camera.py` from repo root without PYTHONPATH.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from demo.camera import CameraController

cam = CameraController()
print("ranges:", cam.ranges)
print("pos:", cam.position())
print("waiting for first frame...")
deadline = time.time() + 5
while time.time() < deadline:
    f = cam.latest_frame()
    if f:
        print(f"first frame: {len(f.jpeg)} bytes at {f.captured_at}")
        break
    time.sleep(0.1)
else:
    raise SystemExit("no frame in 5s")

print("set_position pan=20...")
print(cam.set_position(pan=20))
time.sleep(0.5)
print(cam.set_position(pan=0, tilt=0, zoom=100))
print("OK")
