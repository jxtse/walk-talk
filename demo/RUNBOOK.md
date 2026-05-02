# Demo Runbook (≈3 min recording)

## Pre-flight (do once before recording)
1. Camera plugged in, light on.
2. `tasklist | findstr python` shows no leftover Python processes.
3. Tailscale connected; `curl http://100.99.139.20:18141/v1/models` returns JSON.
4. Speakers unmuted; volume around 50%.
5. Place 1–2 desk objects in front of camera (a plant, a mug, a notebook).
6. Have OBS / Windows Game Bar (`Win+G`) ready to record the browser window
   + system audio.

## Run
```
python -m demo.server
```
Wait for `demo server up: http://127.0.0.1:8788/`. Open in browser, fullscreen
the window.

## Recording script
Lines you actually type are in **bold**.

1. (Recording starts. Click "开始散步".) AI greets within ~5s.
2. Aim the camera at a desk object using the on-screen `/video.mjpg` feed.
   Type: **嘿，那是什么？** AI looks + describes.
3. Wait ~10s for proactive turn (or skip and continue).
4. Type: **附近有什么好玩的？** AI should call `recommend_nearby_place`
   and mention 鸡鸣寺 / 紫峰 / etc.
5. Type: **记一下，下次想再来。** Flash banner appears.
6. Type: **周围有什么？让我看看。** Camera physically sweeps the room
   (left-right-center, ~3s).
7. Click "结束散步". Keepsake collage renders in right panel.
8. Stop recording.

Total wall-clock: 2:30 – 3:30.

## If something goes wrong mid-take
- Camera frozen → leave it, the agent will say "我没看清".
- LLM timeout → wait or restart the server, re-take.
- Audio cuts out → re-record (TTS isn't critical to the visual story).

## Re-takes
Each session writes to `demo_runtime/`. Delete that directory between takes
if you want a clean slate, otherwise old moments and keepsakes accumulate.
